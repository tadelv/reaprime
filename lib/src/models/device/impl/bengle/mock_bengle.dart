import 'dart:async';

import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/impl/simulated_shot_weight_model.dart';
import 'package:reaprime/src/models/device/led_strip.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/scale_calibration.dart';
import 'package:reaprime/src/models/device/simulated_device.dart';
import 'package:rxdart/rxdart.dart';

/// Simulated Bengle. Reuses [MockDe1]'s state machine — Bengle's behavior
/// today is functionally identical to a DE1 plus the FW-prelude hook
/// (which mocks bypass entirely, since `MockDe1.updateFirmware` is faked
/// at the public level rather than going through the `_updateFirmware`
/// template that calls `beforeFirmwareUpload`).
///
/// Capability surfaces (cup warmer, integrated scale, LED) are
/// mirrored here.
class MockBengle extends MockDe1 implements BengleInterface, SimulatedDevice {
  MockBengle({
    super.deviceId = 'MockBengle',
    bool probeAttached = true,
  }) {
    _probeAttachedSubject =
        BehaviorSubject<bool>.seeded(probeAttached);
  }

  @override
  String get name => 'MockBengle';

  // --- cup warmer ---
  double _cupWarmerTemp = 0.0;

  /// Simulated live mat temperature. Defaults to `null` ("no valid
  /// reading") — matching field firmware without the MatCurrentTemp
  /// register — so consumers exercise the placeholder path by default.
  double? _matCurrentTemp;

  @override
  Future<void> setCupWarmerTemperature(double celsius) async {
    _cupWarmerTemp = celsius.clamp(0.0, 80.0).toDouble();
  }

  @override
  Future<double> getCupWarmerTemperature() async => _cupWarmerTemp;

  @override
  Future<double?> getCupWarmerCurrentTemperature() async => _matCurrentTemp;

  /// Test hook: set the simulated live mat temperature reading.
  /// `null` = no valid reading (the default).
  void setMatCurrentTemperature(double? celsius) {
    _matCurrentTemp = celsius;
  }

  // --- scheduled cup-warmer pre-warm (contract v2) ---
  //
  // Models the firmware honestly: the two settings are PERSISTED (a
  // [simulateReboot] does not clear them, unlike the clock and the wake
  // table), and `prewarmActive` is READ-ONLY — nothing in the public API can
  // set it, only the [setCupWarmerPrewarmActive] test hook (standing in for
  // the firmware's own scheduler).

  bool _prewarmEnabled = false;
  int _prewarmLeadMinutes = 30; // FW default
  bool _prewarmActive = false;

  /// Simulates firmware WITHOUT firmware register-table rows 59–61 (e.g. the bench-flashed
  /// the validated firmware build): the reads report "unavailable" (`null`) and the writes are
  /// silently inert, exactly like a write into unmapped MMR space.
  bool _prewarmSupported = true;

  /// Test hook: does this simulated firmware carry the pre-warm registers?
  /// `false` reproduces the older-firmware degradation path end to end.
  void setPrewarmSupported(bool supported) {
    _prewarmSupported = supported;
  }

  /// The last `MatPreheatEnable` written (`false` when never written).
  bool get prewarmEnabled => _prewarmEnabled;

  /// The last `MatPreheatLeadMin` written (firmware default 30).
  int get prewarmLeadMinutes => _prewarmLeadMinutes;

  /// Test hook: the FIRMWARE-owned `MatPreheatActive` status — the schedule is
  /// driving the mat right now. Read-only over the public API.
  void setCupWarmerPrewarmActive(bool active) {
    _prewarmActive = active;
  }

  @override
  Future<void> setCupWarmerPrewarm(bool enabled, int leadMinutes) async {
    // Writes into unmapped space are silently inert on firmware without the
    // registers — no throw, no effect.
    if (!_prewarmSupported) return;
    _prewarmEnabled = enabled;
    _prewarmLeadMinutes = leadMinutes.clamp(0, 120);
  }

  @override
  Future<CupWarmerPrewarm?> getCupWarmerPrewarm() async => _prewarmSupported
      ? CupWarmerPrewarm(
          enabled: _prewarmEnabled,
          leadMinutes: _prewarmLeadMinutes,
        )
      : null;

  @override
  Future<bool?> getCupWarmerPrewarmActive() async =>
      _prewarmSupported ? _prewarmActive : null;

  // --- LED strip ---
  /// Cache of the last-set config (not necessarily committed to NVM).
  final BehaviorSubject<LedStripState> _ledState =
      BehaviorSubject<LedStripState>.seeded(const LedStripState());

