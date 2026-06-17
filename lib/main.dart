import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
// import 'package:flutter/scheduler.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/controllers/battery_controller.dart';
import 'package:reaprime/src/controllers/bengle_probe_bridge.dart';
import 'package:reaprime/src/controllers/bengle_saw_bridge.dart';
import 'package:reaprime/src/controllers/bengle_steam_stop_bridge.dart';
import 'package:reaprime/src/controllers/steam_sequencer.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/remembered_device_sources.dart';
import 'package:reaprime/src/controllers/remembered_devices_controller.dart';
import 'package:reaprime/src/controllers/display_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/presence_controller.dart';
import 'package:reaprime/src/controllers/profile_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/controllers/workflow_device_sync.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/services/wifi/wifi_scale_discovery_service.dart';
import 'package:reaprime/src/services/database/database.dart' hide Workflow;
import 'package:reaprime/src/services/storage/drift_bean_storage.dart';
import 'package:reaprime/src/services/storage/drift_grinder_storage.dart';
import 'package:reaprime/src/services/storage/drift_profile_storage.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/drift_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:reaprime/src/services/account/decent_proxy_service.dart';
import 'package:reaprime/src/services/account/proxy_token_service.dart';
import 'package:reaprime/src/services/account/credential_store_factory.dart';
import 'package:http/http.dart' as http;
import 'package:reaprime/src/services/storage/hive_store_service.dart';
import 'package:reaprime/src/services/universal_ble_discovery_service.dart';
import 'package:reaprime/src/services/simulated_device_service.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:reaprime/src/services/update_check_service.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/cli/cli_args.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';

import 'src/app.dart';
import 'src/launcher/launcher_view.dart';
import 'src/services/foreground_service.dart';
import 'src/settings/settings_controller.dart';
import 'src/settings/settings_service.dart';
import 'src/services/serial/serial_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';
import 'package:reaprime/src/services/telemetry/boot_timing.dart';
import 'package:reaprime/src/services/telemetry/log_buffer.dart';
import 'package:reaprime/src/services/telemetry/anonymization.dart';
import 'package:reaprime/src/services/telemetry/error_report_throttle.dart';
import 'package:reaprime/src/services/telemetry/telemetry_forwarder_filter.dart';
import 'package:reaprime/src/services/webview_log_service.dart';
import 'package:reaprime/src/skin_feature/simulated_webview_device.dart';
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
    await telemetryService.setCustomKey(
      'os_version',
      Platform.operatingSystemVersion,
    );
    await telemetryService.setCustomKey('app_version', BuildInfo.commitShort);

    // Set device model (platform-adaptive field names)
    final deviceModel =
        deviceData['model'] ?? deviceData['computerName'] ?? 'unknown';
    await telemetryService.setCustomKey('device_model', deviceModel);

    // Set device brand (platform-adaptive field names)
    final deviceBrand =
        deviceData['brand'] ?? deviceData['hostName'] ?? 'unknown';
    await telemetryService.setCustomKey('device_brand', deviceBrand);
  } catch (e, st) {
    final log = Logger('Main');
    log.warning('Failed to set system info custom keys', e, st);
    // Non-blocking - continue app startup even if this fails
  }
}

