import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/shot_scale_command_queue.dart';
import 'package:reaprime/src/controllers/step_exit_arbiter.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/shot_state_event.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:rxdart/rxdart.dart';

export 'package:reaprime/src/models/data/shot_state_event.dart'
    show ShotState, ShotDecision, ShotDecisionKind, ShotDecisionReason;

enum _ScaleAvailability { unavailable, awaitingPourTare, ready, stale }

class _CrossingGate {
  int _samples = 0;

  bool add(bool crossed) {
    _samples = crossed ? _samples + 1 : 0;
    return _samples >= 2;
  }

  void reset() => _samples = 0;
}

class ShotSequencer {
  final De1Controller de1controller;
  final ScaleController scaleController;
  final PersistenceController persistenceController;
  final Profile targetProfile;

  final Logger _log = Logger("ShotSequencer");

  final bool _bypassSAW;
  final bool _blockOnNoScale;
  final double _weightFlowMultiplier;
  final double _volumeFlowMultiplier;
  final bool _stepExitArbiterEnabled;
  final Duration _tareConfirmationTimeout;
  final Duration _scaleFreshnessTimeout;

  final bool _machineHasAutonomousSAW;

  Set<int> skippedSteps = const {};
  final StepExitArbiter _stepExitArbiter = StepExitArbiter();
  int _lastProfileFrame = -1;

  int _maxFrameSeen = -1;

  double _accumulatedVolume = 0.0;
  DateTime? _lastVolumeUpdateTime;
  bool _volumeCountingActive = false;

  static const double _settleFlowThreshold = 0.4;
  static const int _settleSampleCount = 10;
  static const double _removalFlowThreshold = 3.0;
  static const double _spikeFlowJump = 3.0;
  static const Duration _stoppingBackstop = Duration(seconds: 4);
  double? _trustedFinalYield;
  bool _stoppingYieldLocked = false;
  int _settleSamples = 0;
  double? _prevStoppingFlow;

  double? get trustedFinalYield => _trustedFinalYield == null
      ? null
      : (_trustedFinalYield! * 10).roundToDouble() / 10;

  ShotSequencer({
    required this.scaleController,
    required this.de1controller,
    required this.persistenceController,
    required this.targetProfile,
    required this.targetYield,
    required bool bypassSAW,
    required bool blockOnNoScale,
    required double weightFlowMultiplier,
    required double volumeFlowMultiplier,
    required bool stepExitArbiterEnabled,
    Duration tareConfirmationTimeout = const Duration(seconds: 2),
    Duration scaleFreshnessTimeout = const Duration(seconds: 2),
  }) : _bypassSAW = bypassSAW,
       _blockOnNoScale = blockOnNoScale,
       _weightFlowMultiplier = weightFlowMultiplier,
       _volumeFlowMultiplier = volumeFlowMultiplier,
       _stepExitArbiterEnabled = stepExitArbiterEnabled,
       _tareConfirmationTimeout = tareConfirmationTimeout,
       _scaleFreshnessTimeout = scaleFreshnessTimeout,
       _machineHasAutonomousSAW =
           de1controller.connectedDe1() is BengleInterface {
    _log.info(
      "Initializing ShotSequencer (weightFlowMultiplier: $_weightFlowMultiplier, volumeFlowMultiplier: $_volumeFlowMultiplier, machineHasAutonomousSAW: $_machineHasAutonomousSAW, stepExitArbiterEnabled: $_stepExitArbiterEnabled)",
    );

    final scaleConnected =
        scaleController.currentConnectionState ==
        device.ConnectionState.connected;

    if (_blockOnNoScale && !scaleConnected) {
      _emitDecision(
        ShotDecisionKind.abort,
        ShotDecisionReason.noScale,
        details: 'No scale connected, blocking shot',
      );
      de1controller
          .connectedDe1()
          .requestState(MachineState.idle)
          .catchError(
            (error) =>
                _log.warning("Failed to abort shot for blockOnNoScale: $error"),
          );
      return;
    }

    if (scaleConnected) {
      _scaleGeneration = scaleController.connectionGeneration;
      _commandQueue = ShotScaleCommandQueue(
        scaleController.connectedScale(),
        isCurrent: () =>
            scaleController.connectionGeneration == _scaleGeneration,
        logger: _log,
      );
      _scaleAvailability = _bypassSAW
          ? _ScaleAvailability.ready
          : _ScaleAvailability.awaitingPourTare;
    }

    _machineSubscription = de1controller.connectedDe1().currentSnapshot.listen(
      _processMachineSnapshot,
      onError: (error, stackTrace) =>
          _log.warning('Error processing machine snapshot', error, stackTrace),
    );
    _scaleSubscription = scaleController.weightSnapshot.listen(
      _processScaleSnapshot,
      onError: (error, stackTrace) =>
          _log.warning('Error processing scale snapshot', error, stackTrace),
    );
    _scaleConnectionSubscription = scaleController.connectionState.listen(
      _processScaleConnection,
      onError: (error, stackTrace) =>
          _log.warning('Error processing scale connection', error, stackTrace),
    );
  }

