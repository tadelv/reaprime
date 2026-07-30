import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/rxdart.dart';

import 'test_scale.dart';

/// Test [ScaleController] with controllable connection state and weight
/// emission. Seeds with [device.ConnectionState.connected] by default.
class TestScaleController extends ScaleController {
  final TestScale testScale;
  final BehaviorSubject<device.ConnectionState> _connectionState;
  final BehaviorSubject<WeightSnapshot> _weight = BehaviorSubject();
  int _generation = 0;

  TestScaleController(this.testScale)
    : _connectionState = BehaviorSubject.seeded(
        device.ConnectionState.connected,
      );

  @override
  Stream<device.ConnectionState> get connectionState => _connectionState.stream;

  @override
  device.ConnectionState get currentConnectionState => _connectionState.value;

  @override
  int get connectionGeneration => _generation;

  @override
  ({Scale scale, int generation})? get currentScaleLease =>
      _connectionState.value == device.ConnectionState.connected
      ? (scale: testScale, generation: _generation)
      : null;

  @override
  Stream<WeightSnapshot> get weightSnapshot => _weight.stream;

  @override
  Scale connectedScale() {
    if (_connectionState.value != device.ConnectionState.connected) {
      throw 'No scale connected';
    }
    return testScale;
  }

  void emitWeight(
    double weight, {
    double weightFlow = 0.0,
    double? controlWeightFlow,
  }) {
    _weight.add(
      WeightSnapshot(
        timestamp: DateTime(2026, 1, 15, 8, 0),
        weight: weight,
        weightFlow: weightFlow,
        controlWeightFlow: controlWeightFlow,
      ),
    );
  }

  void simulateDisconnect() {
    _connectionState.add(device.ConnectionState.disconnected);
  }

  void simulateConnect() {
    _connectionState.add(device.ConnectionState.connected);
  }

  void simulateScaleSwitch() {
    _generation++;
    _connectionState.add(device.ConnectionState.connected);
  }

  @override
  void dispose() {
    _connectionState.close();
    _weight.close();
    super.dispose();
  }
}
