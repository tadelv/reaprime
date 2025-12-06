import 'dart:async';

import 'package:ansi_escape_codes/ansi_escape_codes.dart';
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
  String get deviceId => "${_transport.id}";

  @override
  disconnect() {
    _connectionSubject.add(ConnectionState.disconnected);
    _transportSubscription.cancel();
    _transport.close();
  }

  @override
  Future<Map<String, dynamic>> execute(
    String commandId,
    Map<String, dynamic>? parameters,
  ) async {
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

    _log.fine("executing $commandId");
    await _transport.writeCommand(command);
    final response = await data.first;
    return response;
  }

  @override
  SensorInfo get info => SensorInfo(
    name: "Debug Port",
    vendor: "Decent Espresso",
    dataChannels: [DataChannel(key: "output", type: "string")],
    commands: [
      CommandDescriptor(
        id: "input",
        name: "input",
        description: "Send line to debug port",
        paramsSchema: {"command": "string"},
        resultsSchema: null,
      ),
    ],
  );

  @override
  String get name => "Debug Port";

  @override
  Future<void> onConnect() async {
    if (await _connectionSubject.first == ConnectionState.connected) {
      return;
    }
    _log.info("on connect");
    await _transport.open();
    _transportSubscription = _transport.readStream.listen(
      onData,
      onError: (error) {
        _log.warning("transport error", error);
        disconnect();
      },
      onDone: () {
        disconnect();
      },
    );
    _connectionSubject.add(ConnectionState.connected);
  }

  String _buffer = "";

  void onData(String data) {

    final split = data.split('\n');
    if (split.length == 1) {
      _buffer += split.first;
      return;
    }
    Map<String, dynamic> values = {};
    values['timestamp'] = DateTime.now().toIso8601String();

    values['output'] = AnsiParser(_buffer + split.first).removeAll();
    _streamSubject.add(values);

    _buffer = split[1].replaceAll('\n', '');
  }

  @override
  DeviceType get type => DeviceType.sensor;
}
