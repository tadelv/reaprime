import 'dart:io';
import 'package:collection/collection.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:reaprime/src/controllers/battery_controller.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/services/ble_discovery_service.dart';
import 'package:reaprime/src/services/simulated_device_service.dart';
import 'package:reaprime/src/services/storage/file_storage_service.dart';
import 'package:reaprime/src/services/webserver_service.dart';

import 'src/app.dart';
import 'src/services/foreground_service.dart';
import 'src/settings/settings_controller.dart';
import 'src/settings/settings_service.dart';

import 'src/models/device/impl/de1/de1.dart';
import 'src/services/serial/serial_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top], // Only keep the top bar
  );
  Logger.root.level = Level.FINE;
  Logger.root.clearListeners();
  PrintAppender(formatter: ColorFormatter()).attachToLogger(Logger.root);

  final log = Logger("Main");

  if (Platform.isAndroid) {
    try {
      var dir = Directory('/storage/emulated/0/Download/REA1');
      dir.createSync();
      RotatingFileAppender(
        formatter: const DefaultLogRecordFormatter(),
        baseFilePath: '${dir.path}/log.txt',
      ).attachToLogger(Logger.root);
    } catch (e) {
      log.severe('failed to create log file', e);
    }
  }

  RotatingFileAppender(
    baseFilePath: '${(await getApplicationDocumentsDirectory()).path}/log.txt',
  ).attachToLogger(Logger.root);

  final List<DeviceDiscoveryService> services = [
    BleDiscoveryService({
      De1.advertisingUUID: (id) => De1.fromId(id),
      FelicitaArc.serviceUUID.toUpperCase(): (id) => FelicitaArc(deviceId: id),
      DecentScale.serviceUUID.toUpperCase(): (id) => DecentScale(deviceId: id),
      BookooScale.serviceUUID.toUpperCase(): (id) => BookooScale(deviceId: id),
    }),
  ];

  services.add(createSerialService());

  if (const String.fromEnvironment("simulate") == "1") {
    services.add(SimulatedDeviceService());
    log.shout("adding Simulated Service");
  }
  // TODO: replace with documents once import is implemented
  var storagePath = await getDownloadsDirectory();
  final persistenceController = PersistenceController(
    storageService: FileStorageService(path: storagePath!),
  );

  final settingsController = SettingsController(SettingsService());
  final deviceController = DeviceController(services);
  final de1Controller = De1Controller(controller: deviceController);
  final scaleController = ScaleController(controller: deviceController);
  try {
    await startWebServer(deviceController, de1Controller, scaleController);
  } catch (e, st) {
    log.severe('failed to start web server', e, st);
  }

  if (Platform.isMacOS == false) {
    final batteryController = BatteryController(de1Controller);
  }
  // Load the user's preferred theme while the splash screen is displayed.
  // This prevents a sudden theme change when the app is first displayed.
  await settingsController.loadSettings();

  Logger.root.level = Level.LEVELS
          .firstWhereOrNull((e) => e.name == settingsController.logLevel) ??
      Level.INFO;

  final WorkflowController workflowController = WorkflowController();
  try {
    Workflow? workflow = await persistenceController.loadWorkflow();
    if (workflow != null) {
      workflowController.setWorkflow(workflow);
    }
  } catch (e) {
    log.warning("loading default workflow failed", e);
  }
  workflowController.addListener(() {
    persistenceController.saveWorkflow(workflowController.currentWorkflow);
  });

  // Run the app and pass in the SettingsController. The app listens to the
  // SettingsController for changes, then passes it further down to the
  // SettingsView.
  if (Platform.isAndroid) {
    ForegroundTaskService.init();
  }

  runApp(
    WithForegroundTask(
      child: MyApp(
        settingsController: settingsController,
        deviceController: deviceController,
        de1Controller: de1Controller,
        scaleController: scaleController,
        workflowController: workflowController,
        persistenceController: persistenceController,
      ),
    ),
  );
}
