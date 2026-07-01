import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:reaprime/src/controllers/steam_sequencer.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/device/impl/combustion/mock_combustion_probe.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/services/database/database.dart';
import 'package:reaprime/src/services/storage/drift_storage_service.dart';

import '../helpers/mock_settings_service.dart';

/// Integration tier: wires real [De1Controller], [SensorController],
/// [PersistenceController], and [SteamSequencer] with [MockDe1] and
/// [MockCombustionProbe]. Documents FR-S1 (app-side stop-at-temperature)
/// and FR-S3 ([SteamSnapshot.milkTemperature] from probe readings).
class _EmptyDiscovery extends DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanForDevices({ScanFilter? filter}) async {}
}

void main() {
  group('Combustion steam stop integration', () {
    late AppDatabase db;
    late DriftStorageService storage;
    late PersistenceController persistence;
    late De1Controller de1Controller;
    late SensorController sensors;
    late WorkflowController workflow;
    late MockSettingsService settingsService;
    late SteamSequencer sequencer;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      storage = DriftStorageService(db);
      persistence = PersistenceController(storageService: storage);
      final emptyController = DeviceController([_EmptyDiscovery()]);
      await emptyController.initialize();
      de1Controller = De1Controller(controller: emptyController);
      sensors = SensorController(controller: emptyController);
      workflow = WorkflowController();
      settingsService = MockSettingsService();
      sequencer = SteamSequencer(
        de1Controller: de1Controller,
        sensorController: sensors,
        workflowController: workflow,
        persistenceController: persistence,
        settingsService: settingsService,
      );
    });

    tearDown(() async {
      await sequencer.dispose();
      sensors.dispose();
      persistence.dispose();
      await db.close();
    });

    Future<void> waitForState(
      MockDe1 machine,
      MachineState state, {
      Duration within = const Duration(seconds: 12),
    }) async {
      await machine.currentSnapshot
          .firstWhere((s) => s.state.state == state)
          .timeout(within);
      await Future<void>.delayed(Duration.zero);
    }

    test(
      'FR-S1/S3: stop-at-temperature requests idle and persists milkTemperature',
      () async {
        workflow.updateWorkflow(
          steamSettings: workflow.currentWorkflow.steamSettings
              .copyWith(stopAtTemperature: 60.0),
        );

        final machine = MockDe1();
        await de1Controller.connectToDe1(machine);

        final probe = MockCombustionProbe();
        await probe.onConnect();
        await sensors.register(probe);
        await settingsService.setPreferredSteamProbeId(probe.deviceId);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await machine.requestState(MachineState.steam);
        await waitForState(machine, MachineState.steam);

        probe.setTemperature(45.0);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        probe.setTemperature(62.0);
        await waitForState(machine, MachineState.idle);

        final record = await storage.getLatestSteam();
        expect(record, isNotNull);
        expect(record!.measurements, isNotEmpty);
        final withTemp =
            record.measurements.where((m) => m.milkTemperature != null);
        expect(withTemp, isNotEmpty,
            reason: 'FR-S3: milkTemperature populated from probe');
        expect(withTemp.last.milkTemperature, closeTo(62.0, 0.1));

        await probe.disconnect();
        await machine.disconnect();
      },
    );

    test('probe disconnect mid-steam does not false-stop at temperature',
        () async {
      workflow.updateWorkflow(
        steamSettings: workflow.currentWorkflow.steamSettings
            .copyWith(stopAtTemperature: 60.0),
      );

      final machine = MockDe1();
      await de1Controller.connectToDe1(machine);

      final probe = MockCombustionProbe();
      await probe.onConnect();
      await sensors.register(probe);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await machine.requestState(MachineState.steam);
      await waitForState(machine, MachineState.steam);

      probe.setTemperature(40.0);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await probe.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final snapshot = await machine.currentSnapshot.first;
      expect(
        snapshot.state.state,
        MachineState.steam,
        reason: 'probeLost must disable app-side stop; machine stays steaming',
      );

      await machine.requestState(MachineState.idle);
      await waitForState(machine, MachineState.idle);

      await machine.disconnect();
    });
  });
}
