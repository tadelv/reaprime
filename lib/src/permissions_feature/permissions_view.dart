import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:reaprime/src/home_feature/widgets/device_selection_widget.dart';
import 'package:reaprime/src/landing_feature/landing_feature.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';

class PermissionsView extends StatelessWidget {
  final DeviceController deviceController;
  final De1Controller de1controller;
  final PluginLoaderService? pluginLoaderService;
  final WebUIStorage webUIStorage;

  const PermissionsView({
    super.key,
    required this.deviceController,
    required this.de1controller,
    this.pluginLoaderService,
    required this.webUIStorage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Streamline'),
      ),
      body: SafeArea(
        child: _permissions(context),
      ),
    );
  }

  Widget _permissions(context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Streamline is starting ...'),
          FutureBuilder(
            future: checkPermissions(),
            builder: (context, result) {
              switch (result.connectionState) {
                case ConnectionState.none:
                  return Text("Unknown");
                case ConnectionState.waiting:
                  return _initializingView(context);
                case ConnectionState.active:
                  return Text("Done");
                case ConnectionState.done:
                  return _de1Picker(context);
              }
              return Text("Done");
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
          PermissionsView.getRandomCoffeeMessage(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  static String getRandomCoffeeMessage() {
    final messages = [
      "Dialing in the grinder...",
      "Preheating the portafilter...",
      "Calibrating the tamp pressure...",
      "Blooming the coffee bed...",
      "Checking water hardness...",
      "Polishing the shower screen...",
      "Degassing freshly roasted beans...",
      "Leveling the distribution tool...",
      "Priming the group head...",
      "Adjusting brew temperature to 0.1°C...",
      "Consulting the barista championship rules...",
      "Measuring TDS with lab precision...",
      "Perfecting the WDT technique...",
      "Activating bluetooth (please turn it on)...",
      "Weighing beans to 0.01g accuracy...",
      "Cleaning the espresso altar...",
      "Channeling positive vibes (not water)...",
      "Waiting for third wave to arrive...",
      "Updating espresso definitions...",
    ];
    return messages[DateTime.now().millisecondsSinceEpoch % messages.length];
  }

  Future<bool> checkPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // await Permission.ignoreBatteryOptimizations.request();
      await Permission.manageExternalStorage.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetooth.request();
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
    } else {
      await UniversalBle.availabilityStream
          .firstWhere((e) => e == AvailabilityState.poweredOn);
    }
    deviceController.initialize();

    // Initialize plugins after permissions are granted
    if (pluginLoaderService != null) {
      try {
        await pluginLoaderService!.initialize();
      } catch (e) {
        // Log error but don't fail the permissions check
        debugPrint('Failed to initialize plugins: $e');
      }
    }

    await webUIStorage.initialize();

    return true;
  }

  Widget _de1Picker(BuildContext context) {
    return Center(
      child: DeviceDiscoveryView(
        de1controller: de1controller,
        deviceController: deviceController,
      ),
    );
  }
}

class DeviceDiscoveryView extends StatefulWidget {
  final DeviceController deviceController;
  final De1Controller de1controller;
  const DeviceDiscoveryView(
      {super.key, required this.deviceController, required this.de1controller});

  @override
  State<StatefulWidget> createState() => _DeviceDiscoveryState();
}

class _DeviceDiscoveryState extends State<DeviceDiscoveryView> {
  DiscoveryState _state = DiscoveryState.searching;

  late StreamSubscription<List<dev.Device>> _discoverySubscription;

  final Duration _timeoutDuration = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    
    _discoverySubscription =
        widget.deviceController.deviceStream.listen((data) {
      final discoveredDevices = data.whereType<De1Interface>().toList();
      setState(() {
        _state = discoveredDevices.length > 1
            ? DiscoveryState.foundMany
            : DiscoveryState.searching;
      });
    });
    
    // If 10 seconds elapsed without finding a second de1, continue automatically
    Future.delayed(_timeoutDuration, () {
      if (mounted) {
        final discoveredDevices = widget.deviceController.devices
            .whereType<De1Interface>()
            .toList();
        
        if (discoveredDevices.length == 1) {
          widget.de1controller.connectToDe1(discoveredDevices.first);
          Navigator.popAndPushNamed(context, LandingFeature.routeName);
        } else if (discoveredDevices.isEmpty) {
          Navigator.popAndPushNamed(context, HomeScreen.routeName);
        }
      }
    });
  }

  @override
  void dispose() {
    _discoverySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case DiscoveryState.searching:
        return _searchingView(context);
      case DiscoveryState.foundOne:
      case DiscoveryState.foundMany:
        return SizedBox(height: 500, width: 300, child: _resultsView(context));
    }
  }

  Widget _searchingView(BuildContext context) {
    return Column(
      spacing: 16,
      children: [
        SizedBox(width: 200, child: ShadProgress()),
        Text(
          PermissionsView.getRandomCoffeeMessage(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Widget _resultsView(BuildContext context) {
    return DeviceSelectionWidget(
      deviceController: widget.deviceController,
      de1Controller: widget.de1controller,
      showHeader: true,
      headerText: "Select DE1 from the list",
      onDeviceSelected: (de1) {
        Navigator.popAndPushNamed(context, LandingFeature.routeName);
      },
    );
  }
}

enum DiscoveryState {
  searching,
  foundOne,
  foundMany,
}