  void dispose() {
    _log.fine("dispose");
    _disposed = true;
    _tareConfirmationTimer?.cancel();
    _freshnessTimer?.cancel();
    _stoppingTimer?.cancel();
    _commandQueue?.dispose();
    _machineSubscription?.cancel();
    _scaleSubscription?.cancel();
    _scaleConnectionSubscription?.cancel();
    _rawShotDataStream.close();
    _shotDataStream.close();
    _decisionStream.close();
    _resetCommand.close();
    _stateStream.close();
  }

  StreamSubscription<MachineSnapshot>? _machineSubscription;
  StreamSubscription<WeightSnapshot>? _scaleSubscription;

  final StreamController<ShotSnapshot> _rawShotDataStream =
      StreamController.broadcast();
  Stream<ShotSnapshot> get rawData => _rawShotDataStream.stream;

  final StreamController<ShotSnapshot> _shotDataStream =
      StreamController.broadcast();

  Stream<ShotSnapshot> get shotData => _shotDataStream.stream;

  final StreamController<bool> _resetCommand = StreamController.broadcast();
  Stream<bool> get resetCommand => _resetCommand.stream;

  final BehaviorSubject<ShotState> _stateStream = BehaviorSubject.seeded(
    ShotState.idle,
  );
  Stream<ShotState> get state => _stateStream.stream;

  final BehaviorSubject<ShotDecision> _decisionStream = BehaviorSubject();
  Stream<ShotDecision> get decisions => _decisionStream.stream;

  static final Logger _decisionLog = Logger('ShotState');

  ShotDecisionReason? _finalStopReason;
  ShotDecisionReason? get finalStopReason => _finalStopReason;

  ShotState get currentState => _state;

  bool get scaleLost => _scaleLost;
  bool get machineHasAutonomousSAW => _machineHasAutonomousSAW;

  void _emitDecision(
    ShotDecisionKind kind,
    ShotDecisionReason reason, {
    String? details,
    Map<String, dynamic>? data,
  }) {
    final message =
        '${kind.name}/${reason.name}: ${details ?? ''}'
        '${data != null ? ' $data' : ''}';
    switch (kind) {
      case ShotDecisionKind.abort:
      case ShotDecisionKind.terminal:
        _decisionLog.warning(message);
      case ShotDecisionKind.finalize:
        _decisionLog.fine(message);
      case ShotDecisionKind.advance:
      case ShotDecisionKind.stop:
        _decisionLog.info(message);
    }
    if (!_decisionStream.isClosed) {
      _decisionStream.add(
        ShotDecision(kind: kind, reason: reason, details: details, data: data),
      );
    }
  }

  DateTime _shotStartTime = DateTime.now();
  DateTime get shotStartTime => _shotStartTime;

  final double targetYield;
  ShotState _state = ShotState.idle;
  bool _scaleLost = false;

  bool _disposed = false;
  bool _pourTareStarted = false;
  bool _pourTareSucceeded = false;
  bool _pourTareZeroObserved = false;
  bool _stopRequested = false;
  _ScaleAvailability _scaleAvailability = _ScaleAvailability.unavailable;
  MachineSnapshot? _latestMachine;
  WeightSnapshot? _latestScale;
  ShotScaleCommandQueue? _commandQueue;
  int? _scaleGeneration;
  Timer? _tareConfirmationTimer;
  Timer? _freshnessTimer;
  Timer? _stoppingTimer;
  final _finalCrossing = _CrossingGate();
  final _stepCrossing = _CrossingGate();
  StreamSubscription<device.ConnectionState>? _scaleConnectionSubscription;

