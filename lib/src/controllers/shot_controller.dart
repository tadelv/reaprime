import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/transformers.dart';

class ShotController {
  final De1Controller de1controller;
  final ScaleController scaleController;

  final Logger _log = Logger("ShotController");

  ShotController({required this.scaleController, required this.de1controller}) {
    try {
      var combinedStream = de1controller
          .connectedDe1()
          .currentSnapshot
          .withLatestFrom(
              scaleController.connectedScale().currentSnapshot,
              (machine, weight) =>
                  ShotSnapshot(machine: machine, scale: weight));
      _snapshotSubscription = combinedStream.listen(_processSnapshot);
    } catch (e) {
      _log.warning("Continuing without scale");
      _snapshotSubscription = de1controller
          .connectedDe1()
          .currentSnapshot
          .map((snapshot) => ShotSnapshot(machine: snapshot))
          .listen(_processSnapshot);
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

  TargetShotParameters? _targetShot;
  ShotState _state = ShotState.idle;

  _processSnapshot(ShotSnapshot snapshot) {
    _rawShotDataStream.add(snapshot);
    _handleStateTransition(snapshot);
    if (dataCollectionEnabled) {
      _shotDataStream.add(snapshot);
    }
  }

  bool dataCollectionEnabled = false;

  void _handleStateTransition(ShotSnapshot snapshot) {
    final MachineSnapshot machine = snapshot.machine;
    final ScaleSnapshot? scale = snapshot.scale;

    _log.shout(
        "recv: ${machine.state.substate.name}, ${machine.state.state.name}");

    _log.shout("State in: ${_state.name}");
    switch (_state) {
      case ShotState.idle:
        if (machine.state.substate == MachineSubstate.preparingForShot) {
          if (scale != null) {
            _log.info("Machine getting ready. Taring scale...");
            scaleController.connectedScale().tare();
          }
          _state = ShotState.preheating;
          dataCollectionEnabled = true;
        }
        break;

      case ShotState.preheating:
        if (machine.state.substate == MachineSubstate.pouring) {
          if (scale != null) {
            _log.info("Taring scale again.");
            scaleController.connectedScale().tare();
          }
          _state = ShotState.pouring;
        }
        break;

      case ShotState.pouring:
        if (scale != null && _targetShot != null) {
          double currentWeight = scale.weight;
          if (currentWeight >= _targetShot!.targetWeight) {
            _log.info(
                "Target weight ${_targetShot!.targetWeight}g reached. Stopping shot.");
            de1controller.connectedDe1().requestState(
                MachineState.idle); // Send stop command to machine
            _state = ShotState.stopping;
          }
        }
        if (machine.state.substate == MachineSubstate.pouringDone ||
            machine.state.substate == MachineSubstate.idle) {
          _state = ShotState.stopping;
        }
        break;

      case ShotState.stopping:
        Future.delayed(Duration(seconds: 3), () {
          _log.info("Recording finished.");
          _state = ShotState.finished;
        });
        break;

      case ShotState.finished:
        // Reset or prepare for next shot
        dataCollectionEnabled = false;
				_snapshotSubscription?.cancel();
        break;
    }
    _log.shout("State out: ${_state.name}");
  }
}

class ShotSnapshot {
  final MachineSnapshot machine;
  final ScaleSnapshot? scale;

  ShotSnapshot({required this.machine, this.scale});

  copyWith({MachineSnapshot? machine, ScaleSnapshot? scale}) {
    return ShotSnapshot(
      machine: machine ?? this.machine,
      scale: scale ?? this.scale,
    );
  }
}

class TargetShotParameters {
  final double targetWeight;

  TargetShotParameters({required this.targetWeight});
}

enum ShotState {
  idle,
  preheating,
  pouring,
  stopping,
  finished,
}
