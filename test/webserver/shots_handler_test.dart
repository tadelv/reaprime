import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/services/database/database.dart'
    hide Bean, ShotRecord;
import 'package:reaprime/src/services/storage/drift_bean_storage.dart';
import 'package:reaprime/src/services/storage/drift_storage_service.dart';
import 'package:reaprime/src/services/webserver/shots_handler.dart';
import 'package:shelf_plus/shelf_plus.dart';

void main() {
  late AppDatabase db;
  late DriftBeanStorageService beanStorage;
  late PersistenceController persistence;
  late Handler handler;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    beanStorage = DriftBeanStorageService(db);
    persistence = PersistenceController(
      storageService: DriftStorageService(db),
    );
    final shotsHandler = ShotsHandler(
      controller: persistence,
      beanStorage: beanStorage,
    );
    final app = Router().plus;
    shotsHandler.addRoutes(app);
    handler = app.call;
  });

  tearDown(() async {
    persistence.dispose();
    await db.close();
  });

  Future<Response> sendGet(String path) async =>
      handler(Request('GET', Uri.parse('http://localhost$path')));

  Future<Response> sendPut(String path, Map<String, dynamic> body) async =>
      handler(
        Request(
          'PUT',
          Uri.parse('http://localhost$path'),
          body: jsonEncode(body),
          headers: {'content-type': 'application/json'},
        ),
      );

  group('ShotsHandler', () {
    test('GET /api/v1/shots/<id> returns probeTemperature in measurements',
        () async {
      final snapshot = ShotSnapshot(
        machine: _machineSnapshot(),
        probeTemperature: 93.5,
      );
      await persistence.persistShot(
        makeShot(id: 'probe-shot', measurements: [snapshot]),
      );

      final response = await sendGet('/api/v1/shots/probe-shot');
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final measurements = body['measurements'] as List;
      expect(measurements, hasLength(1));
      expect(
        (measurements.first as Map)['probeTemperature'],
        equals(93.5),
      );
    });

    test('PUT /api/v1/shots/<id> returns probeTemperature in measurements',
        () async {
      final snapshot = ShotSnapshot(
        machine: _machineSnapshot(),
        probeTemperature: 91.2,
      );
      await persistence.persistShot(
        makeShot(id: 'probe-put', measurements: [snapshot]),
      );

      final response = await sendPut('/api/v1/shots/probe-put', {
        'annotations': {'espressoNotes': 'bright'},
      });
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final measurements = body['measurements'] as List;
      expect(measurements, hasLength(1));
      expect(
        (measurements.first as Map)['probeTemperature'],
        equals(91.2),
      );
    });

    test('GET /api/v1/shots filters by beanId across all batches', () async {
      final bean = Bean.create(roaster: 'Old roaster', name: 'Old name');
      final otherBean = Bean.create(roaster: 'Other', name: 'Coffee');
      await beanStorage.insertBean(bean);
      await beanStorage.insertBean(otherBean);
      final firstBatch = BeanBatch.create(beanId: bean.id);
      final secondBatch = BeanBatch.create(beanId: bean.id);
      final otherBatch = BeanBatch.create(beanId: otherBean.id);
      await beanStorage.insertBatch(firstBatch);
      await beanStorage.insertBatch(secondBatch);
      await beanStorage.insertBatch(otherBatch);

      await persistence.persistShot(
        makeShot(
          id: 's1',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          beanBatchId: firstBatch.id,
          coffeeName: 'Old name',
          coffeeRoaster: 'Old roaster',
        ),
      );
      await persistence.persistShot(
        makeShot(
          id: 's2',
          timestamp: DateTime.utc(2026, 1, 2, 10),
          beanBatchId: secondBatch.id,
          coffeeName: 'Renamed coffee',
          coffeeRoaster: 'Renamed roaster',
        ),
      );
      await persistence.persistShot(
        makeShot(
          id: 's3',
          timestamp: DateTime.utc(2026, 1, 3, 10),
          beanBatchId: otherBatch.id,
          coffeeName: 'Other',
          coffeeRoaster: 'Coffee',
        ),
      );
      await beanStorage.updateBean(
        bean.copyWith(
          roaster: 'Renamed roaster',
          name: 'Renamed coffee',
        ),
      );

      final response = await sendGet('/api/v1/shots?beanId=${bean.id}');
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['total'], 2);
      expect(
        (body['items'] as List).map((item) => item['id']).toList(),
        ['s2', 's1'],
      );
    });

    test(
      'GET /api/v1/shots with unknown beanId returns an empty page',
      () async {
        await persistence.persistShot(
          makeShot(
            id: 's1',
            beanBatchId: 'batch-a',
            coffeeName: 'Name',
            coffeeRoaster: 'Roaster',
          ),
        );

        final response = await sendGet('/api/v1/shots?beanId=missing');
        expect(response.statusCode, 200);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['total'], 0);
        expect(body['items'], isEmpty);
      },
    );
  });
}

MachineSnapshot _machineSnapshot() => MachineSnapshot(
      timestamp: DateTime.utc(2026, 7, 1, 12, 0, 0),
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

ShotRecord makeShot({
  required String id,
  DateTime? timestamp,
  String? beanBatchId,
  String? coffeeName,
  String? coffeeRoaster,
  List<ShotSnapshot> measurements = const [],
}) {
  final workflow = WorkflowController().currentWorkflow.copyWith(
    context: WorkflowContext(
      beanBatchId: beanBatchId,
      coffeeName: coffeeName,
      coffeeRoaster: coffeeRoaster,
    ),
  );
  return ShotRecord(
    id: id,
    timestamp: timestamp ?? DateTime.utc(2026, 1, 1, 10),
    measurements: measurements,
    workflow: workflow,
  );
}