  void _processMachineSnapshot(MachineSnapshot machine) {
    if (_disposed) return;
    _latestMachine = machine;
    final snapshotWithVolume = _updateVolume(
      ShotSnapshot(machine: machine, scale: _visibleScale()),
    );

    _rawShotDataStream.add(snapshotWithVolume);
    _handleMachineState(snapshotWithVolume);
    if (dataCollectionEnabled) {
      _shotDataStream.add(snapshotWithVolume);
    }
  }

  WeightSnapshot? _visibleScale() {
    final scale = _latestScale;
    if (scale == null ||
        _scaleAvailability == _ScaleAvailability.unavailable ||
        _scaleAvailability == _ScaleAvailability.stale) {
      return null;
    }
    if (_scaleAvailability == _ScaleAvailability.ready) return scale;
    return WeightSnapshot(
      timestamp: scale.timestamp,
      weight: 0,
      weightFlow: 0,
      controlWeightFlow: 0,
      battery: scale.battery,
      timerValue: scale.timerValue,
    );
  }

  void _processScaleConnection(device.ConnectionState state) {
    if (_disposed || _commandQueue == null) return;
    if (scaleController.connectionGeneration != _scaleGeneration) {
      _commandQueue?.dispose();
      _disableScale(_ScaleAvailability.unavailable, 'Active scale changed');
      return;
    }
    if (state != device.ConnectionState.disconnected) return;
    _commandQueue?.dispose();
    _disableScale(_ScaleAvailability.unavailable, 'Scale disconnected');
  }

  void _processScaleSnapshot(WeightSnapshot scale) {
    if (_disposed ||
        _scaleAvailability == _ScaleAvailability.unavailable ||
        _scaleAvailability == _ScaleAvailability.stale) {
      return;
    }
    if (scaleController.connectionGeneration != _scaleGeneration) {
      _commandQueue?.dispose();
      _disableScale(_ScaleAvailability.unavailable, 'Active scale changed');
      return;
    }
    _latestScale = scale;
    if (_pourTareStarted ||
        _state == ShotState.pouring ||
        _state == ShotState.stopping) {
      _resetFreshnessTimer();
    }
    if (_scaleAvailability == _ScaleAvailability.awaitingPourTare) {
      if (_pourTareStarted && scale.weight.abs() <= 3) {
        _pourTareZeroObserved = true;
        _tryArmScaleControl();
      }
      return;
    }
    if (_state == ShotState.pouring) {
      _evaluateScaleControl(scale);
    } else if (_state == ShotState.stopping) {
      _refineStoppingYield(scale);
      if (_stoppingYieldLocked) _finishStopping();
    }
  }

  void _resetFreshnessTimer() {
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer(_scaleFreshnessTimeout, () {
      if (_state != ShotState.pouring && _state != ShotState.stopping) return;
      if (_scaleAvailability != _ScaleAvailability.awaitingPourTare &&
          _scaleAvailability != _ScaleAvailability.ready) {
        return;
      }
      _disableScale(_ScaleAvailability.stale, 'Scale feed became stale');
    });
  }

  void _disableScale(_ScaleAvailability availability, String reason) {
    if (_scaleAvailability == _ScaleAvailability.unavailable ||
        _scaleAvailability == _ScaleAvailability.stale) {
      return;
    }
    _scaleAvailability = availability;
    _scaleLost = true;
    _latestScale = null;
    _tareConfirmationTimer?.cancel();
    _freshnessTimer?.cancel();
    _finalCrossing.reset();
    _stepCrossing.reset();
    _log.warning('$reason; scale control disabled for this shot');
  }

  void _enqueuePreparingCommands() {
    final queue = _commandQueue;
    if (queue == null || _bypassSAW) return;
    queue.enqueue(ShotScaleCommand.preparingTare, _tareCapturedScale);
    queue.enqueue(ShotScaleCommand.timerReset, (scale) => scale.resetTimer());
  }

  void _enqueuePourCommands() {
    final queue = _commandQueue;
    if (queue == null || _bypassSAW) {
      if (_scaleAvailability == _ScaleAvailability.ready &&
          _latestScale != null) {
        _resetFreshnessTimer();
      }
      return;
    }
    queue.enqueue(
      ShotScaleCommand.pourTare,
      _tareCapturedScale,
      onStart: _beginPourTare,
      onSuccess: _completePourTare,
      onFailure: (_) =>
          _disableScale(_ScaleAvailability.unavailable, 'Pour tare failed'),
    );
    queue.enqueue(ShotScaleCommand.timerStart, (scale) => scale.startTimer());
  }

