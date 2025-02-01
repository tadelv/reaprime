import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:reaprime/src/controllers/battery_controller.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/services/ble_discovery_service.dart';
import 'package:reaprime/src/services/simulated_device_service.dart';
import 'package:reaprime/src/services/webserver_service.dart';

import 'src/app.dart';
import 'src/services/foreground_service.dart';
import 'src/settings/settings_controller.dart';
import 'src/settings/settings_service.dart';

import 'src/models/device/impl/de1/de1.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.root.level = Level.FINE;
  Logger.root.clearListeners();
  PrintAppender(formatter: ColorFormatter()).attachToLogger(Logger.root);

  final log = Logger("Main");

  final List<DeviceDiscoveryService> services = [
    BleDiscoveryService({
      De1.advertisingUUID: (id) => De1.fromId(id),
      FelicitaArc.serviceUUID.toUpperCase(): (id) => FelicitaArc(deviceId: id),
      DecentScale.serviceUUID.toUpperCase(): (id) => DecentScale(deviceId: id),
    }),
  ];

  if (const String.fromEnvironment("simulate") == "1") {
    services.add(SimulatedDeviceService());
    log.shout("adding Simulated Service");
  }

  final settingsController = SettingsController(SettingsService());
  final deviceController = DeviceController(services);
  final de1Controller = De1Controller(controller: deviceController);
  final scaleController = ScaleController(controller: deviceController);
  try {
    await startWebServer(deviceController, de1Controller, scaleController);
  } catch (e, st) {
    log.severe('failed to start web server', e, st);
  }
  final batteryController = BatteryController(de1Controller);
  // Load the user's preferred theme while the splash screen is displayed.
  // This prevents a sudden theme change when the app is first displayed.
  await settingsController.loadSettings();

  // Run the app and pass in the SettingsController. The app listens to the
  // SettingsController for changes, then passes it further down to the
  // SettingsView.
  ForegroundTaskService.init();
  runApp(
    WithForegroundTask(
      child: MyApp(
        settingsController: settingsController,
        deviceController: deviceController,
        de1Controller: de1Controller,
        scaleController: scaleController,
      ),
    ),
  );
}
