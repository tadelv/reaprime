import 'dart:async';
import 'dart:math';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';

class MockScale implements Scale {
  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _snapshotStream.stream;

  @override
  String get deviceId => "Mock Scale";

  @override
  disconnect() async {}

  @override
  String get name => "Mock Scale";

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> tare() async {
    _weight = 0;
  }

  @override
  DeviceType get type => DeviceType.scale;

  final StreamController<ScaleSnapshot> _snapshotStream =
      StreamController.broadcast();

  double _weight = 0;

  MockScale() {
    Timer.periodic(Duration(milliseconds: 200), (_) {
      _weight += 1.1 * Random().nextDouble();
      if (_weight > 100) {
        _weight = 0;
      }
      _snapshotStream.add(ScaleSnapshot(
          weight: _weight, timestamp: DateTime.now(), batteryLevel: 100));
    });
  }
}
