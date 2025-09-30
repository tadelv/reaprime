import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/models/device/serial_port.dart';
import 'package:rxdart/rxdart.dart';

class DebugPort implements Sensor {
  late Logger _log;
  final SerialTransport _transport;

  DebugPort({required SerialTransport transport}) : _transport = transport {
    _log = Logger("Debug Port(${transport.name})");
  }

  final BehaviorSubject<ConnectionState> _connectionSubject =
      BehaviorSubject.seeded(ConnectionState.connecting);

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionSubject.asBroadcastStream();

  late StreamSubscription<String> _transportSubscription;
  final BehaviorSubject<Map<String, dynamic>> _streamSubject =
      BehaviorSubject();

  @override
  Stream<Map<String, dynamic>> get data => _streamSubject.asBroadcastStream();

  @override
  String get deviceId => "dp${_transport.id}";

  @override
  disconnect() {
    _connectionSubject.add(ConnectionState.disconnected);
    _transportSubscription.cancel();
    _transport.close();
  }

  @override
  Future<Map<String, dynamic>> execute(
      String commandId, Map<String, dynamic>? parameters) {
    _log.fine("executing $commandId");
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
  String get name => "Debug Port";

  @override
  Future<void> onConnect() async {
    if (await _connectionSubject.first == ConnectionState.connected) {
      return;
    }
    _log.info("on connect");
    await _transport.open();
    _transportSubscription =
        _transport.readStream.listen(onData, onError: (error) {
      _log.warning("transport error", error);
      disconnect();
    }, onDone: () {
      disconnect();
    });
    _connectionSubject.add(ConnectionState.connected);
  }

  void onData(String data) {
    final elements = data.split(' ');
    if (elements.length != 5) {
      return;
    }
    Map<String, dynamic> values = {};
    values['timestamp'] = DateTime.now().toIso8601String();

    values['output'] = data;
    _streamSubject.add(values);
  }

  @override
  DeviceType get type => DeviceType.sensor;
}
