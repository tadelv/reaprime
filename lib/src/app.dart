import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/main.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/de1_state_manager.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/presence_controller.dart';
import 'package:reaprime/src/controllers/presence_navigator_observer.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/history_feature/history_feature.dart';
import 'package:reaprime/src/landing_feature/landing_feature.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_view.dart';
import 'package:reaprime/src/onboarding_feature/steps/import_step.dart';
import 'package:reaprime/src/onboarding_feature/steps/initialization_step.dart';
import 'package:reaprime/src/onboarding_feature/steps/permissions_step.dart';
import 'package:reaprime/src/onboarding_feature/steps/scan_step.dart';
import 'package:reaprime/src/onboarding_feature/steps/welcome_step.dart';
import 'package:reaprime/src/realtime_shot_feature/realtime_shot_feature.dart';
import 'package:reaprime/src/realtime_steam_feature/realtime_steam_feature.dart';
import 'package:reaprime/src/skin_feature/skin_view.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart' hide Scale;
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/sample_feature/scale_debug_view.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:reaprime/src/services/update_check_service.dart';
import 'package:reaprime/src/services/webview_log_service.dart';
import 'package:reaprime/src/settings/plugins_settings_view.dart';
import 'sample_feature/sample_item_details_view.dart';

import 'sample_feature/sample_item_list_view.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_view.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentContext;
  static String? get currentRoute => ModalRoute.of(context!)?.settings.name;
}

/// The Widget that configures your application.
class MyApp extends StatefulWidget {
  const MyApp({
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
    required this.presenceController,
    required this.connectionManager,
    required this.scanStateGuardian,
    this.updateCheckService,
    this.beanStorage,
    this.grinderStorage,
    this.profileStorageService,
  });

  final SettingsController settingsController;
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;
  final PluginLoaderService pluginLoaderService;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;
  final WebViewLogService webViewLogService;
  final PresenceController presenceController;
  final ConnectionManager connectionManager;
  final ScanStateGuardian scanStateGuardian;
  final UpdateCheckService? updateCheckService;
  final BeanStorageService? beanStorage;
  final GrinderStorageService? grinderStorage;
  final ProfileStorageService? profileStorageService;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final Logger _log = Logger('MyApp');
  De1StateManager? _de1StateManager;
  Timer? _restartTimer;
  late final OnboardingController _onboardingController;

