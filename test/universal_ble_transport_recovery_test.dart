import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/services/ble/universal_ble_transport.dart';
import 'package:universal_ble/universal_ble.dart';

const _serviceUuid = '0000a000-0000-1000-8000-00805f9b34fb';
const _charUuid = '0000a00e-0000-1000-8000-00805f9b34fb';
const _writeTimeout = Duration(milliseconds: 50);

/// Fake [UniversalBlePlatform] driving [UniversalBleTransport] recovery
/// tests. `hangWrites` makes writeValue never complete (so the facade's
/// command queue times out, the same path a dead link produces);
/// `connectionStateResult` is what the OS-level probe reports.
class _FakeBlePlatform extends UniversalBlePlatform {
  BleConnectionState connectionStateResult = BleConnectionState.connected;
  bool hangWrites = false;
  int getConnectionStateCalls = 0;
  final List<String> disconnectCalls = [];

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
    disconnectCalls.add(deviceId);
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
  ) async {
    if (hangWrites) {
      await Completer<void>().future;
    }
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => 23;

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
  Future<BleConnectionState> getConnectionState(String deviceId) async {
    getConnectionStateCalls++;
    return connectionStateResult;
  }

  @override
  Future<List<BleDevice>> getSystemDevices(
    List<String>? withServices,
  ) async =>
      [];
}

void main() {
  late _FakeBlePlatform platform;
  late UniversalBleTransport transport;
  late List<device.ConnectionState> observedStates;
  late StreamSubscription<device.ConnectionState> stateSub;
  var deviceCounter = 0;
  late String deviceId;

  BleDevice bleDevice(String id, {String name = 'DE1'}) =>
      BleDevice(deviceId: id, name: name);

  Future<void> pump([int ms = 50]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() async {
    platform = _FakeBlePlatform();
    UniversalBle.setInstance(platform);
    // Drop any queues left over from a previous test (a hung write keeps
    // its per-device queue slot busy forever otherwise).
    UniversalBle.clearQueue();
    // Unique id per test so per-device queue state can't bleed over.
    deviceId = 'AA:BB:CC:DD:EE:${(deviceCounter++).toString().padLeft(2, '0')}';
    transport = UniversalBleTransport(device: bleDevice(deviceId));
    observedStates = [];
    stateSub = transport.connectionState.listen(observedStates.add);
    await transport.connect();
    await pump(10);
    expect(observedStates, contains(device.ConnectionState.connected));
  });

  tearDown(() async {
    await stateSub.cancel();
    await transport.dispose();
  });

  Future<void> timedOutWrite() async {
    await expectLater(
      transport.write(
        _serviceUuid,
        _charUuid,
        Uint8List.fromList([1]),
        timeout: _writeTimeout,
      ),
      throwsA(isA<TimeoutException>()),
    );
  }

  group('GATT timeout link verification (fix 1)', () {
    test(
        'write timeout with OS reporting disconnected → emits disconnected',
        () async {
      platform.hangWrites = true;
      platform.connectionStateResult = BleConnectionState.disconnected;

      await timedOutWrite();
      await pump();

      expect(observedStates, contains(device.ConnectionState.disconnected));
    });

    test('write timeout with OS reporting connected → stays connected',
        () async {
      platform.hangWrites = true;
      platform.connectionStateResult = BleConnectionState.connected;

      await timedOutWrite();
      await pump();

      expect(
        observedStates,
        isNot(contains(device.ConnectionState.disconnected)),
        reason: 'a single timeout on a live link must stay fail-fast only '
            '(profile-upload safety)',
      );
      expect(platform.getConnectionStateCalls, greaterThan(0),
          reason: 'the timeout should have probed the OS link state');
    });

    test(
        'three consecutive timeouts with OS claiming connected → forced '
        'teardown', () async {
      platform.hangWrites = true;
      platform.connectionStateResult = BleConnectionState.connected;

      await timedOutWrite();
      await timedOutWrite();
      expect(observedStates,
          isNot(contains(device.ConnectionState.disconnected)));

      await timedOutWrite();
      await pump();

      expect(observedStates, contains(device.ConnectionState.disconnected));
      expect(platform.disconnectCalls, contains(deviceId),
          reason: 'forced teardown must release the OS-level handle');
    });

    test('successful write resets the consecutive-timeout counter', () async {
      platform.connectionStateResult = BleConnectionState.connected;

      platform.hangWrites = true;
      await timedOutWrite();
      await timedOutWrite();

      platform.hangWrites = false;
      await transport.write(
        _serviceUuid,
        _charUuid,
        Uint8List.fromList([1]),
        timeout: _writeTimeout,
      );

      platform.hangWrites = true;
      await timedOutWrite();
      await timedOutWrite();
      await pump();

      expect(
        observedStates,
        isNot(contains(device.ConnectionState.disconnected)),
        reason: 'counter must reset on success — only 2 consecutive '
            'timeouts since',
      );
    });
  });

  group('advertising-while-connected detection (fix 2)', () {
    test('own advert + OS reporting disconnected → emits disconnected',
        () async {
      platform.connectionStateResult = BleConnectionState.disconnected;

      platform.updateScanResult(bleDevice(deviceId));
      await pump();

      expect(observedStates, contains(device.ConnectionState.disconnected));
    });

    test('own advert + OS reporting connected → no teardown', () async {
      platform.connectionStateResult = BleConnectionState.connected;

      platform.updateScanResult(bleDevice(deviceId));
      await pump();

      expect(observedStates,
          isNot(contains(device.ConnectionState.disconnected)));
      expect(platform.getConnectionStateCalls, greaterThan(0),
          reason: 'the advert should have triggered an OS probe');
    });

    test('advert for a different device is ignored', () async {
      platform.connectionStateResult = BleConnectionState.disconnected;

      platform.updateScanResult(bleDevice('11:22:33:44:55:66'));
      await pump();

      expect(observedStates,
          isNot(contains(device.ConnectionState.disconnected)));
      expect(platform.getConnectionStateCalls, 0);
    });

    test('advert while transport already disconnected is ignored', () async {
      // Deliver a real disconnect event first.
      platform.updateConnection(deviceId, false);
      await pump(10);
      expect(observedStates, contains(device.ConnectionState.disconnected));
      final probesBefore = platform.getConnectionStateCalls;

      platform.updateScanResult(bleDevice(deviceId));
      await pump();

      expect(platform.getConnectionStateCalls, probesBefore,
          reason: 'no probe when we already know we are disconnected');
    });

    test('advert probes are throttled', () async {
      platform.connectionStateResult = BleConnectionState.connected;

      platform.updateScanResult(bleDevice(deviceId));
      platform.updateScanResult(bleDevice(deviceId));
      platform.updateScanResult(bleDevice(deviceId));
      await pump();

      expect(platform.getConnectionStateCalls, 1,
          reason: 'adverts arrive ~1/s during a scan; one probe per '
              'throttle window is enough');
    });
  });
}
