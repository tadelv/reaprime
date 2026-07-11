import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/ble/universal_ble_transport.dart';
import 'package:universal_ble/universal_ble.dart';

/// Locks the post-connect large-ATT-MTU request in
/// `UniversalBleTransport.connect()`:
///
///  * MTU **517** is requested on every non-Linux platform (it used to be
///    Android-only; the 28-byte Bengle 0xA013 shot-sample notification
///    truncates at the 23-byte ATT default, so the request must be attempted
///    everywhere BLE runs);
///  * **Linux is skipped** — BlueZ manages the MTU itself and universal_ble
///    does not expose `requestMtu` there;
///  * a **failed negotiation is non-fatal** — the DE1/Bengle BLE module
///    self-negotiates up to 247 on connect regardless, so `connect()` must
///    log-and-continue, never throw.
///
/// The platform gate itself (`Platform.isLinux`) is not fakeable in a unit
/// test, so the transport exposes an `isLinuxOverride` test seam.
class _MtuRecordingBlePlatform extends UniversalBlePlatform {
  /// Recorded (deviceId, expectedMtu) pairs from [requestMtu].
  final List<(String, int)> mtuRequests = [];

  /// When true, [requestMtu] throws — simulating a stack that rejects the
  /// negotiation.
  bool throwOnRequestMtu = false;

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    mtuRequests.add((deviceId, expectedMtu));
    if (throwOnRequestMtu) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.failed,
        message: 'simulated MTU negotiation failure',
      );
    }
    return expectedMtu;
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  Future<bool> enableBluetooth() async => true;

  @override
  Future<bool> disableBluetooth() async => false;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
  }) async {
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    updateConnection(deviceId, false);
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async =>
      [];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async =>
      Uint8List(0);

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {}

  @override
  Future<int> readRssi(String deviceId) async => -50;

  @override
  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  ) async {}

  @override
  Future<bool> isPaired(String deviceId) async => false;

  @override
  Future<bool> pair(String deviceId) async => true;

  @override
  Future<void> unpair(String deviceId) async {}

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      BleConnectionState.connected;

  @override
  Future<List<BleDevice>> getSystemDevices(
    List<String>? withServices,
  ) async =>
      [];
}

void main() {
  late _MtuRecordingBlePlatform platform;
  var deviceCounter = 0;
  late String deviceId;

  setUp(() {
    platform = _MtuRecordingBlePlatform();
    UniversalBle.setInstance(platform);
    UniversalBle.clearQueue();
    // Unique id per test so per-device queue state can't bleed over.
    deviceId = 'AA:BB:CC:DD:FF:${(deviceCounter++).toString().padLeft(2, '0')}';
  });

  test('connect() requests MTU 517 on non-Linux platforms', () async {
    final transport = UniversalBleTransport(
      device: BleDevice(deviceId: deviceId, name: 'Bengle'),
      isLinuxOverride: false,
    );

    await transport.connect();

    expect(
      platform.mtuRequests,
      [(deviceId, 517)],
      reason: 'exactly one MTU request, value 517 — required for the '
          '28-byte 0xA013 notification (ATT default is 23)',
    );
    await transport.dispose();
  });

  test('connect() skips the MTU request on Linux (BlueZ owns the MTU)',
      () async {
    final transport = UniversalBleTransport(
      device: BleDevice(deviceId: deviceId, name: 'Bengle'),
      isLinuxOverride: true,
    );

    await transport.connect();

    expect(platform.mtuRequests, isEmpty,
        reason: 'universal_ble exposes no requestMtu on Linux; BlueZ '
            'negotiates the MTU itself');
    await transport.dispose();
  });

  test('a failed MTU negotiation is non-fatal — connect() completes',
      () async {
    platform.throwOnRequestMtu = true;
    final transport = UniversalBleTransport(
      device: BleDevice(deviceId: deviceId, name: 'Bengle'),
      isLinuxOverride: false,
    );

    // Must not throw: the module self-negotiates up to 247 on connect, so
    // the client request is belt-and-suspenders and a rejection only costs
    // the larger MTU.
    await transport.connect();

    expect(platform.mtuRequests, hasLength(1),
        reason: 'the request must still be attempted');
    await transport.dispose();
  });
}
