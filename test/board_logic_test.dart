import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_beds/features/beds/domain/board_logic.dart';
import 'package:hospital_beds/features/beds/domain/entities.dart';

Bed bed(String id, BedStatus status, {Ward ward = Ward.icu}) => Bed(id: id, ward: ward, code: id, status: status);

Board board(List<Bed> beds, {int seq = 0}) => Board(beds: {for (final b in beds) b.id: b}, seq: seq);

void main() {
  final at = DateTime(2026, 3, 2, 10);

  test('follows the bed lifecycle: admit → discharge → cleaning → free', () {
    var b = board([bed('a', BedStatus.free)]);
    b = applyEvent(b, PatientAdmitted(seq: 1, bedId: 'a', at: at, initials: 'M.S.'));
    expect(b.beds['a']!.status, BedStatus.occupied);
    expect(b.beds['a']!.patientInitials, 'M.S.');

    b = applyEvent(b, PatientDischarged(seq: 2, bedId: 'a', at: at));
    expect(b.beds['a']!.status, BedStatus.cleaning);
    expect(b.beds['a']!.patientInitials, isNull);

    b = applyEvent(b, BedCleaned(seq: 3, bedId: 'a', at: at));
    expect(b.beds['a']!.status, BedStatus.free);
    expect(b.seq, 3);
  });

  test('rejects invalid transitions (no admission into a bed awaiting cleaning)', () {
    final b =
        applyEvent(board([bed('a', BedStatus.cleaning)]), PatientAdmitted(seq: 1, bedId: 'a', at: at, initials: 'X'));
    expect(b.beds['a']!.status, BedStatus.cleaning);
    expect(b.seq, 1);
  });

  test('occupancy ignores blocked beds and flags critical ICU at 90%', () {
    final beds = [
      for (var i = 0; i < 9; i++) bed('o$i', BedStatus.occupied),
      bed('f', BedStatus.free),
      bed('x', BedStatus.blocked),
      bed('c1', BedStatus.cleaning, ward: Ward.clinical),
      bed('c2', BedStatus.occupied, ward: Ward.clinical),
    ];
    final icu = occupancyByWard(beds).firstWhere((o) => o.ward == Ward.icu);
    expect(icu.total, 10);
    expect(icu.rate, 0.9);
    expect(icu.critical, isTrue);
    final clinical = occupancyByWard(beds).firstWhere((o) => o.ward == Ward.clinical);
    expect(clinical.cleaning, 1);
    expect(clinical.critical, isFalse);
  });

  test('parses server events and rejects unknown types', () {
    final e =
        BedEvent.fromJson({'seq': 5, 'type': 'admitted', 'bedId': 'a', 'patient': 'A.B.', 'at': at.toIso8601String()});
    expect(e, isA<PatientAdmitted>().having((x) => x.initials, 'initials', 'A.B.'));
    expect(() => BedEvent.fromJson({'seq': 6, 'type': 'teleported', 'bedId': 'a', 'at': at.toIso8601String()}),
        throwsFormatException);
  });
}
