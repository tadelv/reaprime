import 'dart:async';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/models/device/simulated_device.dart';
import 'package:rxdart/rxdart.dart';

/// Simulated Combustion Predictive Thermometer for tests and `--dart-define=simulate`.
class MockCombustionProbe implements Sensor, SimulatedDevice {
  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  final BehaviorSubject<Map<String, dynamic>> _data = BehaviorSubject();

  double _temperatureCelsius = 20.0;
  double? _coreCelsius;
  Timer? _emissionTimer;
  bool _stalled = false;

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Stream<Map<String, dynamic>> get data => _data.stream;

  @override
  String get deviceId => 'MockCombustionProbe';

  @override
  String get name => 'Combustion Probe';

  @override
  DeviceType get type => DeviceType.sensor;

  @override
  SensorInfo get info => SensorInfo(
    name: name,
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

  /// Sets the next reading temperature (virtual core defaults to [celsius]).
  void setTemperature(double celsius, {double? core, double? t1}) {
    _temperatureCelsius = celsius;
    _coreCelsius = core ?? celsius;
    _emitSnapshot(t1: t1 ?? celsius);
  }

  void _emitSnapshot({double? t1}) {
    if (_stalled) {
      return;
    }

    final core = _coreCelsius ?? _temperatureCelsius;
    _data.add({
      CombustionConstants.channelTemperature: core,
      'timestamp': DateTime.now().toIso8601String(),
      CombustionConstants.channelCore: core,
      CombustionConstants.channelT1: t1 ?? _temperatureCelsius,
    });
  }

  @override
  Future<void> onConnect() async {
    _connectionState.add(ConnectionState.connected);
    _emissionTimer?.cancel();
    _emissionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _emitSnapshot();
    });
  }

  @override
  Future<void> disconnect() async {
    _stalled = true;
    _emissionTimer?.cancel();
    _emissionTimer = null;
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  Future<Map<String, dynamic>> execute(
    String commandId,
    Map<String, dynamic>? parameters,
  ) {
    throw UnimplementedError('Combustion UART commands are not implemented');
  }
}