  /// Simulated "FW NVM" — written by commit, read by reset.
  LedStripState _committedLedState = const LedStripState();

  @override
  Stream<LedStripState> get ledStripState => _ledState.stream;

  @override
  Future<LedStripState> getLedStripState() async => _ledState.value;

  @override
  Future<void> setLedStrip(LedStripState state) async {
    _ledState.add(state);
  }

  @override
  Future<void> commitLedStrip() async {
    _committedLedState = _ledState.value;
    // In mock: no actual FW NVM write.
  }

  @override
  Future<void> resetLedStrip() async {
    _ledState.add(_committedLedState);
  }

  @override
  Future<void> previewLedColor(Color16 front, Color16 back) async {
    // Mock: no live strip to preview.
  }

  @override
  Future<void> clearLedPreview() async {
    // Mock: nothing to restore.
  }

  // --- integrated scale ---
  // Weight synthesis lives in the shared SimulatedShotWeightModel (also used
  // by the standalone MockScale): preinfusion absorbed, first-drops holdback,
  // saturation ramp-in, then weight tracking flow 1:1. BehaviorSubject so a
  // late subscriber (e.g. WS client connecting mid-shot) immediately gets the
  // current weight without waiting for the next flow sample. Closed on
  // onDisconnect; existing subscribers receive `done`.
  final SimulatedShotWeightModel _weightModel = SimulatedShotWeightModel();
  final BehaviorSubject<ScaleSnapshot> _weight = BehaviorSubject();
  StreamSubscription<MachineSnapshot>? _flowSub;

  // --- SAW ---
  /// `0.0` = SAW disabled.
  double _sawTarget = 0.0;
  final BehaviorSubject<double> _sawTargetSubject =
      BehaviorSubject<double>.seeded(0.0);

  // --- milk probe / stop-at-temperature ---
  /// `0.0` = stop disabled.
  double _stopAtTempTarget = 0.0;
  final BehaviorSubject<double> _stopAtTempTargetSubject =
      BehaviorSubject<double>.seeded(0.0);
  late final BehaviorSubject<bool> _probeAttachedSubject;
  final PublishSubject<double> _probeTemperatureSubject =
      PublishSubject<double>();

  /// Simulated probe temperature in °C. Rises during `MachineState.steam`
  /// starting from [_probeStartTemp] at [_probeRiseRate] °C per second.
  static const double _probeStartTemp = 4.0;
  static const double _probeRiseRate = 5.0;
  double _probeTemp = _probeStartTemp;
  DateTime? _lastProbeTickAt;

  @override
  Stream<ScaleSnapshot> get weightSnapshot => _weight.stream;

  /// The simulated machine snapshot, enriched with the integrated scale's
  /// synthesised weight and gravimetric flow. A real Bengle's firmware puts
  /// its own gFlow into the shot sample, so `ws/v1/machine/snapshot` carries
  /// `weightFlow`; the plain [MockDe1] leaves both at 0. Overlaying the weight
  /// model here makes the mock behave like the device it mocks, so the machine
  /// surface and the scale surface report the SAME single-source flow instead
  /// of disagreeing by the whole estimator.
  @override
  Stream<MachineSnapshot> get currentSnapshot => super.currentSnapshot.map(
        (s) => s.copyWith(
          weight: _weightModel.weight,
          weightFlow: _weightModel.flow,
        ),
      );

  @override
  Stream<double> get stopAtWeightTarget => _sawTargetSubject.stream;

  @override
  Future<void> setStopAtWeightTarget(double grams) async {
    _sawTarget = grams.clamp(0.0, 10000.0).toDouble();
    if (!_sawTargetSubject.isClosed) {
      _sawTargetSubject.add(_sawTarget);
    }
  }

  @override
  Future<double> getStopAtWeightTarget() async => _sawTarget;

  // --- milk probe surface ---

  @override
  Stream<double> get stopAtTemperatureTarget =>
      _stopAtTempTargetSubject.stream;

  @override
  Stream<bool> get probeAttached => _probeAttachedSubject.stream;

  @override
  Stream<double> get probeTemperature => _probeTemperatureSubject.stream;

  @override
  Future<void> setStopAtTemperatureTarget(double celsius) async {
    // 0..85 matches the real Bengle (TargetMilkTemp FW max 850 deci-°C) —
    // NB wider than the cup-warmer's 0..80.
    _stopAtTempTarget = celsius.clamp(0.0, 85.0).toDouble();
    if (!_stopAtTempTargetSubject.isClosed) {
      _stopAtTempTargetSubject.add(_stopAtTempTarget);
    }
  }

