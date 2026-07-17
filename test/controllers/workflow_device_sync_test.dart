import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/controllers/workflow_device_sync.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/errors.dart';

import '../helpers/fake_ble_transport.dart';
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

class _NotConnectedDe1 extends TestDe1 {
  int totalCalls = 0;

  @override
  Future<void> setProfile(Profile profile) async {
    totalCalls++;
    throw const DeviceNotConnectedException.machine();
  }
}

/// Completes when init settles (shot settings emitted and defaults written).
Future<void> settleInit(De1Controller controller, TestDe1 de1) async {
  de1.emitShotSettings(
    De1ShotSettings(
      steamSetting: 0,
      targetSteamTemp: 150,
      targetSteamDuration: 30,
      targetHotWaterTemp: 75,
      targetHotWaterVolume: 50,
      targetHotWaterDuration: 30,
      targetShotVolume: 36,
      groupTemp: 94.0,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 10));
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
    await settleInit(de1Controller, de1);
    sync = WorkflowDeviceSync(
      workflowController: workflow,
      de1Controller: de1Controller,
    );
    // The initSettled stream replays the already-settled generation, so
    // the sync's on-connect push fires immediately. Let it land and
    // discard it — tests below assert only their own pushes.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    de1.setProfileCalls.clear();
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
      final wf = WorkflowController();
      final dc = DeviceController([MockDeviceDiscoveryService()]);
      await dc.initialize();
      final controller = De1Controller(controller: dc);
      final flaky = _FlakyDe1(failures: 0);
      await controller.connectToDe1(flaky);
      await settleInit(controller, flaky);
      final flakySync = WorkflowDeviceSync(
        workflowController: wf,
        de1Controller: controller,
        retryDelays: const [Duration(milliseconds: 20)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      flaky.setProfileCalls.clear();
      flaky.failures = 1;

      wf.setWorkflow(
        wf.currentWorkflow.copyWith(profile: _profile('Cleaning')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(flaky.setProfileCalls, isEmpty);

      wf.setWorkflow(
        wf.currentWorkflow.copyWith(profile: _profile('Cleaning')),
      );
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

      workflow.setWorkflow(
        initial.copyWith(profile: _profile('After dispose')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(de1.setProfileCalls, isEmpty);
    },
  );

  group('serialized coalescing push with retry', () {
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
      await settleInit(controller, testDe1);
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

    /// Lands + discards the sync's on-connect push.
    Future<void> settleConnectPush({_GatedDe1? gated}) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (gated != null) {
        gated.completeNext();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
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

    test(
      'uploads never overlap and intermediate profiles are skipped',
      () async {
        final gated = _GatedDe1();
        final controller = await connect(gated);
        buildSync(controller);
        await settleConnectPush(gated: gated);
        gated.setProfileCalls.clear();

        applyProfile('A');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          gated.setProfileCalls.map((p) => p.title),
          ['A'],
          reason: 'first change starts an upload immediately',
        );

        applyProfile('B');
        applyProfile('C');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          gated.setProfileCalls.length,
          1,
          reason: 'no second upload may start while A is in flight',
        );

        gated.completeNext(); // A lands
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          gated.setProfileCalls.map((p) => p.title),
          ['A', 'C'],
          reason: 'B was superseded by C before its upload started',
        );

        gated.completeNext(); // C lands
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          gated.maxInFlight,
          1,
          reason: 'profile uploads must be strictly serialized',
        );
        expect(gated.pendingUploads, 0);
      },
    );

    test(
      'a failed upload is retried automatically, no workflow change needed',
      () async {
        final flaky = _FlakyDe1(failures: 0);
        final controller = await connect(flaky);
        buildSync(controller);
        await settleConnectPush();
        flaky.setProfileCalls.clear();
        flaky.failures = 1;

        applyProfile('Cleaning');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          flaky.setProfileCalls,
          isEmpty,
          reason: 'first attempt fails; retry not due yet',
        );

        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(
          flaky.setProfileCalls.map((p) => p.title),
          ['Cleaning'],
          reason: 'retry must fire without any further workflow change',
        );
      },
    );

    test('a pending retry pushes the latest desired profile', () async {
      final flaky = _FlakyDe1(failures: 0);
      final controller = await connect(flaky);
      buildSync(controller);
      await settleConnectPush();
      flaky.setProfileCalls.clear();
      flaky.failures = 1;

      applyProfile('A');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      applyProfile('B');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        flaky.setProfileCalls.map((p) => p.title),
        ['B'],
        reason: 'superseded profile A must never be uploaded',
      );
    });

    test('backoff walks the delay list until the upload lands', () async {
      final flaky = _FlakyDe1(failures: 0);
      final controller = await connect(flaky);
      buildSync(controller);
      await settleConnectPush();
      flaky.setProfileCalls.clear();
      flaky.totalCalls = 0;
      flaky.failures = 2;

      applyProfile('Stubborn');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(flaky.setProfileCalls, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flaky.setProfileCalls.map((p) => p.title), ['Stubborn']);
      expect(flaky.totalCalls, 3);
    });

    test('machine disconnect cancels a pending retry', () async {
      final flaky = _FlakyDe1(failures: 0);
      final controller = await connect(flaky);
      buildSync(controller);
      await settleConnectPush();
      flaky.totalCalls = 0;
      flaky.failures = 100;

      applyProfile('Doomed');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1);

      flaky.setConnectionState(ConnectionState.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        flaky.totalCalls,
        1,
        reason: 'no retry may fire after the machine disconnected',
      );
    });

    test('DeviceNotConnectedException does not schedule a retry', () async {
      final gone = _NotConnectedDe1();
      final controller = await connect(gone);
      buildSync(controller);
      await settleConnectPush();
      gone.totalCalls = 0;

      applyProfile('Unreachable');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(gone.totalCalls, 1);
    });

    test('dispose cancels a pending retry', () async {
      final flaky = _FlakyDe1(failures: 0);
      final controller = await connect(flaky);
      final s = buildSync(controller);
      await settleConnectPush();
      flaky.totalCalls = 0;
      flaky.failures = 100;

      applyProfile('Doomed');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1);

      s.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(flaky.totalCalls, 1);
    });

    test('reverting to the last-pushed profile while another upload is in '
        'flight still converges to the reverted profile', () async {
      final gated = _GatedDe1();
      final controller = await connect(gated);
      buildSync(controller);
      await settleConnectPush(gated: gated);
      gated.setProfileCalls.clear();

      applyProfile('P1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gated.completeNext();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      applyProfile('P2');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      applyProfile('P1');
      gated.completeNext();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        gated.setProfileCalls.map((p) => p.title),
        ['P1', 'P2', 'P1'],
        reason: 'device must converge to the workflow profile, not P2',
      );

      gated.completeNext();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gated.maxInFlight, 1);
    });

    test('a workflow change with the same profile leaves a pending retry\'s '
        'backoff undisturbed', () async {
      final flaky = _FlakyDe1(failures: 0);
      final controller = await connect(flaky);
      buildSync(controller);
      await settleConnectPush();
      flaky.totalCalls = 0;
      flaky.failures = 100;

      applyProfile('Same');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1);

      applyProfile('Same');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(flaky.totalCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(flaky.totalCalls, greaterThanOrEqualTo(2));
    });

    test('failed upload invalidates last-pushed — reverting to the previous '
        'profile re-uploads instead of short-circuiting', () async {
      final de1 = _FailNthDe1({3});
      final controller = await connect(de1);
      buildSync(controller);
      await settleConnectPush();
      de1.setProfileCalls.clear();

      applyProfile('P1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(de1.setProfileCalls.map((p) => p.title), ['P1']);

      applyProfile('P2');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      applyProfile('P1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(de1.setProfileCalls.map((p) => p.title), ['P1', 'P1']);
    });
  });

  group('on-connect profile push via initSettled', () {
    late WorkflowController wf;
    WorkflowDeviceSync? activeSync;

    setUp(() {
      wf = WorkflowController();
      wf.setWorkflow(
        wf.currentWorkflow.copyWith(profile: _profile('Persisted')),
      );
      activeSync = null;
    });

    tearDown(() {
      activeSync?.dispose();
    });

    Future<De1Controller> freshController() async {
      final dc = DeviceController([MockDeviceDiscoveryService()]);
      await dc.initialize();
      return De1Controller(controller: dc);
    }

    WorkflowDeviceSync buildSync(
      De1Controller controller, {
      void Function(ConnectionError)? onUploadError,
      void Function()? onUploadErrorCleared,
    }) {
      final s = WorkflowDeviceSync(
        workflowController: wf,
        de1Controller: controller,
        retryDelays: const [Duration(milliseconds: 20)],
        onUploadError: onUploadError,
        onUploadErrorCleared: onUploadErrorCleared,
      );
      activeSync = s;
      return s;
    }

    test('connecting a machine pushes the current workflow profile', () async {
      final controller = await freshController();
      buildSync(controller);
      final de1 = _RecordingDe1();
      await controller.connectToDe1(de1);
      await settleInit(controller, de1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(de1.setProfileCalls.map((p) => p.title), ['Persisted']);
    });

    test(
      'a machine already connected at construction still gets the profile',
      () async {
        final controller = await freshController();
        final de1 = _RecordingDe1();
        await controller.connectToDe1(de1);
        await settleInit(controller, de1);

        buildSync(controller);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(de1.setProfileCalls.map((p) => p.title), ['Persisted']);
      },
    );

    test(
      'reconnect re-pushes the same profile',
      () async {
        final controller = await freshController();
        buildSync(controller);
        final de1 = _RecordingDe1();
        await controller.connectToDe1(de1);
        await settleInit(controller, de1);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(de1.setProfileCalls.length, 1);

        de1.setConnectionState(ConnectionState.disconnected);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        de1.setConnectionState(ConnectionState.connected);

        await controller.connectToDe1(de1);
        await settleInit(controller, de1);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          de1.setProfileCalls.map((p) => p.title),
          ['Persisted', 'Persisted'],
        );
      },
    );

    test(
      'a failed on-connect push retries with backoff until it lands',
      () async {
        final controller = await freshController();
        buildSync(controller);
        final flaky = _FlakyDe1(failures: 1);

        await controller.connectToDe1(flaky);
        await settleInit(controller, flaky);
        // The on-connect push should have failed on first attempt.
        // Wait long enough for the retry (20ms) to fire and succeed.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(flaky.setProfileCalls.map((p) => p.title), ['Persisted']);
      },
    );

    test(
      'upload failure surfaces once via onUploadError and clears via '
      'onUploadErrorCleared when a retry lands',
      () async {
        final errors = <ConnectionError>[];
        var cleared = 0;
        final controller = await freshController();
        buildSync(
          controller,
          onUploadError: errors.add,
          onUploadErrorCleared: () => cleared++,
        );
        final flaky = _FlakyDe1(failures: 2);

        await controller.connectToDe1(flaky);
        await settleInit(controller, flaky);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(errors.length, 1);
        expect(errors.single.kind, ConnectionErrorKind.profileUploadFailed);
        expect(errors.single.severity, ConnectionErrorSeverity.warning);
        expect(cleared, 0);

        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(errors.length, 1);

        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(flaky.setProfileCalls.map((p) => p.title), ['Persisted']);
        expect(cleared, 1);
      },
    );

    test('dispose clears the error when it is still current', () async {
      final errors = <ConnectionError>[];
      var cleared = 0;
      final controller = await freshController();
      final de1 = _FlakyDe1(failures: 100);
      await controller.connectToDe1(de1);
      await settleInit(controller, de1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final syncUnderTest = WorkflowDeviceSync(
        workflowController: wf,
        de1Controller: controller,
        retryDelays: const [Duration(milliseconds: 20)],
        onUploadError: errors.add,
        onUploadErrorCleared: () => cleared++,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(errors.length, 1);
      expect(cleared, 0);

      syncUnderTest.dispose();
      expect(
        cleared,
        1,
        reason: 'dispose must clear the error if it was still surfaced',
      );
    });

    test('no profile push before init settles', () async {
      final controller = await freshController();
      final de1 = _RecordingDe1();
      buildSync(controller);

      // Connect but do NOT settle init.
      await controller.connectToDe1(de1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        de1.setProfileCalls,
        isEmpty,
        reason: 'profile must not be pushed before init settles',
      );

      // Now settle init — the profile should arrive.
      await settleInit(controller, de1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(de1.setProfileCalls.map((p) => p.title), ['Persisted']);
    });

    test('disconnect clears error via onUploadErrorCleared', () async {
      var cleared = 0;
      final controller = await freshController();
      final de1 = _FlakyDe1(failures: 100);
      await controller.connectToDe1(de1);
      await settleInit(controller, de1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // ignore: unused_local_variable
      final syncUnderTest = WorkflowDeviceSync(
        workflowController: wf,
        de1Controller: controller,
        retryDelays: const [Duration(milliseconds: 20)],
        onUploadError: (_) {},
        onUploadErrorCleared: () => cleared++,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cleared, 0);

      de1.setConnectionState(ConnectionState.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        cleared,
        1,
        reason: 'disconnect must retract the error if it was still surfaced',
      );
    });
  });

  group('UnifiedDe1 production cache invalidation', () {
    test('reconnect clears _currentProfile so same-profile upload is not '
        'skipped', () async {
      final transport = FakeBleTransport();
      transport.queueOnConnectResponses();

      final de1 = UnifiedDe1(transport: transport);
      await de1.onConnect();

      final profile = _profile('TestProfile');
      await de1.setProfile(profile);
      final writesAfterFirst = transport.writes.length;

      // Disconnect and reconnect (same UnifiedDe1 instance).
      await de1.disconnect();
      transport.queueOnConnectResponses();
      await de1.onConnect();

      // Upload the same profile again.
      await de1.setProfile(profile);
      final writesAfterReconnect = transport.writes.length;

      // Must have performed fresh writes (not short-circuited).
      expect(
        writesAfterReconnect,
        greaterThan(writesAfterFirst),
        reason: 'same-profile upload after reconnect must perform new writes',
      );

      // A third upload without reconnect must be a no-op.
      final writesBeforeDedup = transport.writes.length;
      await de1.setProfile(profile);
      expect(
        transport.writes.length,
        writesBeforeDedup,
        reason: 'same-profile upload without reconnect must be deduplicated',
      );
    });
  });
}
