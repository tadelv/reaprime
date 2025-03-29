import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';

class PermissionsView extends StatelessWidget {
  final DeviceController deviceController;

  final De1Controller de1controller;

  const PermissionsView(
      {super.key, required this.deviceController, required this.de1controller});

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
        children: [
          Text('REAPrime is starting ...'),
          FutureBuilder(
            future: checkPermissions(),
            builder: (context, result) {
              switch (result.connectionState) {
                case ConnectionState.none:
                  return Text("Unknown");
                case ConnectionState.waiting:
                  return Text("Checking");
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
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetooth.request();
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
      await deviceController.initialize();
    } else {
      await FlutterBluePlus.isSupported;
      await FlutterBluePlus.adapterState
          .firstWhere((e) => e == BluetoothAdapterState.on);
      await deviceController.initialize();
    }
    return true;
  }

  Widget _de1Picker(BuildContext context) {
    deviceController.scanForDevices();
    return Text("Waiting for devices to be discovered ...");
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
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}
