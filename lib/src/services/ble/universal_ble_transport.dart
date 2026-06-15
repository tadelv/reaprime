import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/ble/ble_exception_mapper.dart';
import 'package:rxdart/subjects.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBleTransport implements BLETransport {
  final BleDevice _device;

  late Logger _log;

  final BehaviorSubject<device.ConnectionState> _connectionStateSubject = BehaviorSubject.seeded(
    device.ConnectionState.discovered,
  );

  StreamSubscription? _connectionStateSubscription;

  UniversalBleTransport({required BleDevice device}) : _device = device {
    _log = Logger("BLETransport-${device.deviceId}");
  }

  @override
  Future<void> connect() async {
    _connectionStateSubscription = UniversalBle.connectionStream(
      _device.deviceId,
    ).listen((d) {
      _connectionStateSubject.add(
        d ? device.ConnectionState.connected : device.ConnectionState.disconnected,
      );
    });
    try {
      await UniversalBle.connect(
        _device.deviceId,
        timeout: Duration(seconds: 10),
      );
    } on UniversalBleException catch (e) {
      throw mapUniversalConnectError(e);
    }
  }

  @override
  Stream<device.ConnectionState> get connectionState =>
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
      _connectionStateSubject.add(device.ConnectionState.disconnected);
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
  Future<Uint8List> read(String serviceUUID, String characteristicUUID, {Duration? timeout}) async {
    return await UniversalBle.read(
      _device.deviceId,
      serviceUUID,
      characteristicUUID,
      timeout: timeout
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
    final key = "$serviceUUID--$characteristicUUID";
    // Cancel any prior listener for this characteristic before replacing it.
    // A re-subscribe without an intervening disconnect (no-op reconnect)
    // would otherwise stack listeners and deliver every notification twice.
    await _subscriptions.remove(key)?.cancel();
    final sub = UniversalBle.characteristicValueStream(
      _device.deviceId,
      characteristicUUID,
    ).listen(callback);
    _subscriptions[key] = sub;

    await UniversalBle.subscribeNotifications(
      _device.deviceId,
      serviceUUID,
      characteristicUUID,
    );
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    await UniversalBle.write(
      _device.deviceId,
      BleUuidParser.string(serviceUUID),
      BleUuidParser.string(characteristicUUID),
      data,
      withoutResponse: !withResponse,
      timeout: timeout
    );
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {
    // Android-only in universal_ble 2.x; throws `notSupported` elsewhere.
    if (!BleCapabilities.supportsConnectionPriorityApi) return;
    try {
      await UniversalBle.requestConnectionPriority(
        _device.deviceId,
        prioritized
            ? BleConnectionPriority.highPerformance
            : BleConnectionPriority.balanced,
      );
    } on UniversalBleException catch (e) {
      // Best-effort hint; never fail a connection over it.
      _log.fine("requestConnectionPriority not applied: ${e.code}");
    }
  }

  @override
  Future<void> dispose() async {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    if (!_connectionStateSubject.isClosed) {
      _connectionStateSubject.close();
    }
  }
}
