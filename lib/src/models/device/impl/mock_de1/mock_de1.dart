import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/subjects.dart';

// steam and hotWater are placeholders for future simulation modes.
// ignore: unused_field
enum _SimulationType { espresso, steam, hotWater, idle }

class MockDe1 implements De1Interface {
  MockDe1({String deviceId = "MockDe1"}) : _deviceId = deviceId;

  final StreamController<MachineSnapshot> _snapshotStream =
      StreamController.broadcast();

  final _log = Logger("MockDe1");

  Timer? _stateTimer;

  MachineSnapshot _lastSnapshot = MachineSnapshot(
    flow: 0,
    state: MachineStateSnapshot(
      state: MachineState.idle,
      substate: MachineSubstate.pouring,
    ),
    steamTemperature: 0,
    profileFrame: 0,
    targetFlow: 0,
    targetPressure: 0,
    targetMixTemperature: 0,
    targetGroupTemperature: 0,
    timestamp: DateTime.now(),
    groupTemperature: 0,
    mixTemperature: 0,
    pressure: 0,
  );

  MachineState _currentState = MachineState.booting;
  _SimulationType _simulationType = _SimulationType.idle;

  // Add profile tracking fields
  Profile? _currentProfile;
  int _currentProfileStepIndex = 0;
  double _profileStepElapsedTime = 0.0; // in milliseconds
  double _profileTargetTemperature = 94.0; // Default if no profile
  int _targetVolumeCountStart = 0;
  // Smooth transition interpolation: targets at step entry.
  double _fromFlowTarget = 0;
  double _fromPressureTarget = 0;

  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshotStream.stream;

  final String _deviceId;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "MockDe1";

  @override
  MachineInfo get machineInfo => MachineInfo(
    version: "1337",
    model: "3",
    serialNumber: "0001",
    groupHeadControllerPresent: false,
    extra: {},
  );

  @override
  Future<void> requestState(MachineState newState) async {
    _currentState = newState;
    if (_currentState == MachineState.espresso) {
      shotTime = 0.0;
      _simulationType = _SimulationType.espresso;
      // Reset profile tracking when starting espresso
      _currentProfileStepIndex = 0;
      _profileStepElapsedTime = 0.0;
      _espressoTickCount = 0;
      _pouringDoneTicks = 0;
      _fromFlowTarget = 0;
      _fromPressureTarget = 0;
    } else if (_currentState == MachineState.skipStep &&
        _simulationType == _SimulationType.espresso &&
        _currentProfile != null) {
      // skipStep: advance to next profile step immediately.
      // ShotController owns the skip decision (weight-based); the mock
      // just advances the step index and continues simulating.
      if (_currentProfileStepIndex < _currentProfile!.steps.length - 1) {
        // Capture current step targets for smooth transition.
        _captureFromTargets(_currentProfile!.steps[_currentProfileStepIndex]);
        _currentProfileStepIndex++;
        _profileStepElapsedTime = 0.0;
        _espressoTickCount = 0; // reset preparingForShot for new step
        _log.fine("skipStep: advanced to step $_currentProfileStepIndex");
      }
      // If already on the last step, skipStep is a no-op — the step
      // will complete naturally via its duration.
      _currentState = MachineState.espresso; // stay in espresso
    } else {
      _simulationType = _SimulationType.idle;
    }
  }

  @override
  Future<void> onConnect() async {
    _currentState = MachineState.idle;
    _simulateState();
  }

  @override
  disconnect() async {
    // Mirror UnifiedDe1.disconnect(): run onDisconnect() so subclass
    // overrides (e.g. MockBengle's integrated-scale teardown, this
    // class's _stateTimer cancel) actually fire when the simulated
    // machine "disconnects".
    await onDisconnect();
  }

  @override
  DeviceType get type => DeviceType.machine;

  DateTime lastIdleSnapshot = DateTime.now();
  void _simulateState() {
    _snapshotStream.add(_lastSnapshot);

    _stateTimer = Timer.periodic(Duration(milliseconds: 100), (t) {
      MachineSnapshot newSnapshot;
      switch (_simulationType) {
        case _SimulationType.espresso:
          newSnapshot = _simulateEspresso();
          break;
        case _SimulationType.idle:
          if (DateTime.now().difference(lastIdleSnapshot).inMilliseconds <
              500) {
            return;
          }
          lastIdleSnapshot = DateTime.now();
          newSnapshot = _simulateIdle();
        default:
          newSnapshot = _simulateIdle();
      }
      _snapshotStream.add(newSnapshot);
      _lastSnapshot = newSnapshot;
    });
  }

