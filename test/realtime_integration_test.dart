import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hospital_beds/core/result.dart';
import 'package:hospital_beds/features/beds/data/bed_repository_impl.dart';
import 'package:hospital_beds/features/beds/data/beds_cache.dart';
import 'package:hospital_beds/features/beds/data/beds_remote.dart';
import 'package:hospital_beds/features/beds/domain/entities.dart';

import '../tool/fake_server.dart';

/// Real HTTP + WebSocket against the local fake hospital server: no mocks in the transport.
void main() {
  late HospitalServer server;
  late BedRepositoryImpl repository;
  late Box<dynamic> box;
  late Directory dir;

  Future<Board> boardWhere(bool Function(Board) test) =>
      repository.watchBoard().firstWhere(test).timeout(const Duration(seconds: 5));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('beds');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>(BedsCache.boxName);
    server = await HospitalServer.start();
    repository = BedRepositoryImpl(
      BedsRestDataSource(Dio(BaseOptions(baseUrl: 'http://localhost:${server.port}'))),
      BedsSocketDataSource(Uri.parse('ws://localhost:${server.port}/ws'),
          initialBackoff: const Duration(milliseconds: 50)),
      BedsCache(box),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await server.stop();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('loads the snapshot and applies live events in order', () async {
    final initial = await boardWhere((b) => b.beds.isNotEmpty);
    expect(initial.beds, hasLength(46));

    final target = initial.beds.values.firstWhere((b) => b.status == BedStatus.occupied);
    server.apply('discharged', target.id);
    final updated = await boardWhere((b) => b.beds[target.id]!.status == BedStatus.cleaning);
    expect(updated.seq, initial.seq + 1);
  });

  test('detects lost events through the sequence gap and resyncs from REST', () async {
    final initial = await boardWhere((b) => b.beds.isNotEmpty);
    final occupied = initial.beds.values.where((b) => b.status == BedStatus.occupied).take(2).toList();

    // First event happens "while the message is lost": applied on the server but not broadcast.
    server.apply('discharged', occupied[0].id, broadcast: false);
    server.apply('discharged', occupied[1].id);

    final resynced = await boardWhere((b) => b.seq == initial.seq + 2);
    expect(resynced.beds[occupied[0].id]!.status, BedStatus.cleaning, reason: 'recovered by snapshot');
    expect(resynced.beds[occupied[1].id]!.status, BedStatus.cleaning);
  });

  test('reconnects after the connection drops and catches up', () async {
    final statuses = <ConnectionStatus>[];
    final sub = repository.connection.listen(statuses.add);
    final initial = await boardWhere((b) => b.beds.isNotEmpty);
    await repository.connection
        .firstWhere((s) => s == ConnectionStatus.live)
        .timeout(const Duration(seconds: 5), onTimeout: () => ConnectionStatus.live);

    await server.dropConnections();
    final bed = initial.beds.values.firstWhere((b) => b.status == BedStatus.free);
    server.apply('admitted', bed.id, patient: 'J.P.'); // happens while offline

    final after = await boardWhere((b) => b.beds[bed.id]!.status == BedStatus.occupied);
    expect(after.beds[bed.id]!.patientInitials, 'J.P.');
    expect(statuses, containsAllInOrder([ConnectionStatus.offline, ConnectionStatus.live]));
    await sub.cancel();
  });

  test('confirming cleaning goes through REST and the result arrives over WebSocket', () async {
    final initial = await boardWhere((b) => b.beds.isNotEmpty);
    final bed = initial.beds.values.firstWhere((b) => b.status == BedStatus.occupied);
    server.apply('discharged', bed.id);
    await boardWhere((b) => b.beds[bed.id]!.status == BedStatus.cleaning);

    expect(await repository.markCleaned(bed.id), isA<Ok<void>>());
    await boardWhere((b) => b.beds[bed.id]!.status == BedStatus.free);

    expect(await repository.markCleaned(bed.id), isA<Err<void>>(), reason: '409: bed is no longer awaiting cleaning');
  });

  test('cached board is shown immediately on the next start, before the network answers', () async {
    final live = await boardWhere((b) => b.beds.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 100)); // let the cache write finish
    await server.stop();

    final offlineRepository = BedRepositoryImpl(
      BedsRestDataSource(Dio(BaseOptions(baseUrl: 'http://localhost:1'))),
      BedsSocketDataSource(Uri.parse('ws://localhost:1/ws'), initialBackoff: const Duration(seconds: 10)),
      BedsCache(box),
    );
    final cached = await offlineRepository.watchBoard().first.timeout(const Duration(seconds: 2));
    expect(cached.beds.length, live.beds.length);
    await offlineRepository.dispose();
    server = await HospitalServer.start(); // for tearDown
  });
}
