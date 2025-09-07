import 'dart:async';
import 'dart:math';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/rng.dart';

class MockSensorBasket implements Sensor {
  @override
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected);

  final BehaviorSubject<Map<String, dynamic>> _streamSubject =
      BehaviorSubject();
  @override
  Stream<Map<String, dynamic>> get data => _streamSubject.stream;

  @override
  String get deviceId => "mock";

  @override
  disconnect() {
    _timer.cancel();
  }

  @override
  Future<Map<String, dynamic>> execute(
      String commandId, Map<String, dynamic>? parameters) async {
    return {};
  }

  @override
  SensorInfo get info =>
      SensorInfo(name: "SensorBasket", vendor: "DecentEspresso", dataChannels: [
        DataChannel(key: "timestamp", type: "string"),
        DataChannel(key: "temperature", type: "number", unit: "°C"),
        DataChannel(key: "pressure", type: "number", unit: "Bar"),
        DataChannel(key: "weight", type: "number", unit: "g"),
        DataChannel(key: "weightFlow", type: "number", unit: "g/s"),
      ], commands: [
        CommandDescriptor(
            id: 'tare',
            name: 'Tare',
            description: 'Tare sensor scale',
            paramsSchema: null,
            resultsSchema: null)
      ]);

  @override
  String get name => "SensorBasket";

  late Timer _timer;

  @override
  Future<void> onConnect() async {
    // start mock stream
    _timer = Timer.periodic(Duration(milliseconds: 300), (t) {
      final rand = Random.secure();
      _streamSubject.add({
        "timestamp": "",
        "temperature": rand.nextDouble(),
        "pressure": rand.nextDouble(),
        "weight": rand.nextDouble(),
        "weightFlow": rand.nextDouble(),
      });
    });
  }

  @override
  DeviceType get type => DeviceType.sensor;
}
