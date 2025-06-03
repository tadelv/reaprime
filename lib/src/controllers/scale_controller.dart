import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/weight_flow_calculator.dart';
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

  MovingAverage weightFlowAverage = MovingAverage(10);

  static const smoothingWindowDuration = Duration(milliseconds: 600);

  FlowCalculator _flowCalculator =
      FlowCalculator(windowDuration: smoothingWindowDuration);

  _processSnapshot(ScaleSnapshot snapshot) {
    final flow = _flowCalculator.addSample(snapshot.timestamp, snapshot.weight);

    weightFlowAverage.add(flow); // Use your existing average queue

    _weightSnapshotController.add(WeightSnapshot(
      timestamp: snapshot.timestamp,
      weight: snapshot.weight,
      weightFlow: weightFlowAverage.average,
      battery: snapshot.batteryLevel,
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
      _flowCalculator =
          FlowCalculator(windowDuration: smoothingWindowDuration);
    }
  }
}

class WeightSnapshot {
  final DateTime timestamp;
  final double weight;
  final double weightFlow;
  final int? battery;
  WeightSnapshot({
    required this.timestamp,
    required this.weight,
    required this.weightFlow,
    this.battery,
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
