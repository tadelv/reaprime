import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Service for installing APK files on Android
class ApkInstaller {
  static const MethodChannel _channel = MethodChannel('com.reaprime.updater/apk_installer');
  final Logger _log = Logger('ApkInstaller');

  /// Install an APK file using the system package installer
  /// 
  /// This will open the Android package installer dialog for the user to confirm
  /// installation. On Android 8.0+, this requires REQUEST_INSTALL_PACKAGES permission.
  /// 
  /// [apkPath] - Absolute path to the APK file to install
  /// 
  /// Returns true if the installation was triggered successfully
  Future<bool> installApk(String apkPath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APK installation is only supported on Android');
    }

    try {
      _log.info('Installing APK from $apkPath');
      
      final bool? result = await _channel.invokeMethod('installApk', {
        'apkPath': apkPath,
      });

      return result ?? false;
    } on PlatformException catch (e, stackTrace) {
      _log.severe('Failed to install APK: ${e.message}', e, stackTrace);
      rethrow;
    }
  }

  /// Check if the app has permission to install packages
  /// 
  /// On Android 8.0+, apps need REQUEST_INSTALL_PACKAGES permission
  /// 
  /// Returns true if permission is granted
  Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final bool? result = await _channel.invokeMethod('canInstallPackages');
      return result ?? false;
    } on PlatformException catch (e) {
      _log.warning('Failed to check install permission: ${e.message}');
      return false;
    }
  }

  /// Request permission to install packages
  /// 
  /// This will open the system settings page where the user can grant permission
  Future<void> requestInstallPermission() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod('requestInstallPermission');
    } on PlatformException catch (e) {
      _log.warning('Failed to request install permission: ${e.message}');
    }
  }
}
