import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:reaprime/src/controllers/shot_sequencer.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/steam_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart' as device_scale;
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/realtime_shot_feature/realtime_shot_feature.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_settings_service.dart';
import '../helpers/test_de1.dart';
import '../helpers/test_scale.dart';

class _FakeDiscoveryService extends device.DeviceDiscoveryService {
  @override
  Stream<List<device.Device>> get devices => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices({ScanFilter? filter}) async {}
}

class _TestDe1Controller extends De1Controller {
  final TestDe1 testDe1;

  _TestDe1Controller(this.testDe1)
    : super(controller: DeviceController([_FakeDiscoveryService()]));

  @override
  De1Interface connectedDe1() => testDe1;

  @override
  Stream<De1Interface?> get de1 => BehaviorSubject.seeded(testDe1).stream;
}

class _TestScaleController extends ScaleController {
  final TestScale testScale;
  final BehaviorSubject<device.ConnectionState> _connectionState;
  final BehaviorSubject<WeightSnapshot> _weight = BehaviorSubject();

  _TestScaleController(this.testScale)
    : _connectionState = BehaviorSubject.seeded(
        device.ConnectionState.disconnected,
      );

  @override
  Stream<device.ConnectionState> get connectionState => _connectionState.stream;

  @override
  device.ConnectionState get currentConnectionState => _connectionState.value;

  @override
  Stream<WeightSnapshot> get weightSnapshot => _weight.stream;

  @override
  device_scale.Scale connectedScale() {
    if (_connectionState.value != device.ConnectionState.connected) {
      throw 'No scale connected';
    }
    return testScale;
  }

  void emitWeight(double weight, {double weightFlow = 0.0}) {
    _weight.add(
      WeightSnapshot(
        timestamp: DateTime(2026, 1, 15, 8, 0),
        weight: weight,
        weightFlow: weightFlow,
      ),
    );
  }
}

class _NullStorageService implements StorageService {
  @override
  Future<void> storeShot(ShotRecord record) async {}
  @override
  Future<void> updateShot(ShotRecord record) async {}
  @override
  Future<void> deleteShot(String id) async {}
  @override
  Future<List<String>> getShotIds() async => [];
  @override
  Future<List<ShotRecord>> getAllShots() async => [];
  @override
  Future<ShotRecord?> getShot(String id) async => null;
  @override
  Future<void> storeCurrentWorkflow(Workflow workflow) async {}
  @override
  Future<Workflow?> loadCurrentWorkflow() async => null;
  @override
  Future<List<ShotRecord>> getShotsPaginated({
    int limit = 20,
    int offset = 0,
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    List<String>? beanBatchIds,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
    bool ascending = false,
  }) async => [];
  @override
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    List<String>? beanBatchIds,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
  }) async => 0;
  @override
  Future<ShotRecord?> getLatestShot() async => null;
  @override
  Future<ShotRecord?> getLatestShotMeta() async => null;
  @override
  Future<void> storeSteam(SteamRecord record) async {}
  @override
  Future<void> updateSteam(SteamRecord record) async {}
  @override
  Future<void> deleteSteam(String id) async {}
  @override
  Future<List<String>> getSteamIds() async => [];
  @override
  Future<List<SteamRecord>> getAllSteams() async => [];
  @override
  Future<SteamRecord?> getSteam(String id) async => null;
  @override
  Future<SteamRecord?> getLatestSteam() async => null;
  @override
  Future<SteamRecord?> getLatestSteamMeta() async => null;
}

class _ProbeTestSensor implements Sensor {
  @override
  String get deviceId => 'test-probe';

  @override
  String get name => 'ProbeTestSensor';

  @override
  device.DeviceType get type => device.DeviceType.sensor;

  final BehaviorSubject<Map<String, dynamic>> _data = BehaviorSubject();

  @override
  Stream<Map<String, dynamic>> get data => _data.stream;

