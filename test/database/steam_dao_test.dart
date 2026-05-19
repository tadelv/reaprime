import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> workflowJson() => {
        'id': 'wf-1',
        'name': 'Test',
        'description': '',
        'profile': {
          'title': 'Test Profile',
          'author': 'Test',
          'notes': '',
          'beverage_type': 'espresso',
          'steps': [],
          'tank_temperature': 0.0,
          'target_weight': 36.0,
          'target_volume_count_start': 0,
          'version': '2',
        },
        'steamSettings': {
          'targetTemperature': 150,
          'duration': 50,
          'flow': 0.8,
          'stopAtTemperature': 65.0,
        },
        'hotWaterData': {
          'targetTemperature': 90,
          'duration': 15,
          'volume': 100,
          'flow': 4.0,
        },
        'rinseData': {'targetTemperature': 90, 'duration': 10, 'flow': 6.0},
      };

  SteamRecordsCompanion makeSteam({
    String id = 'steam-1',
    DateTime? timestamp,
    List<Map<String, dynamic>> measurements = const [],
  }) {
    return SteamRecordsCompanion(
      id: Value(id),
      timestamp: Value(timestamp ?? DateTime.parse('2026-05-18T12:00:00Z')),
      workflowJson: Value(workflowJson()),
      measurementsJson: Value(jsonEncode(measurements)),
    );
  }

  group('SteamDao - CRUD', () {
    test('inserts and retrieves a steam record', () async {
      await db.steamDao.insertSteam(makeSteam(measurements: [
        {
          'machine': {'placeholder': true},
          'milkTemperature': 50.0,
        }
      ]));
      final row = await db.steamDao.getSteamById('steam-1');
      expect(row, isNotNull);
      expect(row!.id, equals('steam-1'));
      expect(jsonDecode(row.measurementsJson), hasLength(1));
    });

    test('gets all steam ids', () async {
      await db.steamDao.insertSteam(makeSteam(id: 's1'));
      await db.steamDao.insertSteam(makeSteam(id: 's2'));
      final ids = await db.steamDao.getAllSteamIds();
      expect(ids, hasLength(2));
      expect(ids, containsAll(['s1', 's2']));
    });

    test('latest steam returns most recent', () async {
      await db.steamDao.insertSteam(makeSteam(
        id: 'older',
        timestamp: DateTime.parse('2026-05-18T11:00:00Z'),
      ));
      await db.steamDao.insertSteam(makeSteam(
        id: 'newer',
        timestamp: DateTime.parse('2026-05-18T13:00:00Z'),
      ));
      final latest = await db.steamDao.getLatestSteam();
      expect(latest?.id, equals('newer'));
    });

    test('latest steam meta omits measurements blob', () async {
      await db.steamDao.insertSteam(makeSteam(measurements: [
        {
          'machine': {'placeholder': true},
          'milkTemperature': 50.0,
        }
      ]));
      final meta = await db.steamDao.getLatestSteamMeta();
      expect(meta, isNotNull);
      expect(meta!.measurementsJson, equals('[]'));
    });

    test('deletes a steam record', () async {
      await db.steamDao.insertSteam(makeSteam());
      await db.steamDao.deleteSteam('steam-1');
      expect(await db.steamDao.getSteamById('steam-1'), isNull);
    });
  });
}