  Future<void> _tareCapturedScale(Scale scale) async {
    if (!identical(scaleController.connectedScale(), scale)) {
      throw StateError('Shot scale changed');
    }
    await scaleController.tare();
  }

  void _enqueueTimerStop() {
    _commandQueue?.enqueue(
      ShotScaleCommand.timerStop,
      (scale) => scale.stopTimer(),
    );
  }

  void _beginPourTare() {
    if (_state != ShotState.pouring ||
        _scaleAvailability != _ScaleAvailability.awaitingPourTare) {
      return;
    }
    _pourTareStarted = true;
    _pourTareSucceeded = false;
    _pourTareZeroObserved = false;
    _finalCrossing.reset();
    _stepCrossing.reset();
    _tareConfirmationTimer?.cancel();
    _tareConfirmationTimer = Timer(_tareConfirmationTimeout, () {
      if (_scaleAvailability == _ScaleAvailability.awaitingPourTare) {
        _disableScale(
          _ScaleAvailability.unavailable,
          'Pour tare confirmation timed out',
        );
      }
    });
  }

  void _completePourTare() {
    if (_scaleAvailability != _ScaleAvailability.awaitingPourTare) return;
    _pourTareSucceeded = true;
    _tryArmScaleControl();
  }

  void _tryArmScaleControl() {
    if (!_pourTareSucceeded || !_pourTareZeroObserved) return;
    _tareConfirmationTimer?.cancel();
    _scaleAvailability = _ScaleAvailability.ready;
    _resetFreshnessTimer();
  }

  void _evaluateScaleControl(WeightSnapshot scale) {
    final machine = _latestMachine;
    if (machine == null || _stopRequested || _bypassSAW) return;
    final projected =
        scale.weight + scale.controlWeightFlow * _weightFlowMultiplier;
    _handleStepWeightExit(machine.profileFrame, projected, machine);
    if (_machineHasAutonomousSAW || targetYield <= 0) return;
    if (!_finalCrossing.add(projected >= targetYield)) return;
    _requestStop(
      ShotDecisionReason.targetWeight,
      'Target weight ${targetYield}g reached (projected: $projected).',
      {'targetYield': targetYield, 'projectedWeight': projected},
    );
  }

  void _requestStop(
    ShotDecisionReason reason,
    String details,
    Map<String, dynamic> data,
  ) {
    if (_stopRequested) return;
    _stopRequested = true;
    _finalStopReason = reason;
    _emitDecision(ShotDecisionKind.stop, reason, details: details, data: data);
    unawaited(_requestMachineState(MachineState.idle, 'stop shot'));
  }

  Future<void> _requestMachineState(
    MachineState state,
    String operation,
  ) async {
    try {
      await de1controller.connectedDe1().requestState(state);
    } catch (error, stackTrace) {
      _log.warning('Failed to $operation', error, stackTrace);
    }
  }

  ShotSnapshot _updateVolume(ShotSnapshot snapshot) {
    final MachineSnapshot machine = snapshot.machine;
    final int currentFrame = machine.profileFrame;

    if (_volumeCountingActive &&
        currentFrame >= targetProfile.targetVolumeCountStart) {
      final now = snapshot.machine.timestamp;

      if (_lastVolumeUpdateTime != null) {
        final timeDelta =
            now.difference(_lastVolumeUpdateTime!).inMilliseconds / 1000.0;

        final volumeDelta = machine.flow * timeDelta;
        _accumulatedVolume += volumeDelta;

        _log.finest(
          "Volume update: flow=${machine.flow} ml/s, delta=${timeDelta}s, "
          "volumeDelta=${volumeDelta}ml, total=${_accumulatedVolume}ml",
        );
      }

      _lastVolumeUpdateTime = now;
    }

    return snapshot.copyWith(volume: _accumulatedVolume);
  }

  bool dataCollectionEnabled = false;

