import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/weight_flow_calculator.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/util/moving_average.dart';
import 'package:rxdart/rxdart.dart';

class ScaleController {
  Scale? _scale;

  StreamSubscription<ConnectionState>? _scaleConnection;
  StreamSubscription<ScaleSnapshot>? _scaleSnapshot;

  final Logger log = Logger('ScaleController');

  ScaleController();

  void dispose() {}

  Future<void> connectToScale(Scale scale) async {
    _onDisconnect();
    _scaleSnapshot = scale.currentSnapshot.listen(_processSnapshot);
    await scale.onConnect();
    // Verify the scale actually connected (onConnect swallows errors internally).
    final state = await scale.connectionState.first;
    if (state != ConnectionState.connected) {
      log.warning('Scale failed to connect (state: ${state.name})');
      _scaleSnapshot?.cancel();
      _scaleSnapshot = null;
      _connectionController.add(ConnectionState.disconnected);
      return;
    }
    // Subscribe to connection state AFTER onConnect succeeds, so we don't
    // get poisoned by a BehaviorSubject replaying a stale 'disconnected'
    // state from before reconnection.
    _scaleConnection = scale.connectionState.listen(_processConnection);
    _scale = scale;
    _connectionController.add(ConnectionState.connected);
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
      BehaviorSubject.seeded(ConnectionState.discovered);

  Stream<ConnectionState> get connectionState => _connectionController.stream;
  ConnectionState get currentConnectionState => _connectionController.value;

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
        timerValue: snapshot.timerValue,
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
  final Duration? timerValue;
  WeightSnapshot({
    required this.timestamp,
    required this.weight,
    required this.weightFlow,
    this.battery,
    this.timerValue,
  });

  Map<String, dynamic> toJson() {
    return {
      "timestamp": timestamp.toIso8601String(),
      "weight": weight,
      "weightFlow": weightFlow,
      "timerValue": timerValue?.inMilliseconds,
    };
  }

  factory WeightSnapshot.fromJson(Map<String, dynamic> json) {
    return WeightSnapshot(
      timestamp: DateTime.parse(json["timestamp"]),
      weight: json["weight"],
      weightFlow: json["weightFlow"],
      timerValue: json["timerValue"] != null
          ? Duration(milliseconds: json["timerValue"])
          : null,
    );
  }
}
