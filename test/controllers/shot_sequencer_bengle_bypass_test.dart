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
import 'package:reaprime/src/models/data/steam_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/led_strip.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_virtual_scale.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/test_de1.dart';

/// Bengle-flavoured TestDe1: reuses every DE1-side behavior but also
/// implements [BengleInterface] so `machine is BengleInterface` returns
/// `true`. The SAW methods record calls; `noSuchMethod` is unused here
/// because TestDe1 already covers the full De1Interface surface.
class _TestBengle extends TestDe1 implements BengleInterface {
  final List<double> sawWrites = [];
  final BehaviorSubject<ScaleSnapshot> _weight = BehaviorSubject(sync: true);
  int tareCalls = 0;

  @override
  Future<void> setStopAtWeightTarget(double grams) async {
    sawWrites.add(grams);
  }

  @override
  Future<double> getStopAtWeightTarget() async => 0.0;

  @override
  Stream<double> get stopAtWeightTarget => const Stream.empty();

  @override
  Future<void> setCupWarmerTemperature(double celsius) async {}
  @override
  Future<double> getCupWarmerTemperature() async => 0.0;
  @override
  Stream<ScaleSnapshot> get weightSnapshot => _weight.stream;
  @override
  Future<void> tareIntegratedScale() async {
    tareCalls++;
    if (tareCalls == 2) _emitWeight(0);
  }

  @override
  Stream<LedStripState> get ledStripState => const Stream.empty();
  @override
  Future<LedStripState> getLedStripState() async => const LedStripState();
  @override
  Future<void> setLedStrip(LedStripState state) async {}
  @override
  Future<void> commitLedStrip() async {}
  @override
  Future<void> resetLedStrip() async {}

  @override
  Future<void> setStopAtTemperatureTarget(double celsius) async {}
  @override
  Future<double> getStopAtTemperatureTarget() async => 0.0;
  @override
  Stream<double> get stopAtTemperatureTarget => const Stream.empty();
  @override
  Stream<bool> get probeAttached => const Stream.empty();
  @override
  Stream<double> get probeTemperature => const Stream.empty();

  void emitIntegratedSample(double weight) {
    emitStateAndSubstate(
      snapshotSubject.value.state.state,
      snapshotSubject.value.state.substate,
    );
    _emitWeight(weight);
  }

  void _emitWeight(double weight) {
    _weight.add(
      ScaleSnapshot(
        timestamp: DateTime(2026, 1, 15, 8, 0),
        weight: weight,
        batteryLevel: 100,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _weight.close();
    await super.dispose();
  }
}

class _FakeDiscoveryService extends DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanForDevices({ScanFilter? filter}) async {}
}

class _BengleDe1Controller extends De1Controller {
  final _TestBengle bengle;

  _BengleDe1Controller(this.bengle)
    : super(controller: DeviceController([_FakeDiscoveryService()]));

  @override
  De1Interface connectedDe1() => bengle;

  @override
  Stream<De1Interface?> get de1 => BehaviorSubject.seeded(bengle).stream;
}

class _BengleScaleController extends ScaleController {
  final BengleVirtualScale scale;

  _BengleScaleController(this.scale);

  @override
  Stream<ConnectionState> get connectionState => scale.connectionState;

  @override
  ConnectionState get currentConnectionState => ConnectionState.connected;

  @override
  ({Scale scale, int generation})? get currentScaleLease =>
      (scale: scale, generation: connectionGeneration);

  @override
  Stream<WeightSnapshot> get weightSnapshot => scale.currentSnapshot.map(
    (snapshot) => WeightSnapshot(
      timestamp: snapshot.timestamp,
      weight: snapshot.weight,
      weightFlow: 0,
      battery: snapshot.batteryLevel,
      timerValue: snapshot.timerValue,
    ),
  );

  @override
  Scale connectedScale() => scale;
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

Profile _simpleProfile({double? stepWeight}) => Profile(
  version: '2',
  title: 'T',
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
      weight: stepWeight,
      temperature: 93,
      sensor: TemperatureSensor.coffee,
      pressure: 9,
    ),
  ],
);

