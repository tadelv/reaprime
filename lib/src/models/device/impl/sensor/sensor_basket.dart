import 'dart:async';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/serial_port.dart';

class SensorBasket implements Sensor {
  late Logger _log;
  final SerialTransport _transport;

  SensorBasket({required SerialTransport transport}) : _transport = transport {
    _log = Logger("SensorBasket");
  }

  final BehaviorSubject<ConnectionState> _connectionSubject =
      BehaviorSubject.seeded(ConnectionState.connecting);
  @override
  Stream<ConnectionState> get connectionState =>
      _connectionSubject.asBroadcastStream();

  @override
  Stream<Map<String, dynamic>> get data => _streamSubject.asBroadcastStream();

  @override
  String get deviceId => "sb${_transport.id}";

  @override
  disconnect() {
    _connectionSubject.add(ConnectionState.disconnected);
    _transportSubscription.cancel();
    _transport.close();
  }

  @override
  String get name => "SensorBasket";

  late StreamSubscription<String> _transportSubscription;
  final BehaviorSubject<Map<String, dynamic>> _streamSubject =
      BehaviorSubject();

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

  @override
  DeviceType get type => DeviceType.sensor;

  void onData(String data) {
    final elements = data.split(' ');
    if (elements.length != 5) {
        return;
      }
    Map<String, dynamic> values = {};
    values['timestamp'] = DateTime.now().toIso8601String();

    if (elements.elementAtOrNull(1) != null) {
      values["temperature"] = double.tryParse(elements[1]);
    }
    if (elements.elementAtOrNull(2) != null) {
      values["pressure"] = double.tryParse(elements[2]);
    }
    if (elements.elementAtOrNull(3) != null) {
      values["weight"] = double.tryParse(elements[3]);
    }
    if (elements.elementAtOrNull(4) != null) {
      values["weightFlow"] = double.tryParse(elements[4]);
    }

    _streamSubject.add(values);
  }

  @override
  Future<Map<String, dynamic>> execute(
      String commandId, Map<String, dynamic>? parameters) async {
    if (commandId == 'tare') {
      await _transport.writeCommand('tare');
      return {'status': 'ok'};
    }
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
}
