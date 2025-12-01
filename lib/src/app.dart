import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/history_feature/history_feature.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/device/hardware_scale.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/permissions_feature/permissions_view.dart';
import 'package:reaprime/src/realtime_shot_feature/realtime_shot_feature.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/sample_feature/scale_debug_view.dart';
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

bool isRealtimeShotFeatureActive = false;
final WebUIService webUIService = WebUIService();

/// The Widget that configures your application.
class MyApp extends StatelessWidget {
  MyApp({
    super.key,
    required this.settingsController,
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
    required this.workflowController,
    required this.persistenceController,
  });

  final SettingsController settingsController;
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;

  @override
  Widget build(BuildContext context) {
    // Glue the SettingsController to the MaterialApp.
    //
    // The ListenableBuilder Widget listens to the SettingsController for changes.
    // Whenever the user updates their settings, the MaterialApp is rebuilt.

    if (Platform.isAndroid) {
      FlutterForegroundTask.startService(
        notificationTitle: "Reaprime talking to DE1",
        notificationText: "Tap to return to Reaprime",
      );
    }

    final themeColor = 'green';
    de1Controller.de1.listen((event) {
      final logger = Logger("de1 event logger");
      if (event != null) {
        event.currentSnapshot.listen((snapshot) {
          switch (snapshot.state.state) {
            case MachineState.espresso:
              break;
            default:
              return;
          }
          logger.finest(
            "handling state: ${snapshot.state.state} in mode: ${settingsController.gatewayMode.name}",
          );
          switch (settingsController.gatewayMode) {
            case GatewayMode.full:
              // full gateway mode, not touching anything
              return;
            case GatewayMode.tracking:
              if (!isRealtimeShotFeatureActive) {
                logger.shout("new shot controller");
                isRealtimeShotFeatureActive = true;
                final controller = ShotController(
                  scaleController: scaleController,
                  de1controller: de1Controller,
                  persistenceController: persistenceController,
                  targetProfile: workflowController.currentWorkflow.profile,
                  doseData: workflowController.currentWorkflow.doseData,
                );
                StreamSubscription<ShotState>? sub;
                List<ShotSnapshot> snapshots = [];
                StreamSubscription<ShotSnapshot> snapshotsSub = controller
                    .shotData
                    .listen((snapshot) {
                      snapshots.add(snapshot);
                    });
                sub = controller.state.listen((st) {
                  if (st == ShotState.finished) {
                    logger.fine("cancelling shot controller");
                    controller.dispose();
                    controller.persistenceController.persistShot(
                      ShotRecord(
                        id: DateTime.now().toIso8601String(),
                        timestamp: controller.shotStartTime,
                        measurements: snapshots,
                        workflow: workflowController.currentWorkflow,
                      ),
                    );
                    snapshotsSub.cancel();
                    sub?.cancel();
                    isRealtimeShotFeatureActive = false;
                  }
                });
              }
            case GatewayMode.disabled:
              BuildContext? context = NavigationService.context;
              if (!isRealtimeShotFeatureActive &&
                  snapshot.state.state == MachineState.espresso &&
                  context != null &&
                  context.mounted) {
                isRealtimeShotFeatureActive = true;
                Navigator.pushNamed(
                  context,
                  RealtimeShotFeature.routeName,
                ).then((_) => isRealtimeShotFeatureActive = false);
              }
          }
        });
      }
    });

    return ListenableBuilder(
      listenable: settingsController,
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
          themeMode: settingsController.themeMode,

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
                      controller: settingsController,
                      persistenceController: persistenceController,
                    );
                  case De1DebugView.routeName:
                    var device = deviceController.devices.firstWhere(
                      (e) => e.deviceId == routeSettings.arguments as String,
                    );
                    if (device is De1Interface) {
                      try {
                        de1Controller.connectedDe1();
                      } catch (_) {
                        // De1 controller has no connected de1, connect to this one
                        de1Controller.connectToDe1(device);
                      }
                      return De1DebugView(
                        machine:
                            deviceController.devices.firstWhere(
                                  (e) =>
                                      e.deviceId ==
                                      (routeSettings.arguments as String),
                                )
                                as De1Interface,
                      );
                    }
                    if (device is HardwareScale) {
                      return ScaleDebugView(scale: device);
                    }
                    return Text("No mapping for ${device.name}");
                  case SampleItemListView.routeName:
                    return SampleItemListView(controller: deviceController);
                  case RealtimeShotFeature.routeName:
                    return RealtimeShotFeature(
                      shotController: ShotController(
                        scaleController: scaleController,
                        de1controller: de1Controller,
                        persistenceController: persistenceController,
                        targetProfile:
                            workflowController.currentWorkflow.profile,
                        doseData: workflowController.currentWorkflow.doseData,
                      ),
                      workflowController: workflowController,
                    );
                  case HomeScreen.routeName:
                    return HomeScreen(
                      de1controller: de1Controller,
                      workflowController: workflowController,
                      scaleController: scaleController,
                      deviceController: deviceController,
                      persistenceController: persistenceController,
                      settingsController: settingsController,
                    );
                  case HistoryFeature.routeName:
                    final possibleShot = routeSettings.arguments as String;
                    return HistoryFeature(
                      persistenceController: persistenceController,
                      workflowController: workflowController,
                      selectedShot: possibleShot,
                    );
                  case WebUIView.routeName:
                    return WebUIView(
                      indexPath: routeSettings.arguments as String,
                    );
                  default:
                    return PermissionsView(
                      deviceController: deviceController,
                      de1controller: de1Controller,
                    );
                }
              },
            );
          },
        );
      },
    );
  }
}
