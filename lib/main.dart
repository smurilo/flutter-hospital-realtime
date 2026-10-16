import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'features/beds/data/bed_repository_impl.dart';
import 'features/beds/data/beds_cache.dart';
import 'features/beds/data/beds_remote.dart';
import 'features/beds/presentation/board_bloc.dart';
import 'features/beds/presentation/board_page.dart';

/// Android emulator reaches the host machine through 10.0.2.2 (run `dart run tool/fake_server.dart`).
const _host = String.fromEnvironment('BEDS_HOST', defaultValue: '10.0.2.2:8080');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<dynamic>(BedsCache.boxName);

  final repository = BedRepositoryImpl(
    BedsRestDataSource(Dio(BaseOptions(baseUrl: 'http://$_host', connectTimeout: const Duration(seconds: 5)))),
    BedsSocketDataSource(Uri.parse('ws://$_host/ws')),
    BedsCache(box),
  );

  runApp(MaterialApp(
    title: 'Painel de Leitos',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0D47A1), useMaterial3: true),
    home: BlocProvider(create: (_) => BoardBloc(repository)..add(const BoardStarted()), child: const BoardPage()),
  ));
}
