import 'entities.dart';

/// Pure state machine of a bed. Invalid transitions (e.g. admitting into a dirty bed)
/// are ignored instead of corrupting the board.
Board applyEvent(Board board, BedEvent event) {
  final bed = board.beds[event.bedId];
  if (bed == null) return Board(beds: board.beds, seq: event.seq);
  final next = switch (event) {
    PatientAdmitted(:final initials) when bed.status == BedStatus.free =>
      bed.copyWith(status: BedStatus.occupied, patientInitials: () => initials, updatedAt: event.at),
    PatientDischarged() when bed.status == BedStatus.occupied =>
      // After discharge the bed must be sanitised before the next admission.
      bed.copyWith(status: BedStatus.cleaning, patientInitials: () => null, updatedAt: event.at),
    BedCleaned() when bed.status == BedStatus.cleaning || bed.status == BedStatus.blocked =>
      bed.copyWith(status: BedStatus.free, updatedAt: event.at),
    BedBlocked() when bed.status != BedStatus.occupied => bed.copyWith(status: BedStatus.blocked, updatedAt: event.at),
    _ => bed,
  };
  return Board(beds: {...board.beds, bed.id: next}, seq: event.seq);
}

class WardOccupancy {
  const WardOccupancy(
      {required this.ward, required this.total, required this.occupied, required this.free, required this.cleaning});

  final Ward ward;
  final int total;
  final int occupied;
  final int free;
  final int cleaning;

  /// Occupancy over operational beds (blocked beds are out of service).
  double get rate => total == 0 ? 0 : occupied / total;

  /// Hospital protocol: ICU above 90% triggers the contingency plan.
  bool get critical => ward == Ward.icu ? rate >= 0.9 : rate >= 0.95;
}

List<WardOccupancy> occupancyByWard(Iterable<Bed> beds) => [
      for (final ward in Ward.values)
        () {
          final inWard = beds.where((b) => b.ward == ward && b.status != BedStatus.blocked).toList();
          int count(BedStatus s) => inWard.where((b) => b.status == s).length;
          return WardOccupancy(
            ward: ward,
            total: inWard.length,
            occupied: count(BedStatus.occupied),
            free: count(BedStatus.free),
            cleaning: count(BedStatus.cleaning),
          );
        }(),
    ];
