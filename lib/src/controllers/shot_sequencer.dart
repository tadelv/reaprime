import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/step_exit_arbiter.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:rxdart/rxdart.dart';

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

  /// `true` when the connected machine runs its own autonomous SAW
  /// (currently only Bengle). The app's SAW loop must defer to FW to
  /// avoid double-stop.
  ///
  /// Captured once at construction. A sequencer's lifetime is bound
  /// to a single shot (owned + recreated per shot by [De1StateManager])
  /// and machines can't be swapped mid-shot — if the connection dies
  /// the shot is already over and a stale flag is the least of our
  /// problems. Don't try to make this reactive.
  ///
  /// Only the FINAL target-yield stop is bypassed for autonomous-SAW
  /// machines. Per-step weight exits (`ProfileStep.weight`) still run
  /// app-side: FW only exposes one SAW target, not per-frame weight
  /// transitions. Wiring per-step skips into FW would need a new
  /// `ProfileStepFrame` data object and likely a separate endpoint —
  /// out of scope until that exists.
  final bool _machineHasAutonomousSAW;

  // Skip step on weight specific
  List<int> skippedSteps = [];
  final StepExitArbiter _stepExitArbiter = StepExitArbiter();
  int _lastProfileFrame = -1;

  // Volume counting state
  double _accumulatedVolume = 0.0;
  DateTime? _lastVolumeUpdateTime;
  bool _volumeCountingActive = false;

  // Final beverage weight on weighed shots. After the machine-reported stop the
  // pump is off, so flow onto the scale can only decay — the post-stop window
  // keeps taking the rising weight (turbo catch-up included, with no flow or
  // gram cap) and locks the yield on the first of three events: the scale
  // settles, the cup is removed (a sharp drop), or a touch spikes the flow back
  // up against the decay. The saved trace stops at the stop boundary, so only
  // this value follows the tail, not the graph. Null when no scale weighs the
  // shot.
  static const double _settleFlowThreshold = 0.4; // g/s; |flow| below = still
  static const int _settleSampleCount =
      3; // consecutive still samples = settled
  static const double _removalFlowThreshold =
      3.0; // g/s; flow < -this = removal
  static const double _spikeFlowJump = 3.0; // g/s; flow rising vs prev = spike
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
  }) : _bypassSAW = bypassSAW,
       _blockOnNoScale = blockOnNoScale,
       _weightFlowMultiplier = weightFlowMultiplier,
       _volumeFlowMultiplier = volumeFlowMultiplier,
       _machineHasAutonomousSAW =
           de1controller.connectedDe1() is BengleInterface {
    _log.info(
      "Initializing ShotSequencer (weightFlowMultiplier: $_weightFlowMultiplier, volumeFlowMultiplier: $_volumeFlowMultiplier, machineHasAutonomousSAW: $_machineHasAutonomousSAW)",
    );

    // When the app won't tare (SAW bypass), trust the scale's readings as-is —
    // there's no app-side tare to gate on.
    _scaleTared = _bypassSAW;

    final scaleConnected =
        scaleController.currentConnectionState ==
        device.ConnectionState.connected;

    if (_blockOnNoScale && !scaleConnected) {
      // The sequencer is created reactively, after the machine has already
      // entered espresso (incl. GHC / physical starts), so "block" means abort
      // the shot in progress and publish the reason rather than prevent it.
      _log.warning(
        "blockOnNoScale enabled and no scale connected — aborting shot",
      );
      _decisionStream.add(
        const ShotDecision(
          reason: ShotDecisionReason.noScale,
          details: 'No scale connected, blocking shot',
        ),
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

    if (!scaleConnected) {
      _log.info("Continuing without scale");
      _snapshotSubscription = de1controller
          .connectedDe1()
          .currentSnapshot
          .map((snapshot) => ShotSnapshot(machine: snapshot))
          .listen(
            _processSnapshot,
            onError: (error) =>
                _log.warning("Error processing DE1 snapshot: $error"),
          );
    } else {
      _log.info("Scale connected, combining streams");
      final combinedStream = de1controller
          .connectedDe1()
          .currentSnapshot
          .withLatestFrom(
            scaleController.weightSnapshot,
            (machine, weight) => ShotSnapshot(machine: machine, scale: weight),
          );

      _snapshotSubscription = combinedStream.listen(
        _processSnapshot,
        onError: (error) =>
            _log.warning("Error processing combined snapshot: $error"),
      );

      // Monitor scale connection during shot
      _scaleConnectionSubscription = scaleController.connectionState.listen((
        state,
      ) {
        if (state == device.ConnectionState.disconnected && !_scaleLost) {
          if (_state != ShotState.idle && _state != ShotState.finished) {
            _scaleLost = true;
            _log.warning(
              'Scale disconnected during shot (state: ${_state.name}). '
              'Stop-at-weight disabled for remainder of this shot.',
            );
          }
        }
      });
    }
  }

  void dispose() {
    _log.fine("dispose");
    _snapshotSubscription?.cancel();
    _scaleConnectionSubscription?.cancel();
    _rawShotDataStream.close();
    _shotDataStream.close();
    _decisionStream.close();
  }

  StreamSubscription<ShotSnapshot>? _snapshotSubscription;

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

  /// Sequencer decisions (e.g. why a shot was stopped). Groundwork for a
  /// future `/ws/v1/shotState` topic. BehaviorSubject so consumers that
  /// subscribe after construction still receive a decision emitted in the
  /// constructor (e.g. the blockOnNoScale abort).
  final BehaviorSubject<ShotDecision> _decisionStream = BehaviorSubject();
  Stream<ShotDecision> get decisions => _decisionStream.stream;

  DateTime _shotStartTime = DateTime.now();
  DateTime get shotStartTime => _shotStartTime;

  final double targetYield;
  ShotState _state = ShotState.idle;
  bool _scaleLost = false;

  /// Whether this shot's scale has been tared for the pour yet. Flips `true`
  /// when the app issues the pour-time tare (the preheating→pouring
  /// transition). Until then the scale's absolute reading is whatever sits on
  /// the platter (cup, portafilter, residual drips) and the derived flow is
  /// noise — so we report 0 for both rather than feed pre-tare garbage into the
  /// recorded trace and the visualizer upload. Gating through the whole
  /// preheat (rather than flipping at the earlier preparing-for-shot tare)
  /// also sidesteps the in-flight-tare race: by the pour the scale has
  /// physically settled to zero. Seeded `true` when the app won't tare (SAW
  /// bypass, e.g. Bengle's autonomous SAW) — there's no app-side tare to wait
  /// for, so the scale's own readings are trusted as-is.
  bool _scaleTared = false;
  StreamSubscription<device.ConnectionState>? _scaleConnectionSubscription;

  void _processSnapshot(ShotSnapshot snapshot) {
    _log.finest("Processing snapshot");

    // Until the scale is tared for this shot, suppress its weight and flow:
    // the pre-tare reading reflects whatever is resting on the scale, not the
    // beverage, and the flow derived from it is noise.
    if (!_scaleTared && snapshot.scale != null) {
      final raw = snapshot.scale!;
      snapshot = snapshot.copyWith(
        scale: WeightSnapshot(
          timestamp: raw.timestamp,
          weight: 0,
          weightFlow: 0,
          battery: raw.battery,
          timerValue: raw.timerValue,
        ),
      );
    }

    // Update volume calculation
    final snapshotWithVolume = _updateVolume(snapshot);

    _rawShotDataStream.add(snapshotWithVolume);
    _handleStateTransition(snapshotWithVolume);
    if (dataCollectionEnabled) {
      _shotDataStream.add(snapshotWithVolume);
    }
  }

  ShotSnapshot _updateVolume(ShotSnapshot snapshot) {
    final MachineSnapshot machine = snapshot.machine;
    final int currentFrame = machine.profileFrame;

    // Check if we should be counting volume
    if (_volumeCountingActive &&
        currentFrame >= targetProfile.targetVolumeCountStart) {
      final now = snapshot.machine.timestamp;

      if (_lastVolumeUpdateTime != null) {
        // Calculate time delta in seconds
        final timeDelta =
            now.difference(_lastVolumeUpdateTime!).inMilliseconds / 1000.0;

        // Integrate flow over time to get volume
        // Flow is in ml/s, timeDelta is in seconds
        final volumeDelta = machine.flow * timeDelta;
        _accumulatedVolume += volumeDelta;

        _log.finest(
          "Volume update: flow=${machine.flow} ml/s, delta=${timeDelta}s, "
          "volumeDelta=${volumeDelta}ml, total=${_accumulatedVolume}ml",
        );
      }

      _lastVolumeUpdateTime = now;
    }

    // Return snapshot with volume data
    return snapshot.copyWith(volume: _accumulatedVolume);
  }

  bool dataCollectionEnabled = false;
  Future<void>? _stoppingStateFuture;

  void _handleStateTransition(ShotSnapshot snapshot) {
    final MachineSnapshot machine = snapshot.machine;
    final WeightSnapshot? scale = snapshot.scale;

    _log.finest(
      "recv: ${machine.state.substate.name}, ${machine.state.state.name}",
    );

    _log.finest("State in: ${_state.name}");
    switch (_state) {
      case ShotState.idle:
        if (machine.state.state == MachineState.espresso &&
            machine.state.substate == MachineSubstate.preparingForShot) {
          _resetCommand.add(true);
          _shotStartTime = DateTime.now();

          // Reset volume counting for new shot
          _accumulatedVolume = 0.0;
          _lastVolumeUpdateTime = null;
          _volumeCountingActive = false;
          _trustedFinalYield = null;
          _stoppingYieldLocked = false;
          _settleSamples = 0;
          _prevStoppingFlow = null;
          skippedSteps.clear();
          _stepExitArbiter.reset();
          _lastProfileFrame = -1;

          if (_bypassSAW == false && scale != null && !_scaleLost) {
            _log.info(
              "Machine getting ready. Taring scale and resetting timer...",
            );
            scaleController.tare().catchError(
              (e) => _log.warning("Failed to tare scale at shot start", e),
            );
            scaleController.connectedScale().resetTimer();
          }
          _state = ShotState.preheating;
          _stateStream.add(_state);
          dataCollectionEnabled = true;
        }
        break;

      case ShotState.preheating:
        if (machine.state.substate == MachineSubstate.preinfusion ||
            machine.state.substate == MachineSubstate.pouring) {
          if (_bypassSAW == false && scale != null && !_scaleLost) {
            _log.info("Taring scale again and starting timer.");
            scaleController.tare().catchError(
              (e) => _log.warning("Failed to tare scale for pour", e),
            );
            scaleController.connectedScale().startTimer();
            _scaleTared = true;
          }

          // Start volume counting when shot begins
          _volumeCountingActive = true;
          _log.info(
            "Volume counting activated. Will start from frame ${targetProfile.targetVolumeCountStart}",
          );

          // TODO: Settings control, whether reset should happen here or not
          //_resetCommand.add(true);
          _state = ShotState.pouring;
          _stateStream.add(_state);
        }
        break;

      case ShotState.pouring:
        if (_bypassSAW == false && scale != null && !_scaleLost) {
          double currentWeight = scale.weight;
          double weightFlow = scale.weightFlow;
          double projectedWeight =
              currentWeight + (weightFlow * _weightFlowMultiplier);
          final int profileFrame = machine.profileFrame;

          if (profileFrame != _lastProfileFrame) {
            _stepExitArbiter.onFrameAdvanced(profileFrame);
            _lastProfileFrame = profileFrame;
          }

          _handleStepWeightExit(profileFrame, projectedWeight, machine);
          if (!_machineHasAutonomousSAW &&
              targetYield > 0 &&
              projectedWeight >= targetYield) {
            _log.info(
              "Target weight ${targetYield}g reached (projected: $projectedWeight). Stopping shot.",
            );
            de1controller.connectedDe1().requestState(
              MachineState.idle,
            ); // Send stop command to machine
            _enterStopping(scale);
            break;
          }
        }
        if (!_bypassSAW &&
            !_machineHasAutonomousSAW &&
            (scale == null || _scaleLost) &&
            (targetProfile.targetVolume ?? 0) > 0) {
          // Use volumeFlowMultiplier to project future volume and stop at the right time
          final projectedVolume =
              _accumulatedVolume + (machine.flow * _volumeFlowMultiplier);
          if (projectedVolume > targetProfile.targetVolume!) {
            _log.info(
              "Target volume ${targetProfile.targetVolume}ml reached (projected: $projectedVolume). Stopping shot.",
            );
            de1controller.connectedDe1().requestState(
              MachineState.idle,
            ); // Send stop command to machine
            _enterStopping(scale);
            break;
          }
        }
        if (machine.state.substate == MachineSubstate.pouringDone ||
            machine.state.substate == MachineSubstate.idle) {
          _enterStopping(scale);
        }
        break;

      case ShotState.stopping:
        // Stop volume counting and scale timer
        _volumeCountingActive = false;
        if (_bypassSAW == false && scale != null && !_scaleLost) {
          scaleController.connectedScale().stopTimer();
        }

        _refineStoppingYield(scale);
        if (_stoppingYieldLocked) {
          _log.info(
            "Final yield ${trustedFinalYield}g locked. "
            "Final volume: ${_accumulatedVolume}ml",
          );
          _finishStopping();
          break;
        }

        // Safety backstop: a noisy scale might never produce a settle / removal
        // / spike event. Guarantee the shot still finalizes.
        _stoppingStateFuture ??= Future.delayed(_stoppingBackstop, () {
          if (_state == ShotState.stopping) {
            _log.info(
              "Stopping backstop fired. Final volume: ${_accumulatedVolume}ml",
            );
            _finishStopping();
          }
        });
        break;

      case ShotState.finished:
        // Reset or prepare for next shot
        dataCollectionEnabled = false;
        _stoppingStateFuture = null;
        _state = ShotState.idle;
        _stateStream.add(_state);
        break;
    }
    _log.finest("State out: ${_state.name}");
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
      return;
    }

    if (skippedSteps.contains(profileFrame)) {
      return;
    }

    if (projectedWeight < stepExitWeight) {
      return;
    }

    // Mixed step: consult the arbiter to avoid racing firmware.
    if (step.exit != null) {
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

    _log.info("Step weight reached, moving on");
    skippedSteps.add(profileFrame);
    de1controller.connectedDe1().requestState(MachineState.skipStep);
  }

  void _enterStopping(WeightSnapshot? scale) {
    _latchTrustedFinalYield(scale);
    // Recording stops at the machine-reported shot end.
    dataCollectionEnabled = false;
    // The post-stop window exists solely to catch the final drips on the scale
    // and fold them into the yield (see _refineStoppingYield). With a scale,
    // hold in `stopping` until the yield locks; without one there is nothing to
    // catch, so end the shot immediately — no settling window, no waiting.
    _state = _trustedFinalYield != null
        ? ShotState.stopping
        : ShotState.finished;
    _stateStream.add(_state);
  }

  void _latchTrustedFinalYield(WeightSnapshot? scale) {
    final weight = scale?.weight;
    if (weight == null || weight <= 0 || !weight.isFinite) return;
    _trustedFinalYield = weight;
  }

  /// Refines the final yield during the post-stop window.
  ///
  /// The pump is off, so flow onto the scale can only decay. We keep taking the
  /// rising weight — turbo catch-up included, with no flow or gram cap — and
  /// lock the yield on the first of:
  ///   * removal: a sharp drop (flow below -[_removalFlowThreshold]) — keep the
  ///     peak from before it;
  ///   * spike: flow jumping up vs the previous sample (a touch/bump rising
  ///     against the decay) — keep the prior value;
  ///   * settle: [_settleSampleCount] consecutive near-still samples — trust the
  ///     settled reading itself.
  ///
  /// Magnitude is never gated, so a high-flow turbo tail is not mistaken for a
  /// spike; only flow rising *against* the decay is.
  void _refineStoppingYield(WeightSnapshot? scale) {
    if (_stoppingYieldLocked) return;
    final weight = scale?.weight;
    if (weight == null || weight <= 0 || !weight.isFinite) return;
    final flow = scale!.weightFlow.isFinite ? scale.weightFlow : 0.0;
    final prevFlow = _prevStoppingFlow;
    _prevStoppingFlow = flow;

    // Cup removal — a sharp drop. Keep the peak from before it.
    if (flow < -_removalFlowThreshold) {
      _stoppingYieldLocked = true;
      return;
    }
    // Touch/bump — flow jumps up against the post-stop decay. Keep the prior
    // value. Skipped on the first sample, which has no decay baseline yet.
    if (prevFlow != null && flow > prevFlow + _spikeFlowJump) {
      _stoppingYieldLocked = true;
      return;
    }

    // Still filling — take the rising weight.
    if (_trustedFinalYield == null || weight > _trustedFinalYield!) {
      _trustedFinalYield = weight;
    }

    // Settled — trust the settled reading (authoritative over any earlier
    // transient peak) and lock.
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
    _state = ShotState.finished;
    _stateStream.add(_state);
  }
}

enum ShotState { idle, preheating, pouring, stopping, finished }

/// Why the sequencer made a decision (currently only shot-stop reasons).
/// [noScale] corresponds to the REST `block_no_scale` error type; keep the two
/// vocabularies aligned when this gains wire serialization for `/ws/v1/shotState`.
enum ShotDecisionReason { noScale }

class ShotDecision {
  final ShotDecisionReason reason;
  final String? details;

  const ShotDecision({required this.reason, this.details});
}