  MachineSnapshot _simulateIdle() {
    // Use profile target temperature or default
    final targetTemp = _profileTargetTemperature;

    // Faster heating when far from target, slower when close
    double tempChangeRate = 0.5; // degrees per 500ms
    if ((_lastSnapshot.mixTemperature - targetTemp).abs() < 5) {
      tempChangeRate = 0.2;
    }

    final newMixTemp = _calculateTemperature(
      current: _lastSnapshot.mixTemperature,
      target: targetTemp,
      rate: tempChangeRate,
    );

    final newGroupTemp = _calculateTemperature(
      current: _lastSnapshot.groupTemperature,
      target: targetTemp,
      rate: tempChangeRate,
    );

    return MachineSnapshot(
      timestamp: lastIdleSnapshot,
      state: MachineStateSnapshot(
        state: _currentState,
        substate: MachineSubstate.idle,
      ),
      flow: 0,
      pressure: 0,
      targetFlow: 0,
      targetPressure: 0,
      mixTemperature: newMixTemp,
      groupTemperature: newGroupTemp,
      targetMixTemperature: targetTemp,
      targetGroupTemperature: targetTemp,
      profileFrame: 0,
      steamTemperature: min(_lastSnapshot.steamTemperature + 1, 150),
    );
  }

  double shotTime = 0.0;
  int _espressoTickCount = 0;
  int _pouringDoneTicks = 0;

  MachineSnapshot _simulateEspresso() {
    MachineSubstate substate = _lastSnapshot.state.substate;

    // Determine substate based on pressure
    switch (_lastSnapshot.pressure) {
      case < 0.5:
        substate = MachineSubstate.preparingForShot;
        break;
      case > 1.0:
        substate = MachineSubstate.pouring;
      default:
        break;
    }

    shotTime +=
        DateTime.now().millisecondsSinceEpoch -
        _lastSnapshot.timestamp.millisecondsSinceEpoch;

    // If we have a profile, use it for simulation
    if (_currentProfile != null && _currentProfile!.steps.isNotEmpty) {
      return _simulateWithProfile();
    }

    // Fallback to original simulation if no profile
    if (shotTime > 30000) {
      _simulationType = _SimulationType.idle;
      _currentState = MachineState.idle;
    }
    return _fallbackEspressoSimulation(substate);
  }

