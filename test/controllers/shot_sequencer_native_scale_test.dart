import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/shot_sequencer.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/test_de1.dart';
import '../helpers/test_scale.dart';
import '../helpers/test_scale_controller.dart';

class _Discovery extends DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices({ScanFilter? filter}) async {}
}

class _De1Controller extends De1Controller {
  final TestDe1 machine;

  _De1Controller(this.machine)
    : super(controller: DeviceController([_Discovery()]));

  @override
  De1Interface connectedDe1() => machine;

  @override
  Stream<De1Interface?> get de1 => BehaviorSubject.seeded(machine).stream;
}

class _UnusedStorage implements StorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile({
  double? targetVolume,
  double? stepWeight,
  double? secondStepWeight,
}) => Profile(
  version: '2',
  title: 'native scale',
  notes: '',
  author: 'test',
  beverageType: BeverageType.espresso,
  targetVolumeCountStart: 0,
  targetVolume: targetVolume,
  targetWeight: 36,
  tankTemperature: 0,
  steps: [
    ProfileStepPressure(
      name: 'pour',
      transition: TransitionType.fast,
      volume: 0,
      seconds: 30,
      weight: stepWeight,
      temperature: 93,
      sensor: TemperatureSensor.coffee,
      pressure: 9,
    ),
    if (secondStepWeight != null)
      ProfileStepPressure(
        name: 'second pour',
        transition: TransitionType.fast,
        volume: 0,
        seconds: 30,
        weight: secondStepWeight,
        temperature: 93,
        sensor: TemperatureSensor.coffee,
        pressure: 9,
      ),
  ],
);

