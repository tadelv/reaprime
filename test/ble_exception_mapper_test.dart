import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/transport/ble_connect_exception.dart';
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:reaprime/src/services/ble/ble_exception_mapper.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('mapFbpConnectError', () {
    test('carries code, description and function', () {
      final mapped = mapFbpConnectError(
        FlutterBluePlusException(
          ErrorPlatform.android,
          'connect',
          133,
          'GATT_ERROR',
        ),
      );

      expect(mapped, isA<BleConnectException>());
      expect(mapped.code, '133');
      expect(mapped.description, 'GATT_ERROR');
      expect(mapped.function, 'connect');
      expect(mapped.cause, isA<FlutterBluePlusException>());
    });

    test('null code/description survive; empty function falls back', () {
      final mapped = mapFbpConnectError(
        FlutterBluePlusException(ErrorPlatform.apple, '', null, null),
      );

      expect(mapped.code, isNull);
      expect(mapped.description, isNull);
      expect(mapped.function, 'connect');
    });
  });

  group('mapUniversalConnectError', () {
    test('connectionTimeout becomes BleTimeoutException', () {
      final mapped = mapUniversalConnectError(
        UniversalBleException(
          code: UniversalBleErrorCode.connectionTimeout,
          message: 'timed out',
        ),
      );

      expect(mapped, isA<BleTimeoutException>());
    });

    test('other codes become BleConnectException with code name', () {
      final mapped = mapUniversalConnectError(
        UniversalBleException(
          code: UniversalBleErrorCode.connectionFailed,
          message: 'nope',
        ),
      );

      expect(mapped, isA<BleConnectException>());
      final e = mapped as BleConnectException;
      expect(e.code, 'connectionFailed');
      expect(e.description, 'nope');
      expect(e.function, 'connect');
      expect(e.cause, isA<UniversalBleException>());
    });
  });
}
