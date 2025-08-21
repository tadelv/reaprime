import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/serial_port.dart';
import 'package:rxdart/subjects.dart';

class HDSSerial implements Scale {
  late Logger _log;
  final SerialTransport _transport;

  HDSSerial({required SerialTransport transport}) : _transport = transport {
    _log = Logger("Serial HDS#${_transport.name}");
  }

  final BehaviorSubject<ConnectionState> _connectionSubject =
      BehaviorSubject.seeded(ConnectionState.connecting);
  @override
  Stream<ConnectionState> get connectionState =>
      _connectionSubject.asBroadcastStream();

  @override
  Stream<ScaleSnapshot> get currentSnapshot =>
      _snapshotHandler.asBroadcastStream();

  @override
  String get deviceId => _transport.name;

  @override
  disconnect() {
    _connectionSubject.add(ConnectionState.disconnected);
    _transportSubscription.cancel();
    _transport.close();
  }

  @override
  // TODO: implement name
  String get name => "Half Decent Scale";

  late StreamSubscription<String> _transportSubscription;
  @override
  Future<void> onConnect() async {
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
  Future<void> tare() async {
    Uint8List cmd = Uint8List(5);
    cmd[0] = 0x03;
    cmd[1] = 0x0F;

    await _transport.writeHexCommand(cmd);
  }

  final BehaviorSubject<ScaleSnapshot> _snapshotHandler = BehaviorSubject();

  @override
  DeviceType get type => DeviceType.scale;

  final dataRegex = RegExp(r'\d+ Weight: (.*)');
  void onData(String data) {
    _log.fine("got message: $data");
    final dataMatch = dataRegex.firstMatch(data);
    if (dataMatch == null) {
      _log.fine("data does not match regex");
      return;
    }
    final match = dataMatch.group(1);
    if (match != null) {
      _snapshotHandler.add(ScaleSnapshot(
          timestamp: DateTime.now(),
          weight: double.tryParse(match) ?? 0.0,
          batteryLevel: 100));
    }
  }
}
