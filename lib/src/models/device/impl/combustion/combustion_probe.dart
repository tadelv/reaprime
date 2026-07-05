import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_protocol.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

/// BLE transports that surface Combustion manufacturer blocks from scan updates.
///
/// Production wiring lives on [UniversalBleTransport]; tests provide fakes.
abstract interface class CombustionAdvertisingTransport {
  Stream<Uint8List> get manufacturerDataStream;
}

/// Advertising-only Combustion Predictive Thermometer sensor.
class CombustionProbe implements Sensor {
  static final BleServiceIdentifier serviceIdentifier =
      BleServiceIdentifier.long(
        CombustionConstants.probeStatusServiceUuid,
      );

  static const int manufacturerId = CombustionConstants.manufacturerId;

  /// Alias used by discovery matching (SP-003).
  static const int manufacturerCompanyId =
      CombustionConstants.manufacturerCompanyId;

  final BLETransport _transport;
  final Logger _log;

  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  final BehaviorSubject<Map<String, dynamic>> _data = BehaviorSubject();

  StreamSubscription<Uint8List>? _advertisementSub;
  bool _listening = false;

  CombustionProbe({required BLETransport transport})
    : _transport = transport,
      _log = Logger('CombustionProbe(${transport.name})');

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
      DataChannel(
        key: CombustionConstants.channelTemperature,
        type: 'number',
        unit: 'Celsius',
      ),
      DataChannel(key: 'timestamp', type: 'string'),
      DataChannel(
        key: CombustionConstants.channelCore,
        type: 'number',
        unit: 'Celsius',
      ),
      DataChannel(
        key: CombustionConstants.channelSurface,
        type: 'number',
        unit: 'Celsius',
      ),
      DataChannel(
        key: CombustionConstants.channelAmbient,
        type: 'number',
        unit: 'Celsius',
      ),
      for (final channel in [
        CombustionConstants.channelT1,
        CombustionConstants.channelT2,
        CombustionConstants.channelT3,
        CombustionConstants.channelT4,
        CombustionConstants.channelT5,
        CombustionConstants.channelT6,
        CombustionConstants.channelT7,
        CombustionConstants.channelT8,
      ])
        DataChannel(key: channel, type: 'number', unit: 'Celsius'),
    ],
    commands: [],
  );

  @override
  Future<void> onConnect() async {
    if (_listening) {
      return;
    }

    final advTransport = _transport;
    if (advTransport is! CombustionAdvertisingTransport) {
      _log.warning(
        'Transport does not implement CombustionAdvertisingTransport; '
        'cannot receive advertising updates',
      );
      _connectionState.add(ConnectionState.disconnected);
      return;
    }

    _connectionState.add(ConnectionState.connecting);
    try {
      await _advertisementSub?.cancel();
      _advertisementSub = (advTransport as CombustionAdvertisingTransport)
          .manufacturerDataStream
          .listen(
            _handleManufacturerData,
            onError: (Object error, StackTrace stackTrace) {
              _log.warning(
                'Combustion advertisement stream error',
                error,
                stackTrace,
              );
            },
          );
      _listening = true;
      _connectionState.add(ConnectionState.connected);
    } catch (e, st) {
      _log.warning('Failed to start Combustion advertisement listener', e, st);
      await _advertisementSub?.cancel();
      _advertisementSub = null;
      _listening = false;
      _connectionState.add(ConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _advertisementSub?.cancel();
    _advertisementSub = null;
    _listening = false;
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  Future<Map<String, dynamic>> execute(
    String commandId,
    Map<String, dynamic>? parameters,
  ) {
    throw UnimplementedError('Combustion UART commands are not implemented');
  }

  void _handleManufacturerData(Uint8List data) {
    final reading = CombustionProtocol.parseManufacturerData(data);
    if (reading == null) {
      return;
    }

    final snapshot = _snapshotFromReading(reading);
    if (snapshot == null) {
      return;
    }
    _data.add(snapshot);
  }

  /// OD-1: steam/brew default channel is virtual core, with T1 fallback.
  Map<String, dynamic>? _snapshotFromReading(CombustionReading reading) {
    final temperature = reading.virtualCore ?? reading.t1;
    if (temperature == null) {
      return null;
    }

    final snapshot = <String, dynamic>{
      CombustionConstants.channelTemperature: temperature,
      'timestamp': reading.timestamp.toIso8601String(),
    };

    _putIfNotNull(
      snapshot,
      CombustionConstants.channelCore,
      reading.virtualCore,
    );
    _putIfNotNull(
      snapshot,
      CombustionConstants.channelSurface,
      reading.virtualSurface,
    );
    _putIfNotNull(
      snapshot,
      CombustionConstants.channelAmbient,
      reading.virtualAmbient,
    );

    final thermistorChannels = [
      CombustionConstants.channelT1,
      CombustionConstants.channelT2,
      CombustionConstants.channelT3,
      CombustionConstants.channelT4,
      CombustionConstants.channelT5,
      CombustionConstants.channelT6,
      CombustionConstants.channelT7,
      CombustionConstants.channelT8,
    ];
    for (var index = 0; index < thermistorChannels.length; index++) {
      _putIfNotNull(
        snapshot,
        thermistorChannels[index],
        reading.thermistors[index],
      );
    }

    return snapshot;
  }

  void _putIfNotNull(
    Map<String, dynamic> target,
    String key,
    double? value,
  ) {
    if (value != null) {
      target[key] = value;
    }
  }
}
