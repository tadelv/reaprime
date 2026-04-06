import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/test_de1.dart';
import '../helpers/test_scale.dart';

// ---------------------------------------------------------------------------
// Test-local helpers
// ---------------------------------------------------------------------------

/// Minimal DeviceDiscoveryService that does nothing.
class _FakeDiscoveryService extends DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {}
}

/// De1Controller subclass whose `connectedDe1()` returns our TestDe1.
class _TestDe1Controller extends De1Controller {
  final TestDe1 testDe1;

  _TestDe1Controller(this.testDe1)
      : super(
          controller: DeviceController([_FakeDiscoveryService()]),
        );

  @override
  De1Interface connectedDe1() => testDe1;

  @override
  Stream<De1Interface?> get de1 => BehaviorSubject.seeded(testDe1).stream;
}

/// ScaleController subclass with controllable connection state and weight
/// emission.
class _TestScaleController extends ScaleController {
  final TestScale testScale;
  final BehaviorSubject<ConnectionState> _connectionState;
  final BehaviorSubject<WeightSnapshot> _weight = BehaviorSubject();

  _TestScaleController(this.testScale)
      : _connectionState = BehaviorSubject.seeded(ConnectionState.connected);

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  ConnectionState get currentConnectionState => _connectionState.value;

  @override
  Stream<WeightSnapshot> get weightSnapshot => _weight.stream;

  @override
  Scale connectedScale() {
    if (_connectionState.value != ConnectionState.connected) {
      throw 'No scale connected';
    }
    return testScale;
  }

  void emitWeight(double weight, {double weightFlow = 0.0}) {
    _weight.add(WeightSnapshot(
      timestamp: DateTime(2026, 1, 15, 8, 0),
      weight: weight,
      weightFlow: weightFlow,
    ));
  }

  void simulateDisconnect() {
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  void dispose() {
    _connectionState.close();
    _weight.close();
    super.dispose();
  }
}

/// Minimal StorageService that stores nothing.
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
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
    bool ascending = false,
  }) async =>
      [];
  @override
  @override
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
  }) async =>
      0;
  @override
  Future<ShotRecord?> getLatestShot() async => null;
  @override
  Future<ShotRecord?> getLatestShotMeta() async => null;
}

/// Creates a minimal Profile with one pressure step and targetWeight of 36g.
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
  group('ShotController — scale disconnect during shot', () {
    late TestDe1 testDe1;
    late TestScale testScale;
    late _TestDe1Controller de1Controller;
    late _TestScaleController scaleController;
    late PersistenceController persistenceController;
    late Profile profile;

    setUp(() {
      testDe1 = TestDe1();
      testScale = TestScale();
      de1Controller = _TestDe1Controller(testDe1);
      scaleController = _TestScaleController(testScale);
      persistenceController =
          PersistenceController(storageService: _NullStorageService());
      profile = _simpleProfile();
    });

    tearDown(() {
      testDe1.dispose();
      testScale.dispose();
      scaleController.dispose();
      persistenceController.dispose();
    });

    /// Drive the ShotController state machine from idle → pouring.
    ///
    /// Emits: preparingForShot → preinfusion, which transitions through
    /// idle → preheating → pouring.
    void driveToPouring(ShotController shotController) {
      // idle → preheating (preparingForShot)
      testDe1.emitStateAndSubstate(
        MachineState.espresso,
        MachineSubstate.preparingForShot,
      );

      // preheating → pouring (preinfusion)
      testDe1.emitStateAndSubstate(
        MachineState.espresso,
        MachineSubstate.pouring,
      );
    }

    test('disables SAW when scale disconnects during pouring', () {
      fakeAsync((async) {
        // Emit initial weight so withLatestFrom has a value to combine with
        scaleController.emitWeight(0.0);

        final shotController = ShotController(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotController);
        async.elapse(Duration(milliseconds: 10));

        // Disconnect the scale mid-shot
        scaleController.simulateDisconnect();
        async.elapse(Duration(milliseconds: 10));

        // Emit weight that exceeds target (40g > 36g target).
        // With the bug, SAW fires on this stale data.
        // With the fix, SAW should be disabled because scale is disconnected.
        scaleController.emitWeight(40.0);

        // Emit a machine snapshot to trigger processing of the combined stream
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        // SAW should NOT have fired because scale is disconnected.
        // The bug: requestedStates will contain MachineState.idle because
        // withLatestFrom still combines with the stale weight.
        expect(
          testDe1.requestedStates,
          isEmpty,
          reason:
              'SAW should not fire when scale is disconnected, but it did — '
              'the controller is using stale weight data',
        );

        shotController.dispose();
      });
    });

    test('does not crash when scale disconnects and timer stop is attempted',
        () {
      fakeAsync((async) {
        // Emit initial weight so withLatestFrom has a value
        scaleController.emitWeight(0.0);

        final shotController = ShotController(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotController);
        async.elapse(Duration(milliseconds: 10));

        // Disconnect the scale
        scaleController.simulateDisconnect();
        async.elapse(Duration(milliseconds: 10));

        // Machine ends the shot — this transitions to stopping state.
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        async.elapse(Duration(milliseconds: 10));

        // Now emit another snapshot. The ShotController is in the stopping
        // state, which calls scaleController.connectedScale().stopTimer().
        // With the bug, connectedScale() throws because scale is disconnected.
        expect(
          () {
            testDe1.emitStateAndSubstate(
              MachineState.espresso,
              MachineSubstate.pouringDone,
            );
            async.elapse(Duration(milliseconds: 10));
          },
          returnsNormally,
          reason:
              'Should not crash when scale disconnects and shot ends — '
              'connectedScale() throws when scale is gone',
        );

        shotController.dispose();
      });
    });

    test('SAW still works normally when scale stays connected', () {
      fakeAsync((async) {
        // Emit initial weight so withLatestFrom has a value
        scaleController.emitWeight(0.0);

        final shotController = ShotController(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotController);
        async.elapse(Duration(milliseconds: 10));

        // Scale stays connected; emit weight above target
        scaleController.emitWeight(40.0);

        // Emit a machine snapshot to trigger combined stream processing
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        // SAW SHOULD fire because scale is still connected and weight > target
        expect(
          testDe1.requestedStates,
          contains(MachineState.idle),
          reason:
              'SAW should fire when scale is connected and weight exceeds target',
        );

        shotController.dispose();
      });
    });
  });
}