  void _handleMachineState(ShotSnapshot snapshot) {
    final MachineSnapshot machine = snapshot.machine;

    _log.finest(
      "recv: ${machine.state.substate.name}, ${machine.state.state.name}",
    );

    _log.finest("State in: ${_state.name}");

    if (machine.state.state == MachineState.error &&
        _state != ShotState.idle &&
        _state != ShotState.finished) {
      _finalStopReason ??= ShotDecisionReason.error;
      _emitDecision(
        ShotDecisionKind.terminal,
        ShotDecisionReason.error,
        details: 'Machine entered error state (${machine.state.substate.name})',
        data: {'substate': machine.state.substate.name},
      );
      _volumeCountingActive = false;
      dataCollectionEnabled = false;
      _state = ShotState.finished;
      _stateStream.add(_state);
      return;
    }

    switch (_state) {
      case ShotState.idle:
        if (machine.state.state == MachineState.espresso &&
            machine.state.substate == MachineSubstate.preparingForShot) {
          _resetCommand.add(true);
          _shotStartTime = DateTime.now();

          _accumulatedVolume = 0.0;
          _lastVolumeUpdateTime = null;
          _volumeCountingActive = false;
          _trustedFinalYield = null;
          _stoppingYieldLocked = false;
          _settleSamples = 0;
          _prevStoppingFlow = null;
          skippedSteps = const {};
          _stepExitArbiter.reset();
          _lastProfileFrame = -1;
          _maxFrameSeen = -1;
          _finalStopReason = null;
          _stopRequested = false;
          _pourTareStarted = false;
          _pourTareSucceeded = false;
          _pourTareZeroObserved = false;
          _finalCrossing.reset();
          _stepCrossing.reset();

          _enqueuePreparingCommands();
          _state = ShotState.preheating;
          _stateStream.add(_state);
          dataCollectionEnabled = true;
        }
        break;

      case ShotState.preheating:
        if (machine.state.state != MachineState.espresso) {
          final intent = de1controller.consumeStopIntent();
          _emitDecision(
            ShotDecisionKind.abort,
            intent ?? ShotDecisionReason.machineEnded,
            details: 'Shot aborted during preheat, before the pour began',
          );
          break;
        }
        if (machine.state.substate == MachineSubstate.preinfusion ||
            machine.state.substate == MachineSubstate.pouring) {
          _volumeCountingActive = true;
          _log.info(
            "Volume counting activated. Will start from frame ${targetProfile.targetVolumeCountStart}",
          );

          _state = ShotState.pouring;
          _stateStream.add(_state);
          _enqueuePourCommands();
        }
        break;

      case ShotState.pouring:
        _trackFrameAdvance(machine.profileFrame);
        if (machine.state.substate == MachineSubstate.pouringDone ||
            machine.state.substate == MachineSubstate.idle) {
          if (!_stopRequested) {
            final intent = de1controller.consumeStopIntent();
            final reason = intent ?? ShotDecisionReason.machineEnded;
            _finalStopReason ??= reason;
            _emitDecision(
              ShotDecisionKind.stop,
              reason,
              details: switch (reason) {
                ShotDecisionReason.apiStop =>
                  'Shot stopped via REST API request',
                ShotDecisionReason.appStop => 'Shot stopped from the app UI',
                _ =>
                  'Machine reported shot end '
                      '(${machine.state.substate.name})',
              },
            );
          }
          _enterStopping(
            _scaleAvailability == _ScaleAvailability.ready
                ? _latestScale
                : null,
          );
          break;
        }
        if (!_stopRequested &&
            !_bypassSAW &&
            !_machineHasAutonomousSAW &&
            (_scaleAvailability == _ScaleAvailability.unavailable ||
                _scaleAvailability == _ScaleAvailability.stale) &&
            (targetProfile.targetVolume ?? 0) > 0) {
          final projectedVolume =
              _accumulatedVolume + (machine.flow * _volumeFlowMultiplier);
          if (projectedVolume > targetProfile.targetVolume!) {
            _requestStop(
              ShotDecisionReason.targetVolume,
              'Target volume ${targetProfile.targetVolume}ml reached '
              '(projected: $projectedVolume).',
              {
                'targetVolume': targetProfile.targetVolume,
                'projectedVolume': projectedVolume,
              },
            );
          }
        }
        break;

      case ShotState.stopping:
        break;

      case ShotState.finished:
        dataCollectionEnabled = false;
        _stoppingTimer?.cancel();
        _stoppingTimer = null;
        _state = ShotState.idle;
        _stateStream.add(_state);
        break;
    }
    _log.finest("State out: ${_state.name}");
  }

