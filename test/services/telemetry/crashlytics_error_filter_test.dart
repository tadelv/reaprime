import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/services/telemetry/crashlytics_error_filter.dart';

void main() {
  group('isBenignFrameworkError', () {
    group('DeviceNotConnectedException', () {
      test('.machine is benign', () {
        expect(
          isBenignFrameworkError(const DeviceNotConnectedException.machine()),
          isTrue,
        );
      });

      test('.scale is benign', () {
        expect(
          isBenignFrameworkError(const DeviceNotConnectedException.scale()),
          isTrue,
        );
      });

      test('.unknown is benign', () {
        expect(
          isBenignFrameworkError(const DeviceNotConnectedException.unknown()),
          isTrue,
        );
      });

      test('with positional kind is benign', () {
        expect(
          isBenignFrameworkError(
            const DeviceNotConnectedException(DeviceKind.scale),
          ),
          isTrue,
        );
      });
    });

    group('UniversalBleException with gone-device codes', () {
      // We match by toString() prefix + error code string because we can't
      // import universal_ble in the telemetry layer (would create a layer
      // dependency). The crash events use both formats:
      //   "UniversalBleException: Code: UniversalBleErrorCode.deviceNotFound"
      //   "UniversalBleException: Code: deviceNotFound"

      test('deviceNotFound (Code: format) is benign', () {
        final e = _FakeUniversalBleException(
          'Code: UniversalBleErrorCode.deviceNotFound, Message: Unknown deviceId',
        );
        expect(isBenignFrameworkError(e), isTrue);
      });

      test('characteristicNotFound is benign', () {
        final e = _FakeUniversalBleException(
          'Code: UniversalBleErrorCode.characteristicNotFound',
        );
        expect(isBenignFrameworkError(e), isTrue);
      });

      test('serviceNotFound is benign', () {
        final e = _FakeUniversalBleException(
          'Code: UniversalBleErrorCode.serviceNotFound',
        );
        expect(isBenignFrameworkError(e), isTrue);
      });

      test('connectionTerminated is benign', () {
        final e = _FakeUniversalBleException(
          'Code: UniversalBleErrorCode.connectionTerminated',
        );
        expect(isBenignFrameworkError(e), isTrue);
      });

      test('deviceDisconnected is benign', () {
        final e = _FakeUniversalBleException(
          'Code: UniversalBleErrorCode.deviceDisconnected',
        );
        expect(isBenignFrameworkError(e), isTrue);
      });

      test('unknownError is benign', () {
        final e = _FakeUniversalBleException(
          'Code: UniversalBleErrorCode.unknownError',
        );
        expect(isBenignFrameworkError(e), isTrue);
      });

      test('short format "Code: deviceNotFound" is benign', () {
        final e = _FakeUniversalBleException(
          'Code: deviceNotFound, Message: Unknown deviceId',
        );
        expect(isBenignFrameworkError(e), isTrue);
      });
    });

    group('Queue Cancelled exception', () {
      test('Exception("Queue Cancelled") is benign', () {
        expect(isBenignFrameworkError(Exception('Queue Cancelled')), isTrue);
      });
    });

    group('non-benign errors (should crash)', () {
      test('StateError is NOT benign', () {
        expect(isBenignFrameworkError(StateError('bad state')), isFalse);
      });

      test('RangeError is NOT benign', () {
        expect(
          isBenignFrameworkError(RangeError('Invalid value: Not in range')),
          isFalse,
        );
      });

      test('LateInitializationError is NOT benign', () {
        final error = _LateInitError();
        expect(isBenignFrameworkError(error), isFalse);
      });

      test('plain Exception with other message is NOT benign', () {
        expect(isBenignFrameworkError(Exception('something else')), isFalse);
      });

      test('UniversalBleException with non-gone code is NOT benign', () {
        final e = _FakeUniversalBleException(
          'Code: UniversalBleErrorCode.gattError',
        );
        expect(isBenignFrameworkError(e), isFalse);
      });

      test('Null check operator error is NOT benign', () {
        expect(
          isBenignFrameworkError(_NullCheckError()),
          isFalse,
        );
      });
    });
  });
}

/// Stand-in for UniversalBleException whose toString() matches the real
/// package's format without importing it.
class _FakeUniversalBleException implements Exception {
  final String message;
  _FakeUniversalBleException(this.message);

  @override
  String toString() => 'UniversalBleException: $message';
}

class _NullCheckError implements Exception {
  @override
  String toString() => 'Null check operator used on a null value';
}

class _LateInitError implements Exception {
  @override
  String toString() =>
      'LateInitializationError: Field \'_field\' has not been initialized.';
}