  MachineSnapshot _simulateWithProfile() {
    if (_currentProfile == null) {
      return _fallbackEspressoSimulation(_lastSnapshot.state.substate);
    }

    // Update elapsed time for current step
    _profileStepElapsedTime += 100; // Timer runs every 100ms

    // Get current step
    final currentStep = _currentProfile!.steps[_currentProfileStepIndex];

    // Check if we should move to next step
    final stepDurationMs = currentStep.seconds * 1000;
    if (_profileStepElapsedTime >= stepDurationMs && _pouringDoneTicks == 0) {
      if (_currentProfileStepIndex < _currentProfile!.steps.length - 1) {
        // Capture current step targets as "from" for smooth transition interpolation.
        _captureFromTargets(currentStep);
        // Move to next step
        _currentProfileStepIndex++;
        _profileStepElapsedTime = 0.0;
        _log.fine("Moving to profile step: $_currentProfileStepIndex");
      } else {
        // Last step is done — trigger pouringDone transition (don't go to idle yet).
        _pouringDoneTicks = 3;
        _log.fine("Profile completed, pouringDone transition");
      }
    }

    // Calculate progress through current step (0.0 to 1.0)
    final stepProgress =
        stepDurationMs > 0
            ? min(_profileStepElapsedTime / stepDurationMs, 1.0)
            : 0.0;

    // Calculate temperature movement toward target
    final targetTemp = currentStep.temperature;
    // Adjust heating rate based on step progress - slower near target
    final heatingRate = 0.1 * (1.0 - stepProgress * 0.5);
    final newMixTemp = _calculateTemperature(
      current: _lastSnapshot.mixTemperature,
      target: targetTemp,
      rate: heatingRate, // degrees per 100ms
    );

    final newGroupTemp = _calculateTemperature(
      current: _lastSnapshot.groupTemperature,
      target: targetTemp,
      rate: heatingRate,
    );

    // --- Flow → Pressure coupling model ---
    // Constants (tuned for visual believability from shot history):
    const baseResistance = 2.5; // bar/(mL/s) — pressure per unit flow
    const resistanceGrowth = 0.3; // 30% increase over step (puck compression)
    const flowResponseRate = 0.7; // per-tick convergence toward flow target
    const pressureDamping = 0.3; // per-tick convergence toward pressure eq

    // Resistance grows over step duration (puck compression).
    final resistance = baseResistance * (1.0 + resistanceGrowth * stepProgress);

    // Determine flow/pressure targets from step type.
    double targetFlow;
    double targetPressure;
    double stepTargetFlow; // what the profile step prescribes (for snapshot)
    double stepTargetPressure; // what the profile step prescribes (for snapshot)
    if (currentStep is ProfileStepPressure) {
      stepTargetPressure = currentStep.pressure;
      stepTargetFlow = 0; // unconstrained in this step
      targetPressure = currentStep.pressure;
      targetFlow = 8.0; // internal: pump max ~8 mL/s
    } else if (currentStep is ProfileStepFlow) {
      stepTargetFlow = currentStep.flow;
      stepTargetPressure = 0; // unconstrained in this step
      targetFlow = currentStep.flow;
      targetPressure = 0; // internal: unconstrained, coupling sets pressure
    } else {
      stepTargetFlow = 4.0;
      stepTargetPressure = 0.0;
      targetFlow = 4.0;
      targetPressure = 0.0;
    }

    // Apply transition shaping: smooth interpolates target over step duration;
    // fast uses step target immediately.
    if (currentStep.transition == TransitionType.smooth) {
      targetFlow = _fromFlowTarget +
          (targetFlow - _fromFlowTarget) * stepProgress;
      targetPressure = _fromPressureTarget +
          (targetPressure - _fromPressureTarget) * stepProgress;
      stepTargetFlow = _fromFlowTarget +
          (stepTargetFlow - _fromFlowTarget) * stepProgress;
      stepTargetPressure = _fromPressureTarget +
          (stepTargetPressure - _fromPressureTarget) * stepProgress;
    }

    // Flow responds quickly (pump-driven).
    double newFlow = _lastSnapshot.flow +
        (targetFlow - _lastSnapshot.flow) * flowResponseRate;

    // Pressure lags behind flow (puck-mediated).
    final unboundedPressure = newFlow * resistance;
    double newPressure = _lastSnapshot.pressure +
        (unboundedPressure - _lastSnapshot.pressure) * pressureDamping;

    // Pressure-step: clamp flow when pressure hits the step's ceiling.
    if (currentStep is ProfileStepPressure) {
      if (newPressure >= targetPressure) {
        newPressure = targetPressure;
        // Flow rate that maintains target pressure against puck resistance.
        newFlow = targetPressure / resistance;
      }
    }

    // Clamp flow-step: don't exceed target (pump can't deliver more).
    if (currentStep is ProfileStepFlow && newFlow > targetFlow) {
      newFlow = targetFlow;
    }

    // Physical pressure ceiling (real DE1 max ~10.5 bar, cap at 12).
    const physicalMaxPressure = 12.0;
    if (newPressure > physicalMaxPressure) {
      newPressure = physicalMaxPressure;
      newFlow = physicalMaxPressure / resistance;
    }

    _espressoTickCount++;

    // Derive substate from profile position, not pressure thresholds.
    // First 500ms (5 ticks): preparingForShot.
    // Then: preinfusion (frame < targetVolumeCountStart) or pouring (frame >=).
    MachineSubstate substate;
    if (_pouringDoneTicks > 0) {
      substate = MachineSubstate.pouringDone;
      _pouringDoneTicks--;
      if (_pouringDoneTicks == 0) {
        _simulationType = _SimulationType.idle;
        _currentState = MachineState.idle;
      }
    } else if (_espressoTickCount <= 5) {
      // First ~500ms (5 ticks @ 100ms)
      substate = MachineSubstate.preparingForShot;
    } else if (_currentProfileStepIndex < _targetVolumeCountStart) {
      substate = MachineSubstate.preinfusion;
    } else {
      substate = MachineSubstate.pouring;
    }

    return MachineSnapshot(
      timestamp: DateTime.now(),
      state: MachineStateSnapshot(state: _currentState, substate: substate),
      flow: newFlow,
      pressure: newPressure,
      targetFlow: stepTargetFlow,
      targetPressure: stepTargetPressure,
      mixTemperature: newMixTemp,
      groupTemperature: newGroupTemp,
      targetMixTemperature: targetTemp,
      targetGroupTemperature: targetTemp,
      profileFrame: _currentProfileStepIndex,
      steamTemperature:
          _calculateTemperature(
            current: _lastSnapshot.steamTemperature.toDouble(),
            target: 150.0,
            rate: 0.2,
          ).toInt(),
    );
  }