void main() {
  late TestDe1 machine;
  late TestScale scale;
  late TestScaleController scaleController;
  late _De1Controller de1Controller;
  late PersistenceController persistence;

  setUp(() {
    machine = TestDe1();
    scale = TestScale();
    scaleController = TestScaleController(scale);
    de1Controller = _De1Controller(machine);
    persistence = PersistenceController(storageService: _UnusedStorage());
  });

  tearDown(() {
    machine.dispose();
    scale.dispose();
    scaleController.dispose();
    persistence.dispose();
  });

  ShotSequencer makeShot({
    Duration timeout = const Duration(milliseconds: 100),
    double targetYield = 36,
    double? targetVolume,
    double? stepWeight,
    double? secondStepWeight,
  }) => ShotSequencer(
    scaleController: scaleController,
    de1controller: de1Controller,
    persistenceController: persistence,
    targetProfile: _profile(
      targetVolume: targetVolume,
      stepWeight: stepWeight,
      secondStepWeight: secondStepWeight,
    ),
    targetYield: targetYield,
    bypassSAW: false,
    blockOnNoScale: false,
    weightFlowMultiplier: 0,
    volumeFlowMultiplier: 0,
    stepExitArbiterEnabled: true,
    tareConfirmationTimeout: timeout,
    scaleFreshnessTimeout: timeout,
  );

  void driveToPouring(FakeAsync async) {
    machine.emitStateAndSubstate(
      MachineState.espresso,
      MachineSubstate.preparingForShot,
    );
    machine.emitStateAndSubstate(
      MachineState.espresso,
      MachineSubstate.pouring,
    );
    async.flushMicrotasks();
  }

  void enableAutomaticZero() {
    scale.tareHandler = () async {
      if (scale.tareCallCount == 2) scaleController.emitWeight(0);
    };
  }

  test(
    'machine cadence stays independent and crossings use native samples',
    () {
      fakeAsync((async) {
        final shot = makeShot();
        final states = <ShotState>[];
        final raw = <Object>[];
        final persisted = <Object>[];
        shot.state.listen(states.add);
        shot.rawData.listen(raw.add);
        shot.shotData.listen(persisted.add);

        machine.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.preparingForShot,
        );
        machine.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouring,
        );
        async.flushMicrotasks();
        expect(shot.currentState, ShotState.pouring);
        scaleController.emitWeight(0);
        async.flushMicrotasks();

        final rawBefore = raw.length;
        final persistedBefore = persisted.length;
        scaleController.emitWeight(40);
        for (var i = 0; i < 10; i++) {
          machine.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouring,
          );
        }
        async.flushMicrotasks();
        expect(machine.requestedStates, isNot(contains(MachineState.idle)));
        expect(raw, hasLength(rawBefore + 10));
        expect(persisted, hasLength(persistedBefore + 10));

        scaleController.emitWeight(20);
        scaleController.emitWeight(40);
        expect(machine.requestedStates, isNot(contains(MachineState.idle)));
        scaleController.emitWeight(40);
        async.flushMicrotasks();
        expect(
          machine.requestedStates.where((state) => state == MachineState.idle),
          hasLength(1),
        );
        expect(states.last, ShotState.pouring);
        expect(raw, hasLength(rawBefore + 10));

        machine.emitStateAndSubstate(
          MachineState.espresso,
          MachineSubstate.pouringDone,
        );
        async.flushMicrotasks();
        expect(states, contains(ShotState.stopping));
        expect(
          scale.commandCalls.where((call) => call == 'stop'),
          hasLength(1),
        );
        shot.dispose();
      });
    },
  );

  test('tare success without a zero sample never arms scale control', () {
    fakeAsync((async) {
      final shot = makeShot();
      driveToPouring(async);
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      expect(machine.requestedStates, isEmpty);
      async.elapse(const Duration(milliseconds: 101));
      scaleController.emitWeight(0);
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      expect(machine.requestedStates, isEmpty);
      expect(shot.scaleLost, isTrue);
      shot.dispose();
    });
  });

  test('zero before tare completion arms only after completion', () {
    fakeAsync((async) {
      final pourTare = Completer<void>();
      scale.tareHandler = () {
        if (scale.tareCallCount != 2) return Future.value();
        scaleController.emitWeight(0);
        return pourTare.future;
      };
      final shot = makeShot();
      driveToPouring(async);
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      expect(machine.requestedStates, isEmpty);
      pourTare.complete();
      async.flushMicrotasks();
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      async.flushMicrotasks();
      expect(machine.requestedStates, [MachineState.idle]);
      shot.dispose();
    });
  });

  test('tare completion before zero arms only after the zero sample', () {
    fakeAsync((async) {
      final shot = makeShot();
      driveToPouring(async);
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      expect(machine.requestedStates, isEmpty);
      scaleController.emitWeight(0);
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      async.flushMicrotasks();
      expect(machine.requestedStates, [MachineState.idle]);
      shot.dispose();
    });
  });

  test('tare failure permanently enables volume fallback', () {
    fakeAsync((async) {
      scale.tareHandler = () => scale.tareCallCount == 2
          ? Future.error(StateError('tare failed'))
          : Future.value();
      final shot = makeShot(targetVolume: 1);
      driveToPouring(async);

      var snapshot = machine.snapshotSubject.value;
      machine.emitSnapshot(
        snapshot.copyWith(
          timestamp: snapshot.timestamp.add(const Duration(seconds: 1)),
          flow: 2,
        ),
      );
      snapshot = machine.snapshotSubject.value;
      machine.emitSnapshot(
        snapshot.copyWith(
          timestamp: snapshot.timestamp.add(const Duration(seconds: 1)),
          flow: 2,
        ),
      );
      async.flushMicrotasks();
      expect(machine.requestedStates, [MachineState.idle]);
      expect(shot.scaleLost, isTrue);
      shot.dispose();
    });
  });

  test('disconnect cannot re-arm scale control', () {
    fakeAsync((async) {
      enableAutomaticZero();
      final disconnected = makeShot();
      driveToPouring(async);
      scaleController.emitWeight(40);
      scaleController.simulateDisconnect();
      async.flushMicrotasks();
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      expect(machine.requestedStates, isEmpty);
      expect(disconnected.scaleLost, isTrue);
      disconnected.dispose();
    });
  });

  test('replacement scale samples cannot stop or skip the shot', () {
    fakeAsync((async) {
      enableAutomaticZero();
      final shot = makeShot(stepWeight: 10);
      driveToPouring(async);

      scaleController.simulateScaleSwitch();
      async.flushMicrotasks();
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      async.flushMicrotasks();

      expect(machine.requestedStates, isEmpty);
      expect(shot.scaleLost, isTrue);
      shot.dispose();
    });
  });

  test('stale feed cannot re-arm scale control', () {
    fakeAsync((async) {
      enableAutomaticZero();
      final stale = makeShot();
      driveToPouring(async);
      async.elapse(const Duration(milliseconds: 101));
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      expect(machine.requestedStates, isEmpty);
      expect(stale.scaleLost, isTrue);
      stale.dispose();
    });
  });

  test('pour freshness expires while preparing command is blocked', () {
    fakeAsync((async) {
      final preparingTare = Completer<void>();
      scale.tareHandler = () => preparingTare.future;
      final shot = makeShot(targetYield: 0, targetVolume: 1);
      driveToPouring(async);

      async.elapse(const Duration(milliseconds: 101));
      var snapshot = machine.snapshotSubject.value;
      machine.emitSnapshot(
        snapshot.copyWith(
          timestamp: snapshot.timestamp.add(const Duration(seconds: 1)),
          flow: 2,
        ),
      );
      snapshot = machine.snapshotSubject.value;
      machine.emitSnapshot(
        snapshot.copyWith(
          timestamp: snapshot.timestamp.add(const Duration(seconds: 1)),
          flow: 2,
        ),
      );
      async.flushMicrotasks();

      expect(machine.requestedStates, [MachineState.idle]);
      expect(shot.scaleLost, isTrue);
      preparingTare.complete();
      async.flushMicrotasks();
      shot.dispose();
    });
  });

  test('tare completion does not renew callback freshness', () {
    fakeAsync((async) {
      final pourTare = Completer<void>();
      scale.tareHandler = () {
        if (scale.tareCallCount != 2) return Future.value();
        scaleController.emitWeight(0);
        return pourTare.future;
      };
      final shot = makeShot(targetYield: 0);
      driveToPouring(async);

      async.elapse(const Duration(milliseconds: 90));
      pourTare.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 11));

      expect(shot.scaleLost, isTrue);
      shot.dispose();
    });
  });

  test('profile frame change resets final crossing candidate', () {
    fakeAsync((async) {
      enableAutomaticZero();
      final shot = makeShot();
      driveToPouring(async);

      scaleController.emitWeight(40);
      machine.emitSnapshot(
        machine.snapshotSubject.value.copyWith(profileFrame: 1),
      );
      scaleController.emitWeight(40);
      async.flushMicrotasks();
      expect(machine.requestedStates, isEmpty);

      scaleController.emitWeight(40);
      async.flushMicrotasks();
      expect(machine.requestedStates, [MachineState.idle]);
      shot.dispose();
    });
  });

  test('first profile frame change resets step crossing candidate', () {
    fakeAsync((async) {
      enableAutomaticZero();
      final shot = makeShot(
        targetYield: 0,
        stepWeight: 10,
        secondStepWeight: 10,
      );
      driveToPouring(async);

      scaleController.emitWeight(12);
      machine.emitSnapshot(
        machine.snapshotSubject.value.copyWith(profileFrame: 1),
      );
      scaleController.emitWeight(12);
      async.flushMicrotasks();
      expect(machine.requestedStates, isEmpty);

      scaleController.emitWeight(12);
      async.flushMicrotasks();
      expect(machine.requestedStates, [MachineState.skipStep]);
      shot.dispose();
    });
  });

  test('failed machine stop is owned until machine confirmation', () {
    fakeAsync((async) {
      enableAutomaticZero();
      machine.requestStateHandler = (_) => Future.error(StateError('write'));
      final shot = makeShot();
      final states = <ShotState>[];
      shot.state.listen(states.add);
      driveToPouring(async);
      scaleController.emitWeight(40);
      scaleController.emitWeight(40);
      async.flushMicrotasks();
      expect(machine.requestedStates, [MachineState.idle]);
      expect(states.last, ShotState.pouring);

      machine.requestStateHandler = null;
      machine.emitStateAndSubstate(
        MachineState.espresso,
        MachineSubstate.pouringDone,
      );
      async.flushMicrotasks();
      expect(states, contains(ShotState.stopping));
      expect(scale.commandCalls.where((call) => call == 'stop'), hasLength(1));
      shot.dispose();
    });
  });

  test('blocked reset preserves command order and timer start', () {
    fakeAsync((async) {
      final reset = Completer<void>();
      enableAutomaticZero();
      scale.resetTimerHandler = () => reset.future;
      final shot = makeShot(targetYield: 0);
      driveToPouring(async);
      expect(scale.commandCalls, ['tare', 'reset']);

      reset.complete();
      async.flushMicrotasks();
      expect(scale.commandCalls, ['tare', 'reset', 'tare', 'start']);
      machine.emitStateAndSubstate(
        MachineState.espresso,
        MachineSubstate.pouringDone,
      );
      async.flushMicrotasks();
      expect(scale.commandCalls, ['tare', 'reset', 'tare', 'start', 'stop']);
      shot.dispose();
    });
  });
}
