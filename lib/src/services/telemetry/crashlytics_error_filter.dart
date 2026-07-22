import 'package:reaprime/src/models/errors.dart';

/// Error codes from universal_ble that indicate the device is gone and the
/// error is already handled by [UniversalBleTransport._handleGattError].
/// When these escape to the framework error handler (e.g., from a
/// fire-and-forget timer callback or a cancelled queue item), they are
/// not crash signals — the transport already emitted `disconnected` and
/// the device impl's disconnect cascade handles cleanup.
const _goneDeviceBleErrorCodes = <String>{
  'characteristicNotFound',
  'deviceNotFound',
  'serviceNotFound',
  'connectionTerminated',
  'deviceDisconnected',
  'unknownError',
};

/// Returns `true` if [error] is a known-benign exception that should NOT be
/// recorded as a Crashlytics FATAL.
///
/// These are exceptions that are part of the codebase's normal error model —
/// they are caught and handled by upper layers, but can escape to the
/// framework's global error handler (`FlutterError.onError` or
/// `PlatformDispatcher.instance.onError`) from fire-and-forget contexts
/// (Timer.periodic callbacks, unawaited Futures). Recording them as FATAL
/// pollutes Crashlytics with false crash signals (see `fa51312d`,
/// `eeea9be0`).
///
/// This is the framework-level safety net — the last line of defence.
/// Individual device implementations should still catch these at their
/// write/heartbeat level for graceful recovery.
bool isBenignFrameworkError(Object error) {
  // DeviceNotConnectedException — thrown by _handleGattError when a BLE
  // write/read/subscribe hits a gone device. Upper layers catch it; when
  // it escapes a timer callback it hits the framework handler.
  if (error is DeviceNotConnectedException) return true;

  // UniversalBleException with a gone-device code — the raw exception
  // from universal_ble's native layer that _handleGattError converts to
  // DeviceNotConnectedException. When it escapes from a fire-and-forget
  // context or a clearQueue'd pending item, it reaches the framework
  // handler before our try/catch sees it. Match by toString() prefix to
  // avoid a layer dependency on the universal_ble package.
  final errorString = error.toString();
  if (errorString.startsWith('UniversalBleException:') ||
      errorString.contains('UniversalBleException:')) {
    for (final code in _goneDeviceBleErrorCodes) {
      if (errorString.contains('UniversalBleErrorCode.$code') ||
          errorString.contains('Code: $code')) {
        return true;
      }
    }
  }

  // Exception('Queue Cancelled') — thrown by universal_ble's Queue.dispose()
  // when clearQueue cancels pending items. Not a UniversalBleException, so
  // _handleGattError can't catch it.
  if (errorString.contains('Queue Cancelled')) return true;

  // PlatformException from bonsoir DNS-SD plugin — ServiceNotRunning means
  // the mDNS daemon isn't available on the platform (iOS/macOS transient
  // state). Not a code bug.
  if (errorString.startsWith('PlatformException(') &&
      (errorString.contains('Bonsoir') ||
       errorString.contains('ServiceNotRunning'))) {
    return true;
  }

  return false;
}