  MachineSnapshot _fallbackEspressoSimulation(MachineSubstate substate) {
    return MachineSnapshot(
      timestamp: DateTime.now(),
      state: MachineStateSnapshot(state: _currentState, substate: substate),
      flow: min(_lastSnapshot.flow + 0.05, 4.0),
      pressure: min(_lastSnapshot.pressure + 0.04, 9.0),
      targetFlow: 4.5,
      targetPressure: 9.0,
      mixTemperature: _calculateTemperature(
        current: _lastSnapshot.mixTemperature,
        target: _profileTargetTemperature,
        rate: 0.1,
      ),
      groupTemperature: _calculateTemperature(
        current: _lastSnapshot.groupTemperature,
        target: _profileTargetTemperature,
        rate: 0.1,
      ),
      targetMixTemperature: _profileTargetTemperature,
      targetGroupTemperature: _profileTargetTemperature,
      profileFrame: 0,
      steamTemperature: min(_lastSnapshot.steamTemperature + 1, 150),
    );
  }

  /// Snapshot the current step's targets so smooth transitions can interpolate from them.
  void _captureFromTargets(ProfileStep step) {
    if (step is ProfileStepPressure) {
      _fromPressureTarget = step.pressure;
      _fromFlowTarget = 0;
    } else if (step is ProfileStepFlow) {
      _fromFlowTarget = step.flow;
      _fromPressureTarget = 0;
    }
  }

  double _calculateTemperature({
    required double current,
    required double target,
    required double rate,
  }) {
    if ((current - target).abs() < rate) {
      return target;
    }
    if (current < target) {
      return min(current + rate, target);
    } else {
      return max(current - rate, target);
    }
  }

  Future<void> onDisconnect() async {
    _stateTimer?.cancel();
  }

  bool _chargerOn = false;
  int _steamPurgeMode = 0; // 0 = normal, 1 = two tap stop
  double _flowEstimation = 1.0;

  @override
  Future<bool> getUsbChargerMode() async {
    return _chargerOn;
  }

  @override
  Future<void> setUsbChargerMode(bool t) async {
    _chargerOn = t;
  }

  @override
  Future<double> getFlowEstimation() async {
    return _flowEstimation;
  }

  @override
  Future<void> setFlowEstimation(double multiplier) async {
    _flowEstimation = multiplier;
  }

  @override
  Future<int> getSteamPurgeMode() async {
    return _steamPurgeMode;
  }

  @override
  Future<void> setSteamPurgeMode(int mode) async {
    _steamPurgeMode = mode;
  }

  @override
  Future<void> setProfile(Profile profile) async {
    _log.info("set profile: ${profile.title}");

    // Store the profile and extract target temperature
    _currentProfile = profile;
    _targetVolumeCountStart = profile.targetVolumeCountStart;

    if (profile.steps.isNotEmpty) {
      // Use first step's temperature as target
      _profileTargetTemperature = profile.steps.first.temperature;
      _log.fine("Target temperature set to: $_profileTargetTemperature");

      // Log step durations for debugging
      for (var i = 0; i < profile.steps.length; i++) {
        final step = profile.steps[i];
        _log.fine(
          "Step $i: ${step.name} - ${step.seconds}s, Temp: ${step.temperature}°C",
        );
        if (step is ProfileStepPressure) {
          _log.fine("  Pressure: ${step.pressure} bar");
        } else if (step is ProfileStepFlow) {
          _log.fine("  Flow: ${step.flow} ml/s");
        }
      }
    }

    // Reset profile tracking
    _currentProfileStepIndex = 0;
    _profileStepElapsedTime = 0.0;
  }

