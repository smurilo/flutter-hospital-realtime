import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/entities.dart';

class BedsRestDataSource {
  const BedsRestDataSource(this._dio);

  final Dio _dio;

  Future<Board> snapshot() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/beds');
    final data = response.data!;
    final beds = [for (final b in data['beds'] as List) Bed.fromJson(b as Map<String, dynamic>)];
    return Board(beds: {for (final b in beds) b.id: b}, seq: data['seq'] as int);
  }

  Future<void> markCleaned(String bedId) => _dio.post<void>('/api/beds/$bedId/cleaned');
}

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// WebSocket with automatic reconnection (exponential backoff capped at 30s).
class BedsSocketDataSource {
  BedsSocketDataSource(this.uri,
      {ChannelFactory? connect,
      this.maxBackoff = const Duration(seconds: 30),
      this.initialBackoff = const Duration(seconds: 1)})
      : _connect = connect ?? WebSocketChannel.connect;

  final Uri uri;
  final ChannelFactory _connect;
  final Duration maxBackoff;
  final Duration initialBackoff;

  final _events = StreamController<BedEvent>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  WebSocketChannel? _channel;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;

  Stream<BedEvent> get events => _events.stream;
  Stream<ConnectionStatus> get status => _status.stream;

  /// Fires after every successful (re)connection so the repository can resync.
  final _connected = StreamController<void>.broadcast();
  Stream<void> get connected => _connected.stream;

  void open() {
    if (_closed) return;
    _status.add(_attempt == 0 ? ConnectionStatus.connecting : ConnectionStatus.reconnecting);
    final channel = _connect(uri);
    _channel = channel;
    channel.ready.then((_) {
      _attempt = 0;
      _status.add(ConnectionStatus.live);
      _connected.add(null);
    }, onError: (_) {});
    channel.stream.listen(
      (message) {
        try {
          _events.add(BedEvent.fromJson(jsonDecode(message as String) as Map<String, dynamic>));
        } on FormatException {
          // Unknown event types from a newer server version are ignored, not fatal.
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_closed || (_retry?.isActive ?? false)) return;
    _status.add(ConnectionStatus.offline);
    final delay = initialBackoff * (1 << _attempt.clamp(0, 5));
    _attempt++;
    _retry = Timer(delay > maxBackoff ? maxBackoff : delay, open);
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    // A socket that never finished its handshake may never acknowledge the close: don't hang shutdown.
    await _channel?.sink.close().timeout(const Duration(seconds: 1), onTimeout: () {});
    await _events.close();
    await _status.close();
    await _connected.close();
  }
}
