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
  disconnect() async {
    _connectionSubject.add(ConnectionState.disconnected);
    _transportSubscription.cancel();
    _stringSubscription.cancel();
    await _transport.disconnect();
  }

  @override
  String get name => "Half Decent Scale";

  late StreamSubscription<Uint8List> _transportSubscription;
  late StreamSubscription<String> _stringSubscription;
  @override
  Future<void> onConnect() async {
    _log.info("on connect");
    await _transport.connect();
    _transportSubscription = _transport.rawStream.listen(
      onData,
      onError: (error) {
        _log.warning("transport error", error);
        disconnect();
      },
      onDone: () {
        disconnect();
      },
    );

    _stringSubscription = _transport.readStream.listen(
      onStringData,
      onError: (error) {
        _log.warning("transport error", error);
        disconnect();
      },
      onDone: () {
        disconnect();
      },
    );
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

  @override
  Future<void> sleepDisplay() async {
    _log.info('Putting serial Decent Scale display to sleep');
    await _sendOledOff();
  }

  @override
  Future<void> wakeDisplay() async {
    _log.info('Waking serial Decent Scale display');
    await _sendOledOn();
  }

  Future<void> _sendOledOn() async {
    List<int> payload = [];
    // payload = [0x03, 0x0A, 0x01, 0x00, 0x00, 0x01, 0x08];
    // await _transport.writeHexCommand(Uint8List.fromList(payload));
    payload = [0x03, 0x0A, 0x04, 0x00, 0x00, 0x01, 0x08];
    await _transport.writeHexCommand(Uint8List.fromList(payload));
  }

  Future<void> _sendOledOff() async {
    List<int> payload = [];
    // payload = [0x03, 0x0A, 0x04, 0x01, 0x00, 0x01, 0x09];
    // await _transport.writeHexCommand(Uint8List.fromList(payload));
    payload = [0x03, 0x0A, 0x00, 0x01, 0x00, 0x01, 0x09];
    await _transport.writeHexCommand(Uint8List.fromList(payload));
  }

  final BehaviorSubject<ScaleSnapshot> _snapshotHandler = BehaviorSubject();

  @override
  DeviceType get type => DeviceType.scale;

  void onData(Uint8List data) {
    try {
      _log.finest("got message: $data");
    } catch (_) {}
    if (data.length < 5 || data[0] != 0x03 || data[1] != 0xCE) {
      _log.finest("data is not weight data");
      return;
    }
    var d = ByteData(2);
    d.setInt8(0, data[2]);
    d.setInt8(1, data[3]);
    var weight = d.getInt16(0) / 10;
    _snapshotHandler.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: 100,
      ),
    );
  }

  final _hdsRegex = RegExp(r'\d+ Weight: (.*)');
  void onStringData(String data) {
    return;
    _log.finest("received string $data");
    final matches = _hdsRegex.allMatches(data);
    if (matches.isNotEmpty) {
      final weightStr = matches.first.groups([1]).first;
      if (weightStr != null) {
        final weight = double.parse(weightStr);

        _snapshotHandler.add(
          ScaleSnapshot(
            timestamp: DateTime.now(),
            weight: weight,
            batteryLevel: 100,
          ),
        );
      }
    }
  }

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}
}
