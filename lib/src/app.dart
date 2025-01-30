import 'package:flutter_foreground_task/ui/with_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/sample_feature/scale_debug_view.dart';
import 'package:reaprime/src/services/webserver_service.dart';

import 'sample_feature/sample_item_details_view.dart';
import 'sample_feature/sample_item_list_view.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_view.dart';

Future<void> waitForPermission(bool wait, Future<void> Function() exec) async {
  await Future.doWhile(() => wait);
  wait = true;
  await exec();
  wait = false;
}

/// The Widget that configures your application.
class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.settingsController,
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
  });

  final SettingsController settingsController;
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;

  @override
  Widget build(BuildContext context) {
    // Glue the SettingsController to the MaterialApp.
    //
    // The ListenableBuilder Widget listens to the SettingsController for changes.
    // Whenever the user updates their settings, the MaterialApp is rebuilt.
    var wait = false;
    Future.forEach([
      Permission.bluetoothScan.request,
      Permission.bluetoothConnect.request,
      Permission.bluetooth.request,
      Permission.locationWhenInUse.request,
      Permission.locationAlways.request,
      deviceController.initialize,
    ], (e) async => await waitForPermission(wait, e));

    return ListenableBuilder(
      listenable: settingsController,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          // Providing a restorationScopeId allows the Navigator built by the
          // MaterialApp to restore the navigation stack when a user leaves and
          // returns to the app after it has been killed while running in the
          // background.
          restorationScopeId: 'app',

          // Provide the generated AppLocalizations to the MaterialApp. This
          // allows descendant Widgets to display the correct translations
          // depending on the user's locale.
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''), // English, no country code
          ],

          // Use AppLocalizations to configure the correct application title
          // depending on the user's locale.
          //
          // The appTitle is defined in .arb files found in the localization
          // directory.
          onGenerateTitle:
              (BuildContext context) => AppLocalizations.of(context)!.appTitle,

          // Define a light and dark color theme. Then, read the user's
          // preferred ThemeMode (light, dark, or system default) from the
          // SettingsController to display the correct theme.
          theme: ThemeData(),
          darkTheme: ThemeData.dark(),
          themeMode: settingsController.themeMode,

          // Define a function to handle named routes in order to support
          // Flutter web url navigation and deep linking.
          onGenerateRoute: (RouteSettings routeSettings) {
            return MaterialPageRoute<void>(
              settings: routeSettings,
              builder: (BuildContext context) {
                switch (routeSettings.name) {
                  case SettingsView.routeName:
                    return SettingsView(controller: settingsController);
                  case SampleItemDetailsView.routeName:
                    var device = deviceController.devices.firstWhere(
                      (e) => e.deviceId == routeSettings.arguments as String,
                    );
                    if (device is De1Interface) {
                      return SampleItemDetailsView(
                        machine:
                            deviceController.devices.firstWhere(
                                  (e) =>
                                      e.deviceId ==
                                      (routeSettings.arguments as String),
                                )
                                as De1Interface,
                      );
                    }
                    if (device is Scale) {
                      return ScaleDebugView(scale: device);
                    }
                    return Text("No mapping for ${device.name}");
                  case SampleItemListView.routeName:
                  default:
                    return WithForegroundTask(
                      child: SampleItemListView(controller: deviceController),
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
