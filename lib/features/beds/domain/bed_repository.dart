import '../../../core/result.dart';
import 'entities.dart';

abstract interface class BedRepository {
  /// Board updates: cached snapshot first, then server snapshot, then live events.
  Stream<Board> watchBoard();

  Stream<ConnectionStatus> get connection;

  Future<Result<void>> markCleaned(String bedId);

  Future<void> dispose();
}
