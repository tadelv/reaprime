import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:rxdart/rxdart.dart';

class ShotController {
  final De1Controller de1controller;
  final ScaleController scaleController;

  final Logger _log = Logger("ShotController");

  ShotController(
      {required this.scaleController,
      required this.de1controller,
      TargetShotParameters? targetShot})
      : _targetShot = targetShot {
    Future.value(_initialize()).then((_) {
      _log.info("ShotController initialized");
    });
  }

  Future<void> _initialize() async {
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

  final TargetShotParameters? _targetShot;
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

  void _handleStateTransition(ShotSnapshot snapshot) {
    final MachineSnapshot machine = snapshot.machine;
    final WeightSnapshot? scale = snapshot.scale;

    _log.finest(
        "recv: ${machine.state.substate.name}, ${machine.state.state.name}");

    _log.finest("State in: ${_state.name}");
    switch (_state) {
      case ShotState.idle:
        if (machine.state.substate == MachineSubstate.preparingForShot) {
          _resetCommand.add(true);
          _shotStartTime = DateTime.now();
          if (scale != null) {
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
          if (scale != null) {
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
        if (scale != null && _targetShot != null) {
          double currentWeight = scale.weight;
          if (currentWeight >= _targetShot.targetWeight) {
            _log.info(
                "Target weight ${_targetShot.targetWeight}g reached. Stopping shot.");
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
        Future.delayed(Duration(seconds: 4), () {
          _log.info("Recording finished.");
          _state = ShotState.finished;
          _stateStream.add(_state);
        });
        break;

      case ShotState.finished:
        // Reset or prepare for next shot
        dataCollectionEnabled = false;
        _state = ShotState.idle;
        _stateStream.add(_state);
        break;
    }
    _log.finest("State out: ${_state.name}");
  }
}

class ShotSnapshot {
  final MachineSnapshot machine;
  final WeightSnapshot? scale;

  ShotSnapshot({required this.machine, this.scale});

  copyWith({MachineSnapshot? machine, WeightSnapshot? scale}) {
    return ShotSnapshot(
      machine: machine ?? this.machine,
      scale: scale ?? this.scale,
    );
  }
}

class TargetShotParameters {
  final double targetWeight;

  const TargetShotParameters({required this.targetWeight});
}

enum ShotState {
  idle,
  preheating,
  pouring,
  stopping,
  finished,
}
