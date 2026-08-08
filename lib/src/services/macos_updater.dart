import 'dart:io';

import 'package:flutter/services.dart';
import 'package:reaprime/src/services/android_updater.dart' show UpdateChannel;

/// Thin MethodChannel wrapper for the native Sparkle updater on macOS.
///
/// No-op off macOS. All update logic lives in `MacOSUpdater.swift`; Dart never
/// downloads, validates, or replaces application code.
class MacOSUpdater {
  static const MethodChannel _channel = MethodChannel(
    'net.tadel.reaprime/macos_updater',
  );

  final bool _supported;
  bool _available = false;

  MacOSUpdater({bool? supported}) : _supported = supported ?? Platform.isMacOS;

  /// Whether the native Sparkle updater exists on this platform.
  bool get isSupported => _supported;

  /// Whether the native updater is configured and usable. Stays false after a
  /// failed [configure], so callers stop routing controls to Sparkle and fall
  /// back to the Dart-side schedule instead of silently no-op'ing.
  bool get isAvailable => _supported && _available;

  /// Starts the native updater and applies the persisted settings.
  /// Idempotent on the native side; safe to call on every launch. Marks the
  /// updater available only on success.
  Future<void> configure({
    required bool automaticChecks,
    required UpdateChannel channel,
  }) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('configure', {
      'automaticChecks': automaticChecks,
      'channel': channel.name,
    });
    _available = true;
  }

  /// Enables/disables Sparkle's automatic checks. Only meaningful after
  /// [configure]; ignored before the one-time migration happens natively.
  Future<void> setAutomaticChecks(bool enabled) async {
    if (!isAvailable) return;
    await _channel.invokeMethod<void>('setAutomaticChecks', {
      'enabled': enabled,
    });
  }

  /// Switches the Sparkle update channel. No-op when unchanged.
  Future<void> setChannel(UpdateChannel channel) async {
    if (!isAvailable) return;
    await _channel.invokeMethod<void>('setChannel', {'channel': channel.name});
  }

  /// Asks Sparkle to check for updates now and present its native UI.
  /// No-op until the native side has been configured.
  Future<void> checkForUpdates() async {
    if (!isAvailable) return;
    await _channel.invokeMethod<void>('checkForUpdates');
  }
}