  @override
  void initState() {
    super.initState();
    _initializeDe1StateManager();
    _onboardingController = OnboardingController(steps: [
      OnboardingStep(
        id: 'welcome',
        shouldShow: () async =>
            !widget.settingsController.onboardingCompleted,
        builder: createWelcomeStep().builder,
      ),
      createPermissionsStep(
        de1Controller: widget.de1Controller,
      ),
      createInitializationStep(
        deviceController: widget.deviceController,
        pluginLoaderService: widget.pluginLoaderService,
        webUIStorage: widget.webUIStorage,
        webUIService: widget.webUIService,
      ),
      if (widget.profileStorageService != null &&
          widget.beanStorage != null &&
          widget.grinderStorage != null)
        OnboardingStep(
          id: 'import',
          shouldShow: () async =>
              !widget.settingsController.onboardingCompleted,
          builder: createImportStep(
            storageService: widget.persistenceController.storageService,
            profileStorageService: widget.profileStorageService!,
            beanStorageService: widget.beanStorage!,
            grinderStorageService: widget.grinderStorage!,
            settingsController: widget.settingsController,
            persistenceController: widget.persistenceController,
          ).builder,
        ),
      createScanStep(
        connectionManager: widget.connectionManager,
        deviceController: widget.deviceController,
        settingsController: widget.settingsController,
        scanStateGuardian: widget.scanStateGuardian,
        onSkipToDashboard: () {
          NavigationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
            HomeScreen.routeName,
            (_) => false,
          );
        },
      ),
    ]);
    _onboardingController.initialize();
  }

  @override
  void didUpdateWidget(MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recreate De1StateManager if any of the required controllers change
    if (oldWidget.settingsController != widget.settingsController ||
        oldWidget.de1Controller != widget.de1Controller ||
        oldWidget.connectionManager != widget.connectionManager ||
        oldWidget.scaleController != widget.scaleController ||
        oldWidget.workflowController != widget.workflowController ||
        oldWidget.persistenceController != widget.persistenceController) {
      _de1StateManager?.dispose();
      _de1StateManager = null;
      _initializeDe1StateManager();
    }
  }

  void _initializeDe1StateManager() {
    _de1StateManager = De1StateManager(
      de1Controller: widget.de1Controller,
      scaleController: widget.scaleController,
      workflowController: widget.workflowController,
      persistenceController: widget.persistenceController,
      settingsController: widget.settingsController,
      connectionManager: widget.connectionManager,
      navigatorKey: NavigationService.navigatorKey,
    );
  }

  /// Navigates to the appropriate screen after onboarding completes.
  ///
  /// Replicates the logic from DeviceDiscoveryView._navigateAfterConnection:
  /// 1. Check platform WebView support
  /// 2. Ensure WebUI service is running
  /// 3. Push HomeScreen, then SkinView on top (or LandingFeature if no WebView)
  Future<void> _navigateAfterOnboarding() async {
    final navigator = NavigationService.navigatorKey.currentState;
    if (navigator == null) return;

    // Check platform - only use WebView on iOS, Android, macOS
    final supportedPlatforms =
        Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

    if (!supportedPlatforms) {
      _log.info(
        'Platform not supported for WebView, using Landing page',
      );
      navigator.pushNamedAndRemoveUntil(
        LandingFeature.routeName,
        (_) => false,
      );
      return;
    }

    // Ensure WebUI is ready
    if (!widget.webUIService.isServing) {
      _log.info('WebUI not serving, attempting to start...');

      final defaultSkin = widget.webUIStorage.defaultSkin;
      if (defaultSkin != null) {
        try {
          await widget.webUIService.serveFolderAtPath(defaultSkin.path);
          _log.info('WebUI service started successfully');
        } catch (e) {
          _log.severe('Failed to start WebUI service: $e');
          navigator.pushNamedAndRemoveUntil(
            LandingFeature.routeName,
            (_) => false,
          );
          return;
        }
      } else {
        _log.warning('No default skin available, using Landing page');
        navigator.pushNamedAndRemoveUntil(
          LandingFeature.routeName,
          (_) => false,
        );
        return;
      }
    }

    // Wait a brief moment for WebUI to be fully ready
    await Future.delayed(const Duration(milliseconds: 500));

    _log.info('Navigating to SkinView');
    // Push both routes to stack: HomeScreen first, then SkinView on top
    navigator.pushNamedAndRemoveUntil(
      HomeScreen.routeName,
      (_) => false,
    );
    navigator.pushNamed(SkinView.routeName);
  }

  @override
  void dispose() {
    _de1StateManager?.dispose();
    _onboardingController.dispose();
    _restartTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _restartTimer?.cancel();
    _restartTimer = Timer.periodic(Duration(hours: 1), (_) {
      // _restartTimer = Timer.periodic(Duration(seconds: 40), (_) {
      final now = DateTime.now();
      if (now.hour == 1) {
        AppRoot.restart(context);
      }
    });
    // Foreground service is now started in main.dart for Android

    final themeColor = 'green';

    final body = ScaffoldMessenger(
        child: ListenableBuilder(
          listenable: widget.settingsController,
          builder: (BuildContext context, Widget? child) {
            return ShadApp(
            // Providing a restorationScopeId allows the Navigator built by the
            // MaterialApp to restore the navigation stack when a user leaves and
            // returns to the app after it has been killed while running in the
            // background.
            restorationScopeId: null,

            // Provide the generated AppLocalizations to the MaterialApp. This
            // allows descendant Widgets to display the correct translations
            // depending on the user's locale.
            // localizationsDelegates: const [
            //   GlobalMaterialLocalizations.delegate,
            //   GlobalWidgetsLocalizations.delegate,
            //   GlobalCupertinoLocalizations.delegate,
            // ],
            supportedLocales: const [
              Locale('en', ''), // English, no country code
            ],

            // Use AppLocalizations to configure the correct application title
            // depending on the user's locale.
            //
            // The appTitle is defined in .arb files found in the localization
            // directory.
            onGenerateTitle: (BuildContext context) => "Streamline",

            // Define a light and dark color theme. Then, read the user's
            // preferred ThemeMode (light, dark, or system default) from the
            // SettingsController to display the correct theme.
            theme: ShadThemeData(
              colorScheme: ShadColorScheme.fromName(
                themeColor,
                brightness: Brightness.light,
              ),
              brightness: Brightness.light,
            ),
            darkTheme: ShadThemeData(
              colorScheme: ShadColorScheme.fromName(
                themeColor,
                brightness: Brightness.dark,
              ),
              brightness: Brightness.dark,
            ),
            themeMode: widget.settingsController.themeMode,

            navigatorKey: NavigationService.navigatorKey,
            navigatorObservers: [
              PresenceNavigatorObserver(presenceController: widget.presenceController),
            ],
            // Define a function to handle named routes in order to support
            // Flutter web url navigation and deep linking.
            onGenerateRoute: (RouteSettings routeSettings) {
              return MaterialPageRoute<void>(
                settings: routeSettings,
                builder: (BuildContext context) {
                  switch (routeSettings.name) {
                    case SettingsView.routeName:
                      return SettingsView(
                        controller: widget.settingsController,
                        persistenceController: widget.persistenceController,
                        deviceController: widget.deviceController,
                        presenceController: widget.presenceController,
                        webUIService: widget.webUIService,
                        webUIStorage: widget.webUIStorage,
                        updateCheckService: widget.updateCheckService,
                        profileStorageService: widget.profileStorageService,
                        beanStorageService: widget.beanStorage,
                        grinderStorageService: widget.grinderStorage,
                      );
                    case De1DebugView.routeName:
                      final args = routeSettings.arguments;
                      final String deviceId;
                      final bool inspect;
                      if (args is Map<String, dynamic>) {
                        deviceId = args['deviceId'] as String;
                        inspect = args['inspect'] as bool? ?? true;
                      } else {
                        // Legacy: plain string deviceId, default to inspect
                        deviceId = args as String;
                        inspect = true;
                      }
                      var device = widget.deviceController.devices.firstWhere(
                        (e) => e.deviceId == deviceId,
                      );
                      if (device is De1Interface) {
                        return De1DebugView(
                          machine: device,
                          inspect: inspect,
                        );
                      }
                      if (device is Scale) {
                        return ScaleDebugView(
                          scale: device,
                          inspect: inspect,
                        );
                      }
                      return Scaffold(
                        body: ShadButton.link(
                          child: Text("No mapping for ${device.name}"),
                          onPressed: () {
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      );
                    case SampleItemListView.routeName:
                      return SampleItemListView(
                        controller: widget.deviceController,
                        connectionManager: widget.connectionManager,
                      );
                    case RealtimeShotFeature.routeName:
                      final args = routeSettings.arguments;
                      ShotController shotController;
                      if (args is ShotController) {
                        shotController = args;
                      } else {
                        shotController = ShotController(
                          scaleController: widget.scaleController,
                          de1controller: widget.de1Controller,
                          persistenceController: widget.persistenceController,
                          targetProfile:
                              widget.workflowController.currentWorkflow.profile,
                          targetYield:
                              widget
                                  .workflowController
                                  .currentWorkflow
                                  .context
                                  ?.targetYield ?? 0,
                        );
                      }
                      return RealtimeShotFeature(
                        shotController: shotController,
                        workflowController: widget.workflowController,
                      );
                    case RealtimeSteamFeature.routeName:
                      final args =
                          routeSettings.arguments as Map<String, dynamic>;
                      De1Controller de1Controller = args['controller'];
                      SteamSettings steamSettings = args['data'];
                      return RealtimeSteamFeature(
                        de1Controller: de1Controller,
                        initialSteamSettings: steamSettings,
                        gatewayMode: widget.settingsController.gatewayMode,
                      );
                    case HomeScreen.routeName:
                      return HomeScreen(
                        de1controller: widget.de1Controller,
                        workflowController: widget.workflowController,
                        scaleController: widget.scaleController,
                        deviceController: widget.deviceController,
                        persistenceController: widget.persistenceController,
                        settingsController: widget.settingsController,
                        webUIService: widget.webUIService,
                        webUIStorage: widget.webUIStorage,
                        beanStorage: widget.beanStorage,
                        grinderStorage: widget.grinderStorage,
                        connectionManager: widget.connectionManager,
                      );
                    case HistoryFeature.routeName:
                      final possibleShot = routeSettings.arguments as String;
                      return HistoryFeature(
                        persistenceController: widget.persistenceController,
                        workflowController: widget.workflowController,
                        selectedShot: possibleShot,
                      );
                    case PluginsSettingsView.routeName:
                      return PluginsSettingsView(
                        pluginLoaderService: widget.pluginLoaderService,
                      );
                    case LandingFeature.routeName:
                      return LandingFeature(
                        webUIStorage: widget.webUIStorage,
                        webUIService: widget.webUIService,
                      );
                    case SkinView.routeName:
                      return SkinView(
                        settingsController: widget.settingsController,
                        webViewLogService: widget.webViewLogService,
                        deviceIp: widget.webUIService.deviceIp(),
                      );
                    default:
                      return OnboardingView(
                        controller: _onboardingController,
                        onComplete: () => _navigateAfterOnboarding(),
                      );
                  }
                },
              );
            },
          );
        },
      ),
    );

    if (Platform.isMacOS) {
      return PlatformMenuBar(
        menus: _buildPlatformMenus(),
        child: body,
      );
    }
    return body;
  }

  List<PlatformMenuItem> _buildPlatformMenus() {
    if (!Platform.isMacOS) return [];

    return [
      PlatformMenu(
        label: 'Streamline',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'About Streamline',
                onSelected: null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Quit Streamline',
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
                  HomeScreen.routeName,
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
    ];
  }
}

