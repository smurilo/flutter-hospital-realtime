import 'package:equatable/equatable.dart';

enum BedStatus { free, occupied, cleaning, blocked }

enum Ward {
  icu('UTI'),
  emergency('Emergência'),
  clinical('Clínica Médica'),
  pediatrics('Pediatria');

  const Ward(this.label);
  final String label;
}

class Bed extends Equatable {
  const Bed(
      {required this.id,
      required this.ward,
      required this.code,
      required this.status,
      this.patientInitials,
      this.updatedAt});

  final String id;
  final Ward ward;
  final String code;
  final BedStatus status;

  /// Only initials leave the hospital system (LGPD / patient privacy).
  final String? patientInitials;
  final DateTime? updatedAt;

  Bed copyWith({BedStatus? status, String? Function()? patientInitials, DateTime? updatedAt}) => Bed(
        id: id,
        ward: ward,
        code: code,
        status: status ?? this.status,
        patientInitials: patientInitials != null ? patientInitials() : this.patientInitials,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'ward': ward.name,
        'code': code,
        'status': status.name,
        'patient': patientInitials,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory Bed.fromJson(Map<dynamic, dynamic> j) => Bed(
        id: j['id'] as String,
        ward: Ward.values.byName(j['ward'] as String),
        code: j['code'] as String,
        status: BedStatus.values.byName(j['status'] as String),
        patientInitials: j['patient'] as String?,
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String),
      );

  @override
  List<Object?> get props => [id, ward, code, status, patientInitials, updatedAt];
}

/// Real-time events pushed by the hospital server over WebSocket.
sealed class BedEvent extends Equatable {
  const BedEvent({required this.seq, required this.bedId, required this.at});

  /// Monotonic sequence number: a gap means events were lost and a resync is needed.
  final int seq;
  final String bedId;
  final DateTime at;

  static BedEvent fromJson(Map<String, dynamic> j) {
    final seq = j['seq'] as int;
    final bedId = j['bedId'] as String;
    final at = DateTime.parse(j['at'] as String);
    return switch (j['type']) {
      'admitted' => PatientAdmitted(seq: seq, bedId: bedId, at: at, initials: j['patient'] as String),
      'discharged' => PatientDischarged(seq: seq, bedId: bedId, at: at),
      'cleaned' => BedCleaned(seq: seq, bedId: bedId, at: at),
      'blocked' => BedBlocked(seq: seq, bedId: bedId, at: at),
      final other => throw FormatException('Evento desconhecido: $other'),
    };
  }

  @override
  List<Object?> get props => [seq, bedId, at];
}

final class PatientAdmitted extends BedEvent {
  const PatientAdmitted({required super.seq, required super.bedId, required super.at, required this.initials});
  final String initials;
}

final class PatientDischarged extends BedEvent {
  const PatientDischarged({required super.seq, required super.bedId, required super.at});
}

final class BedCleaned extends BedEvent {
  const BedCleaned({required super.seq, required super.bedId, required super.at});
}

final class BedBlocked extends BedEvent {
  const BedBlocked({required super.seq, required super.bedId, required super.at});
}

class Board extends Equatable {
  const Board({required this.beds, required this.seq});

  final Map<String, Bed> beds;

  /// Sequence number of the last event applied.
  final int seq;

  @override
  List<Object?> get props => [beds, seq];
}

enum ConnectionStatus { connecting, live, reconnecting, offline }
