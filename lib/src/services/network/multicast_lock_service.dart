import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Holds an Android `MulticastLock` for the app's lifetime so the Wi-Fi
/// firmware stops dropping inbound broadcast/multicast traffic.
///
/// Android Wi-Fi power-save filters multicast/broadcast frames by default,
/// which silently drops inbound ARP requests once the radio idles. For a
/// gateway that exposes REST (8080) and WebSocket APIs on the LAN, that makes
/// the tablet unreachable: peers can't resolve its MAC, so connections never
/// get established. A held `MulticastLock` tells the firmware to keep
/// delivering those frames — it needs only the `CHANGE_WIFI_MULTICAST_STATE`
/// permission, no root.
///
/// The lock is process-level (held in a static field on the native side), so
/// it survives Activity recreation and is released by the OS when the process
/// dies.
///
/// No-op on non-Android platforms. Not unit-tested — it drives a platform
/// channel; verified on-device. The native handler lives in `MainActivity.kt`
/// on the `com.reaprime/network` channel.
class MulticastLockService {
  static const MethodChannel _channel = MethodChannel('com.reaprime/network');
  final Logger _log = Logger('MulticastLockService');

  /// Acquire the lock. Idempotent on the native side. Returns true if the lock
  /// is held afterwards (always false off Android).
  Future<bool> acquire() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? held = await _channel.invokeMethod('acquireMulticastLock');
      _log.info('MulticastLock acquire -> held=$held');
      return held ?? false;
    } on PlatformException catch (e, st) {
      _log.warning('Failed to acquire MulticastLock: ${e.message}', e, st);
      return false;
    }
  }

  /// Release the lock if held. Safe to call on any platform.
  Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseMulticastLock');
      _log.info('MulticastLock released');
    } on PlatformException catch (e) {
      _log.warning('Failed to release MulticastLock: ${e.message}');
    }
  }

  /// Whether the lock is currently held (always false off Android).
  Future<bool> isHeld() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? held = await _channel.invokeMethod('isMulticastLockHeld');
      return held ?? false;
    } on PlatformException catch (e) {
      _log.warning('Failed to query MulticastLock state: ${e.message}');
      return false;
    }
  }
}
