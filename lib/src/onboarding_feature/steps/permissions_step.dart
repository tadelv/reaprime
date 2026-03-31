import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/foreground_service.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:universal_ble/universal_ble.dart';

import '../onboarding_controller.dart';

final _log = Logger('PermissionsStep');

/// Creates an [OnboardingStep] that requests BLE permissions and initializes
/// core services (WebUI, plugins, device controller).
///
/// The step shows only when platform permissions are not yet granted.
/// After permissions are obtained and services initialized, it calls
/// [OnboardingController.advance] to proceed.
OnboardingStep createPermissionsStep({
  required DeviceController deviceController,
  required De1Controller de1Controller,
  PluginLoaderService? pluginLoaderService,
  required WebUIStorage webUIStorage,
  required WebUIService webUIService,
}) {
  return OnboardingStep(
    id: 'permissions',
    shouldShow: () => _checkPermissionsNeeded(),
    builder: (controller) => _PermissionsStepView(
      onboardingController: controller,
      deviceController: deviceController,
      de1Controller: de1Controller,
      pluginLoaderService: pluginLoaderService,
      webUIStorage: webUIStorage,
      webUIService: webUIService,
    ),
  );
}

/// Checks whether BLE permissions still need to be requested.
///
/// Returns `true` if the step should be shown (permissions not yet granted),
/// `false` if permissions are already granted or not needed (desktop).
Future<bool> _checkPermissionsNeeded() async {
  if (Platform.isAndroid) {
    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt >= 31) {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      return !scan.isGranted || !connect.isGranted;
    } else {
      final bt = await Permission.bluetooth.status;
      final loc = await Permission.locationWhenInUse.status;
      return !bt.isGranted || !loc.isGranted;
    }
  } else if (Platform.isIOS) {
    final bt = await Permission.bluetooth.status;
    return !bt.isGranted;
  }
  // Desktop platforms: no runtime permissions needed
  return false;
}

class _PermissionsStepView extends StatefulWidget {
  final OnboardingController onboardingController;
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final PluginLoaderService? pluginLoaderService;
  final WebUIStorage webUIStorage;
  final WebUIService webUIService;

  const _PermissionsStepView({
    required this.onboardingController,
    required this.deviceController,
    required this.de1Controller,
    this.pluginLoaderService,
    required this.webUIStorage,
    required this.webUIService,
  });

  @override
  State<_PermissionsStepView> createState() => _PermissionsStepViewState();
}

class _PermissionsStepViewState extends State<_PermissionsStepView> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _requestPermissionsAndInitialize();
  }

  Future<void> _requestPermissionsAndInitialize() async {
    // Request platform permissions
    if (Platform.isAndroid || Platform.isIOS) {
      if (Platform.isAndroid) {
        final sdkVersion = await _getAndroidSdkVersion();
        if (sdkVersion >= 31) {
          await Permission.bluetoothScan.request();
          await Permission.bluetoothConnect.request();
        } else {
          await Permission.bluetooth.request();
          await Permission.locationWhenInUse.request();
        }

        await Permission.notification.request();
        await ForegroundTaskService.start();

        ForegroundTaskService.watchMachineConnection(
          widget.de1Controller.de1,
        );

        final batteryOptStatus =
            await Permission.ignoreBatteryOptimizations.status;
        if (!batteryOptStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      } else if (Platform.isIOS) {
        await Permission.bluetooth.request();
      }
    } else {
      try {
        await UniversalBle.availabilityStream
            .firstWhere((e) => e == AvailabilityState.poweredOn)
            .timeout(Duration(seconds: 5));
      } on TimeoutException {
        _log.warning(
            'Bluetooth availability check timed out, continuing without BLE');
      }
    }

    // Initialize WebUI storage
    _log.info('Initializing WebUI storage...');
    try {
      await widget.webUIStorage.initialize();
      _log.info('WebUI storage initialized successfully');
    } catch (e) {
      _log.severe('Failed to initialize WebUI storage', e);
    }

    // Start WebUI service with default skin
    final defaultSkin = widget.webUIStorage.defaultSkin;
    if (defaultSkin != null) {
      _log.info('Starting WebUI service with skin: ${defaultSkin.name}');
      try {
        await widget.webUIService.serveFolderAtPath(defaultSkin.path);
        _log.info('WebUI service started successfully');
      } catch (e) {
        _log.severe('Failed to start WebUI service', e);
      }
    } else {
      _log.warning('No default skin available, WebUI service not started');
    }

    // Initialize plugins
    if (widget.pluginLoaderService != null) {
      try {
        await widget.pluginLoaderService!.initialize();
      } catch (e) {
        _log.warning('Failed to initialize plugins: $e');
      }
    }

    // Initialize device controller last
    await widget.deviceController.initialize();

    // All done - advance to next onboarding step
    widget.onboardingController.advance();
  }

  Future<int> _getAndroidSdkVersion() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Streamline is starting ...'),
          FutureBuilder<void>(
            future: _initFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              return Column(
                spacing: 16,
                children: [
                  SizedBox(width: 200, child: ShadProgress()),
                  Text(
                    'Requesting permissions...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
