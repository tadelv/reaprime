import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reaprime/src/landing_feature/landing_feature.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
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
        title: Text('ReaPrime'),
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
          Text('REAPrime is starting ...'),
          FutureBuilder(
            future: checkPermissions(),
            builder: (context, result) {
              switch (result.connectionState) {
                case ConnectionState.none:
                  return Text("Unknown");
                case ConnectionState.waiting:
                  return Text("Checking, make sure Bluetooth is turned on");
                case ConnectionState.active:
                  return Text("Done");
                case ConnectionState.done:
                  // Future.delayed(Duration(milliseconds: 300), () {
                  //   if (context.mounted) {
                  //     Navigator.pushReplacementNamed(
                  //         context, HomeScreen.routeName);
                  //   }
                  // });
                  return _de1Picker(context);
              }
              return Text("Done");
            },
          ),
        ],
      ),
    );
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

  List<De1Interface> _discoveredDevices = [];

  late StreamSubscription<List<dev.Device>> _discoverySubscription;

  final Duration _timeoutDuration = Duration(seconds: 10);
  bool _timeoutReached = false;

  @override
  void initState() {
    _discoverySubscription =
        widget.deviceController.deviceStream.listen((data) {
      _discoveredDevices.clear();
      setState(() {
        _discoveredDevices.addAll(data.whereType<De1Interface>());
        _state = _discoveredDevices.length > 1
            ? DiscoveryState.foundMany
            : DiscoveryState.searching;
      });
      // If it took more than 10 seconds to find the first de1, or the second de1
      // appeared after the timeout,
      // connect to first one automatically
      // if (_timeoutReached && _discoveredDevices.isNotEmpty && mounted) {
      //   widget.de1controller.connectToDe1(_discoveredDevices.first);
      //   Navigator.popAndPushNamed(context, HomeScreen.routeName);
      // }
    });
    _discoveredDevices
        .addAll(widget.deviceController.devices.whereType<De1Interface>());
    super.initState();
    // If 10 seconds elapsed without finding a second de1, continue automatically
    Future.delayed(_timeoutDuration, () {
      _timeoutReached = true;
      if (mounted && _discoveredDevices.length == 1) {
        widget.de1controller.connectToDe1(_discoveredDevices.first);
        Navigator.popAndPushNamed(context, LandingFeature.routeName);
      } else if (mounted && _discoveredDevices.isEmpty) {
        Navigator.popAndPushNamed(context, HomeScreen.routeName);
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
          "Getting things ready",
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Widget _resultsView(BuildContext context) {
    return Column(
      spacing: 16,
      children: [
        Text(
          "Select De1 from the list",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Expanded(
          child: ListView.builder(
            itemBuilder: (context, index) {
              final de1 = _discoveredDevices[index];
              return TapRegion(
                child: SizedBox(
                  width: 200,
                  child: ShadCard(
                    title: Text(de1.name),
                    description: Text("Identifier: ${de1.deviceId}"),
                  ),
                ),
                onTapUpInside: (_) {
                  widget.de1controller.connectToDe1(de1);
                  Navigator.popAndPushNamed(context, LandingFeature.routeName);
                },
              );
            },
            itemCount: _discoveredDevices.length,
          ),
        ),
      ],
    );
  }
}

enum DiscoveryState {
  searching,
  foundOne,
  foundMany,
}