  final BehaviorSubject<device.ConnectionState> _connection =
      BehaviorSubject.seeded(device.ConnectionState.connected);

  @override
  Stream<device.ConnectionState> get connectionState => _connection.stream;

  @override
  SensorInfo get info => SensorInfo(
    name: name,
    vendor: 'test',
    dataChannels: const [],
    commands: const [],
  );

  @override
  Future<Map<String, dynamic>> execute(
    String command,
    Map<String, dynamic>? params,
  ) async => const {};

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> disconnect() async {}

  void emitTemperature(double celsius) {
    _data.add({
      'timestamp': DateTime(2026, 1, 15, 8, 0).toIso8601String(),
      'temperature': celsius,
    });
  }

  void dispose() {
    _data.close();
    _connection.close();
  }
}

Profile _simpleProfile() {
  return Profile(
    version: '2',
    title: 'Test Profile',
    notes: '',
    author: 'test',
    beverageType: BeverageType.espresso,
    targetVolumeCountStart: 0,
    tankTemperature: 0,
    targetWeight: 36,
    steps: [
      ProfileStepPressure(
        name: 'step1',
        transition: TransitionType.fast,
        volume: 0,
        seconds: 30,
        temperature: 93,
        sensor: TemperatureSensor.coffee,
        pressure: 9,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RealtimeShotFeature probe display', () {
    late TestDe1 testDe1;
    late TestScale testScale;
    late _TestDe1Controller de1Controller;
    late _TestScaleController scaleController;
    late PersistenceController persistenceController;
    late SensorController sensorController;
    late MockSettingsService settingsService;
    late _ProbeTestSensor probe;
    late ShotSequencer shotSequencer;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      testDe1 = TestDe1();
      testScale = TestScale();
      de1Controller = _TestDe1Controller(testDe1);
      scaleController = _TestScaleController(testScale);
      persistenceController = PersistenceController(
        storageService: _NullStorageService(),
      );
      sensorController = SensorController(
        controller: DeviceController([_FakeDiscoveryService()]),
      );
      settingsService = MockSettingsService();
      probe = _ProbeTestSensor();
      await sensorController.register(probe);

      shotSequencer = ShotSequencer(
        scaleController: scaleController,
        de1controller: de1Controller,
        persistenceController: persistenceController,
        sensorController: sensorController,
        settingsService: settingsService,
        targetProfile: _simpleProfile(),
        targetYield: 100.0,
        bypassSAW: true,
        blockOnNoScale: false,
        weightFlowMultiplier: 0.0,
        volumeFlowMultiplier: 0.0,
        stepExitArbiterEnabled: true,
      );
    });

    tearDown(() {
      SharedPreferencesAsyncPlatform.instance = null;
      shotSequencer.dispose();
      probe.dispose();
      testDe1.dispose();
      testScale.dispose();
      scaleController.dispose();
      persistenceController.dispose();
      sensorController.dispose();
    });

    Future<void> driveToPouring() async {
      testDe1.emitStateAndSubstate(
        MachineState.espresso,
        MachineSubstate.preparingForShot,
      );
      testDe1.emitStateAndSubstate(
        MachineState.espresso,
        MachineSubstate.pouring,
      );
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> pumpFeature(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ShadApp(
          home: RealtimeShotFeature(
            shotSequencer: shotSequencer,
            workflowController: WorkflowController(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows probe temperature when sensor data is present', (
      tester,
    ) async {
      await pumpFeature(tester);

      await tester.runAsync(() async {
        await driveToPouring();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        probe.emitTemperature(93.5);
        await Future<void>.delayed(Duration.zero);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(find.textContaining('PT: 93.5'), findsOneWidget);
    });

    testWidgets('hides probe temperature when sensor data is absent', (
      tester,
    ) async {
      await pumpFeature(tester);

      await tester.runAsync(() async {
        await driveToPouring();
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(find.textContaining('PT:'), findsNothing);
    });
  });
}
