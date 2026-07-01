import 'dart:async';

import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

/// Advertising-only Combustion Predictive Thermometer sensor.
///
/// Full adv parsing and data streaming are implemented in SP-005.
class CombustionProbe implements Sensor {
  static final BleServiceIdentifier serviceIdentifier = BleServiceIdentifier.long(
    CombustionConstants.probeStatusServiceUuid,
  );

  static const int manufacturerCompanyId =
      CombustionConstants.manufacturerCompanyId;

  final BLETransport _transport;
  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  final BehaviorSubject<Map<String, dynamic>> _data = BehaviorSubject();

  CombustionProbe({required BLETransport transport}) : _transport = transport;

  @override
  String get deviceId => _transport.id;

  @override
  String get name => _transport.name;

  @override
  DeviceType get type => DeviceType.sensor;

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Stream<Map<String, dynamic>> get data => _data.stream;

  @override
  SensorInfo get info => SensorInfo(
    name: name.isNotEmpty ? name : 'Combustion Probe',
    vendor: 'Combustion Inc',
    dataChannels: [
      DataChannel(key: 'temperature', type: 'number', unit: 'Celsius'),
    ],
    commands: [],
  );

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> disconnect() async {
    await _transport.disconnect();
  }

  @override
  Future<Map<String, dynamic>> execute(
    String commandId,
    Map<String, dynamic>? parameters,
  ) {
    throw UnimplementedError();
  }
}