void main() {
  group(
    'ShotSequencer bypasses app-side SAW when machine is BengleInterface',
    () {
      late _TestBengle bengle;
      late _BengleDe1Controller de1Controller;
      late ScaleController scaleController;
      late PersistenceController persistence;
      late Profile profile;

      setUp(() {
        bengle = _TestBengle();
        de1Controller = _BengleDe1Controller(bengle);
        scaleController = _BengleScaleController(BengleVirtualScale(bengle));
        persistence = PersistenceController(
          storageService: _NullStorageService(),
        );
        profile = _simpleProfile();
      });

      tearDown(() async {
        scaleController.dispose();
        await bengle.dispose();
        persistence.dispose();
      });

      test(
        'does not request idle even when projected weight exceeds target',
        () {
          fakeAsync((async) {
            final shot = ShotSequencer(
              scaleController: scaleController,
              de1controller: de1Controller,
              persistenceController: persistence,
              targetProfile: profile,
              targetYield: 30.0,
              bypassSAW: false,
              blockOnNoScale: false,
              weightFlowMultiplier: 0.0,
              volumeFlowMultiplier: 0.0,
              stepExitArbiterEnabled: true,
            );

            async.elapse(const Duration(milliseconds: 10));

            // idle → preheating
            bengle.emitStateAndSubstate(
              MachineState.espresso,
              MachineSubstate.preparingForShot,
            );
            // preheating → pouring
            bengle.emitStateAndSubstate(
              MachineState.espresso,
              MachineSubstate.pouring,
            );
            async.elapse(const Duration(milliseconds: 10));

            // Weight blows past the target. App SAW would normally fire.
            bengle.emitIntegratedSample(40.0);
            async.elapse(const Duration(milliseconds: 10));

            expect(
              bengle.requestedStates,
              isEmpty,
              reason:
                  'BengleInterface machine runs autonomous SAW; ShotSequencer '
                  'must not double-stop the shot',
            );

            shot.dispose();
          });
        },
      );

      test('keeps machine cadence and app-side step exits', () {
        fakeAsync((async) {
          final nativeWeights = <WeightSnapshot>[];
          final weightSubscription = scaleController.weightSnapshot.listen(
            nativeWeights.add,
          );
          final shot = ShotSequencer(
            scaleController: scaleController,
            de1controller: de1Controller,
            persistenceController: persistence,
            targetProfile: _simpleProfile(stepWeight: 10),
            targetYield: 30,
            bypassSAW: false,
            blockOnNoScale: false,
            weightFlowMultiplier: 0,
            volumeFlowMultiplier: 0,
            stepExitArbiterEnabled: true,
          );
          final states = <ShotState>[];
          final raw = <Object>[];
          final persisted = <Object>[];
          shot.state.listen(states.add);
          shot.rawData.listen(raw.add);
          shot.shotData.listen(persisted.add);

          bengle.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.preparingForShot,
          );
          bengle.emitStateAndSubstate(
            MachineState.espresso,
            MachineSubstate.pouring,
          );
          async.flushMicrotasks();
          final rawBefore = raw.length;
          final persistedBefore = persisted.length;

          bengle.emitIntegratedSample(12);
          bengle.emitIntegratedSample(12);
          async.flushMicrotasks();
          expect(bengle.tareCalls, 2);
          expect(nativeWeights.map((sample) => sample.weight), [0, 12, 12]);
          expect(shot.scaleLost, isFalse);
          expect(bengle.requestedStates, [MachineState.skipStep]);
          expect(raw, hasLength(rawBefore + 2));
          expect(persisted, hasLength(persistedBefore + 2));
          expect(
            states.where((state) => state == ShotState.pouring),
            hasLength(1),
          );

          expect(bengle.requestedStates, isNot(contains(MachineState.idle)));
          shot.dispose();
          weightSubscription.cancel();
        });
      });
    },
  );
}
