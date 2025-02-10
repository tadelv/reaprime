import 'dart:async';

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
      weightFlow =
          difference / snapshot.timestamp.difference(_lastTimestamp!).inMilliseconds;
      weightFlowAverage.add(weightFlow * 1000);
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
}
