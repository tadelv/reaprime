import 'dart:typed_data';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';



class SensorBasket implements Sensor {
  @override
  // TODO: implement connectionState
  Stream<ConnectionState> get connectionState => throw UnimplementedError();

  @override
  // TODO: implement data
  Stream<Uint8List> get data => throw UnimplementedError();

  @override
  // TODO: implement deviceId
  String get deviceId => throw UnimplementedError();

  @override
  disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  // TODO: implement name
  String get name => throw UnimplementedError();

  @override
  Future<void> onConnect() {
    // TODO: implement onConnect
    throw UnimplementedError();
  }

  @override
  Future<void> tare() {
    // TODO: implement tare
    throw UnimplementedError();
  }

  @override
  // TODO: implement type
  DeviceType get type => throw UnimplementedError();

  }
