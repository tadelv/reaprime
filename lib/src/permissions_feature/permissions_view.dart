import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/device_discovery_feature/device_discovery_view.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

class PermissionsView extends StatefulWidget {
  final DeviceController deviceController;
  final De1Controller de1controller;
  final ScaleController scaleController;
  final PluginLoaderService? pluginLoaderService;
  final WebUIStorage webUIStorage;
  final WebUIService webUIService;
  final SettingsController settingsController;

  const PermissionsView({
    super.key,
    required this.deviceController,
    required this.de1controller,
    required this.scaleController,
    this.pluginLoaderService,
    required this.webUIStorage,
    required this.webUIService,
    required this.settingsController,
  });

  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<PermissionsView> {
  final Logger _log = Logger("PermissionsView");
  late final Future<bool> _permissionsFuture;

  @override
  void initState() {
    super.initState();
    _permissionsFuture = _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Streamline')),
      body: SafeArea(child: _permissions(context)),
    );
  }

  Widget _permissions(context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Streamline is starting ...'),
          FutureBuilder(
            future: _permissionsFuture,
            builder: (context, result) {
              switch (result.connectionState) {
                case ConnectionState.none:
                  return Text("Unknown");
                case ConnectionState.waiting:
                  return _initializingView(context);
                case ConnectionState.active:
                case ConnectionState.done:
                  return _devicePicker(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _initializingView(BuildContext context) {
    return Column(
      spacing: 16,
      children: [
        SizedBox(width: 200, child: ShadProgress()),
        Text(
          DeviceDiscoveryView.getRandomCoffeeMessage(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // await Permission.ignoreBatteryOptimizations.request();
      await Permission.manageExternalStorage.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetooth.request();
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();

      // Request notification permission for Android 13+ (API 33+)
      // This allows foreground service notification to appear in notification drawer
      if (Platform.isAndroid) {
        await Permission.notification.request();

        // CRITICAL: Request battery optimization exemption
        // This prevents Android from killing the app in the background
        final batteryOptStatus =
            await Permission.ignoreBatteryOptimizations.status;
        if (!batteryOptStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    } else {
      try {
        await UniversalBle.availabilityStream.firstWhere(
          (e) => e == AvailabilityState.poweredOn,
        ).timeout(Duration(seconds: 5));
      } on TimeoutException {
        _log.warning('Bluetooth availability check timed out, continuing without BLE');
      }
    }

    // Telemetry consent prompt is shown as a dialog after device picker loads
    // (see DeviceDiscoveryView.initState). This keeps startup non-blocking
    // while still prompting the user (PRIV-03, PRIV-04).

    // Initialize WebUI storage and service BEFORE device controller
    _log.info('Initializing WebUI storage...');
    try {
      await widget.webUIStorage.initialize();
      _log.info('WebUI storage initialized successfully');
    } catch (e) {
      _log.severe('Failed to initialize WebUI storage', e);
      // Continue anyway - we can still use the app without WebUI
    }

    // Start WebUI service if we have a default skin
    final defaultSkin = widget.webUIStorage.defaultSkin;
    if (defaultSkin != null) {
      _log.info('Starting WebUI service with skin: ${defaultSkin.name}');
      try {
        await widget.webUIService.serveFolderAtPath(defaultSkin.path);
        _log.info('WebUI service started successfully');
      } catch (e) {
        _log.severe('Failed to start WebUI service', e);
        // Continue anyway - we can still use the app without WebUI
      }
    } else {
      _log.warning('No default skin available, WebUI service not started');
    }

    // Initialize plugins after WebUI is ready
    if (widget.pluginLoaderService != null) {
      try {
        await widget.pluginLoaderService!.initialize();
      } catch (e) {
        // Log error but don't fail the permissions check
        _log.warning('Failed to initialize plugins: $e');
      }
    }

    // Initialize device controller last
    await widget.deviceController.initialize();

    return true;
  }

  Widget _devicePicker(BuildContext context) {
    return Center(
      child: DeviceDiscoveryView(
        de1controller: widget.de1controller,
        deviceController: widget.deviceController,
        scaleController: widget.scaleController,
        settingsController: widget.settingsController,
        webUIService: widget.webUIService,
        webUIStorage: widget.webUIStorage,
        logger: _log,
      ),
    );
  }
}
