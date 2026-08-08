import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

class TestSensor implements Sensor {
  @override
  final String deviceId;

  @override
  final String name;

  final ConnectionState state;
  int connectCallCount = 0;

  TestSensor({
    required this.deviceId,
    this.name = 'Test Sensor',
    this.state = ConnectionState.connected,
  });

  @override
  DeviceType get type => DeviceType.sensor;

  @override
  DeviceImplementation get implementation => DeviceImplementation.sensorBasket;

  @override
  TransportType get transportType => TransportType.unknown;

  @override
  Stream<ConnectionState> get connectionState => Stream.value(state);

  @override
  Stream<Map<String, dynamic>> get data => const Stream.empty();

  @override
  SensorInfo get info => SensorInfo(
    name: name,
    vendor: 'test',
    dataChannels: const [],
    commands: const [],
  );

  @override
  Future<Map<String, dynamic>> execute(
    String commandId,
    Map<String, dynamic>? parameters,
  ) async => const {};

  @override
  Future<void> onConnect() async {
    connectCallCount++;
  }

  @override
  Future<void> disconnect() async {}
}
