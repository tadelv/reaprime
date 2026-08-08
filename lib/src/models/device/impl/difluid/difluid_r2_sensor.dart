import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_r2_protocol.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:rxdart/rxdart.dart';

class DifluidR2Sensor implements Sensor {
  static final BleServiceIdentifier serviceIdentifier =
      BleServiceIdentifier.long('000000ff-0000-1000-8000-00805f9b34fb');
  static final BleServiceIdentifier dataCharacteristic =
      BleServiceIdentifier.long('0000aa01-0000-1000-8000-00805f9b34fb');

  final BLETransport _transport;
  final Logger _log;
  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  final BehaviorSubject<Map<String, dynamic>> _data = BehaviorSubject();
  final Set<Completer<Map<String, dynamic>>> _measurementWaiters = {};

  StreamSubscription<ConnectionState>? _disconnectSub;
  bool _initialized = false;
  double? _lastTemperatureC;

  DifluidR2Sensor({required BLETransport transport})
    : _transport = transport,
      _log = Logger('DifluidR2Sensor(${transport.name})');

  @override
  String get deviceId => _transport.id;

  @override
  DeviceImplementation get implementation =>
      DeviceImplementation.difluidR2Sensor;

  @override
  TransportType get transportType => _transport.transportType;

  @override
  String get name => 'DiFluid R2';

  @override
  DeviceType get type => DeviceType.sensor;

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Stream<Map<String, dynamic>> get data => _data.stream;

  @override
  SensorInfo get info => SensorInfo(
    name: name,
    vendor: 'DiFluid',
    dataChannels: [
      DataChannel(key: 'timestamp', type: 'string'),
      DataChannel(key: 'tds', type: 'number', unit: 'percent'),
      DataChannel(key: 'temperature', type: 'number', unit: 'Celsius'),
      DataChannel(key: 'temperatureC', type: 'number', unit: 'Celsius'),
      DataChannel(key: 'refractiveIndex', type: 'number'),
      DataChannel(key: 'status', type: 'string'),
      DataChannel(key: 'measuring', type: 'boolean'),
      DataChannel(key: 'error', type: 'string'),
    ],
    commands: [
      CommandDescriptor(
        id: 'measure',
        name: 'Measure TDS',
        description: 'Trigger a single DiFluid R2 TDS reading.',
        paramsSchema: {
          'type': 'object',
          'properties': {
            'timeout': {'type': 'number'},
          },
        },
        resultsSchema: {
          'type': 'object',
          'properties': {
            'reading': {'type': 'object'},
          },
        },
      ),
    ],
  );

  @override
  Future<void> onConnect() async {
    if (_initialized) return;

    _connectionState.add(ConnectionState.connecting);
    try {
      await _transport.connect();
      _disconnectSub?.cancel();
      _disconnectSub = _transport.connectionState
          .where((state) => state == ConnectionState.disconnected)
          .listen((_) {
            _initialized = false;
            _connectionState.add(ConnectionState.disconnected);
          });

      final services = await _transport.discoverServices();
      if (!serviceIdentifier.matchesAny(services)) {
        throw Exception(
          'Expected service ${serviceIdentifier.long} not found. '
          'Discovered services: $services',
        );
      }

      await _transport.subscribe(
        serviceIdentifier.long,
        dataCharacteristic.long,
        _handleNotification,
      );
      await _transport.write(
        serviceIdentifier.long,
        dataCharacteristic.long,
        DifluidR2Protocol.setCelsiusCommand(),
        withResponse: true,
      );

      _initialized = true;
      _connectionState.add(ConnectionState.connected);
    } catch (e, st) {
      _log.warning('Failed to initialize DiFluid R2', e, st);
      _initialized = false;
      _connectionState.add(ConnectionState.disconnected);
      await _disconnectSub?.cancel();
      _disconnectSub = null;
      try {
        await _transport.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _initialized = false;
    _completeWaitersWithError('R2 disconnected');
    await _disconnectSub?.cancel();
    _disconnectSub = null;
    _connectionState.add(ConnectionState.disconnected);
    await _transport.disconnect();
  }

  @override
  Future<Map<String, dynamic>> execute(
    String commandId,
    Map<String, dynamic>? parameters,
  ) async {
    if (commandId != 'measure') {
      throw UnsupportedError('Unsupported R2 command: $commandId');
    }

    await onConnect();
    final timeout = _measurementTimeout(parameters);
    final completer = Completer<Map<String, dynamic>>();
    _measurementWaiters.add(completer);
    try {
      await _transport.write(
        serviceIdentifier.long,
        dataCharacteristic.long,
        DifluidR2Protocol.singleTestCommand(),
        withResponse: true,
      );
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw TimeoutException('Timed out waiting for R2 reading', timeout);
    } finally {
      _measurementWaiters.remove(completer);
    }
  }

  void _handleNotification(Uint8List raw) {
    try {
      final event = DifluidR2Protocol.parse(raw);
      _handleEvent(event);
    } on DifluidR2ProtocolException catch (e, st) {
      _log.warning('Invalid R2 packet', e, st);
      _data.add({
        'timestamp': DateTime.now().toIso8601String(),
        'error': e.message,
      });
    }
  }

  void _handleEvent(DifluidR2Event event) {
    final snapshot = _snapshotForEvent(event);
    if (snapshot == null) return;

    _data.add(snapshot);
    if (event.kind == DifluidR2EventKind.reading) {
      _completeWaiters({'reading': snapshot});
    } else if (event.kind == DifluidR2EventKind.error) {
      _completeWaitersWithError(event.error ?? 'R2 measurement failed');
    }
  }

  Map<String, dynamic>? _snapshotForEvent(DifluidR2Event event) {
    final timestamp = DateTime.now().toIso8601String();
    switch (event.kind) {
      case DifluidR2EventKind.status:
        return {
          'timestamp': timestamp,
          'status': event.status,
          'measuring': event.measuring,
        };
      case DifluidR2EventKind.temperature:
        _lastTemperatureC = event.temperatureC;
        return {
          'timestamp': timestamp,
          'temperature': event.temperatureC,
          'temperatureC': event.temperatureC,
        };
      case DifluidR2EventKind.reading:
        return {
          'timestamp': timestamp,
          'tds': event.tds,
          if (_lastTemperatureC != null) 'temperature': _lastTemperatureC,
          if (_lastTemperatureC != null) 'temperatureC': _lastTemperatureC,
          if (event.refractiveIndex != null)
            'refractiveIndex': event.refractiveIndex,
        };
      case DifluidR2EventKind.error:
        return {
          'timestamp': timestamp,
          'error': event.error,
          'measuring': false,
        };
      case DifluidR2EventKind.ack:
      case DifluidR2EventKind.unknown:
        return null;
    }
  }

  Duration _measurementTimeout(Map<String, dynamic>? parameters) {
    final rawTimeout = parameters?['timeout'];
    if (rawTimeout is num && rawTimeout > 0) {
      return Duration(milliseconds: (rawTimeout * 1000).round());
    }
    return const Duration(seconds: 30);
  }

  void _completeWaiters(Map<String, dynamic> value) {
    for (final waiter in List.of(_measurementWaiters)) {
      if (!waiter.isCompleted) waiter.complete(value);
    }
  }

  void _completeWaitersWithError(String message) {
    for (final waiter in List.of(_measurementWaiters)) {
      if (!waiter.isCompleted) waiter.completeError(Exception(message));
    }
  }
}
