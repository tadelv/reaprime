import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:collection/collection.dart';
// import 'package:flutter/scheduler.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/controllers/battery_controller.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/profile_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_pyxis_scale.dart';
import 'package:reaprime/src/models/device/impl/atomheart/atomheart_scale.dart';
import 'package:reaprime/src/models/device/impl/blackcoffee/blackcoffee_scale.dart';
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_scale.dart';
import 'package:reaprime/src/models/device/impl/eureka/eureka_scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/hiroia/hiroia_scale.dart';
import 'package:reaprime/src/models/device/impl/machine_parser.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/impl/smartchef/smartchef_scale.dart';
import 'package:reaprime/src/models/device/impl/varia/varia_aku_scale.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/blue_plus_discovery_service.dart';
import 'package:reaprime/src/services/ble/linux_ble_discovery_service.dart';
import 'package:reaprime/src/services/storage/hive_store_service.dart';
import 'package:reaprime/src/services/storage/hive_profile_storage.dart';
import 'package:reaprime/src/services/universal_ble_discovery_service.dart';
import 'package:reaprime/src/services/simulated_device_service.dart';
import 'package:reaprime/src/services/storage/file_storage_service.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:reaprime/src/services/update_check_service.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/services/foreground_service.dart';
import 'src/settings/settings_controller.dart';
import 'src/settings/settings_service.dart';

