import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const simulatedWebViewDevicePreferenceKey = 'simulatedWebViewDevice';

class SimulatedWebViewDevice {
  const SimulatedWebViewDevice({
    required this.id,
    required this.name,
    required this.physicalSize,
    required this.webViewSurfaceSize,
    required this.densityDpi,
    required this.viewportSize,
    required this.screenSize,
    required this.platform,
    required this.maxTouchPoints,
  });

  final String id;
  final String name;
  final Size physicalSize;
  final Size webViewSurfaceSize;
  final double densityDpi;
  final Size viewportSize;
  final Size screenSize;
  final String platform;
  final int maxTouchPoints;

  double get devicePixelRatio => densityDpi / 160.0;

  double get aspectRatio => physicalSize.width / physicalSize.height;

  // Matches the measured Android WebView quirk for this tablet profile.
  double get outerWidth => screenSize.width + 1;

  static const teclastT50Mini = SimulatedWebViewDevice(
    id: 'teclast-t50-mini',
    name: 'Teclast M50/T50 Mini',
    physicalSize: Size(1340, 800),
    webViewSurfaceSize: Size(1341, 801),
    densityDpi: 213,
    viewportSize: Size(1007, 602),
    screenSize: Size(1007, 601),
    platform: 'Linux aarch64',
    maxTouchPoints: 5,
  );
}

final simulatedWebViewDevice = ValueNotifier<SimulatedWebViewDevice?>(null);

SimulatedWebViewDevice? simulatedWebViewDeviceById(String? id) {
  if (id == SimulatedWebViewDevice.teclastT50Mini.id) {
    return SimulatedWebViewDevice.teclastT50Mini;
  }
  return null;
}

Future<SimulatedWebViewDevice?> loadPersistedSimulatedWebViewDevice() async {
  final id = await SharedPreferencesAsync().getString(
    simulatedWebViewDevicePreferenceKey,
  );
  return simulatedWebViewDeviceById(id);
}

Future<void> persistSimulatedWebViewDevice(
  SimulatedWebViewDevice? device,
) async {
  final prefs = SharedPreferencesAsync();
  if (device == null) {
    await prefs.remove(simulatedWebViewDevicePreferenceKey);
    return;
  }
  await prefs.setString(simulatedWebViewDevicePreferenceKey, device.id);
}
