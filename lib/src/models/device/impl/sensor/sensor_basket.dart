import 'dart:typed_data';
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
  Stream<Uint8List> get data => _streamSubject.asBroadcastStream();

  @override
  String get deviceId => _transport.name;

  @override
  disconnect() {
    _connectionSubject.add(ConnectionState.disconnected);
    _transportSubscription.cancel();
    _transport.close();
  }

  @override
  String get name => "SensorBasket";

  late StreamSubscription<Uint8List> _transportSubscription;
  final BehaviorSubject<Uint8List> _streamSubject = BehaviorSubject();

  @override
  Future<void> onConnect() async {
    _log.info("on connect");
    await _transport.open();
    _transportSubscription =
        _transport.rawStream.listen(onData, onError: (error) {
      _log.warning("transport error", error);
      disconnect();
    }, onDone: () {
      disconnect();
    });
    _connectionSubject.add(ConnectionState.connected);
  }

  @override
  Future<void> tare() {
    // TODO: implement tare
    throw UnimplementedError();
  }

  @override
  DeviceType get type => DeviceType.sensor;

  void onData(Uint8List data) {
    _log.finest("recv: ${data.map((e) => e.toRadixString(16))}");
    _streamSubject.add(data);
  }
}
