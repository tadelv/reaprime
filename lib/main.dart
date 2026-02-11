import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
// import 'package:flutter/scheduler.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

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
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/machine_parser.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/blue_plus_discovery_service.dart';
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
    // await WindowManager.instance.setSize(const Size(1200, 800));
    await WindowManager.instance.setAspectRatio(1.6);
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

  Logger.root.info("==== REA PRIME starting ====");

  Logger.root.info(
    "build: ${BuildInfo.commitShort}, branch: ${BuildInfo.branch}",
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    log.warning(e, st);
  }

  final List<DeviceDiscoveryService> services = [];
  if (!Platform.isWindows) {
    services.add(
      BluePlusDiscoveryService(
        mappings: {
          UnifiedDe1.advertisingUUID.toUpperCase():
              (t) => MachineParser.machineFrom(transport: t),
          FelicitaArc.serviceUUID.toUpperCase(): (t) async {
            return FelicitaArc(transport: t);
          },
          DecentScale.serviceUUID.toUpperCase(): (t) async {
            return DecentScale(transport: t);
          },
          BookooScale.serviceUUID.toUpperCase(): (t) async {
            return BookooScale(transport: t);
          },
        },
      ),
    );
  } else {
    services.add(
      UniversalBleDiscoveryService(
        mappings: {
          UnifiedDe1.advertisingUUID.toUpperCase():
              (t) => MachineParser.machineFrom(transport: t),
          FelicitaArc.serviceUUID.toUpperCase(): (t) async {
            return FelicitaArc(transport: t);
          },
          DecentScale.serviceUUID.toUpperCase(): (t) async {
            return DecentScale(transport: t);
          },
          BookooScale.serviceUUID.toUpperCase(): (t) async {
            return BookooScale(transport: t);
          },
        },
      ),
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

  // Initialize profile storage and controller
  final profileController = ProfileController(
    storage: HiveProfileStorageService(),
  );
  await profileController.initialize();

  final deviceController = DeviceController(services);
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
        settingsController.simulatedDevices;
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
  WidgetsBinding.instance.addObserver(AppLifecycleObserver(
    updateCheckService: updateCheckService,
    de1Controller: de1Controller,
  ));

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

  AppLifecycleObserver({
    this.updateCheckService,
    this.de1Controller,
  }) {
    _memTimer = Timer.periodic(Duration(minutes: 5), (t) {
      final rss = ProcessInfo.currentRss / (1024 * 1024);
      _log.info("[MEM] RSS=${rss.toStringAsFixed(1)}MB");
    });

    // Monitor machine state changes for sleep-to-idle transitions
    _machineStateSubscription = de1Controller?.de1.listen((machine) {
      _stateStreamSubscription?.cancel();
      
      if (machine == null) return;
      
      // Check if machine transitioned from sleep to idle
      _stateStreamSubscription = machine.currentSnapshot.listen((snapshot) {
        final currentState = snapshot.state.state.index;
        
        // Detect transition from sleep (0) to idle (2)
        if (_lastMachineState == 0 && currentState == 2 && updateCheckService?.hasAvailableUpdate == true) {
          _log.info('Machine transitioned from sleep to idle, showing update notification');
          _showUpdateNotification();
        }
        
        _lastMachineState = currentState;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // STOP charts, timers, streams
      _log.info("state: paused");
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

    // Show snackbar with action to open update dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Update available: ${updateInfo.version}'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            _showUpdateDialog(context, updateInfo);
          },
        ),
        duration: const Duration(days: 1), // Persistent snackbar
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      ),
    );
  }
}
















