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
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:rxdart/rxdart.dart';

class ShotController {
  final De1Controller de1controller;
  final ScaleController scaleController;
  final PersistenceController persistenceController;
  final Profile targetProfile;

  final Logger _log = Logger("ShotController");

  late bool _bypassSAW;

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
    _bypassSAW = await SettingsService().bypassShotController();
    _log.shout("Initializing ShotController");
    try {
      final state = await scaleController.connectionState.first;
      _log.shout("Scale state: $state");
      if (state != device.ConnectionState.connected) {
        throw Exception("Scale not connected");
      }

      // Combine DE1 and scale data if the scale is connected
      final combinedStream =
          de1controller.connectedDe1().currentSnapshot.withLatestFrom(
                scaleController.weightSnapshot,
                (machine, weight) =>
                    ShotSnapshot(machine: machine, scale: weight),
              );

      _snapshotSubscription = combinedStream.listen(
        _processSnapshot,
        onError: (error) =>
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
            onError: (error) =>
                _log.warning("Error processing DE1 snapshot: $error"),
          );
    }
  }

  void dispose() {
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

  final BehaviorSubject<ShotState> _stateStream =
      BehaviorSubject.seeded(ShotState.idle);
  Stream<ShotState> get state => _stateStream.stream;

  DateTime _shotStartTime = DateTime.now();
  DateTime get shotStartTime => _shotStartTime;

  final DoseData doseData;
  ShotState _state = ShotState.idle;

  _processSnapshot(ShotSnapshot snapshot) {
    _log.finest("Processing snapshot");
    _rawShotDataStream.add(snapshot);
    _handleStateTransition(snapshot);
    if (dataCollectionEnabled) {
      _shotDataStream.add(snapshot);
    }
  }

  bool dataCollectionEnabled = false;
  Future<void>? _stoppingStateFuture;

  void _handleStateTransition(ShotSnapshot snapshot) {
    final MachineSnapshot machine = snapshot.machine;
    final WeightSnapshot? scale = snapshot.scale;

    _log.finest(
        "recv: ${machine.state.substate.name}, ${machine.state.state.name}");

    _log.finest("State in: ${_state.name}");
    switch (_state) {
      case ShotState.idle:
        if (machine.state.state == MachineState.espresso &&
            machine.state.substate == MachineSubstate.preparingForShot) {
          _resetCommand.add(true);
          _shotStartTime = DateTime.now();
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
          double projectedWeight = currentWeight + weightFlow;
          if (targetProfile.steps.length > machine.profileFrame &&
              targetProfile.steps[machine.profileFrame].weight != null &&
              targetProfile.steps[machine.profileFrame].weight! > 0) {
            var stepExitWeight =
                targetProfile.steps[machine.profileFrame].weight!;
            if (projectedWeight >= stepExitWeight) {
              _log.info("Step weight reached, moving on");
              de1controller.connectedDe1().requestState(MachineState.skipStep);
            }
          }
          if (doseData.doseOut > 0 && projectedWeight >= doseData.doseOut) {
            _log.info(
                "Target weight ${doseData.doseOut}g reached. Stopping shot.");
            de1controller.connectedDe1().requestState(
                MachineState.idle); // Send stop command to machine
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
        if (_stoppingStateFuture != null) {
          break;
        }
        _stoppingStateFuture = Future.delayed(Duration(seconds: 4), () {
          _log.info("Recording finished.");
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

enum ShotState {
  idle,
  preheating,
  pouring,
  stopping,
  finished,
}
