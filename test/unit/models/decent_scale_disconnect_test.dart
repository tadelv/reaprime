import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/rxdart.dart';

/// Regression coverage for four Crashlytics FATAL paths that all traced
/// back to one missing `await` in `DecentScale.disconnect()`:
///
/// - iOS   `d84d8f29…` — blamed `BluePlusTransport.write`
/// - Android `5792e252…` — blamed `AndroidBluePlusTransport.write`
/// - iOS   `21b6c4a7…` — blamed `FirebaseCrashlyticsTelemetryService`
///   at the `PlatformDispatcher.onError` handler
/// - Android `4d12d3a3…` — same as above on Android
///
/// The last two are just the `PlatformDispatcher.onError` fallback
/// catching the exception that orphaned out of `disconnect()`'s
/// try/catch because `_sendPowerOff()` wasn't awaited.
///
/// The fix is a single `await` in front of `_sendPowerOff()`. This test
/// drives `disconnect()` against a transport whose `write()` throws
/// the exact `device is disconnected` exception seen in production and
/// asserts that the exception is caught inside `disconnect()` rather
/// than leaking to the surrounding Zone.

class _DisconnectedBleTransport extends BLETransport {
  final _connectionState = BehaviorSubject<ConnectionState>.seeded(
    ConnectionState.disconnected,
  );

  @override
  String get id => 'decent-scale-test';

  @override
  String get name => 'Test Decent Scale';

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Future<ConnectionState> getConnectionState() async =>
      _connectionState.value;

  @override
  Future<void> connect() async {
    _connectionState.add(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  Future<List<String>> discoverServices() async => [];

  @override
  Future<Uint8List> read(
    String serviceUUID,
    String characteristicUUID, {
    Duration? timeout,
  }) async =>
      Uint8List(0);

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {}

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  /// Mirrors the production failure mode: `flutter_blue_plus` throws
  /// `PlatformException(writeCharacteristic, device is disconnected)`
  /// on any write after the peer has dropped.
  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    throw Exception(
      'PlatformException(writeCharacteristic, device is disconnected)',
    );
  }

  @override
  Future<void> dispose() async {
    _connectionState.close();
  }
}

/// Variant of the throwing transport whose `write()` hangs forever.
/// Models a flaky BLE link where the platform channel never resolves
/// the write — the reason `disconnect()` now caps the wait with a 2 s
/// timeout instead of relying on the underlying 10 s write timeout.
class _HangingBleTransport extends _DisconnectedBleTransport {
  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) {
    return Completer<void>().future; // never completes
  }
}

class _RecordingBleTransport extends BLETransport {
  _RecordingBleTransport({
    ConnectionState initialState = ConnectionState.disconnected,
  }) : _connectionState = BehaviorSubject.seeded(initialState);

  final BehaviorSubject<ConnectionState> _connectionState;
  int connectCalls = 0;
  int subscribeCalls = 0;
  bool failWrites = false;

  @override
  String get id => 'recording-decent-scale';

  @override
  String get name => 'Recording Decent Scale';

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Future<ConnectionState> getConnectionState() async =>
      _connectionState.value;

  @override
  Future<void> connect() async {
    connectCalls++;
    _connectionState.add(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  Future<List<String>> discoverServices() async => [
    DecentScale.serviceIdentifier.long,
  ];

  @override
  Future<Uint8List> read(
    String serviceUUID,
    String characteristicUUID, {
    Duration? timeout,
  }) async =>
      Uint8List(0);

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    subscribeCalls++;
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    if (failWrites) {
      _connectionState.add(ConnectionState.disconnected);
      throw const DeviceNotConnectedException.scale();
    }
  }

  @override
  Future<void> dispose() async {
    await _connectionState.close();
  }
}

void main() {
  test('disconnected initialization write never publishes connected', () async {
    final transport = _RecordingBleTransport()..failWrites = true;
    final scale = DecentScale(transport: transport);
    final states = <ConnectionState>[];
    final subscription = scale.connectionState.listen(states.add);

    await expectLater(
      scale.onConnect(),
      throwsA(isA<DeviceNotConnectedException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(states, isNot(contains(ConnectionState.connected)));
    expect(await scale.connectionState.first, ConnectionState.disconnected);

    await subscription.cancel();
    await transport.dispose();
  });

  test('fresh wrapper initializes an already-connected transport', () async {
    final transport = _RecordingBleTransport(
      initialState: ConnectionState.connected,
    );
    final scale = DecentScale(transport: transport);

    await scale.onConnect();

    expect(transport.connectCalls, 0);
    expect(transport.subscribeCalls, 1);
    expect(await scale.connectionState.first, ConnectionState.connected);

    await scale.disconnectForHandoff();
    await transport.dispose();
  });

  test(
    'disconnect() does not leak an uncaught async error when the '
    'power-off write throws because the device is already disconnected',
    () async {
      final uncaughtErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final transport = _DisconnectedBleTransport();
          final scale = DecentScale(transport: transport);

          // Directly call disconnect — mirrors the production path where
          // an `onConnect` subscription fires on a `disconnected`
          // transport-state event and invokes `disconnect()` while the
          // BLE link is already down.
          await scale.disconnect();

          // Let any queued microtasks run so an unawaited Future that
          // threw would have a chance to escape before we assert.
          await Future<void>.delayed(const Duration(milliseconds: 50));

          transport.dispose();
        },
        (error, stack) {
          uncaughtErrors.add(error);
        },
      );

      expect(
        uncaughtErrors,
        isEmpty,
        reason:
            'Before the fix, `_sendPowerOff()` was called without `await` '
            'inside `disconnect()`. Its write-to-disconnected exception '
            'escaped the surrounding try/catch and landed in '
            'PlatformDispatcher.onError → Crashlytics fatal.',
      );
    },
  );

  test(
    'disconnect() returns within the power-off timeout window when the '
    'BLE write hangs forever',
    () async {
      final transport = _HangingBleTransport();
      final scale = DecentScale(transport: transport);

      final stopwatch = Stopwatch()..start();
      await scale.disconnect();
      stopwatch.stop();

      // Power-off cap is 2s — give a generous ceiling to avoid flake
      // on CI but still catch a regression that drops the timeout.
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 4)),
        reason:
            'A hung BLE write must not stall the disconnect sequence — '
            'common on flaky links after wake-from-sleep.',
      );

      transport.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
