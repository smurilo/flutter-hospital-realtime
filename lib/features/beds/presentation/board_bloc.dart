import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/result.dart';
import '../domain/bed_repository.dart';
import '../domain/board_logic.dart';
import '../domain/entities.dart';

sealed class BoardEvent {
  const BoardEvent();
}

final class BoardStarted extends BoardEvent {
  const BoardStarted();
}

final class WardSelected extends BoardEvent {
  const WardSelected(this.ward);
  final Ward ward;
}

final class CleaningConfirmed extends BoardEvent {
  const CleaningConfirmed(this.bedId);
  final String bedId;
}

class BoardState extends Equatable {
  const BoardState({this.board, this.ward = Ward.icu, this.connection = ConnectionStatus.connecting, this.message});

  final Board? board;
  final Ward ward;
  final ConnectionStatus connection;
  final String? message;

  List<Bed> get beds =>
      (board?.beds.values.where((b) => b.ward == ward).toList() ?? [])..sort((a, b) => a.code.compareTo(b.code));

  List<WardOccupancy> get occupancy => occupancyByWard(board?.beds.values ?? const []);

  BoardState copyWith({Board? board, Ward? ward, ConnectionStatus? connection, String? Function()? message}) =>
      BoardState(
        board: board ?? this.board,
        ward: ward ?? this.ward,
        connection: connection ?? this.connection,
        message: message != null ? message() : this.message,
      );

  @override
  List<Object?> get props => [board, ward, connection, message];
}

class BoardBloc extends Bloc<BoardEvent, BoardState> {
  BoardBloc(this._repository) : super(const BoardState()) {
    on<BoardStarted>((event, emit) async {
      // Two independent streams merged into the state; emit.forEach keeps them tied to the bloc lifecycle.
      await Future.wait([
        emit.forEach<Board>(_repository.watchBoard(), onData: (b) => state.copyWith(board: b)),
        emit.forEach<ConnectionStatus>(_repository.connection, onData: (c) => state.copyWith(connection: c)),
      ]);
    });
    on<WardSelected>((event, emit) => emit(state.copyWith(ward: event.ward)));
    on<CleaningConfirmed>((event, emit) async {
      emit(state.copyWith(message: () => null));
      final result = await _repository.markCleaned(event.bedId);
      if (result case Err(:final failure)) emit(state.copyWith(message: () => failure.message));
    });
  }

  final BedRepository _repository;
}
