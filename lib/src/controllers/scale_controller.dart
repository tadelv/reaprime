import 'dart:async';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/weight_flow_calculator.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/util/moving_average.dart';
import 'package:rxdart/rxdart.dart';

class ScaleController {
  final DeviceController _deviceController;

  StreamSubscription<List<Device>>? _deviceStreamSubscription;

  Scale? _scale;

  String? _preferredScaleId;

  StreamSubscription<ConnectionState>? _scaleConnection;
  StreamSubscription<ScaleSnapshot>? _scaleSnapshot;

  final Logger log = Logger('ScaleController');

  ScaleController({
    required DeviceController controller,
    String? preferredScaleId,
  }) : _deviceController = controller,
       _preferredScaleId = preferredScaleId {
    _deviceStreamSubscription = _deviceController.deviceStream.listen((devices) async {
      var scales = devices.whereType<Scale>().toList();
      if (_scale == null &&
          scales.isNotEmpty &&
          _deviceController.shouldAutoConnect) {
        if (_preferredScaleId != null) {
          // Connect only to the preferred scale
          final preferred = scales.firstWhereOrNull(
            (s) => s.deviceId == _preferredScaleId,
          );
          if (preferred != null) {
            await connectToScale(preferred);
          }
          // If preferred not found, don't connect to any scale
        } else {
          // No preference set — connect to first scale found
          await connectToScale(scales.first);
        }
      }
    });
  }

  set preferredScaleId(String? id) => _preferredScaleId = id;

  void dispose() {
      _deviceStreamSubscription?.cancel();
    }

  Future<void> connectToScale(Scale scale) async {
    _onDisconnect();
    _scaleConnection = scale.connectionState.listen(_processConnection);
    _scaleSnapshot = scale.currentSnapshot.listen(_processSnapshot);
    await scale.onConnect();
    // Only set _scale if we're still connected (onConnect may have failed
    // and triggered _onDisconnect which nulls _scaleConnection).
    if (_scaleConnection != null) {
      _scale = scale;
    }
  }

  void _onDisconnect() {
    _scaleSnapshot?.cancel();
    _scaleConnection?.cancel();
    _scale = null;
    _scaleConnection = null;
    _flowCalculator = FlowCalculator(windowDuration: smoothingWindowDuration);
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

  FlowCalculator _flowCalculator = FlowCalculator(
    windowDuration: smoothingWindowDuration,
  );

  _processSnapshot(ScaleSnapshot snapshot) {
    final flow = _flowCalculator.addSample(snapshot.timestamp, snapshot.weight);

    weightFlowAverage.add(flow); // Use your existing average queue

    _weightSnapshotController.add(
      WeightSnapshot(
        timestamp: snapshot.timestamp,
        weight: snapshot.weight,
        weightFlow: weightFlowAverage.average,
        battery: snapshot.batteryLevel,
      ),
    );
  }

  _processConnection(ConnectionState d) {
    log.info('scale connection update: ${d.name}');
    _connectionController.add(d);
    if (d == ConnectionState.disconnected) {
      _onDisconnect();
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
