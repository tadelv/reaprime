import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart' as domain;
import 'package:reaprime/src/models/device/watch_filter.dart';
import 'package:reaprime/src/services/universal_ble_discovery_service.dart';
import 'package:universal_ble/universal_ble.dart';

/// Fake platform backend for universal_ble. The abstract base class
/// already carries the stream plumbing (`updateScanResult`,
/// `updateAvailability`); this fake records scan start/stop calls.
class _FakeBlePlatform extends UniversalBlePlatform {
  final List<({ScanFilter? filter, PlatformConfig? config})> startScanCalls =
      [];
  int stopScanCalls = 0;
  Object? failNextStartScanWith;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  Future<bool> enableBluetooth() async => true;

  @override
  Future<bool> disableBluetooth() async => true;

  /// When set, the next [startScan] call blocks until this completes
  /// (consumed after one use). Lets tests race other operations into
  /// the start window.
  Completer<void>? holdNextStartScan;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    if (failNextStartScanWith != null) {
      final e = failNextStartScanWith;
      failNextStartScanWith = null;
      throw e!;
    }
    final hold = holdNextStartScan;
    if (hold != null) {
      holdNextStartScan = null;
      await hold.future;
    }
    startScanCalls.add((filter: scanFilter, config: platformConfig));
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls++;
  }

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
  }) async {}

  @override
  Future<void> disconnect(String deviceId) async {}

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
  Future<int> requestMtu(String deviceId, int expectedMtu) async => 23;

  @override
  Future<int> readRssi(String deviceId) async => 0;

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
      BleConnectionState.disconnected;

  @override
  Future<List<BleDevice>> getSystemDevices(
    List<String>? withServices,
  ) async =>
      [];
}

const _watchFilter = DeviceWatchFilter(namePrefix: 'Decent Scale');

