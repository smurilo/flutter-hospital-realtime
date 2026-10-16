// Simulated hospital server: REST snapshot + WebSocket events.
// Run: dart run tool/fake_server.dart [port]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  final server =
      await HospitalServer.start(port: args.isEmpty ? 8080 : int.parse(args.first), tick: const Duration(seconds: 2));
  stdout.writeln('Servidor de leitos em http://localhost:${server.port}  (ws://localhost:${server.port}/ws)');
}

class HospitalServer {
  HospitalServer._(this._http, Duration? tick) {
    _seed();
    _http.listen(_handle);
    if (tick != null) _timer = Timer.periodic(tick, (_) => randomEvent());
  }

  static Future<HospitalServer> start({int port = 0, Duration? tick}) async =>
      HospitalServer._(await HttpServer.bind(InternetAddress.anyIPv4, port), tick);

  final HttpServer _http;
  final _sockets = <WebSocket>[];
  final _beds = <String, Map<String, Object?>>{};
  final _random = Random(7);
  Timer? _timer;
  int seq = 0;

  int get port => _http.port;

  void _seed() {
    const wards = {'icu': 10, 'emergency': 12, 'clinical': 16, 'pediatrics': 8};
    const prefix = {'icu': 'UTI', 'emergency': 'EM', 'clinical': 'CM', 'pediatrics': 'PED'};
    wards.forEach((ward, count) {
      for (var i = 1; i <= count; i++) {
        final id = '$ward-$i';
        final occupied = _random.nextDouble() < 0.75;
        _beds[id] = {
          'id': id,
          'ward': ward,
          'code': '${prefix[ward]}-${i.toString().padLeft(2, '0')}',
          'status': occupied ? 'occupied' : 'free',
          'patient': occupied ? _initials() : null,
          'updatedAt': DateTime.now().toIso8601String(),
        };
      }
    });
  }

  String _initials() => String.fromCharCodes([65 + _random.nextInt(26), 46, 65 + _random.nextInt(26), 46]);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen((_) {}, onDone: () => _sockets.remove(socket));
      return;
    }
    request.response.headers.contentType = ContentType.json;
    if (request.method == 'GET' && path == '/api/beds') {
      request.response.write(jsonEncode({'seq': seq, 'beds': _beds.values.toList()}));
    } else if (request.method == 'POST' && RegExp(r'^/api/beds/[\w-]+/cleaned$').hasMatch(path)) {
      final id = path.split('/')[3];
      if (_beds[id]?['status'] != 'cleaning') {
        request.response.statusCode = HttpStatus.conflict;
      } else {
        apply('cleaned', id);
        request.response.statusCode = HttpStatus.accepted;
      }
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  /// Applies an event to the server state and broadcasts it.
  void apply(String type, String bedId, {String? patient, bool broadcast = true}) {
    final bed = _beds[bedId]!;
    switch (type) {
      case 'admitted':
        bed['status'] = 'occupied';
        bed['patient'] = patient;
      case 'discharged':
        bed['status'] = 'cleaning';
        bed['patient'] = null;
      case 'cleaned':
        bed['status'] = 'free';
      case 'blocked':
        bed['status'] = 'blocked';
    }
    seq++;
    final event = jsonEncode(
        {'seq': seq, 'type': type, 'bedId': bedId, 'patient': patient, 'at': DateTime.now().toIso8601String()});
    if (broadcast) {
      for (final s in _sockets.where((s) => s.readyState == WebSocket.open)) {
        s.add(event);
      }
    }
  }

  void randomEvent() {
    final bed = _beds.values.elementAt(_random.nextInt(_beds.length));
    final id = bed['id']! as String;
    switch (bed['status']) {
      case 'free':
        apply('admitted', id, patient: _initials());
      case 'occupied':
        apply('discharged', id);
      case 'cleaning' || 'blocked':
        apply('cleaned', id);
    }
  }

  /// Simulates a network drop on the server side.
  Future<void> dropConnections() async {
    final open = [..._sockets];
    _sockets.clear();
    for (final s in open) {
      await s.close();
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    await dropConnections();
    await _http.close(force: true);
  }
}
