import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/shot_record.dart' as domain;
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart' as domain_workflow;
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/services/database/database.dart';
import 'package:reaprime/src/services/database/mappers/shot_mapper.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ShotRecordsCompanion makeShot({
    String id = 'shot-1',
    DateTime? timestamp,
    String profileTitle = 'Test Profile',
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    double? enjoyment,
    String? espressoNotes,
  }) {
    return ShotRecordsCompanion(
      id: Value(id),
      timestamp: Value(timestamp ?? DateTime.parse('2024-01-15T10:30:00Z')),
      profileTitle: Value(profileTitle),
      grinderModel: Value(grinderModel),
      beanBatchId: Value(beanBatchId),
      coffeeName: Value(coffeeName),
      coffeeRoaster: Value(coffeeRoaster),
      enjoyment: Value(enjoyment),
      espressoNotes: Value(espressoNotes),
      workflowJson: Value({
        'id': 'wf-1',
        'name': 'Test',
        'description': '',
        'profile': {
          'title': profileTitle,
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
        },
        'hotWaterData': {
          'targetTemperature': 90,
          'duration': 15,
          'volume': 100,
          'flow': 4.0,
        },
        'rinseData': {'targetTemperature': 90, 'duration': 10, 'flow': 6.0},
      }),
      measurementsJson: const Value('[]'),
    );
  }

  group('ShotDao - CRUD', () {
    test('inserts and retrieves a shot', () async {
      await db.shotDao.insertShot(makeShot());
      final shot = await db.shotDao.getShotById('shot-1');
      expect(shot, isNotNull);
      expect(shot!.id, 'shot-1');
      expect(shot.profileTitle, 'Test Profile');
    });

    test('gets all shot IDs', () async {
      await db.shotDao.insertShot(makeShot(id: 's1'));
      await db.shotDao.insertShot(makeShot(id: 's2'));
      final ids = await db.shotDao.getAllShotIds();
      expect(ids, hasLength(2));
      expect(ids, containsAll(['s1', 's2']));
    });

    test('gets all shots ordered by timestamp desc', () async {
      await db.shotDao.insertShot(
        makeShot(
          id: 's1',
          timestamp: DateTime.parse('2024-01-01T10:00:00Z'),
        ),
      );
      await db.shotDao.insertShot(
        makeShot(
          id: 's2',
          timestamp: DateTime.parse('2024-01-02T10:00:00Z'),
        ),
      );

      final shots = await db.shotDao.getAllShots();
      expect(shots.first.id, 's2'); // newer first
      expect(shots.last.id, 's1');
    });

    test('updates a shot', () async {
      await db.shotDao.insertShot(makeShot(espressoNotes: 'original'));
      await db.shotDao.updateShot(
        ShotRecordsCompanion(
          id: const Value('shot-1'),
          espressoNotes: const Value('updated'),
        ),
      );
      final shot = await db.shotDao.getShotById('shot-1');
      expect(shot!.espressoNotes, 'updated');
    });

    test('deletes a shot', () async {
      await db.shotDao.insertShot(makeShot());
      await db.shotDao.deleteShot('shot-1');
      final shot = await db.shotDao.getShotById('shot-1');
      expect(shot, isNull);
    });

    test('gets latest shot', () async {
      await db.shotDao.insertShot(
        makeShot(
          id: 's1',
          timestamp: DateTime.parse('2024-01-01T10:00:00Z'),
        ),
      );
      await db.shotDao.insertShot(
        makeShot(
          id: 's2',
          timestamp: DateTime.parse('2024-01-02T10:00:00Z'),
        ),
      );

      final latest = await db.shotDao.getLatestShot();
      expect(latest!.id, 's2');
    });

    test('upserts a shot', () async {
      await db.shotDao.upsertShot(makeShot(id: 's1', espressoNotes: 'first'));
      await db.shotDao.upsertShot(makeShot(id: 's1', espressoNotes: 'second'));

      final shots = await db.shotDao.getAllShots();
      expect(shots, hasLength(1));
      expect(shots.first.espressoNotes, 'second');
    });
  });

  group('ShotDao - Pagination & Filtering', () {
    test('paginates shots', () async {
      for (int i = 0; i < 10; i++) {
        await db.shotDao.insertShot(
          makeShot(
            id: 'shot-$i',
            timestamp: DateTime.parse(
              '2024-01-01T10:00:00Z',
            ).add(Duration(hours: i)),
          ),
        );
      }

      final page1 = await db.shotDao.getShotsPaginated(limit: 3, offset: 0);
      expect(page1, hasLength(3));
      expect(page1.first.id, 'shot-9'); // newest first

      final page2 = await db.shotDao.getShotsPaginated(limit: 3, offset: 3);
      expect(page2, hasLength(3));
    });

    test('filters by grinderModel', () async {
      await db.shotDao.insertShot(makeShot(id: 's1', grinderModel: 'Niche'));
      await db.shotDao.insertShot(makeShot(id: 's2', grinderModel: 'DF64'));
      await db.shotDao.insertShot(makeShot(id: 's3'));

      final filtered = await db.shotDao.getShotsPaginated(
        grinderModel: 'Niche',
      );
      expect(filtered, hasLength(1));
      expect(filtered.first.id, 's1');
    });

    test('filters by coffeeRoaster', () async {
      await db.shotDao.insertShot(makeShot(id: 's1', coffeeRoaster: 'Sey'));
      await db.shotDao.insertShot(makeShot(id: 's2', coffeeRoaster: 'Other'));

      final filtered = await db.shotDao.getShotsPaginated(coffeeRoaster: 'Sey');
      expect(filtered, hasLength(1));
      expect(filtered.first.id, 's1');
    });

    test('filters by multiple beanBatchIds', () async {
      await db.shotDao.insertShot(
        makeShot(
          id: 's1',
          beanBatchId: 'batch-a',
          timestamp: DateTime.parse('2024-01-01T10:00:00Z'),
        ),
      );
      await db.shotDao.insertShot(
        makeShot(
          id: 's2',
          beanBatchId: 'batch-b',
          timestamp: DateTime.parse('2024-01-02T10:00:00Z'),
        ),
      );
      await db.shotDao.insertShot(
        makeShot(
          id: 's3',
          beanBatchId: 'batch-c',
          timestamp: DateTime.parse('2024-01-03T10:00:00Z'),
        ),
      );
      await db.shotDao.insertShot(makeShot(id: 's4'));

      final filtered = await db.shotDao.getShotsPaginated(
        beanBatchIds: ['batch-a', 'batch-b'],
      );
      expect(filtered.map((shot) => shot.id), ['s2', 's1']);

      final total = await db.shotDao.countShots(
        beanBatchIds: ['batch-a', 'batch-b'],
      );
      expect(total, 2);
    });

    test('empty beanBatchIds match no shots', () async {
      await db.shotDao.insertShot(makeShot(id: 's1', beanBatchId: 'batch-a'));

      final filtered = await db.shotDao.getShotsPaginated(beanBatchIds: []);
      expect(filtered, isEmpty);

      final total = await db.shotDao.countShots(beanBatchIds: []);
      expect(total, 0);
    });

    test('filters by profileTitle', () async {
      await db.shotDao.insertShot(
        makeShot(id: 's1', profileTitle: 'Blooming Espresso'),
      );
      await db.shotDao.insertShot(makeShot(id: 's2', profileTitle: 'Rao'));

      final filtered = await db.shotDao.getShotsPaginated(
        profileTitle: 'Blooming Espresso',
      );
      expect(filtered, hasLength(1));
    });

    test('counts shots with filters', () async {
      await db.shotDao.insertShot(makeShot(id: 's1', coffeeRoaster: 'Sey'));
      await db.shotDao.insertShot(makeShot(id: 's2', coffeeRoaster: 'Sey'));
      await db.shotDao.insertShot(makeShot(id: 's3', coffeeRoaster: 'Other'));

      final total = await db.shotDao.countShots();
      expect(total, 3);

      final filtered = await db.shotDao.countShots(coffeeRoaster: 'Sey');
      expect(filtered, 2);
    });
  });

  group('ShotDao - Measurements', () {
    test('stores and retrieves measurements JSON', () async {
      final measurements = [
        {
          'machine': {
            'timestamp': '2024-01-15T10:30:01Z',
            'pressure': 9.0,
            'flow': 2.0,
            'state': {'state': 'espresso', 'substate': 'pouring'},
          },
        },
      ];

      await db.shotDao.insertShot(
        ShotRecordsCompanion(
          id: const Value('shot-m'),
          timestamp: Value(DateTime.parse('2024-01-15T10:30:00Z')),
          workflowJson: Value({
            'id': 'wf-1',
            'name': 'T',
            'description': '',
            'profile': {
              'title': 'T',
              'author': 'T',
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
            },
            'hotWaterData': {
              'targetTemperature': 90,
              'duration': 15,
              'volume': 100,
              'flow': 4.0,
            },
            'rinseData': {'targetTemperature': 90, 'duration': 10, 'flow': 6.0},
          }),
          measurementsJson: Value(jsonEncode(measurements)),
        ),
      );

      final shot = await db.shotDao.getShotById('shot-m');
      final decoded = jsonDecode(shot!.measurementsJson) as List;
      expect(decoded, hasLength(1));
      expect((decoded.first as Map)['machine']['pressure'], 9.0);
    });
  });

  group('ShotDao - probeTemperature', () {
    MachineSnapshot machineSnapshot() => MachineSnapshot(
      timestamp: DateTime.parse('2024-01-15T10:30:01Z'),
      state: const MachineStateSnapshot(
        state: MachineState.espresso,
        substate: MachineSubstate.pouring,
      ),
      flow: 2.0,
      pressure: 9.0,
      targetFlow: 2.0,
      targetPressure: 9.0,
      mixTemperature: 92.0,
      groupTemperature: 92.0,
      targetMixTemperature: 92.0,
      targetGroupTemperature: 92.0,
      profileFrame: 0,
      steamTemperature: 0,
    );

    Map<String, dynamic> workflowJson() => {
      'id': 'wf-1',
      'name': 'Test',
      'description': '',
      'profile': {
        'title': 'Test Profile',
        'author': 'Test',
        'notes': '',
        'beverage_type': 'espresso',
        'steps': [
          {
            'name': 'pour',
            'pump': 'pressure',
            'transition': 'fast',
            'volume': 100,
            'seconds': 30,
            'temperature': 93,
            'sensor': 'coffee',
            'pressure': 9,
          },
        ],
        'tank_temperature': 93.0,
        'target_weight': 36.0,
        'target_volume_count_start': 0,
        'version': '2',
      },
      'steamSettings': {
        'targetTemperature': 150,
        'duration': 50,
        'flow': 0.8,
      },
      'hotWaterData': {
        'targetTemperature': 90,
        'duration': 15,
        'volume': 100,
        'flow': 4.0,
      },
      'rinseData': {'targetTemperature': 90, 'duration': 10, 'flow': 6.0},
    };

    test(
      'migration-on-read: legacy measurements without probeTemperature',
      () async {
        final legacyMeasurements = [
          {
            'machine': machineSnapshot().toJson(),
            'volume': 40.0,
          },
        ];

        await db.shotDao.insertShot(
          ShotRecordsCompanion(
            id: const Value('shot-legacy'),
            timestamp: Value(DateTime.parse('2024-01-15T10:30:00Z')),
            workflowJson: Value(workflowJson()),
            measurementsJson: Value(jsonEncode(legacyMeasurements)),
          ),
        );

        final row = await db.shotDao.getShotById('shot-legacy');
        final record = ShotMapper.fromRow(row!);
        expect(record.measurements, hasLength(1));
        expect(record.measurements.first.probeTemperature, isNull);
        expect(record.measurements.first.volume, equals(40.0));
      },
    );

    test('round-trips shot with probeTemperature via ShotMapper', () async {
      final record = domain.ShotRecord(
        id: 'shot-probe',
        timestamp: DateTime.parse('2024-01-15T10:30:00Z'),
        workflow: domain_workflow.Workflow.fromJson(workflowJson()),
        measurements: [
          ShotSnapshot(
            machine: machineSnapshot(),
            probeTemperature: 93.2,
          ),
          ShotSnapshot(
            machine: machineSnapshot(),
            probeTemperature: 94.1,
          ),
        ],
      );

      await db.shotDao.insertShot(ShotMapper.toCompanion(record));
      final row = await db.shotDao.getShotById('shot-probe');
      final restored = ShotMapper.fromRow(row!);

      expect(restored.measurements, hasLength(2));
      expect(restored.measurements.first.probeTemperature, equals(93.2));
      expect(restored.measurements.last.probeTemperature, equals(94.1));
    });

    test('round-trips shot without probeTemperature via ShotMapper', () async {
      final record = domain.ShotRecord(
        id: 'shot-no-probe',
        timestamp: DateTime.parse('2024-01-15T10:30:00Z'),
        workflow: domain_workflow.Workflow.fromJson(workflowJson()),
        measurements: [
          ShotSnapshot(machine: machineSnapshot()),
        ],
      );

      await db.shotDao.insertShot(ShotMapper.toCompanion(record));
      final row = await db.shotDao.getShotById('shot-no-probe');
      final restored = ShotMapper.fromRow(row!);

      expect(restored.measurements.single.probeTemperature, isNull);
      final decoded = jsonDecode(row.measurementsJson) as List;
      expect((decoded.single as Map)['probeTemperature'], isNull);
    });
  });
}
