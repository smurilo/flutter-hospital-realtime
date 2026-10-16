import 'package:hive_ce/hive.dart';

import '../domain/entities.dart';

/// Last known board persisted in Hive: the panel opens instantly, even before the network answers.
class BedsCache {
  const BedsCache(this._box);

  final Box<dynamic> _box;

  static const boxName = 'beds_cache';

  Board? read() {
    final raw = _box.get('board') as Map<dynamic, dynamic>?;
    if (raw == null) return null;
    final beds = [for (final b in raw['beds'] as List) Bed.fromJson(b as Map<dynamic, dynamic>)];
    return Board(beds: {for (final b in beds) b.id: b}, seq: raw['seq'] as int);
  }

  Future<void> write(Board board) => _box.put('board', {
        'seq': board.seq,
        'beds': [for (final b in board.beds.values) b.toJson()],
      });
}