import 'src/services/serial/serial_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';
import 'package:reaprime/src/services/telemetry/log_buffer.dart';
import 'package:reaprime/src/services/telemetry/anonymization.dart';
import 'package:reaprime/src/services/telemetry/error_report_throttle.dart';
import 'package:reaprime/src/services/webview_log_service.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Set system information as custom keys in telemetry service.
/// This provides critical context for diagnosing platform-specific issues.
Future<void> _setSystemInfoKeys(TelemetryService telemetryService) async {
  try {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final deviceInfo = await deviceInfoPlugin.deviceInfo;
    final deviceData = deviceInfo.data;

    // Set platform info
    await telemetryService.setCustomKey('os_name', Platform.operatingSystem);
    await telemetryService.setCustomKey('os_version', Platform.operatingSystemVersion);
    await telemetryService.setCustomKey('app_version', BuildInfo.commitShort);

    // Set device model (platform-adaptive field names)
    final deviceModel = deviceData['model'] ??
                       deviceData['computerName'] ??
                       'unknown';
    await telemetryService.setCustomKey('device_model', deviceModel);

    // Set device brand (platform-adaptive field names)
    final deviceBrand = deviceData['brand'] ??
                       deviceData['hostName'] ??
                       'unknown';
    await telemetryService.setCustomKey('device_brand', deviceBrand);
  } catch (e, st) {
    final log = Logger('Main');
    log.warning('Failed to set system info custom keys', e, st);
    // Non-blocking - continue app startup even if this fails
  }
}

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

  if (Platform.isWindows || Platform.isMacOS) {
    await WindowManager.instance.ensureInitialized();
    WindowManager.instance.setMinimumSize(const Size(1280, 800));
    await WindowManager.instance.setAspectRatio(1.6);
    await WindowManager.instance.setSize(const Size(1280, 800));
  }

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

  // Initialize WebView console log service (separate from app logs)
  final webViewLogDir = Platform.isAndroid
      ? '/storage/emulated/0/Download/REA1'
      : (await getApplicationDocumentsDirectory()).path;
  final webViewLogService = WebViewLogService(logDirectoryPath: webViewLogDir);
  await webViewLogService.initialize();

  Logger.root.info("==== REA PRIME starting ====");

  Logger.root.info(
    "build: ${BuildInfo.commitShort}, branch: ${BuildInfo.branch}",
  );

  // Initialize Firebase on supported platforms (not Linux/Windows, not debug, not simulate)
  final isDebugOrSimulate = kDebugMode || const String.fromEnvironment("simulate") == "1";
  if (!Platform.isLinux && !Platform.isWindows && !isDebugOrSimulate) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e, st) {
      log.warning('Firebase initialization failed', e, st);
    }
  }

  // Create log buffer, error report throttle, and telemetry service
  final logBuffer = LogBuffer();
  final errorReportThrottle = ErrorReportThrottle();
  final telemetryService = TelemetryService.create(logBuffer: logBuffer);

  // Initialize telemetry (disables collection by default, sets up error handlers)
  try {
    await telemetryService.initialize();
  } catch (e, st) {
    log.warning('Telemetry initialization failed', e, st);
  }

  // Set system information custom keys for error reports
  await _setSystemInfoKeys(telemetryService);

  // Hook Logger.root to capture WARNING+ in log buffer with PII scrubbing
  // and trigger non-fatal error reports with rate limiting
  Logger.root.onRecord.listen((record) {
    if (record.level >= Level.WARNING) {
      final scrubbed = Anonymization.scrubString(
        '${record.level.name}: ${record.loggerName}: ${record.message}'
      );
      logBuffer.append(scrubbed);

      // Trigger telemetry error report if rate limit allows
      if (errorReportThrottle.shouldReport(scrubbed)) {
        final error = record.error ?? scrubbed;
        telemetryService.recordError(error, record.stackTrace);
      }
    }
  });

  final List<DeviceDiscoveryService> services = [];

  // Device UUID mappings shared across BLE discovery services
  final bleDeviceMappings = {
    UnifiedDe1.advertisingUUID.toUpperCase():
        (t) => MachineParser.machineFrom(transport: t),
    FelicitaArc.serviceUUID.toUpperCase(): (t) async {
      return FelicitaArc(transport: t);
    },
    // FFF0 is shared by Decent Scale, Eureka Precisa, Solo Barista,
    // SmartChef, and Varia AKU. Disambiguate by BLE advertising name.
    DecentScale.serviceUUID.toUpperCase(): (t) async {
      final name = t.name.toLowerCase();
      if (name.contains('cfs-9002') ||
          name.contains('eureka') ||
          name.contains('precisa')) {
        return EurekaScale(transport: t);
      } else if (name.contains('solo barista') ||
          name.contains('lsj-001')) {
        // Solo Barista uses the same protocol as Eureka Precisa
        return EurekaScale(transport: t);
      } else if (name.contains('smartchef')) {
        return SmartChefScale(transport: t);
      } else if (name.contains('aku') || name.contains('varia')) {
        return VariaAkuScale(transport: t);
      }
      return DecentScale(transport: t);
    },
    BookooScale.serviceUUID.toUpperCase(): (t) async {
      return BookooScale(transport: t);
    },
    AcaiaScale.serviceUUID.toUpperCase(): (t) async {
      return AcaiaScale(transport: t);
    },
    AcaiaPyxisScale.serviceUUID.toUpperCase(): (t) async {
      return AcaiaPyxisScale(transport: t);
    },
    Skale2Scale.serviceUUID.toUpperCase(): (t) async {
      return Skale2Scale(transport: t);
    },
    HiroiaScale.serviceUUID.toUpperCase(): (t) async {
      return HiroiaScale(transport: t);
    },
    DifluidScale.serviceUUID.toUpperCase(): (t) async {
      return DifluidScale(transport: t);
    },
    BlackCoffeeScale.serviceUUID.toUpperCase(): (t) async {
      return BlackCoffeeScale(transport: t);
    },
    AtomheartScale.serviceUUID.toUpperCase(): (t) async {
      return AtomheartScale(transport: t);
    },
  };

  if (Platform.isLinux) {
    // Use Linux-specific BLE discovery service that handles BlueZ quirks:
    // - Stops scan before connecting (avoids le-connection-abort-by-local)
    // - Adapter state monitoring and recovery
    // - Connection retry logic with backoff
    // - Sequential device processing with settle delays
    services.add(
      LinuxBleDiscoveryService(mappings: bleDeviceMappings),
    );
  } else if (!Platform.isWindows) {
    services.add(
      BluePlusDiscoveryService(mappings: bleDeviceMappings),
    );
  } else {
    services.add(
      UniversalBleDiscoveryService(mappings: bleDeviceMappings),
    );
  }

  await Hive.initFlutter('store');

  services.add(createSerialService());

  final simulatedDevicesService = SimulatedDeviceService();
  services.add(simulatedDevicesService);
  if (const String.fromEnvironment("simulate") == "1") {
    simulatedDevicesService.simulationEnabled = true;
    log.info("enabling Simulated Service");
  }
  final storagePath = await getApplicationDocumentsDirectory();
  final persistenceController = PersistenceController(
    storageService: FileStorageService(path: storagePath),
  );
  persistenceController.loadShots();

  final WorkflowController workflowController = WorkflowController();
  try {
    Workflow? workflow = await persistenceController.loadWorkflow();
    if (workflow != null) {
      workflowController.setWorkflow(workflow);
    }
  } catch (e) {
    log.warning("loading default workflow failed", e);
  }

  final settingsController = SettingsController(SettingsService());
  settingsController.telemetryService = telemetryService;

  // Initialize profile storage and controller
  final profileController = ProfileController(
    storage: HiveProfileStorageService(),
  );
  await profileController.initialize();

  final deviceController = DeviceController(services);
  deviceController.telemetryService = telemetryService;
  final de1Controller = De1Controller(controller: deviceController)
    ..defaultWorkflow = workflowController.currentWorkflow;
  final scaleController = ScaleController(controller: deviceController);
  final sensorController = SensorController(controller: deviceController);

  workflowController.addListener(() {
    persistenceController.saveWorkflow(workflowController.currentWorkflow);
    de1Controller.defaultWorkflow = workflowController.currentWorkflow;
  });
  final PluginLoaderService pluginService = PluginLoaderService(
    kvStore: HiveStoreService(defaultNamespace: "plugins")..initialize(),
  );
  // Don't initialize plugins yet - wait for permissions to be granted
  // pluginService.initialize() will be called from PermissionsView after permissions are granted
  pluginService.pluginManager.de1Controller = de1Controller;

  final WebUIService webUIService = WebUIService();
  final WebUIStorage webUIStorage = WebUIStorage(settingsController);

  try {
    await startWebServer(
      deviceController,
      de1Controller,
      scaleController,
      settingsController,
      sensorController,
      workflowController,
      persistenceController,
      pluginService,
      webUIService,
      webUIStorage,
      profileController,
      logBuffer,
      webViewLogService,
    );
  } catch (e, st) {
    log.severe('failed to start web server', e, st);
  }

  if (Platform.isAndroid || Platform.isIOS) {
    final batteryController = BatteryController(de1Controller);
  }
  // Load the user's preferred theme while the splash screen is displayed.
  // This prevents a sudden theme change when the app is first displayed.
  settingsController.addListener(() {
    simulatedDevicesService.simulationEnabled =
        settingsController.simulatedDevices || (const String.fromEnvironment("simulate") == "1");
  });
  await settingsController.loadSettings();

  Logger.root.level =
      Level.LEVELS.firstWhereOrNull(
        (e) => e.name == settingsController.logLevel,
      ) ??
      Level.FINE;

  // Initialize update check service
  final updateCheckService = UpdateCheckService(
    settingsService: SettingsService(),
  );
  await updateCheckService.initialize();

  // Add lifecycle observer for all platforms (for update notifications)
  WidgetsBinding.instance.addObserver(
    AppLifecycleObserver(
      updateCheckService: updateCheckService,
      de1Controller: de1Controller,
    ),
  );

  if (Platform.isAndroid) {
    // Initialize and start foreground service as early as possible
    ForegroundTaskService.init();
    await ForegroundTaskService.start();
    // SchedulerBinding.instance.addTimingsCallback((timings) {
    //   // If this keeps firing while app is "backgrounded",
    //   // something is forcing frames.
    //   print("timings callback");
    // });
  }

  runApp(
    WithForegroundTask(
      child: AppRoot(
        settingsController: settingsController,
        deviceController: deviceController,
        de1Controller: de1Controller,
        scaleController: scaleController,
        workflowController: workflowController,
        persistenceController: persistenceController,
        pluginLoaderService: pluginService,
        webUIService: webUIService,
        webUIStorage: webUIStorage,
        updateCheckService: updateCheckService,
        webViewLogService: webViewLogService,
      ),
    ),
  );
}