  @override
  Future<double> getStopAtTemperatureTarget() async => _stopAtTempTarget;

  /// Test hook: toggle the simulated probe-attached state.
  void setProbeAttached(bool attached) {
    if (!_probeAttachedSubject.isClosed) {
      _probeAttachedSubject.add(attached);
    }
  }

  // --- autonomous sleep + wake schedule ---
  //
  // Models the firmware's registers closely enough to be honest: the clock and
  // the table are RAM-only (a [simulateReboot] wipes them, exactly as a real
  // power-cycle does), the sleep timeout persists, and the reads are WRITE
  // ECHOES, not live state.

  int _inactivitySleepTimeout = 60; // FW default
  int _localTimeOfWeekEcho = 0; // 0 = never synced since boot
  int _scheduleControl = 0;
  List<int> _wakeScheduleTable = const [];

  /// Last `InactivitySleepTimeout` written (minutes; persisted in FW).
  int get inactivitySleepTimeout => _inactivitySleepTimeout;

  /// Last `SetLocalTimeOfWeek` written. `0` = never synced since boot.
  int get localTimeOfWeekEcho => _localTimeOfWeekEcho;

  /// The simulated firmware wake table (packed windows).
  List<int> get wakeScheduleTable => List.unmodifiable(_wakeScheduleTable);

  /// Whether the simulated firmware schedule is enabled.
  bool get scheduleEnabled => _scheduleControl == 1;

  @override
  Future<void> setInactivitySleepTimeout(int minutes) async {
    _inactivitySleepTimeout = minutes.clamp(0, 240);
  }

  @override
  Future<void> setLocalTimeOfWeek(int secondsOfWeek) async {
    _localTimeOfWeekEcho = secondsOfWeek.clamp(1, 604799);
  }

  @override
  Future<void> pushWakeSchedule(List<int> packedWindows) async {
    // ScheduleControl = 0 clears the table AND disables.
    _wakeScheduleTable = const [];
    _scheduleControl = 0;
    if (packedWindows.isEmpty) return;
    _wakeScheduleTable = List.of(packedWindows.take(32));
    _scheduleControl = 1;
  }

  @override
  Future<int> readLocalTimeOfWeekEcho() async => _localTimeOfWeekEcho;

  @override
  Future<int> readScheduleControl() async => _scheduleControl;

  /// Test hook: simulate a machine power-cycle. The clock and the schedule
  /// table are RAM-only in firmware and do not survive; the sleep timeout and
  /// the pre-warm settings (`MatPreheatEnable` / `MatPreheatLeadMin`, both
  /// PERM_RWD) are persisted and do.
  void simulateReboot() {
    _localTimeOfWeekEcho = 0;
    _scheduleControl = 0;
    _wakeScheduleTable = const [];
  }

  @override
  Future<void> tareIntegratedScale() async {
    _weightModel.tare();
    _emit();
  }

  // --- load-cell calibration (two-point) ---
  // Behavioural mock: each step "succeeds" immediately (no real load cells to
  // settle). Emits a terminal status so progress subscribers see a completion,
  // then returns a successful result. Left latch => Incomplete (awaiting
  // right); right latch / zero => Ok / none. NB: the seeded idle/done status
  // is mock-only convenience — the real mixin starts an EMPTY BehaviorSubject
  // (no synthetic initial status); do not copy the seed there.
  final BehaviorSubject<ScaleCalStatus> _calProgress =
      BehaviorSubject<ScaleCalStatus>.seeded(
        const ScaleCalStatus(
          step: ScaleCalStep.idle,
          subState: ScaleCalSubState.done,
          remainingSeconds: 0,
          pointStatus: ScaleCalPointStatus.none,
          raw: 0,
        ),
      );

  @override
  Stream<ScaleCalStatus> get scaleCalibrationProgress => _calProgress.stream;

  @override
  Future<ScaleCalResult> calibrateScaleZero() async =>
      _mockCalComplete(ScaleCalPointStatus.none);

  @override
  Future<ScaleCalResult> calibrateScaleWeightLeft(double grams) async =>
      _mockCalComplete(ScaleCalPointStatus.incomplete);

  @override
  Future<ScaleCalResult> calibrateScaleWeightRight(double grams) async =>
      _mockCalComplete(ScaleCalPointStatus.ok);

  @override
  Future<void> abortScaleCalibration() async {}

