import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
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

  void dispose() {
    _connectionState.close();
  }
}

void main() {
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
}
