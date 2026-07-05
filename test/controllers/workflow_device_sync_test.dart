import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/controllers/workflow_device_sync.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/errors.dart';

import '../helpers/mock_device_discovery_service.dart';
import '../helpers/test_de1.dart';

Profile _profile(String title) => Profile(
      version: '2',
      title: title,
      notes: '',
      author: 'test',
      beverageType: BeverageType.espresso,
      steps: const [],
      targetVolumeCountStart: 0,
      tankTemperature: 0,
    );

class _RecordingDe1 extends TestDe1 {
  final List<Profile> setProfileCalls = [];

  @override
  Future<void> setProfile(Profile profile) async {
    setProfileCalls.add(profile);
  }
}

/// Fails the first [failures] setProfile calls (simulating a BLE write timeout),
/// then records subsequent ones.
class _FlakyDe1 extends TestDe1 {
  _FlakyDe1({this.failures = 1});
  int failures;
  int totalCalls = 0;
  final List<Profile> setProfileCalls = [];

  @override
  Future<void> setProfile(Profile profile) async {
    totalCalls++;
    if (failures > 0) {
      failures--;
      throw Exception('simulated BLE write timeout');
    }
    setProfileCalls.add(profile);
  }
}

/// Holds every upload open until the test releases it via [completeNext],
/// tracking how many uploads run concurrently.
class _GatedDe1 extends TestDe1 {
  final List<Profile> setProfileCalls = [];
  final List<Completer<void>> _gates = [];
  int _inFlight = 0;
  int maxInFlight = 0;

  int get pendingUploads => _gates.length;

  void completeNext() => _gates.removeAt(0).complete();

  @override
  Future<void> setProfile(Profile profile) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    setProfileCalls.add(profile);
    final gate = Completer<void>();
    _gates.add(gate);
    try {
      await gate.future;
    } finally {
      _inFlight--;
    }
  }
}

/// Fails the calls whose 1-based sequence number is in [failOnCalls].
class _FailNthDe1 extends TestDe1 {
  _FailNthDe1(this.failOnCalls);
  final Set<int> failOnCalls;
  int totalCalls = 0;
  final List<Profile> setProfileCalls = [];

  @override
  Future<void> setProfile(Profile profile) async {
    totalCalls++;
    if (failOnCalls.contains(totalCalls)) {
      throw Exception('simulated failure on call #$totalCalls');
    }
    setProfileCalls.add(profile);
  }
}

/// Always reports the machine as gone.
class _NotConnectedDe1 extends TestDe1 {
  int totalCalls = 0;

  @override
  Future<void> setProfile(Profile profile) async {
    totalCalls++;
    throw const DeviceNotConnectedException.machine();
  }
}