/// Parses the `--dart-define=simulate=` flag value.
/// Accepts "1" for all device types, or a comma-delimited list
/// like "machine,scale" for selective simulation.
Set<SimulatedDevicesTypes> _parseSimulateFlag(String value) {
  if (value == '1') {
    return SimulatedDevicesTypes.values.toSet();
  }
  return value
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => SimulatedDevicesTypesFromString.fromString(e))
      .whereType<SimulatedDevicesTypes>()
      .toSet();
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final cliArgs = parseCliArgs(args);
  // Force the semantics tree to always be active so assistive technologies
  // (TalkBack, VoiceOver, Accessibility Inspector) can read Flutter elements.
  SemanticsBinding.instance.ensureSemantics();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top], // Only keep the top bar
  );
  Logger.root.level = Level.FINE;
  Logger.root.clearListeners();
  PrintAppender(formatter: ColorFormatter()).attachToLogger(Logger.root);

  final log = Logger("Main");

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await WindowManager.instance.ensureInitialized();
    // Windows/macOS lock to the default kiosk window size at startup. Linux is
    // left free-form (its default windowing is unchanged); WindowManager is
    // still initialized so a simulated WebView can resize the window on demand.
    if (!Platform.isLinux) {
      WindowManager.instance.setMinimumSize(defaultDesktopWindowSize);
      await WindowManager.instance.setAspectRatio(defaultDesktopAspectRatio);
      await WindowManager.instance.setSize(defaultDesktopWindowSize);
    }
    final startupSimulatedWebViewDevice =
        await SharedPreferencesSettingsService().enableSimulatedWebViews()
            ? await loadPersistedSimulatedWebViewDevice()
            : null;
    if (startupSimulatedWebViewDevice != null) {
      await setSimulatedWebViewDevice(
        startupSimulatedWebViewDevice,
        persist: false,
      );
    }
  }

  final appDocsPath = (await getApplicationDocumentsDirectory()).path;

  RotatingFileAppender(
    baseFilePath: '$appDocsPath/log.txt',
  ).attachToLogger(Logger.root);

  // Initialize WebView console log service (separate from app logs)
  final webViewLogDir = appDocsPath;
  final webViewLogService = WebViewLogService(logDirectoryPath: webViewLogDir);
  await webViewLogService.initialize();

  Logger.root.info("==== Decent starting ====");
  BootTiming.start();

  Logger.root.info(
    "build: ${BuildInfo.commitShort}, branch: ${BuildInfo.branch}",
  );
  Logger.root.info(
    "version: ${BuildInfo.version}, platform: ${Platform.operatingSystem}",
  );

  // Initialize Firebase on supported platforms (not Linux/Windows, not debug, not simulate)
  final isDebugOrSimulate =
      kDebugMode || const String.fromEnvironment("simulate").isNotEmpty;
  if (!Platform.isLinux && !Platform.isWindows && !isDebugOrSimulate) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e, st) {
      log.warning('Firebase initialization failed', e, st);
    }
  }
  BootTiming.mark('firebase_done');

  // Create log buffer, error report throttle, and telemetry service
  final logBuffer = LogBuffer();
  final errorReportThrottle = ErrorReportThrottle();
  final telemetryService = TelemetryService.create(logBuffer: logBuffer);
  BootTiming.telemetry = telemetryService;

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
        '${record.level.name}: ${record.loggerName}: ${record.message}',
      );
      logBuffer.append(scrubbed);

      if (!shouldForwardToTelemetry(record)) return;

      // Trigger telemetry error report if rate limit allows
      if (errorReportThrottle.shouldReport(scrubbed)) {
        final error = record.error ?? scrubbed;
        telemetryService.recordError(error, record.stackTrace);
      }
    }
  });

  final List<DeviceDiscoveryService> services = [];

  // Every platform always has exactly one BLE service.
  final BleDiscoveryService bleDiscoveryService;

  // flutter_blue_plus → universal_ble migration complete: every platform
  // (Windows, macOS, iOS, Android, and Linux as of Phase 3) runs on the single
  // universal_ble stack. Linux uses universal_ble's pure-Dart BlueZ backend.
  // See doc/plans/flutter-blue-plus-to-universal-ble-migration.md.
  bleDiscoveryService = UniversalBleDiscoveryService();
  if (!cliArgs.serial) {
    services.add(bleDiscoveryService);
  } else {
    log.info('--serial: BLE service not added to scan list');
  }

  await Hive.initFlutter('store');

  services.add(createSerialService());

  // WiFi Half Decent Scale discovery (DNS-SD + manual-IP fallback). Native
  // mDNS on every platform via bonsoir; discovered scales flow into the same
  // device stream as BLE/USB. DeviceController.initialize() calls its
  // initialize() and wires its device stream like any other service.
  final wifiScaleDiscoveryService = WifiScaleDiscoveryService();
  services.add(wifiScaleDiscoveryService);

  final simulatedDevicesService = SimulatedDeviceService();
  services.add(simulatedDevicesService);
  const simulateEnv = String.fromEnvironment("simulate");
  if (simulateEnv.isNotEmpty) {
    final dartDefineDevices = _parseSimulateFlag(simulateEnv);
    simulatedDevicesService.enabledDevices = dartDefineDevices;
    log.info("enabling simulated devices from dart-define: $dartDefineDevices");
  }
  // Initialize Drift database
  final appDatabase = AppDatabase.defaults();

  final persistenceController = PersistenceController(
    storageService: DriftStorageService(appDatabase),
  );

  // Entity storage services
  final beanStorage = DriftBeanStorageService(appDatabase);
  final grinderStorage = DriftGrinderStorageService(appDatabase);
  final profileStorage = DriftProfileStorageService(appDatabase);

  final WorkflowController workflowController = WorkflowController();
  try {
    Workflow? workflow = await persistenceController.loadWorkflow();
    if (workflow != null) {
      workflowController.setWorkflow(workflow);
    }
  } catch (e) {
    log.warning("loading default workflow failed", e);
  }

  final settingsController = SettingsController(
    SharedPreferencesSettingsService(),
  );
  settingsController.telemetryService = telemetryService;

  // Initialize profile storage and controller
  final profileController = ProfileController(
    storage: profileStorage,
  );
  await profileController.initialize();

  final deviceController = DeviceController(services);
  deviceController.telemetryService = telemetryService;
  final de1Controller = De1Controller(controller: deviceController)
    ..defaultWorkflow = workflowController.currentWorkflow;
  final scaleController = ScaleController();
  final sensorController = SensorController(controller: deviceController);

  final connectionManager = ConnectionManager(
    deviceScanner: deviceController,
    de1Controller: de1Controller,
    scaleController: scaleController,
    settingsController: settingsController,
  );

  // Remembers devices the user connects to (machine + scale), shown as
  // unavailable when absent. The stream mappers (which read {id,name,type} off
  // the connected device and skip simulated devices) live in
  // `remembered_device_sources.dart` so they're unit-testable; the controller
  // itself stays interface-agnostic.
  final rememberedDevicesController = RememberedDevicesController(
    machineConnections: de1Controller.de1.map(rememberedFromMachine),
    scaleConnections: scaleController.connectionState.map(
      (state) =>
          rememberedFromScaleState(state, scaleController.connectedScale),
    ),
    settings: SharedPreferencesSettingsService(),
  );
  await rememberedDevicesController.initialize();

  final scanStateGuardian = ScanStateGuardian(
    bleService: cliArgs.serial ? null : bleDiscoveryService,
  );

  final presenceController = PresenceController(
    de1Controller: de1Controller,
    settingsController: settingsController,
  );
  presenceController.initialize();

  workflowController.addListener(() {
    persistenceController.saveWorkflow(workflowController.currentWorkflow);
    de1Controller.defaultWorkflow = workflowController.currentWorkflow;
  });
  // Single writer of DE1 setProfile across REST + UI paths. Must be
  // constructed after workflowController has its persisted workflow
  // loaded so its initial snapshot matches what was last pushed.
  // ignore: unused_local_variable
  final workflowDeviceSync = WorkflowDeviceSync(
    workflowController: workflowController,
    de1Controller: de1Controller,
  );
  // Reflects WorkflowContext.targetYield into Bengle's autonomous SAW
  // MMR. Single writer for both REST and UI yield-edits; re-applies on
  // every Bengle (re)connect.
  // ignore: unused_local_variable
  final bengleSawBridge = BengleSawBridge(
    workflowController: workflowController,
    de1Controller: de1Controller,
  );

  // Reflects SteamSettings.stopAtTemperature into Bengle's stop-at-
  // temperature MMR (currently stubbed FW slot — bridge keeps the
  // cache consistent so the day FW publishes, writes hit the wire
  // automatically). See [[bengle_steam_stop_bridge]].
  // ignore: unused_local_variable
  final bengleSteamStopBridge = BengleSteamStopBridge(
    workflowController: workflowController,
    de1Controller: de1Controller,
  );

  // Registers a BengleMilkProbe sensor adapter with SensorController
  // when a Bengle's probe-attached signal flips true. Inert today —
  // real `Bengle.probeAttached` never emits true until FW publishes
  // a presence signal.
  // ignore: unused_local_variable
  final bengleProbeBridge = BengleProbeBridge(
    de1Controller: de1Controller,
    sensorController: sensorController,
  );

  // Records steaming sessions + scaffolding for stop-at-temperature.
  // See [[steam_sequencer]] for the predicate truth table and
  // record lifecycle.
  // ignore: unused_local_variable
  final steamSequencer = SteamSequencer(
    de1Controller: de1Controller,
    sensorController: sensorController,
    workflowController: workflowController,
    persistenceController: persistenceController,
  );
  final PluginLoaderService pluginService = PluginLoaderService(
    kvStore: HiveStoreService(defaultNamespace: "plugins")..initialize(),
  );
  // Don't initialize plugins yet - wait for permissions to be granted
  // pluginService.initialize() will be called from PermissionsView after permissions are granted
  pluginService.pluginManager.de1Controller = de1Controller;

  final WebUIService webUIService = WebUIService();
  final WebUIStorage webUIStorage = WebUIStorage(settingsController);

  // Credential store + account service — skip on headless Linux where
  // libsecret blocks on the XDG secrets portal (no desktop session).
  DecentAccountService? decentAccountService;
  DecentProxyService? decentProxyService;
  final proxyTokenService = ProxyTokenService();
  if (cliArgs.noAccount) {
    log.info('--no-account: skipping credential store and account service');
    decentAccountService = null;
    decentProxyService = null;
  } else {
    final decentCredentialStore = await createCredentialStore();
    decentAccountService = DecentAccountService(
      httpClient: http.Client(),
      credentialStore: decentCredentialStore,
    );
    // Same credential store as the account service: the proxy reads the
    // credentials that account login wrote, and never exposes them to callers.
    decentProxyService = DecentProxyService(
      httpClient: http.Client(),
      credentialStore: decentCredentialStore,
    );
  }
  // Serve the skin token into :3000 HTML so skins can call the account proxy.
  webUIService.skinProxyToken = proxyTokenService.skinToken;

  BatteryController? batteryController;
  if (Platform.isAndroid || Platform.isIOS) {
    batteryController = BatteryController(
      de1Controller: de1Controller,
      deviceController: deviceController,
      settingsController: settingsController,
    );
  }

  final displayController = DisplayController(
    de1Controller: de1Controller,
    settingsController: settingsController,
    batteryStateStream: batteryController?.chargingState,
  );
  displayController.initialize();

  // Update check service — constructed before the web server so the update
  // API (/api/v1/update, /ws/v1/update) shares its state. initialize() is
  // still deferred below.
  final updateCheckService = UpdateCheckService(
    settingsService: SharedPreferencesSettingsService(),
    webUIStorage: webUIStorage,
  );

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
      '$appDocsPath/log.txt',
      webViewLogService,
      batteryController,
      presenceController,
      displayController,
      beanStorage: beanStorage,
      grinderStorage: grinderStorage,
      connectionManager: connectionManager,
      wifiScaleDiscoveryService: wifiScaleDiscoveryService,
      rememberedDevicesController: rememberedDevicesController,
      decentAccountService: decentAccountService,
      decentProxyService: decentProxyService,
      proxyTokenService: proxyTokenService,
      updateCheckService: updateCheckService,
    );
  } catch (e, st) {
    log.severe('failed to start web server', e, st);
  }
  BootTiming.mark('webserver_up');
  // Load the user's preferred theme while the splash screen is displayed.
  // This prevents a sudden theme change when the app is first displayed.
  settingsController.addListener(() {
    // Merge dart-define devices with user-selected devices from settings
    const simEnv = String.fromEnvironment("simulate");
    final dartDefineDevices = simEnv.isNotEmpty ? _parseSimulateFlag(simEnv) : <SimulatedDevicesTypes>{};
    simulatedDevicesService.enabledDevices =
        {...dartDefineDevices, ...settingsController.simulatedDevices};
  });
  await settingsController.loadSettings();

  // CLI overrides — apply after loadSettings so they overwrite any persisted
  // values and persist themselves.
  if (cliArgs.bypassOnboarding) {
    log.info('--bypass-onboarding: skipping onboarding screens');
    await settingsController.setOnboardingCompleted(true);
    await settingsController.setAccountStepSeen(true);
    await settingsController.setAndroidWarningDismissed(true);
  }
  if (cliArgs.skinId != null) {
    log.info('--skin: setting default skin to ${cliArgs.skinId}');
    await settingsController.setDefaultSkinId(cliArgs.skinId!);
  }
  if (cliArgs.skinPath != null) {
    log.info('--skin-path: overriding skin source to ${cliArgs.skinPath}');
    webUIService.skinOverride = SkinOverride.path(cliArgs.skinPath!);
  }

  // Dart-define overrides for preferred devices — allows headless/MCP launches
  // to bypass the device selection screen by seeding the direct-connect path.
  const envMachineId = String.fromEnvironment("preferredMachineId");
  const envScaleId = String.fromEnvironment("preferredScaleId");
  if (envMachineId.isNotEmpty) {
    await settingsController.setPreferredMachineId(envMachineId);
    log.info("preferredMachineId overridden from dart-define: $envMachineId");
  }
  if (envScaleId.isNotEmpty) {
    await settingsController.setPreferredScaleId(envScaleId);
    log.info("preferredScaleId overridden from dart-define: $envScaleId");
  }

  Logger.root.level =
      Level.LEVELS.firstWhereOrNull(
        (e) => e.name == settingsController.logLevel,
      ) ??
      Level.FINE;

  // Defer the first update check / skin sync (service constructed above).
  Future.delayed(Duration(minutes: 10), () async {
    await updateCheckService.initialize();
  });

  // Add lifecycle observer for all platforms (for update notifications)
  WidgetsBinding.instance.addObserver(
    AppLifecycleObserver(
      updateCheckService: updateCheckService,
      de1Controller: de1Controller,
    ),
  );

  if (Platform.isAndroid) {
    ForegroundTaskService.init();
  }

  BootTiming.mark('runapp');
  runApp(
    WithForegroundTask(
      child: AppRoot(
        directConnect: cliArgs.direct,
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
        presenceController: presenceController,
        beanStorage: beanStorage,
        grinderStorage: grinderStorage,
        profileStorageService: profileStorage,
        connectionManager: connectionManager,
        scanStateGuardian: scanStateGuardian,
        decentAccountService: decentAccountService,
        batteryController: batteryController,
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
        content: Row(
          children: [
            Expanded(
              child: Text('Update: ${updateInfo.version}'),
            ),
            SnackBarAction(
              label: 'View',
              onPressed: () {
                _showUpdateDialog(context, updateInfo);
              },
            ),
            SnackBarAction(
              label: 'Download',
              onPressed: () {
                if (Platform.isAndroid) {
                  _showAndroidDownloadDialog(context, updateInfo);
                } else {
                  final releaseUrl =
                      updateCheckService?.getReleaseUrl();
                  if (releaseUrl != null) {
                    launchUrl(Uri.parse(releaseUrl));
                  }
                }
              },
            ),
          ],
        ),
        showCloseIcon: true,
        duration: const Duration(days: 1),
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
      _showAndroidDownloadDialog(context, updateInfo as UpdateInfo);
    } else {
      final info = updateInfo as UpdateInfo;
      final releaseUrl = updateCheckService?.getReleaseUrl();
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text('Update ${info.version}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version ${info.version} is available'),
                  const SizedBox(height: 8),
                  Text(
                    'Current version: ${BuildInfo.version}',
                  ),
                  if (info.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Release Notes:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints:
                          const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Text(info.releaseNotes),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Later'),
                ),
                if (releaseUrl != null)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      launchUrl(Uri.parse(releaseUrl));
                    },
                    child: const Text('Download'),
                  ),
              ],
            ),
      );
    }
  }

  /// Show a download+install dialog that starts downloading immediately.
  void _showAndroidDownloadDialog(
    BuildContext context,
    UpdateInfo updateInfo,
  ) {
    final updater = AndroidUpdater(owner: 'tadelv', repo: 'reaprime');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AndroidQuickUpdateDialog(
        updateInfo: updateInfo,
        updater: updater,
      ),
    );
  }

  void dispose() {
    _memTimer.cancel();
    _machineStateSubscription?.cancel();
    _stateStreamSubscription?.cancel();
  }
}