void main() {
  late _FakeBlePlatform platform;
  late UniversalBleDiscoveryService service;

  Future<void> pump([int n = 3]) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    platform = _FakeBlePlatform();
    UniversalBle.setInstance(platform);
    service = UniversalBleDiscoveryService(watchSupportGate: () => true);
    await service.initialize();
  });

  ({ScanFilter? filter, PlatformConfig? config}) lastStart() =>
      platform.startScanCalls.last;

  group('startDeviceWatch', () {
    test('starts a name-prefix-filtered balanced scan', () async {
      await service.startDeviceWatch(_watchFilter);

      expect(platform.startScanCalls, hasLength(1));
      expect(lastStart().filter?.withNamePrefix, ['Decent Scale']);
      expect(
        lastStart().config?.android?.scanMode,
        AndroidScanMode.balanced,
        reason: 'the watch must leave most of the radio duty cycle to GATT',
      );
    });

    test('null name prefix scans unfiltered, still balanced', () async {
      await service.startDeviceWatch(const DeviceWatchFilter());

      expect(platform.startScanCalls, hasLength(1));
      expect(lastStart().filter?.withNamePrefix, isEmpty);
      // The duty cycle protects the DE1 link; the fork's name filter is
      // plugin-side anyway, so mode does not depend on filtering.
      expect(lastStart().config?.android?.scanMode, AndroidScanMode.balanced);
    });

    test('watch discovery flows into the devices stream', () async {
      final emissions = <List<domain.Device>>[];
      final sub = service.devices.listen(emissions.add);
      await service.startDeviceWatch(_watchFilter);

      platform.updateScanResult(
        BleDevice(deviceId: 'AA:BB:CC:DD:EE:FF', name: 'Decent Scale'),
      );
      await pump();

      expect(
        emissions.expand((l) => l).map((d) => d.deviceId),
        contains('AA:BB:CC:DD:EE:FF'),
      );
      await sub.cancel();
    });
  });

  group('stopDeviceWatch', () {
    test('stops the platform scan', () async {
      await service.startDeviceWatch(_watchFilter);
      await service.stopDeviceWatch();
      expect(platform.stopScanCalls, 1);
    });

    test('is idempotent and safe without a watch', () async {
      await service.stopDeviceWatch();
      expect(platform.stopScanCalls, 0);
    });
  });

  group('burst arbitration', () {
    test('a burst scan pauses the watch and resumes it afterwards', () async {
      await service.startDeviceWatch(_watchFilter);
      expect(platform.startScanCalls, hasLength(1));

      final burst = service.scanForDevices();
      await pump();
      // Watch paused (one stopScan), burst started with lowLatency.
      expect(platform.stopScanCalls, 1,
          reason: 'the watch scan must be stopped before the burst starts');
      expect(platform.startScanCalls, hasLength(2));
      expect(
        lastStart().filter?.withNamePrefix,
        isEmpty,
        reason: 'bursts stay unfiltered (name-match happens in Dart)',
      );

      service.stopScan(); // end the burst early
      await burst;
      await pump();

      expect(platform.startScanCalls, hasLength(3),
          reason: 'the watch must resume after the burst');
      expect(lastStart().filter?.withNamePrefix, ['Decent Scale']);
      expect(lastStart().config?.android?.scanMode, AndroidScanMode.balanced);
    });

    test('startDeviceWatch during a burst defers until the burst ends',
        () async {
      final burst = service.scanForDevices();
      await pump();
      expect(platform.startScanCalls, hasLength(1)); // the burst itself

      await service.startDeviceWatch(_watchFilter);
      expect(platform.startScanCalls, hasLength(1),
          reason: 'watch start must not fight the in-flight burst');

      service.stopScan();
      await burst;
      await pump();

      expect(platform.startScanCalls, hasLength(2),
          reason: 'the requested watch starts once the burst is done');
      expect(lastStart().filter?.withNamePrefix, ['Decent Scale']);
    });

    test('external stopScan() with only the watch active is a no-op',
        () async {
      await service.startDeviceWatch(_watchFilter);
      service.stopScan();
      await pump();

      expect(platform.stopScanCalls, 0,
          reason: 'stopScan means "stop burst" — it must not kill the watch');
    });
  });

  group('start-window races', () {
    test('stopDeviceWatch during an in-flight start undoes the scan',
        () async {
      final hold = Completer<void>();
      platform.holdNextStartScan = hold;

      final start = service.startDeviceWatch(_watchFilter);
      await pump();
      await service.stopDeviceWatch();

      hold.complete();
      await start;
      await pump();

      expect(platform.startScanCalls, hasLength(1));
      expect(platform.stopScanCalls, 1,
          reason: 'the scan that started after the stop must be undone — '
              'otherwise it runs orphaned forever');
    });

    test(
        'a burst racing the watch start is serialized: the burst scan '
        'starts only after the watch start settles and owns the session',
        () async {
      final hold = Completer<void>();
      platform.holdNextStartScan = hold;

      final start = service.startDeviceWatch(_watchFilter);
      await pump();
      final burst = service.scanForDevices();
      await pump();

      expect(platform.startScanCalls, isEmpty,
          reason: 'the burst must wait for the in-flight watch start — '
              'issuing its startScan concurrently leaves session '
              'ownership undefined');

      hold.complete();
      await start;
      await pump();

      // Ownership order: the watch start settles first, then the burst's
      // startScan runs — the burst's unfiltered scan is the live native
      // session for the whole burst.
      final prefixes = platform.startScanCalls
          .map((c) => c.filter?.withNamePrefix ?? const <String>[])
          .toList();
      expect(prefixes.first, ['Decent Scale'],
          reason: 'the raced watch start settles before the burst starts');
      expect(prefixes[1], isEmpty,
          reason: 'the burst scan follows and owns the session');

      service.stopScan(); // end the burst
      await burst;
      await pump();

      expect(platform.startScanCalls, hasLength(3),
          reason: 'the watch must resume after the burst');
      expect(lastStart().filter?.withNamePrefix, ['Decent Scale'],
          reason: 'the burst finally-block must resume a real watch scan, '
              'not skip it because the raced start claimed to be active');
    });

    test(
        'stopDeviceWatch waits for an in-flight start before stopping',
        () async {
      final hold = Completer<void>();
      platform.holdNextStartScan = hold;

      final start = service.startDeviceWatch(_watchFilter);
      await pump();
      final stop = service.stopDeviceWatch();
      await pump();

      hold.complete();
      await start;
      await stop;
      await pump();

      expect(platform.startScanCalls, hasLength(1));
      expect(platform.stopScanCalls, greaterThanOrEqualTo(1),
          reason: 'the scan the raced start opened must be stopped');
    });
  });

  group('resilience', () {
    test('adapter powering off during the start window stands the watch '
        'down and power-on restarts it', () async {
      final hold = Completer<void>();
      platform.holdNextStartScan = hold;

      final start = service.startDeviceWatch(_watchFilter);
      await pump();
      platform.updateAvailability(AvailabilityState.poweredOff);
      await pump();

      hold.complete();
      await start;
      await pump();

      expect(platform.startScanCalls, hasLength(1),
          reason: 'the raced start alone — nothing may claim active while '
              'the adapter is off');

      platform.updateAvailability(AvailabilityState.poweredOn);
      await pump();

      expect(platform.startScanCalls, hasLength(2),
          reason: 'a still-requested watch must restart on power-on; a '
              'stale active claim from the raced start would block this');
      expect(lastStart().filter?.withNamePrefix, ['Decent Scale']);
    });

    test('a failed post-burst resume emits a watch failure', () async {
      await service.startDeviceWatch(_watchFilter);
      final failures = <void>[];
      final sub = service.deviceWatchFailures.listen(failures.add);

      final burst = service.scanForDevices();
      await pump();
      platform.failNextStartScanWith = Exception('resume denied');
      service.stopScan();
      await burst;
      await pump();

      expect(failures, hasLength(1),
          reason: 'a dead watch must be reported so ScaleWatch can fall '
              'back to the legacy loop instead of staying silently armed');

      // The request is cleared: adapter recovery must not resurrect it.
      platform.updateAvailability(AvailabilityState.poweredOff);
      await pump();
      platform.updateAvailability(AvailabilityState.poweredOn);
      await pump();
      expect(platform.startScanCalls, hasLength(2),
          reason: 'watch start + burst only — no resurrection after a '
              'reported failure');
      await sub.cancel();
    });

    test('a failed refresh restart emits a watch failure', () {
      fakeAsync((async) {
        final zoned = UniversalBleDiscoveryService(
          watchSupportGate: () => true,
        );
        zoned.initialize();
        async.flushMicrotasks();
        final failures = <void>[];
        zoned.deviceWatchFailures.listen(failures.add);
        zoned.startDeviceWatch(_watchFilter);
        async.flushMicrotasks();
        expect(platform.startScanCalls, hasLength(1));

        platform.failNextStartScanWith = Exception('refresh denied');
        async.elapse(const Duration(minutes: 26));
        async.flushMicrotasks();

        expect(failures, hasLength(1),
            reason: 'a refresh that cannot restart the scan leaves the '
                'watch dead — it must be reported, not swallowed');
      });
    });

    test('adapter off kills the watch; adapter on restarts it', () async {
      await service.startDeviceWatch(_watchFilter);
      expect(platform.startScanCalls, hasLength(1));

      platform.updateAvailability(AvailabilityState.poweredOff);
      await pump();
      platform.updateAvailability(AvailabilityState.poweredOn);
      await pump();

      expect(platform.startScanCalls, hasLength(2),
          reason: 'a still-requested watch must restart when the adapter '
              'comes back');
      expect(lastStart().filter?.withNamePrefix, ['Decent Scale']);
    });

    test('the periodic refresh restarts the scan before the Android '
        '30-minute opportunistic downgrade', () {
      fakeAsync((async) {
        // Fresh service inside the fake zone so its Timer is controllable.
        final zoned = UniversalBleDiscoveryService(
          watchSupportGate: () => true,
        );
        zoned.initialize();
        async.flushMicrotasks();
        zoned.startDeviceWatch(_watchFilter);
        async.flushMicrotasks();
        expect(platform.startScanCalls, hasLength(1));

        async.elapse(const Duration(minutes: 26));
        async.flushMicrotasks();

        expect(platform.stopScanCalls, greaterThanOrEqualTo(1),
            reason: 'refresh must stop the aging scan');
        expect(platform.startScanCalls.length, greaterThanOrEqualTo(2),
            reason: 'and start a fresh one');
        expect(lastStart().filter?.withNamePrefix, ['Decent Scale']);

        zoned.stopDeviceWatch();
        async.flushMicrotasks();
      });
    });
  });
}
