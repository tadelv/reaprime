import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:reaprime/src/controllers/de1_state_manager.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/history_feature/history_feature.dart';
import 'package:reaprime/src/permissions_feature/permissions_view.dart';
import 'package:reaprime/src/realtime_shot_feature/realtime_shot_feature.dart';
import 'package:reaprime/src/realtime_steam_feature/realtime_steam_feature.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/sample_feature/scale_debug_view.dart';
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

final WebUIService webUIService = WebUIService();

/// The Widget that configures your application.
class MyApp extends StatefulWidget {
  MyApp({
    super.key,
    required this.settingsController,
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
    required this.workflowController,
    required this.persistenceController,
    required this.pluginLoaderService,
  });

  final SettingsController settingsController;
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;
  final PluginLoaderService pluginLoaderService;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  De1StateManager? _de1StateManager;

  @override
  void initState() {
    super.initState();
    _initializeDe1StateManager();
  }

  @override
  void didUpdateWidget(MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recreate De1StateManager if any of the required controllers change
    if (oldWidget.settingsController != widget.settingsController ||
        oldWidget.de1Controller != widget.de1Controller ||
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
      navigatorKey: NavigationService.navigatorKey,
    );
  }

  @override
  void dispose() {
    _de1StateManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Start foreground service for Android
    if (Platform.isAndroid) {
      FlutterForegroundTask.startService(
        notificationTitle: "Reaprime talking to DE1",
        notificationText: "Tap to return to Reaprime",
      );
    }

    final themeColor = 'green';

    return ScaffoldMessenger(
      child: ListenableBuilder(
        listenable: widget.settingsController,
        builder: (BuildContext context, Widget? child) {
          return ShadApp(
            // Providing a restorationScopeId allows the Navigator built by the
            // MaterialApp to restore the navigation stack when a user leaves and
            // returns to the app after it has been killed while running in the
            // background.
            restorationScopeId: 'app',

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
            onGenerateTitle: (BuildContext context) => "ReaPrime",

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
                      );
                    case De1DebugView.routeName:
                      var device = widget.deviceController.devices.firstWhere(
                        (e) => e.deviceId == routeSettings.arguments as String,
                      );
                      if (device is De1Interface) {
                        try {
                          widget.de1Controller.connectedDe1();
                        } catch (_) {
                          // De1 controller has no connected de1, connect to this one
                          widget.de1Controller.connectToDe1(device);
                        }
                        return De1DebugView(
                          machine: widget.deviceController.devices.firstWhere(
                                (e) =>
                                    e.deviceId ==
                                    (routeSettings.arguments as String),
                              ) as De1Interface,
                        );
                      }
                      if (device is Scale) {
                        return ScaleDebugView(scale: device);
                      }
                      return Text("No mapping for ${device.name}");
                    case SampleItemListView.routeName:
                      return SampleItemListView(
                        controller: widget.deviceController,
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
                          doseData:
                              widget.workflowController.currentWorkflow.doseData,
                        );
                      }
                      return RealtimeShotFeature(
                        shotController: shotController,
                        workflowController: widget.workflowController,
                      );
                    case RealtimeSteamFeature.routeName:
                      final args = routeSettings.arguments;
                      De1Controller de1Controller;
                      if (args is De1Controller) {
                        de1Controller = args;
                      } else {
                        de1Controller = widget.de1Controller;
                      }
                      return RealtimeSteamFeature(
                        de1Controller: de1Controller,
                      );
                    case HomeScreen.routeName:
                      return HomeScreen(
                        de1controller: widget.de1Controller,
                        workflowController: widget.workflowController,
                        scaleController: widget.scaleController,
                        deviceController: widget.deviceController,
                        persistenceController: widget.persistenceController,
                        settingsController: widget.settingsController,
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
                    default:
                      return PermissionsView(
                        deviceController: widget.deviceController,
                        de1controller: widget.de1Controller,
                        pluginLoaderService: widget.pluginLoaderService,
                      );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
