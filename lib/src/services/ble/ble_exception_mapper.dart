import 'package:reaprime/src/models/device/transport/ble_connect_exception.dart';
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:universal_ble/universal_ble.dart';

/// Maps native BLE-library exceptions into domain exceptions at the
/// `services/ble/` transport boundary. Keeping the `is UniversalBleException`
/// check here is what lets every layer above `services/ble/` depend only on
/// [BleConnectException] / [BleTimeoutException].

/// Map a universal_ble connect-time exception to a domain exception.
///
/// A connection timeout becomes a [BleTimeoutException]; everything else
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
