import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';

class DebugPort implements Sensor {
  @override
  // TODO: implement connectionState
  Stream<ConnectionState> get connectionState => throw UnimplementedError();

  @override
  // TODO: implement data
  Stream<Map<String, dynamic>> get data => throw UnimplementedError();

  @override
  // TODO: implement deviceId
  String get deviceId => throw UnimplementedError();

  @override
  disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> execute(
      String commandId, Map<String, dynamic>? parameters) {
    // TODO: implement execute
    throw UnimplementedError();
  }

  @override
  SensorInfo get info =>
      SensorInfo(name: "Debug Port", vendor: "Decent Espresso", dataChannels: [
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
  // TODO: implement name
  String get name => throw UnimplementedError();

  @override
  Future<void> onConnect() {
    // TODO: implement onConnect
    throw UnimplementedError();
  }

  @override
  // TODO: implement type
  DeviceType get type => throw UnimplementedError();
}