void main() {
  late WorkflowController workflow;
  late DeviceController deviceController;
  late De1Controller de1Controller;
  late _RecordingDe1 de1;
  late WorkflowDeviceSync sync;

  setUp(() async {
    workflow = WorkflowController();
    deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    de1Controller = De1Controller(controller: deviceController);
    de1 = _RecordingDe1();
    await de1Controller.connectToDe1(de1);
    // Unblock De1Controller._initializeData which awaits shotSettings.first.
    de1.emitShotSettings(De1ShotSettings(
      steamSetting: 0,
      targetSteamTemp: 150,
      targetSteamDuration: 30,
      targetHotWaterTemp: 75,
      targetHotWaterVolume: 50,
      targetHotWaterDuration: 30,
      targetShotVolume: 36,
      groupTemp: 94.0,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    sync = WorkflowDeviceSync(
      workflowController: workflow,
      de1Controller: de1Controller,
    );
  });

  tearDown(() {
    sync.dispose();
    de1.dispose();
  });

  test('profile change triggers exactly one setProfile on the DE1', () async {
    final initial = workflow.currentWorkflow;
    workflow.setWorkflow(initial.copyWith(profile: _profile('Adaptive v2')));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(de1.setProfileCalls.length, equals(1));
    expect(de1.setProfileCalls.single.title, equals('Adaptive v2'));
  });

  test(
    'setWorkflow with identical profile does not push again',
    () async {
      final initial = workflow.currentWorkflow;
      final next = initial.copyWith(profile: _profile('Adaptive v2'));
      workflow.setWorkflow(next);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(de1.setProfileCalls.length, equals(1));

      // Apply a workflow with a semantically-equal profile — should
      // short-circuit via Profile's Equatable equality.
      workflow.setWorkflow(next.copyWith(profile: _profile('Adaptive v2')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        de1.setProfileCalls.length,
        equals(1),
        reason: 'equal profile value must not trigger a second BLE upload',
      );
    },
  );

  test(
    'non-profile workflow changes do not trigger setProfile',
    () async {
      final initial = workflow.currentWorkflow;
      workflow.setWorkflow(initial.copyWith(name: 'renamed'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(de1.setProfileCalls, isEmpty);
    },
  );

  test(
    'a failed setProfile is not marked pushed — the same profile still '
    'lands via the automatic retry',
    () async {
      // Build an isolated sync wired to a DE1 whose first upload fails.
      final wf = WorkflowController();
      final dc = DeviceController([MockDeviceDiscoveryService()]);
      await dc.initialize();
      final controller = De1Controller(controller: dc);
      final flaky = _FlakyDe1(failures: 1);
      await controller.connectToDe1(flaky);
      flaky.emitShotSettings(De1ShotSettings(
        steamSetting: 0,
        targetSteamTemp: 150,
        targetSteamDuration: 30,
        targetHotWaterTemp: 75,
        targetHotWaterVolume: 50,
        targetHotWaterDuration: 30,
        targetShotVolume: 36,
        groupTemp: 94.0,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final flakySync = WorkflowDeviceSync(
        workflowController: wf,
        de1Controller: controller,
        retryDelays: const [Duration(milliseconds: 20)],
      );

      // First push of the cleaning profile fails (timeout) — nothing recorded,
      // and the profile is NOT marked pushed.
      wf.setWorkflow(wf.currentWorkflow.copyWith(profile: _profile('Cleaning')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(flaky.setProfileCalls, isEmpty);

      // Re-applying the SAME profile leaves the armed retry undisturbed; the
      // profile must land when it fires (it was never marked pushed, so it
      // cannot be skipped by the equality guard).
      wf.setWorkflow(wf.currentWorkflow.copyWith(profile: _profile('Cleaning')));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(flaky.setProfileCalls.length, equals(1));
      expect(flaky.setProfileCalls.single.title, equals('Cleaning'));

      flakySync.dispose();
    },
  );

  test(
    'dispose removes the listener — later workflow changes are ignored',
    () async {
      final initial = workflow.currentWorkflow;
      sync.dispose();

      workflow.setWorkflow(initial.copyWith(profile: _profile('After dispose')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(de1.setProfileCalls, isEmpty);
    },
  );

  // Serialized/coalescing push loop + failure retry. Regression coverage for
  // the 2026-07-05 stuck-machine incident: rapid temperature "+" presses
  // produced overlapping profile uploads whose header/frame writes
  // interleaved on the BLE queue, wedging the firmware's profile-receive
  // state machine; and after the resulting write timeout nothing retried.
  group('serialized coalescing push with retry', () {
    // Short, test-friendly backoff. Last entry is the cap.
    const retryDelays = [
      Duration(milliseconds: 20),
      Duration(milliseconds: 40),
    ];

    late WorkflowController wf;
    WorkflowDeviceSync? activeSync;

    Future<De1Controller> connect(TestDe1 testDe1) async {
      final dc = DeviceController([MockDeviceDiscoveryService()]);
      await dc.initialize();
      final controller = De1Controller(controller: dc);
      await controller.connectToDe1(testDe1);
      testDe1.emitShotSettings(De1ShotSettings(
        steamSetting: 0,
        targetSteamTemp: 150,
        targetSteamDuration: 30,
        targetHotWaterTemp: 75,
        targetHotWaterVolume: 50,
        targetHotWaterDuration: 30,
        targetShotVolume: 36,
        groupTemp: 94.0,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return controller;
    }

    WorkflowDeviceSync buildSync(De1Controller controller) {
      final s = WorkflowDeviceSync(
        workflowController: wf,
        de1Controller: controller,
        retryDelays: retryDelays,
      );
      activeSync = s;
      return s;
    }

    void applyProfile(String title) {
      wf.setWorkflow(wf.currentWorkflow.copyWith(profile: _profile(title)));
    }

    setUp(() {
      wf = WorkflowController();
      activeSync = null;
    });

    tearDown(() {
      activeSync?.dispose();
    });

    test('uploads never overlap and intermediate profiles are skipped',
        () async {
      final gated = _GatedDe1();
      final controller = await connect(gated);
      buildSync(controller);

      applyProfile('A');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gated.setProfileCalls.map((p) => p.title), ['A'],
          reason: 'first change starts an upload immediately');

      // Two more changes while upload A is still in flight.
      applyProfile('B');
      applyProfile('C');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gated.setProfileCalls.length, 1,
          reason: 'no second upload may start while A is in flight');

      gated.completeNext(); // A lands
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gated.setProfileCalls.map((p) => p.title), ['A', 'C'],
          reason: 'B was superseded by C before its upload started');

      gated.completeNext(); // C lands
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(gated.maxInFlight, 1,
          reason: 'profile uploads must be strictly serialized');
      expect(gated.pendingUploads, 0);
    });

    test('a failed upload is retried automatically, no workflow change needed',
        () async {
      final flaky = _FlakyDe1(failures: 1);
      final controller = await connect(flaky);
      buildSync(controller);

      applyProfile('Cleaning');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(flaky.setProfileCalls, isEmpty,
          reason: 'first attempt fails; retry not due yet');

      // First retry is due after retryDelays[0] (20ms).
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(flaky.setProfileCalls.map((p) => p.title), ['Cleaning'],
          reason: 'retry must fire without any further workflow change');
    });

    test('a pending retry pushes the latest desired profile', () async {
      final flaky = _FlakyDe1(failures: 1);
      final controller = await connect(flaky);
      buildSync(controller);

      applyProfile('A'); // fails, retry armed for +20ms
      await Future<void>.delayed(const Duration(milliseconds: 5));
      applyProfile('B'); // supersedes A before the retry fires

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(flaky.setProfileCalls.map((p) => p.title), ['B'],
          reason: 'superseded profile A must never be uploaded');
    });

    test('backoff walks the delay list until the upload lands', () async {
      final flaky = _FlakyDe1(failures: 2);
      final controller = await connect(flaky);
      buildSync(controller);

      applyProfile('Stubborn');
      // Attempt 1 at ~0ms fails, retry at +20ms fails, retry at +20+40ms lands.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(flaky.setProfileCalls, isEmpty,
          reason: 'second retry is not due before 60ms');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flaky.setProfileCalls.map((p) => p.title), ['Stubborn']);
      expect(flaky.totalCalls, 3);
    });

    test('machine disconnect cancels a pending retry', () async {
      final flaky = _FlakyDe1(failures: 100);
      final controller = await connect(flaky);
      buildSync(controller);

      applyProfile('Doomed');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1);

      flaky.setConnectionState(ConnectionState.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(flaky.totalCalls, 1,
          reason: 'no retry may fire after the machine disconnected');
    });

    test('DeviceNotConnectedException does not schedule a retry', () async {
      final gone = _NotConnectedDe1();
      final controller = await connect(gone);
      buildSync(controller);

      applyProfile('Unreachable');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(gone.totalCalls, 1,
          reason: 'reconnect path owns the re-upload; no retry timer');
    });

    test('dispose cancels a pending retry', () async {
      final flaky = _FlakyDe1(failures: 100);
      final controller = await connect(flaky);
      final s = buildSync(controller);

      applyProfile('Doomed');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1);

      s.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(flaky.totalCalls, 1);
    });

    test(
        'reverting to the last-pushed profile while another upload is in '
        'flight still converges to the reverted profile', () async {
      final gated = _GatedDe1();
      final controller = await connect(gated);
      buildSync(controller);

      applyProfile('P1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gated.completeNext(); // P1 lands
      await Future<void>.delayed(const Duration(milliseconds: 10));

      applyProfile('P2');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Revert to P1 while P2 is still uploading. Once P2 lands the device
      // holds P2, so the loop must push P1 again to match the workflow.
      applyProfile('P1');
      gated.completeNext(); // P2 lands
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(gated.setProfileCalls.map((p) => p.title), ['P1', 'P2', 'P1'],
          reason: 'device must converge to the workflow profile, not P2');

      gated.completeNext(); // trailing P1 lands
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gated.maxInFlight, 1);
    });

    test(
        'a workflow change with the same profile leaves a pending retry\'s '
        'backoff undisturbed', () async {
      final flaky = _FlakyDe1(failures: 100);
      final controller = await connect(flaky);
      buildSync(controller);

      applyProfile('Same'); // attempt 1 fails, retry armed for +20ms
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1);

      // Same profile content again (e.g. a non-profile workflow edit
      // notifying listeners): must not trigger an immediate re-attempt.
      applyProfile('Same');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1,
          reason: 'identical content must not reset the backoff to now');

      // The originally armed retry still fires on schedule.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(flaky.totalCalls, greaterThanOrEqualTo(2),
          reason: 'the pending retry must survive the duplicate change');
    });

    test(
        'failed upload invalidates last-pushed — reverting to the previous '
        'profile re-uploads instead of short-circuiting', () async {
      // Call 1 (profile P1) succeeds, call 2 (P2) fails mid-upload.
      final de1 = _FailNthDe1({2});
      final controller = await connect(de1);
      buildSync(controller);

      applyProfile('P1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(de1.setProfileCalls.map((p) => p.title), ['P1']);

      applyProfile('P2'); // fails — device state now unknown (possibly wedged)
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // User reverts to P1 before the retry fires. The device may be stuck
      // mid-receive of P2, so this MUST re-upload P1, not skip it as
      // already-pushed.
      applyProfile('P1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(de1.setProfileCalls.map((p) => p.title), ['P1', 'P1']);
    });
  });
}