class AppLifecycleObserver with WidgetsBindingObserver {
  final _log = Logger("App Lifecycle");
  final UpdateCheckService? updateCheckService;
  final De1Controller? de1Controller;

  late Timer _memTimer;
  bool _wasBackgrounded = false;
  StreamSubscription? _machineStateSubscription;
  StreamSubscription? _stateStreamSubscription;
  int? _lastMachineState;

  AppLifecycleObserver({this.updateCheckService, this.de1Controller}) {
    _memTimer = Timer.periodic(Duration(minutes: 5), (t) {
      final rss = ProcessInfo.currentRss / (1024 * 1024);
      _log.info("[MEM] RSS=${rss.toStringAsFixed(1)}MB");
    });

    // Show initial update notification once the widget tree is fully built
    if (updateCheckService?.hasAvailableUpdate == true) {
      Future.delayed(const Duration(seconds: 3), () {
        _showUpdateNotification();
      });
    }

    // Monitor machine state changes for sleep-to-idle transitions
    _machineStateSubscription = de1Controller?.de1.listen((machine) {
      _stateStreamSubscription?.cancel();

      if (machine == null) return;

      // Check if machine transitioned from sleep to idle
      _stateStreamSubscription = machine.currentSnapshot.listen((snapshot) {
        final currentState = snapshot.state.state.index;

        // Detect transition from sleep (0) to idle (2)
        if (_lastMachineState == 0 &&
            currentState == 2 &&
            updateCheckService?.hasAvailableUpdate == true) {
          _log.info(
            'Machine transitioned from sleep to idle, showing update notification',
          );
          _showUpdateNotification();
        }

        _lastMachineState = currentState;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // STOP charts, timers, streams
      _log.info("state: $state");
      _wasBackgrounded = true;
    }
    if (state == AppLifecycleState.resumed) {
      // Resume if needed
      _log.info("state: resumed");

      // Check for updates when app comes to foreground
      if (_wasBackgrounded && updateCheckService?.hasAvailableUpdate == true) {
        _showUpdateNotification();
      }
      _wasBackgrounded = false;
    }
  }

  void _showUpdateNotification() {
    final context = NavigationService.context;
    if (context == null || !context.mounted) return;

    final updateInfo = updateCheckService?.availableUpdate;
    if (updateInfo == null) return;

    final messenger = ScaffoldMessenger.of(context);

    // Clear any existing snackbars to prevent stacking
    messenger.clearSnackBars();

    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Update available: ${updateInfo.version}'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            _showUpdateDialog(context, updateInfo);
          },
        ),
        showCloseIcon: true,
        duration: const Duration(days: 1), // Persistent snackbar
        behavior: SnackBarBehavior.floating,
      ),
    );

