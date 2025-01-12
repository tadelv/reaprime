import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';

class De1 with ChangeNotifier implements Machine {
  static Uuid advertisingUUID = Uuid.parse(
    '0000FFFF-0000-1000-8000-00805F9B34FB',
  );

  final String _deviceId;

  De1({required String deviceId}) : _deviceId = deviceId;

  factory De1.fromId(String id) {
    return De1(deviceId: id);
  }

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "DE1";

  @override
  Future<void> onConnect() {
    // TODO: implement onConnect
    throw UnimplementedError();
  }

  @override
  DeviceType get type => DeviceType.machine;

  @override
  // TODO: implement currentSnapshot
  MachineSnapshot get currentSnapshot => throw UnimplementedError();
}
