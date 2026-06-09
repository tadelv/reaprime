import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/weight_flow_calculator.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/util/moving_average.dart';
import 'package:rxdart/rxdart.dart';

class ScaleController {
  Scale? _scale;

  StreamSubscription<ConnectionState>? _scaleConnection;
  StreamSubscription<ScaleSnapshot>? _scaleSnapshot;

  /// The deviceId of the most recently connected scale. Not cleared on
  /// disconnect — ConnectionManager reads this after a drop to know which
  /// device went away. Overwritten on the next successful connect.
  String? _lastConnectedDeviceId;
  String? get lastConnectedDeviceId => _lastConnectedDeviceId;

  final Logger log = Logger('ScaleController');

  ScaleController();

  /// End-of-life cleanup. Cancels active stream subscriptions and
  /// closes the exposed subjects so downstream listeners see
  /// `onDone` (comms-harden #13). Safe to call more than once.
  void dispose() {
    _scaleSnapshot?.cancel();
    _scaleSnapshot = null;
    _scaleConnection?.cancel();
    _scaleConnection = null;
    if (!_connectionController.isClosed) {
      _connectionController.close();
    }
    if (!_weightSnapshotController.isClosed) {
      _weightSnapshotController.close();
    }
  }

  Future<void> connectToScale(Scale scale) async {
    // Only one scale is active at a time. Disconnect the previously-connected
    // scale device before connecting the new one — `_onDisconnect()` only drops
    // this controller's references/subscriptions; without an explicit
    // `disconnect()` the old scale keeps reporting `connected` and the device
    // list shows two scales connected at once.
    final previous = _scale;
    _onDisconnect();
    if (previous != null && previous.deviceId != scale.deviceId) {
      try {
        // Switching the active scale is a handoff, not a user "turn off". The
        // BLE Decent Scale powers the physical device off on a normal
        // disconnect; since the same physical Half Decent Scale can be reached
        // via BLE/USB/WiFi, powering it off here would defeat a transport
        // switch (and turn the scale off). Use the non-destructive handoff
        // path when the scale supports it.
        if (previous is TransportHandoffScale) {
          await (previous as TransportHandoffScale).disconnectForHandoff();
        } else {
          await previous.disconnect();
        }
      } catch (e) {
        log.warning(
            'Failed to disconnect previous scale ${previous.deviceId}', e);
      }
    }
    _scaleSnapshot = scale.currentSnapshot.listen(_processSnapshot);
    await scale.onConnect();
    // Verify the scale actually connected (onConnect swallows errors internally).
    final state = await scale.connectionState.first;
    if (state != ConnectionState.connected) {
      log.warning('Scale failed to connect (state: ${state.name})');
      _scaleSnapshot?.cancel();
      _scaleSnapshot = null;
      _connectionController.add(ConnectionState.disconnected);
      throw StateError(
        'Scale failed to connect (state: ${state.name})',
      );
    }
    // Subscribe to connection state AFTER onConnect succeeds, so we don't
    // get poisoned by a BehaviorSubject replaying a stale 'disconnected'
    // state from before reconnection.
    _scaleConnection = scale.connectionState.listen(_processConnection);
    _scale = scale;
    _lastConnectedDeviceId = scale.deviceId;
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
      throw const DeviceNotConnectedException.scale();
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

  void _processSnapshot(ScaleSnapshot snapshot) {
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

  void _processConnection(ConnectionState d) {
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
      "battery": battery,
      "timerValue": timerValue?.inMilliseconds,
    };
  }

  factory WeightSnapshot.fromJson(Map<String, dynamic> json) {
    return WeightSnapshot(
      timestamp: DateTime.parse(json["timestamp"]),
      weight: json["weight"],
      weightFlow: json["weightFlow"],
      battery: json["battery"],
      timerValue: json["timerValue"] != null
          ? Duration(milliseconds: json["timerValue"])
          : null,
    );
  }
}
