import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_beds/core/result.dart';
import 'package:hospital_beds/features/beds/domain/bed_repository.dart';
import 'package:hospital_beds/features/beds/domain/entities.dart';
import 'package:hospital_beds/features/beds/presentation/board_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements BedRepository {}

void main() {
  const icuBed = Bed(id: 'a', ward: Ward.icu, code: 'UTI-01', status: BedStatus.cleaning);
  const pedBed = Bed(id: 'b', ward: Ward.pediatrics, code: 'PED-01', status: BedStatus.free);
  final board = const Board(beds: {'a': icuBed, 'b': pedBed}, seq: 1);
  late _MockRepository repo;

  setUp(() {
    repo = _MockRepository();
    when(() => repo.watchBoard()).thenAnswer((_) => Stream.value(board));
    when(() => repo.connection).thenAnswer((_) => Stream.value(ConnectionStatus.live));
  });

  blocTest<BoardBloc, BoardState>(
    'combines board and connection streams and filters by ward',
    build: () => BoardBloc(repo),
    act: (bloc) async {
      bloc.add(const BoardStarted());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const WardSelected(Ward.pediatrics));
    },
    verify: (bloc) {
      expect(bloc.state.connection, ConnectionStatus.live);
      expect(bloc.state.beds.map((b) => b.code), ['PED-01']);
    },
  );

  blocTest<BoardBloc, BoardState>(
    'surfaces a message when confirming cleaning fails',
    setUp: () => when(() => repo.markCleaned('a')).thenAnswer((_) async => const Err(NetworkFailure('falhou'))),
    build: () => BoardBloc(repo),
    act: (bloc) => bloc.add(const CleaningConfirmed('a')),
    verify: (bloc) => expect(bloc.state.message, 'falhou'),
  );
}