class AppRoot extends StatefulWidget {
  final bool directConnect;
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
  final PresenceController presenceController;
  final BeanStorageService? beanStorage;
  final GrinderStorageService? grinderStorage;
  final ProfileStorageService? profileStorageService;
  final ConnectionManager connectionManager;
  final ScanStateGuardian scanStateGuardian;
  final DecentAccountService? decentAccountService;
  final BatteryController? batteryController;

  const AppRoot({
    super.key,
    this.directConnect = false,
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
    required this.presenceController,
    required this.connectionManager,
    required this.scanStateGuardian,
    this.updateCheckService,
    this.beanStorage,
    this.grinderStorage,
    this.profileStorageService,
    this.decentAccountService,
    this.batteryController,
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

  // NOTE: No dispose() override here — _AppRootState is torn down and
  // recreated on every app restart (WebView crash, reinit), which must
  // NOT tear down the DE1/scale connection. ConnectionManager.dispose()
  // is wired but intentionally not called from here. The OS reclaims
  // BLE handles and serial ports on process death; the subjects are
  // harmless at exit.

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
    final child = KeyedSubtree(
      key: _key,
      child: MyApp(
        directConnect: widget.directConnect,
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
        presenceController: widget.presenceController,
        beanStorage: widget.beanStorage,
        grinderStorage: widget.grinderStorage,
        profileStorageService: widget.profileStorageService,
        connectionManager: widget.connectionManager,
        scanStateGuardian: widget.scanStateGuardian,
        decentAccountService: widget.decentAccountService,
        batteryController: widget.batteryController,
      ),
    );

    // PlatformMenuBar must live ABOVE KeyedSubtree so it survives app restarts
    // (which change the key). Otherwise, the new PlatformMenuBar tries to
    // acquire the static _lockedContext lock before the old one is disposed.
    if (Platform.isMacOS) {
      return PlatformMenuBar(
        menus: _buildPlatformMenus(),
        child: child,
      );
    }
    // Windows/Linux have no native menu bar, so mirror the macOS simulated-
    // WebView menu shortcuts with Ctrl+Alt+<digit> bindings (Cmd→Ctrl) when the
    // feature is enabled. The Advanced-settings picker is the discoverable path;
    // these match the muscle memory of the macOS menu accelerators.
    if ((Platform.isWindows || Platform.isLinux) &&
        widget.settingsController.enableSimulatedWebViews) {
      return CallbackShortcuts(
        bindings: _simulatedWebViewShortcuts(),
        child: child,
      );
    }
    return child;
  }

  /// `Ctrl+Alt+<digit>` accelerators for switching the simulated WebView on
  /// Windows/Linux, mirroring the macOS Cmd+Alt menu shortcuts in
  /// [_buildPlatformMenus]: 0 → native, 8 → T50 Mini, 7 → P80X, 6 → P85 Pro.
  Map<ShortcutActivator, VoidCallback> _simulatedWebViewShortcuts() {
    return {
      const SingleActivator(
        LogicalKeyboardKey.digit0,
        control: true,
        alt: true,
      ): () => unawaited(setSimulatedWebViewDevice(null)),
      const SingleActivator(
        LogicalKeyboardKey.digit8,
        control: true,
        alt: true,
      ): () => unawaited(
        setSimulatedWebViewDevice(SimulatedWebViewDevice.teclastT50Mini),
      ),
      const SingleActivator(
        LogicalKeyboardKey.digit7,
        control: true,
        alt: true,
      ): () => unawaited(
        setSimulatedWebViewDevice(SimulatedWebViewDevice.teclastP80X),
      ),
      const SingleActivator(
        LogicalKeyboardKey.digit6,
        control: true,
        alt: true,
      ): () => unawaited(
        setSimulatedWebViewDevice(SimulatedWebViewDevice.teclastP85Pro),
      ),
    };
  }

  List<PlatformMenuItem> _buildPlatformMenus() {
    return [
      PlatformMenu(
        label: 'Decent',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'About Decent',
                onSelected: null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Quit Decent',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyQ,
                  meta: true,
                ),
                onSelected: () {
                  SystemNavigator.pop();
                },
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'View',
        menus: [
          PlatformMenuItem(
            label: 'Back to Dashboard',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyD,
              meta: true,
            ),
            onSelected: () {
              final navigator = NavigationService.navigatorKey.currentState;
              if (navigator != null) {
                navigator.pushNamedAndRemoveUntil(
                  LauncherView.routeName,
                  (_) => false,
                );
              }
            },
          ),
          if (widget.settingsController.enableSimulatedWebViews) ...[
            PlatformMenuItem(
              label: 'Use Native macOS WebView',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit0,
                alt: true,
                meta: true,
              ),
              onSelected: () async {
                await setSimulatedWebViewDevice(null);
              },
            ),
            PlatformMenuItem(
              label: 'Simulate Teclast M50/T50 Mini WebView',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit8,
                alt: true,
                meta: true,
              ),
              onSelected: () async {
                await setSimulatedWebViewDevice(
                  SimulatedWebViewDevice.teclastT50Mini,
                );
              },
            ),
            PlatformMenuItem(
              label: 'Simulate Teclast P80X WebView',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit7,
                alt: true,
                meta: true,
              ),
              onSelected: () async {
                await setSimulatedWebViewDevice(
                  SimulatedWebViewDevice.teclastP80X,
                );
              },
            ),
            PlatformMenuItem(
              label: 'Simulate Teclast P85 Pro WebView',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit6,
                alt: true,
                meta: true,
              ),
              onSelected: () async {
                await setSimulatedWebViewDevice(
                  SimulatedWebViewDevice.teclastP85Pro,
                );
              },
            ),
          ],
        ],
      ),
    ];
  }
}

/// Minimal update dialog that starts downloading immediately.
/// Used from the persistent SnackBar "Download" action on Android.
class _AndroidQuickUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final AndroidUpdater updater;

  const _AndroidQuickUpdateDialog({
    required this.updateInfo,
    required this.updater,
  });

  @override
  State<_AndroidQuickUpdateDialog> createState() =>
      _AndroidQuickUpdateDialogState();
}

class _AndroidQuickUpdateDialogState
    extends State<_AndroidQuickUpdateDialog> {
  bool _isDownloading = true;
  bool _isInstalling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final path = await widget.updater.downloadUpdate(widget.updateInfo);
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isInstalling = true;
      });
      final success = await widget.updater.installUpdate(path);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Update installation started. Follow the on-screen prompts.',
            ),
          ),
        );
      } else {
        setState(() {
          _isInstalling = false;
          _error =
              'Install permission required. Grant permission and try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed: $e';
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update ${widget.updateInfo.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isDownloading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Downloading update…'),
          ],
          if (_isInstalling) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Installing update…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_error != null)
          ElevatedButton(
            onPressed: () {
              setState(() {
                _error = null;
                _isDownloading = true;
              });
              _startDownload();
            },
            child: const Text('Retry'),
          ),
      ],
    );
  }
}
