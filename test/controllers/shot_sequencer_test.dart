import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/shot_sequencer.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/steam_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
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
  Future<void> scanForDevices({ScanFilter? filter}) async {}
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
    List<String>? beanBatchIds,
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
    List<String>? beanBatchIds,
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
  group('ShotSequencer — scale disconnect during shot', () {
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

    /// Drive the ShotSequencer state machine from idle → pouring.
    ///
    /// Emits: preparingForShot → preinfusion, which transitions through
    /// idle → preheating → pouring.
    void driveToPouring(ShotSequencer shotSequencer) {
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

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
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

        shotSequencer.dispose();
      });
    });

    test('does not crash when scale disconnects and timer stop is attempted',
        () {
      fakeAsync((async) {
        // Emit initial weight so withLatestFrom has a value
        scaleController.emitWeight(0.0);

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
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

        // Now emit another snapshot. The ShotSequencer is in the stopping
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

        shotSequencer.dispose();
      });
    });

    test('SAW still works normally when scale stays connected', () {
      fakeAsync((async) {
        // Emit initial weight so withLatestFrom has a value
        scaleController.emitWeight(0.0);

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
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

        shotSequencer.dispose();
      });
    });

    test('trusted final yield ignores cup removal during drip window', () {
      fakeAsync((async) {
        scaleController.emitWeight(0.0);

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
        async.elapse(Duration(milliseconds: 10));

        scaleController.emitWeight(36.0, weightFlow: 0.4);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        scaleController.emitWeight(36.5, weightFlow: 0.3);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        async.elapse(Duration(milliseconds: 10));

        scaleController.emitWeight(2.0, weightFlow: -20.0);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        async.elapse(Duration(milliseconds: 10));

        expect(shotSequencer.trustedFinalYield, 36.5);

        shotSequencer.dispose();
      });
    });

    test('an upward touch spike locks the yield at the pre-spike value', () {
      fakeAsync((async) {
        scaleController.emitWeight(0.0);

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
        async.elapse(Duration(milliseconds: 10));

        // SAW stops the shot, then one real settling drip establishes the
        // decaying-flow baseline.
        scaleController.emitWeight(36.0, weightFlow: 0.4);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        scaleController.emitWeight(36.3, weightFlow: 0.3);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        async.elapse(Duration(milliseconds: 10));

        // A finger touch spikes the flow up against the decay — locked out.
        scaleController.emitWeight(45.0, weightFlow: 12.0);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        async.elapse(Duration(milliseconds: 10));

        expect(shotSequencer.trustedFinalYield, 36.3);

        shotSequencer.dispose();
      });
    });

    test('captures a turbo catch-up beyond the old gram and flow caps', () {
      fakeAsync((async) {
        scaleController.emitWeight(0.0);

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 30.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
        async.elapse(Duration(milliseconds: 10));

        // SAW stops at the 30 g target while flow is still high (turbo).
        scaleController.emitWeight(30.0, weightFlow: 8.0);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        // In-flight water keeps landing at high (but decaying) flow — an 8 g
        // rise the old >5 g / flow>3 caps would have rejected.
        for (final s in [
          [34.0, 6.0],
          [37.0, 4.0],
          [38.0, 1.0],
        ]) {
          scaleController.emitWeight(s[0], weightFlow: s[1]);
          testDe1.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouringDone,
          );
          async.elapse(Duration(milliseconds: 10));
        }

        // Then it settles.
        for (var i = 0; i < 3; i++) {
          scaleController.emitWeight(38.1, weightFlow: 0.1);
          testDe1.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouringDone,
          );
          async.elapse(Duration(milliseconds: 10));
        }

        expect(shotSequencer.trustedFinalYield, 38.1);

        shotSequencer.dispose();
      });
    });

    test('settling locks the yield and finishes the shot', () {
      fakeAsync((async) {
        scaleController.emitWeight(0.0);

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 100.0, // no SAW; machine reports the end
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        final states = <ShotState>[];
        shotSequencer.state.listen(states.add);

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
        async.elapse(Duration(milliseconds: 10));

        scaleController.emitWeight(36.0, weightFlow: 0.3);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        async.elapse(Duration(milliseconds: 10));

        // Three near-still samples settle the yield.
        for (var i = 0; i < 3; i++) {
          scaleController.emitWeight(36.1, weightFlow: 0.1);
          testDe1.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouringDone,
          );
          async.elapse(Duration(milliseconds: 10));
        }

        expect(shotSequencer.trustedFinalYield, 36.1);
        expect(
          states,
          contains(ShotState.finished),
          reason: 'settling finalizes the shot without waiting for the backstop',
        );

        shotSequencer.dispose();
      });
    });

    test(
      'recorded trace stops at the machine-reported shot end; drips only '
      'refine the yield',
      () {
        fakeAsync((async) {
          scaleController.emitWeight(0.0);

          final shotSequencer = ShotSequencer(
            scaleController: scaleController,
            de1controller: de1Controller,
            persistenceController: persistenceController,
            targetProfile: profile,
            // High target so app-side SAW never fires — the machine itself
            // reports the shot end via the pouringDone substate.
            targetYield: 100.0,
            bypassSAW: false,
            blockOnNoScale: false,
            weightFlowMultiplier: 0.0,
            volumeFlowMultiplier: 0.0,
          );

          final recorded = <ShotSnapshot>[];
          shotSequencer.shotData.listen(recorded.add);

          async.elapse(Duration(milliseconds: 10));
          driveToPouring(shotSequencer);
          async.elapse(Duration(milliseconds: 10));

          // Two real pour samples climb toward the final weight.
          scaleController.emitWeight(30.0, weightFlow: 1.5);
          testDe1.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouring,
          );
          async.elapse(Duration(milliseconds: 10));

          scaleController.emitWeight(35.5, weightFlow: 0.8);
          testDe1.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouring,
          );
          async.elapse(Duration(milliseconds: 10));

          // Machine reports the shot is done — this is the boundary. Recording
          // must stop here; this sample and the drips after it are excluded.
          scaleController.emitWeight(36.0, weightFlow: 0.3);
          testDe1.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouringDone,
          );
          async.elapse(Duration(milliseconds: 10));

          // Post-stop drip refines the yield but stays out of the trace.
          scaleController.emitWeight(36.4, weightFlow: 0.2);
          testDe1.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouringDone,
          );
          async.elapse(Duration(milliseconds: 10));

          // The two driveToPouring frames carry the seeded 0.0 weight, then the
          // two pour samples. Nothing from the stopping window is recorded.
          expect(
            recorded.map((s) => s.scale?.weight).toList(),
            [0.0, 0.0, 30.0, 35.5],
          );
          expect(
            recorded.last.machine.state.substate,
            MachineSubstate.pouring,
            reason: 'trace ends on the last actively-pouring sample',
          );
          // The yield, however, follows the last drip.
          expect(shotSequencer.trustedFinalYield, 36.4);

          shotSequencer.dispose();
        });
      },
    );

    test('suppresses weight and flow to 0 until the pour-time tare', () {
      fakeAsync((async) {
        // A cup is already sitting on the scale when the shot begins — its
        // weight (and the noise-flow off it) must not leak into the trace
        // before the scale is tared for the pour.
        scaleController.emitWeight(80.0, weightFlow: 1.2);

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        final recorded = <ShotSnapshot>[];
        shotSequencer.shotData.listen(recorded.add);

        async.elapse(Duration(milliseconds: 10));

        // idle → preheating: the preparing-for-shot frame is recorded but
        // pre-tare, so it must read 0 despite the 80g cup on the platter.
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.preparingForShot,
        );
        async.elapse(Duration(milliseconds: 10));

        // Still preheating, scale still shows the cup — still suppressed.
        scaleController.emitWeight(80.1, weightFlow: 0.4);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.preparingForShot,
        );
        async.elapse(Duration(milliseconds: 10));

        // preheating → pouring: the pour-time tare fires here. This frame is
        // gated before the transition, so it is still 0...
        scaleController.emitWeight(0.0, weightFlow: 0.0);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        // ...and subsequent pour samples flow through for real.
        scaleController.emitWeight(18.0, weightFlow: 2.0);
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        expect(
          recorded.map((s) => s.scale?.weight).toList(),
          [0.0, 0.0, 0.0, 18.0],
          reason: 'pre-tare frames are 0; real weight only after the pour tare',
        );
        expect(
          recorded.map((s) => s.scale?.weightFlow).toList(),
          [0.0, 0.0, 0.0, 2.0],
          reason: 'flow off the un-tared cup must not leak either',
        );

        shotSequencer.dispose();
      });
    });

    test('non-scale shot finishes immediately, with no settling window', () {
      fakeAsync((async) {
        // No scale: the settling window only exists to catch scale drips, so
        // the shot must end the moment the machine reports it — no 4s wait.
        scaleController.simulateDisconnect();

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        final states = <ShotState>[];
        shotSequencer.state.listen(states.add);

        async.elapse(Duration(milliseconds: 10));
        driveToPouring(shotSequencer);
        async.elapse(Duration(milliseconds: 10));

        // Machine reports the shot end.
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        // Only a tiny tick elapses — far less than the 4s scale settling window.
        async.elapse(Duration(milliseconds: 50));

        expect(
          states,
          contains(ShotState.finished),
          reason: 'no-scale shot finishes without waiting for drips',
        );
        expect(
          states,
          isNot(contains(ShotState.stopping)),
          reason: 'no-scale shot never enters the drip-settling window',
        );
        expect(shotSequencer.trustedFinalYield, isNull);

        shotSequencer.dispose();
      });
    });
  });

  group('ShotSequencer — blockOnNoScale', () {
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

    test(
        'aborts shot and emits noScale decision when no scale connected at start',
        () {
      fakeAsync((async) {
        // No scale at shot start.
        scaleController.simulateDisconnect();

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: true,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        final decisions = <ShotDecision>[];
        final snapshots = <ShotSnapshot>[];
        shotSequencer.decisions.listen(decisions.add);
        shotSequencer.shotData.listen(snapshots.add);

        async.elapse(Duration(milliseconds: 10));

        // Machine entered espresso (e.g. via GHC) — drive snapshots that would
        // normally be tracked.
        testDe1.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.elapse(Duration(milliseconds: 10));

        expect(
          testDe1.requestedStates,
          contains(MachineState.idle),
          reason: 'shot should be aborted back to idle',
        );
        expect(decisions, hasLength(1));
        expect(decisions.single.reason, ShotDecisionReason.noScale);
        expect(
          snapshots,
          isEmpty,
          reason: 'no monitoring should be wired when the shot is blocked',
        );

        shotSequencer.dispose();
      });
    });

    test('does not block when blockOnNoScale is false and no scale connected',
        () {
      fakeAsync((async) {
        scaleController.simulateDisconnect();

        final shotSequencer = ShotSequencer(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: persistenceController,
          targetProfile: profile,
          targetYield: 36.0,
          bypassSAW: false,
          blockOnNoScale: false,
          weightFlowMultiplier: 0.0,
          volumeFlowMultiplier: 0.0,
        );

        final decisions = <ShotDecision>[];
        shotSequencer.decisions.listen(decisions.add);

        async.elapse(Duration(milliseconds: 10));

        expect(testDe1.requestedStates, isEmpty);
        expect(decisions, isEmpty);

        shotSequencer.dispose();
      });
    });
  });
}
