import 'dart:async';

import '../../../core/result.dart';
import '../domain/bed_repository.dart';
import '../domain/board_logic.dart';
import '../domain/entities.dart';
import 'beds_cache.dart';
import 'beds_remote.dart';

/// Merges cache, REST snapshot and WebSocket events into one consistent board.
///
/// Consistency rule: events carry a sequence number. Events older than the snapshot are
/// dropped; a gap (missed events while disconnected) triggers a fresh snapshot.
class BedRepositoryImpl implements BedRepository {
  BedRepositoryImpl(this._rest, this._socket, this._cache);

  final BedsRestDataSource _rest;
  final BedsSocketDataSource _socket;
  final BedsCache _cache;

  final _board = StreamController<Board>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  Board? _current;
  bool _resyncing = false;

  @override
  Stream<ConnectionStatus> get connection => _socket.status;

  @override
  Stream<Board> watchBoard() {
    if (_subscriptions.isEmpty) _start();
    return Stream.multi((controller) {
      if (_current != null) controller.add(_current!);
      final sub = _board.stream.listen(controller.add);
      controller.onCancel = sub.cancel;
    });
  }

  void _start() {
    final cached = _cache.read();
    if (cached != null) _emit(cached, persist: false);
    _subscriptions
      ..add(_socket.connected.listen((_) => _resync()))
      ..add(_socket.events.listen(_onEvent));
    _socket.open();
  }

  Future<void> _resync() async {
    if (_resyncing) return;
    _resyncing = true;
    try {
      _emit(await _rest.snapshot());
    } catch (_) {
      // Keep showing the last known board; the socket's reconnect loop will try again.
    } finally {
      _resyncing = false;
    }
  }

  void _onEvent(BedEvent event) {
    final board = _current;
    if (board == null || _resyncing) return;
    if (event.seq <= board.seq) return; // duplicate or already in the snapshot
    if (event.seq > board.seq + 1) {
      _resync(); // lost events: rebuild from the source of truth
      return;
    }
    _emit(applyEvent(board, event));
  }

  void _emit(Board board, {bool persist = true}) {
    _current = board;
    _board.add(board);
    if (persist) unawaited(_cache.write(board));
  }

  @override
  Future<Result<void>> markCleaned(String bedId) async {
    try {
      await _rest.markCleaned(bedId);
      return const Ok(null); // the confirmation arrives as a 'cleaned' event over the socket
    } catch (_) {
      return const Err(NetworkFailure('Não foi possível registrar a higienização.'));
    }
  }

  @override
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _socket.close();
    await _board.close();
  }
}
