
import 'dart:async';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:rxdart/rxdart.dart';

class MockDebugPort implements Sensor {
  @override
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected);

  final BehaviorSubject<Map<String, dynamic>> _streamSubject =
      BehaviorSubject();
  @override
  Stream<Map<String, dynamic>> get data => _streamSubject.stream;

  @override
  String get deviceId => "mockDebugPort";

  @override
  disconnect() {
    _timer.cancel();
  }

  @override
  Future<Map<String, dynamic>> execute(
      String commandId, Map<String, dynamic>? parameters) async {
    if (commandId != "input") {
      throw "Invalid command";
    }
    if (parameters == null) {
      throw 'Parameter "command" required';
    }

    final command = parameters["command"];

    if (command == null || command.runtimeType != String) {
      throw 'Invalid "command" type: ${command.runtimeType}';
    }

    _streamSubject.add({
        "timestamp": "${DateTime.timestamp()}",
        "output": "[DEBUG] execute: $command"
      });
    return {};
  }

  @override
  SensorInfo get info =>
      SensorInfo(name: "DebugPort", vendor: "DecentEspresso", dataChannels: [
        DataChannel(key: "output", type: "string")
      ], commands: [
        CommandDescriptor(
            id: "input",
            name: "input",
            description: "Send line to debug port",
            paramsSchema: {"command": "string"},
            resultsSchema: null)
      ]);

  @override
  String get name => "DebugPort";

  late Timer _timer;

  @override
  Future<void> onConnect() async {
    // start mock stream
    _timer = Timer.periodic(Duration(milliseconds: 500), (t) {
      _streamSubject.add({
        "timestamp": "${DateTime.timestamp()}",
        "output": "R 1234567"
      });
    });
  }

  @override
  DeviceType get type => DeviceType.sensor;
}
