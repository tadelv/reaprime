import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
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
    _transport.disconnect();
  }

  @override
  String get name => "Half Decent Scale";

  late StreamSubscription<Uint8List> _transportSubscription;
  @override
  Future<void> onConnect() async {
    _log.info("on connect");
    await _transport.disconnect();
    _transportSubscription =
        _transport.rawStream.listen(onData, onError: (error) {
      _log.warning("transport error", error);
      disconnect();
    }, onDone: () {
      disconnect();
    });
    await _transport.writeHexCommand(Uint8List.fromList([0x03, 0x20, 0x01]));
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

  void onData(Uint8List data) {
    _log.fine("got message: $data");
    if (data.length != 7 || data[0] != 0x03 || data[1] != 0xCE) {
      _log.finest("data is not weight data");
      return;
    }
    var d = ByteData(2);
    d.setInt8(0, data[2]);
    d.setInt8(1, data[3]);
    var weight = d.getInt16(0) / 10;
    _snapshotHandler.add(ScaleSnapshot(
        timestamp: DateTime.now(), weight: weight, batteryLevel: 100));
  }
}
