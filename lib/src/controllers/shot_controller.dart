import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:rxdart/rxdart.dart';

class ShotController {
  final De1Controller de1controller;
  final ScaleController scaleController;
  final PersistenceController persistenceController;
  final Profile targetProfile;

  final Logger _log = Logger("ShotController");

  late bool _bypassSAW;
  late double _weightFlowMultiplier;

  // Skip step on weight specific
  List<int> skippedSteps = [];

  // Volume counting state
  double _accumulatedVolume = 0.0;
  DateTime? _lastVolumeUpdateTime;
  bool _volumeCountingActive = false;

  ShotController({
    required this.scaleController,
    required this.de1controller,
    required this.persistenceController,
    required this.targetProfile,
    required this.doseData,
  }) {
    Future.value(_initialize()).then((_) {
      _log.info("ShotController initialized");
    });
  }

  Future<void> _initialize() async {
    _bypassSAW = await SettingsService().gatewayMode() == GatewayMode.full;
    _weightFlowMultiplier = await SettingsService().weightFlowMultiplier();
    _log.info(
      "Initializing ShotController (weightFlowMultiplier: $_weightFlowMultiplier)",
    );
    try {
      final state = await scaleController.connectionState.first;
      _log.info("Scale state: $state");
      if (state != device.ConnectionState.connected) {
        throw Exception("Scale not connected");
      }

      // Combine DE1 and scale data if the scale is connected
      final combinedStream = de1controller
          .connectedDe1()
          .currentSnapshot
          .withLatestFrom(
            scaleController.weightSnapshot,
            (machine, weight) => ShotSnapshot(machine: machine, scale: weight),
          );

      _snapshotSubscription = combinedStream.listen(
        _processSnapshot,
        onError:
            (error) =>
                _log.warning("Error processing combined snapshot: $error"),
      );
    } catch (e) {
      _log.warning("Continuing without scale: $e");

      // Fallback: Only DE1 data if the scale is not connected
      _snapshotSubscription = de1controller
          .connectedDe1()
          .currentSnapshot
          .map((snapshot) => ShotSnapshot(machine: snapshot))
          .listen(
            _processSnapshot,
            onError:
                (error) =>
                    _log.warning("Error processing DE1 snapshot: $error"),
          );
    }
  }

  void dispose() {
    _log.fine("dispose");
    _snapshotSubscription?.cancel();
    _rawShotDataStream.close();
    _shotDataStream.close();
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

  DateTime _shotStartTime = DateTime.now();
  DateTime get shotStartTime => _shotStartTime;

  final DoseData doseData;
  ShotState _state = ShotState.idle;

  _processSnapshot(ShotSnapshot snapshot) {
    _log.finest("Processing snapshot");

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
          skippedSteps.clear();

          if (_bypassSAW == false && scale != null) {
            _log.info("Machine getting ready. Taring scale...");
            scaleController.connectedScale().tare();
          }
          _state = ShotState.preheating;
          _stateStream.add(_state);
          dataCollectionEnabled = true;
        }
        break;

      case ShotState.preheating:
        if (machine.state.substate == MachineSubstate.preinfusion ||
            machine.state.substate == MachineSubstate.pouring) {
          if (_bypassSAW == false && scale != null) {
            _log.info("Taring scale again.");
            scaleController.connectedScale().tare();
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
        if (_bypassSAW == false && scale != null) {
          double currentWeight = scale.weight;
          double weightFlow = scale.weightFlow;
          double projectedWeight =
              currentWeight + (weightFlow * _weightFlowMultiplier);

          if (targetProfile.steps.length > machine.profileFrame &&
              skippedSteps.contains(machine.profileFrame) == false &&
              targetProfile.steps[machine.profileFrame].weight != null &&
              targetProfile.steps[machine.profileFrame].weight! > 0) {
            var stepExitWeight =
                targetProfile.steps[machine.profileFrame].weight!;
            if (projectedWeight >= stepExitWeight) {
              _log.info("Step weight reached, moving on");
              skippedSteps.add(machine.profileFrame);
              de1controller.connectedDe1().requestState(MachineState.skipStep);
            }
          }
          if (doseData.doseOut > 0 && projectedWeight >= doseData.doseOut) {
            _log.info(
              "Target weight ${doseData.doseOut}g reached (projected: $projectedWeight). Stopping shot.",
            );
            de1controller.connectedDe1().requestState(
              MachineState.idle,
            ); // Send stop command to machine
            _state = ShotState.stopping;
            _stateStream.add(_state);
            break;
          }
        }
        if (!_bypassSAW &&
            scale == null &&
            (targetProfile.targetVolume ?? 0) > 0) {
          // Account for about a 300ms delay until next frame, might as well stop here
          final projectedVolume = _accumulatedVolume + (machine.flow * 0.3);
          if (projectedVolume > targetProfile.targetVolume!) {
            _log.info(
              "Target volume ${targetProfile.targetVolume}ml reached (projected: $projectedVolume). Stopping shot.",
            );
            de1controller.connectedDe1().requestState(
              MachineState.idle,
            ); // Send stop command to machine
            _state = ShotState.stopping;
            _stateStream.add(_state);
            break;
          }
        }
        if (machine.state.substate == MachineSubstate.pouringDone ||
            machine.state.substate == MachineSubstate.idle) {
          _state = ShotState.stopping;
          _stateStream.add(_state);
        }
        break;

      case ShotState.stopping:
        // Stop volume counting
        _volumeCountingActive = false;

        if (_stoppingStateFuture != null) {
          break;
        }
        _stoppingStateFuture = Future.delayed(Duration(seconds: 4), () {
          _log.info(
            "Recording finished. Final volume: ${_accumulatedVolume}ml",
          );
          _state = ShotState.finished;
          _stateStream.add(_state);
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
}

enum ShotState { idle, preheating, pouring, stopping, finished }