  void _trackFrameAdvance(int profileFrame) {
    if (profileFrame != _lastProfileFrame) {
      _stepExitArbiter.onFrameAdvanced(profileFrame);
      _stepCrossing.reset();
      _lastProfileFrame = profileFrame;
    }
    if (_maxFrameSeen < 0) {
      _maxFrameSeen = profileFrame;
      return;
    }
    if (profileFrame <= _maxFrameSeen) {
      return;
    }
    for (var frame = _maxFrameSeen; frame < profileFrame; frame++) {
      if (skippedSteps.contains(frame)) {
        continue;
      }
      _emitDecision(
        ShotDecisionKind.advance,
        ShotDecisionReason.profileAdvance,
        details: 'Firmware advanced from frame $frame to ${frame + 1}',
        data: {'fromFrame': frame, 'toFrame': frame + 1},
      );
    }
    _maxFrameSeen = profileFrame;
  }

  void _handleStepWeightExit(
    int profileFrame,
    double projectedWeight,
    MachineSnapshot machineSnapshot,
  ) {
    if (profileFrame < 0 || profileFrame >= targetProfile.steps.length) {
      return;
    }

    final step = targetProfile.steps[profileFrame];
    final stepExitWeight = step.weight;
    if (stepExitWeight == null || stepExitWeight <= 0) {
      _stepCrossing.reset();
      return;
    }

    if (skippedSteps.contains(profileFrame)) {
      _stepCrossing.reset();
      return;
    }

    if (!_stepCrossing.add(projectedWeight >= stepExitWeight)) {
      return;
    }

    if (_stepExitArbiterEnabled && step.exit != null) {
      final verdict = _stepExitArbiter.evaluate(
        profileFrame: profileFrame,
        exit: step.exit!,
        currentPressure: machineSnapshot.pressure,
        currentFlow: machineSnapshot.flow,
      );
      if (verdict == StepExitVerdict.defer) {
        return;
      }
    }

    _emitDecision(
      ShotDecisionKind.advance,
      ShotDecisionReason.profileSkip,
      details:
          'Step weight ${stepExitWeight}g reached '
          '(projected: $projectedWeight), skipping frame $profileFrame',
      data: {
        'frame': profileFrame,
        'stepExitWeight': stepExitWeight,
        'projectedWeight': projectedWeight,
      },
    );
    skippedSteps = {...skippedSteps, profileFrame};
    unawaited(_requestMachineState(MachineState.skipStep, 'skip profile step'));
  }

  void _enterStopping(WeightSnapshot? scale) {
    _latchTrustedFinalYield(scale);
    _prevStoppingFlow = scale?.controlWeightFlow;
    _volumeCountingActive = false;
    dataCollectionEnabled = false;
    if (!_bypassSAW) _enqueueTimerStop();
    _state = _trustedFinalYield != null
        ? ShotState.stopping
        : ShotState.finished;
    _stateStream.add(_state);
    if (_state != ShotState.stopping) return;
    _stoppingTimer?.cancel();
    _stoppingTimer = Timer(_stoppingBackstop, () {
      if (_state != ShotState.stopping) return;
      _emitDecision(
        ShotDecisionKind.finalize,
        ShotDecisionReason.stoppingBackstop,
        details: 'Stopping backstop fired. Final volume: $_accumulatedVolume',
        data: {'finalVolume': _accumulatedVolume},
      );
      _finishStopping();
    });
  }

  void _latchTrustedFinalYield(WeightSnapshot? scale) {
    final weight = scale?.weight;
    if (weight == null || weight <= 0 || !weight.isFinite) return;
    _trustedFinalYield = weight;
  }

  void _refineStoppingYield(WeightSnapshot? scale) {
    if (_stoppingYieldLocked) return;
    final weight = scale?.weight;
    if (weight == null || weight <= 0 || !weight.isFinite) return;
    final flow = scale!.controlWeightFlow.isFinite
        ? scale.controlWeightFlow
        : 0.0;
    final prevFlow = _prevStoppingFlow;
    _prevStoppingFlow = flow;

    if (flow < -_removalFlowThreshold) {
      _stoppingYieldLocked = true;
      return;
    }
    if (prevFlow != null && flow > prevFlow + _spikeFlowJump) {
      _stoppingYieldLocked = true;
      return;
    }

    if (_trustedFinalYield == null || weight > _trustedFinalYield!) {
      _trustedFinalYield = weight;
    }

    if (flow.abs() < _settleFlowThreshold) {
      if (++_settleSamples >= _settleSampleCount) {
        _trustedFinalYield = weight;
        _stoppingYieldLocked = true;
      }
    } else {
      _settleSamples = 0;
    }
  }

  void _finishStopping() {
    _freshnessTimer?.cancel();
    _stoppingTimer?.cancel();
    _state = ShotState.finished;
    _stateStream.add(_state);
  }
}
