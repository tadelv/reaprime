import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBleTransport implements BLETransport {
  final BleDevice _device;

  late Logger _log;

  final BehaviorSubject<bool> _connectionStateSubject = BehaviorSubject.seeded(
    false,
  );

  StreamSubscription<bool>? _connectionStateSubscription;

  UniversalBleTransport({required BleDevice device}) : _device = device {
    _log = Logger("BLETransport-${device.deviceId}");
  }

  @override
  Future<void> connect() async {
    _connectionStateSubscription = UniversalBle.connectionStream(
      _device.deviceId,
    ).listen((d) {
      _connectionStateSubject.add(d);
    });
    await UniversalBle.connect(
      _device.deviceId,
      timeout: Duration(seconds: 10),
    );
  }

  @override
  Stream<bool> get connectionState =>
      _connectionStateSubject.asBroadcastStream();

  @override
  Future<void> disconnect() async {
    try {
      _log.fine("disconnect");
      for (var sub in _subscriptions.keys) {
        final split = sub.split('--');
        UniversalBle.unsubscribe(_device.deviceId, split[0], split[1]);
        _subscriptions[sub]?.cancel();
      }
      await UniversalBle.disconnect(
        _device.deviceId,
        timeout: Duration(seconds: 5),
      );
    } catch (e) {
      _log.warning("failed to disconnect", e);
      _connectionStateSubject.add(false);
    }
    _connectionStateSubscription?.cancel();
  }

  @override
  Future<List<String>> discoverServices() async {
    final services = await UniversalBle.discoverServices(
      _device.deviceId,
      timeout: Duration(seconds: 10),
    );
    _log.fine(
      "discovered services: ${services.map((e) => e.toString()).toList().join('\n')}",
    );
    return services.map((s) => s.uuid).toList();
  }

  @override
  String get id => _device.deviceId;

  @override
  String get name => _device.name ?? "Unknown";

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID) async {
    return await UniversalBle.read(
      _device.deviceId,
      serviceUUID,
      characteristicUUID,
    );
  }

  final Map<String, StreamSubscription<Uint8List>> _subscriptions = {};

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    _log.fine("subscribe to: $serviceUUID, $characteristicUUID");
    final sub = UniversalBle.characteristicValueStream(
      _device.deviceId,
      characteristicUUID,
    ).listen(callback);
    _subscriptions["$serviceUUID--$characteristicUUID"] = sub;

    await UniversalBle.subscribeNotifications(
      _device.deviceId,
      parsedService,
      parsedCharacteristic,
    );
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
  }) async {
    await UniversalBle.write(
      _device.deviceId,
      BleUuidParser.string(serviceUUID),
      BleUuidParser.string(characteristicUUID),
      data,
      withoutResponse: !withResponse,
    );
  }
}
