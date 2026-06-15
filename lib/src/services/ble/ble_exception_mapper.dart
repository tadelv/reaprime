import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlusException;
import 'package:reaprime/src/models/device/transport/ble_connect_exception.dart';
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:universal_ble/universal_ble.dart';

/// Maps native BLE-library exceptions into domain exceptions at the
/// `services/ble/` transport boundary. Keeping the `is FlutterBluePlusException`
/// / `is UniversalBleException` checks here is what lets every layer above
/// `services/ble/` depend only on [BleConnectException] / [BleTimeoutException].

/// Map a flutter_blue_plus connect-time exception to [BleConnectException].
BleConnectException mapFbpConnectError(FlutterBluePlusException e) {
  return BleConnectException(
    code: e.code?.toString(),
    description: e.description,
    function: e.function.isNotEmpty ? e.function : 'connect',
    cause: e,
  );
}

/// Map a universal_ble connect-time exception to a domain exception.
///
/// A connection timeout becomes a [BleTimeoutException] (parity with the fbp
/// transports, which throw it on timed-out operations); everything else
/// becomes a [BleConnectException].
Object mapUniversalConnectError(UniversalBleException e) {
  if (e.code == UniversalBleErrorCode.connectionTimeout) {
    return BleTimeoutException('connect', e);
  }
  return BleConnectException(
    code: e.code.name,
    description: e.message,
    function: 'connect',
    cause: e,
  );
}