    // When user taps the close icon, skip this version permanently
    controller.closed.then((reason) {
      if (reason == SnackBarClosedReason.dismiss) {
        updateCheckService?.skipCurrentUpdate();
      }
    });
  }

  void _showUpdateDialog(BuildContext context, dynamic updateInfo) async {
    if (Platform.isAndroid) {
      // On Android, navigate to settings where user can download and install
      Navigator.of(context).pushNamed('/settings');
    } else {
      // On other platforms, open the release page in browser
      final releaseUrl = updateCheckService?.getReleaseUrl();
      if (releaseUrl != null) {
        try {
          await launchUrl(Uri.parse(releaseUrl));
        } catch (e) {
          _log.warning('Failed to open release URL', e);
        }
      }
    }
  }

  void dispose() {
    _memTimer.cancel();
    _machineStateSubscription?.cancel();
    _stateStreamSubscription?.cancel();
  }
}

class AppRoot extends StatefulWidget {
  final SettingsController settingsController;
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;
  final PluginLoaderService pluginLoaderService;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;
  final UpdateCheckService? updateCheckService;
  final WebViewLogService webViewLogService;

  const AppRoot({
    super.key,
    required this.settingsController,
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
    required this.workflowController,
    required this.persistenceController,
    required this.pluginLoaderService,
    required this.webUIService,
    required this.webUIStorage,
    required this.webViewLogService,
    this.updateCheckService,
  });

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_AppRootState>()?.restart();
  }

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final Logger _log = Logger("AppRoot");
  Key _key = UniqueKey();

  Future<void> restart() async {
    _log.info("recreating App Root");
    // TODO: need better app base logic for recreate activity
    // await recreateActivity();
    setState(() {
      _key = UniqueKey();
    });
  }

  static const _channel = MethodChannel('app/lifecycle');

  Future<void> recreateActivity() async {
    try {
      await _channel.invokeMethod('recreateActivity');
    } catch (e) {
      // Log but never crash
      _log.severe('[ActivityControl] recreate failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: MyApp(
        settingsController: widget.settingsController,
        deviceController: widget.deviceController,
        de1Controller: widget.de1Controller,
        scaleController: widget.scaleController,
        workflowController: widget.workflowController,
        persistenceController: widget.persistenceController,
        pluginLoaderService: widget.pluginLoaderService,
        webUIService: widget.webUIService,
        webUIStorage: widget.webUIStorage,
        updateCheckService: widget.updateCheckService,
        webViewLogService: widget.webViewLogService,
      ),
    );
  }
}
