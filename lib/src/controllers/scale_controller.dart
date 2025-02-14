import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/util/moving_average.dart';
import 'package:rxdart/rxdart.dart';

class ScaleController {
  final DeviceController _deviceController;

  Scale? _scale;

  StreamSubscription<ConnectionState>? _scaleConnection;
  StreamSubscription<ScaleSnapshot>? _scaleSnapshot;

  final Logger log = Logger('ScaleController');

  ScaleController({required DeviceController controller})
      : _deviceController = controller {
    _deviceController.deviceStream.listen((devices) async {
      var scales = devices.whereType<Scale>().toList();
      if (_scale == null && scales.firstOrNull != null) {
        var scale = scales.first;
        _scaleConnection = scale.connectionState.listen(_processConnection);
        _scaleSnapshot = scale.currentSnapshot.listen(_processSnapshot);
        await scale.onConnect();
        _scale = scale;
      }
    });
  }

  Scale connectedScale() {
    if (_scale == null) {
      throw "No scale connected";
    }
    return _scale!;
  }

  final BehaviorSubject<ConnectionState> _connectionController =
      BehaviorSubject.seeded(ConnectionState.disconnected);

  Stream<ConnectionState> get connectionState => _connectionController.stream;

  final StreamController<WeightSnapshot> _weightSnapshotController =
      StreamController.broadcast();

  Stream<WeightSnapshot> get weightSnapshot => _weightSnapshotController.stream;

  double? _lastWeight;
  DateTime? _lastTimestamp;
  MovingAverage weightFlowAverage = MovingAverage(20);

  _processSnapshot(ScaleSnapshot snapshot) {
    // calculate weight flow
    var weightFlow = 0.0;
    if (_lastWeight != null) {
      var difference = snapshot.weight - _lastWeight!;
      log.finest("weight diff: ${difference.toStringAsFixed(3)}");
      weightFlow = (difference * 1000) /
          snapshot.timestamp.difference(_lastTimestamp!).inMilliseconds;
      log.finest("raw flow: ${weightFlow.toStringAsFixed(3)}");
      log.finest(
          "ms difference: ${snapshot.timestamp.difference(_lastTimestamp!).inMilliseconds}");
      if (!weightFlow.isNaN && !weightFlow.isInfinite) {
        weightFlow = weightFlow.abs();
        weightFlow = max(0, min(weightFlow, 8.0));
        log.finest("smoothed flow: ${weightFlow.toStringAsFixed(3)}");
        weightFlowAverage.add(weightFlow);
        log.finest(
            "new average: ${weightFlowAverage.average.toStringAsFixed(3)}");
      } else {
        weightFlowAverage.add(0);
      }
    }
    _lastWeight = snapshot.weight;
    _lastTimestamp = snapshot.timestamp;
    _weightSnapshotController.add(WeightSnapshot(
      timestamp: snapshot.timestamp,
      weight: snapshot.weight,
      weightFlow: weightFlowAverage.average,
    ));
  }

  _processConnection(ConnectionState d) {
    log.info('scale connection update: ${d.name}');
    _connectionController.add(d);
    if (d == ConnectionState.disconnected) {
      _scaleSnapshot?.cancel();
      _scaleConnection?.cancel();
      _scale = null;
      _scaleConnection = null;
    }
  }
}

class WeightSnapshot {
  final DateTime timestamp;
  final double weight;
  final double weightFlow;
  WeightSnapshot({
    required this.timestamp,
    required this.weight,
    required this.weightFlow,
  });

  Map<String, dynamic> toJson() {
    return {
      "timestamp": timestamp.toIso8601String(),
      "weight": weight,
      "weightFlow": weightFlow,
    };
  }

  factory WeightSnapshot.fromJson(Map<String, dynamic> json) {
    return WeightSnapshot(
      timestamp: DateTime.parse(json["timestamp"]),
      weight: json["weight"],
      weightFlow: json["weightFlow"],
    );
  }
}