  @override
  Future<void> setRefillLevel(int newRefillLevel) async {}

  final StreamController<De1ShotSettings> _shotSettingsController =
      BehaviorSubject.seeded(
        De1ShotSettings(
          steamSetting: 0,
          targetSteamTemp: 150,
          targetSteamDuration: 60,
          targetHotWaterTemp: 85,
          targetHotWaterVolume: 100,
          targetHotWaterDuration: 35,
          targetShotVolume: 36,
          groupTemp: 94,
        ),
      );

  @override
  Stream<De1ShotSettings> get shotSettings =>
      _shotSettingsController.stream.distinct();

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {
    _shotSettingsController.add(newSettings);
  }

  @override
  Stream<De1WaterLevels> get waterLevels =>
      Stream.periodic(Duration(seconds: 1), (_) {
        return De1WaterLevels(currentLevel: 50.0, refillLevel: 5.0);
      });

  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.connected);

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Future<int> getFanThreshhold() async {
    return 50;
  }

  @override
  Future<void> setFanThreshhold(int temp) async {}

  double _steamFlow = 1.0;
  @override
  Future<double> getSteamFlow() {
    return Future(() {
      return _steamFlow;
    });
  }

  @override
  Future<void> setSteamFlow(double newFlow) async {
    _steamFlow = newFlow;
  }

  double _hotWaterFlow = 1.0;
  @override
  Future<double> getHotWaterFlow() async {
    return _hotWaterFlow;
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    _hotWaterFlow = newFlow;
  }

  double _flushFlow = 1.0;
  @override
  Future<double> getFlushFlow() async {
    return _flushFlow;
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    _flushFlow = newFlow;
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) async {}

  @override
  Future<double> getFlushTimeout() async {
    return 10.0;
  }

  @override
  Future<double> getFlushTemperature() async {
    return 25.0;
  }

  @override
  Future<void> setFlushTemperature(double newTemp) async {}

  @override
  Future<int> getTankTempThreshold() async {
    return 20;
  }

  @override
  Future<void> setTankTempThreshold(int temp) async {}

  @override
  Stream<bool> get ready => Stream.value(true);

  @override
  Future<double> getHeaterIdleTemp() async {
    return 98.0;
  }

  @override
  Future<double> getHeaterPhase1Flow() async {
    return 2.5;
  }

  @override
  Future<double> getHeaterPhase2Flow() async {
    return 5.0;
  }

  @override
  Future<double> getHeaterPhase2Timeout() async {
    return 5.0;
  }

  @override
  Future<void> setHeaterIdleTemp(double val) async {}

  @override
  Future<void> setHeaterPhase1Flow(double val) async {}

  @override
  Future<void> setHeaterPhase2Flow(double val) async {}

  @override
  Future<void> setHeaterPhase2Timeout(double val) async {
    // simulate disconnect
    _connectionState.add(ConnectionState.disconnected);

    Future.delayed(Duration(seconds: 10), () {
      _connectionState.add(ConnectionState.connected);
    });
  }

  @override
  // TODO: implement rawOutStream
  Stream<De1RawMessage> get rawOutStream => throw UnimplementedError();

  @override
  void sendRawMessage(De1RawMessage message) {
    _log.fine("sending raw message: ${message.toJson()}");
  }

  @override
  Future<void> updateFirmware(
    Uint8List fwImage, {
    required void Function(double) onProgress,
  }) async {
    // uploading bytes ...
    final chunkSize = 4096;
    final total = fwImage.length;
    for (int offset = 0; offset < total; offset += chunkSize) {
      // Simulate work
      await Future.delayed(Duration(milliseconds: 20));

      // Send chunk to device...
      // await sendChunk(data.sublist(offset, min(offset + chunkSize, total)));

      // Report progress
      onProgress(offset / total);
    }
    onProgress(1.0);
  }

  @override
  Future<void> cancelFirmwareUpload() async {}

  @override
  Future<void> enableUserPresenceFeature() async {}

  @override
  Future<void> sendUserPresent() async {}
}