  ScaleCalResult _mockCalComplete(ScaleCalPointStatus pointStatus) {
    if (!_calProgress.isClosed) {
      _calProgress.add(
        ScaleCalStatus(
          step: ScaleCalStep.complete,
          subState: ScaleCalSubState.done,
          remainingSeconds: 0,
          pointStatus: pointStatus,
          raw: 0,
        ),
      );
    }
    return ScaleCalResult(
      success: true,
      finalStep: ScaleCalStep.complete,
      pointStatus: pointStatus,
    );
  }

  void _emit() {
    if (_weight.isClosed) return;
    _weight.add(ScaleSnapshot(
      timestamp: DateTime.now(),
      weight: _weightModel.weight,
      // Report the synthesised gravimetric flow so ScaleController takes the
      // device-flow path (no estimator), exactly as a real Bengle's firmware
      // gFlow does — the opt-out this branch introduces.
      flow: _weightModel.flow,
      batteryLevel: 100,
    ));
  }

  @override
  Future<void> onConnect() async {
    if (_ledState.isClosed) {
      _ledState.add(const LedStripState());
    }
    await super.onConnect();
    _weightModel.reset();
    _emit();
    _flowSub = currentSnapshot.listen(_integrateFlow);
  }

  void _integrateFlow(MachineSnapshot s) {
    _weightModel
      ..targetVolumeCountStart = targetVolumeCountStart
      ..ingest(s);
    _emit();
    _maybeTriggerSaw(s);
    _tickProbeTemperature(s, s.timestamp);
  }

  /// Synthesises milk-probe temperature during `MachineState.steam`.
  /// Rises linearly from [_probeStartTemp]; resets when steam exits.
  /// If [_stopAtTempTarget] is set and reached, requests `idle` — the
  /// FW-autonomous stop behaviour the real Bengle performs when a probe
  /// is attached (`TargetMilkTemp`).
  void _tickProbeTemperature(MachineSnapshot s, DateTime now) {
    if (!(_probeAttachedSubject.hasValue && _probeAttachedSubject.value)) {
      _lastProbeTickAt = null;
      _probeTemp = _probeStartTemp;
      return;
    }
    if (s.state.state != MachineState.steam) {
      _lastProbeTickAt = null;
      _probeTemp = _probeStartTemp;
      return;
    }
    final last = _lastProbeTickAt;
    _lastProbeTickAt = now;
    if (last == null) return;
    final dtSec = now.difference(last).inMilliseconds / 1000.0;
    if (dtSec <= 0) return;
    _probeTemp += _probeRiseRate * dtSec;
    if (!_probeTemperatureSubject.isClosed) {
      _probeTemperatureSubject.add(_probeTemp);
    }
    if (_stopAtTempTarget > 0.0 && _probeTemp >= _stopAtTempTarget) {
      // ignore: discarded_futures
      requestState(MachineState.idle);
    }
  }

  /// Simulated autonomous SAW. Once the post-tare weight reaches the
  /// active target and the machine is mid-shot (`espresso`/`pouring`),
  /// requests `MachineState.idle` to halt the shot — same effect as the
  /// real Bengle FW would have on its own integrated scale.
  void _maybeTriggerSaw(MachineSnapshot s) {
    if (_sawTarget <= 0.0) return;
    if (s.state.state != MachineState.espresso) return;
    if (s.state.substate != MachineSubstate.preinfusion &&
        s.state.substate != MachineSubstate.pouring) {
      return;
    }
    if (_weightModel.weight >= _sawTarget) {
      // ignore: discarded_futures
      requestState(MachineState.idle);
    }
  }

  @override
  Future<void> onDisconnect() async {
    await _flowSub?.cancel();
    _flowSub = null;
    if (!_ledState.isClosed) {
      await _ledState.close();
    }
    if (!_weight.isClosed) {
      await _weight.close();
    }
    if (!_sawTargetSubject.isClosed) {
      await _sawTargetSubject.close();
    }
    if (!_stopAtTempTargetSubject.isClosed) {
      await _stopAtTempTargetSubject.close();
    }
    if (!_probeAttachedSubject.isClosed) {
      await _probeAttachedSubject.close();
    }
    if (!_probeTemperatureSubject.isClosed) {
      await _probeTemperatureSubject.close();
    }
    if (!_calProgress.isClosed) {
      await _calProgress.close();
    }
    await super.onDisconnect();
  }

  @override
  MachineInfo get machineInfo => MachineInfo(
        version: '1.0',
        model: 'Bengle',
        serialNumber: 'mock-bengle',
        groupHeadControllerPresent: true,
        extra: {'voltage': 220, 'refillKit': false},
      );
}
