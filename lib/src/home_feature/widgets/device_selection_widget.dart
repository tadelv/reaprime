import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:shadcn_ui/shadcn_ui.dart';

/// Reusable widget for selecting a DE1 machine from a list of discovered devices.
/// 
/// This widget can be used in dialogs or as a standalone view. It automatically
/// updates as new devices are discovered and allows the user to select a device
/// to connect to.
/// 
/// Usage in a dialog:
/// ```dart
/// showShadDialog(
///   context: context,
///   builder: (context) => ShadDialog(
///     title: Text('Select DE1'),
///     child: DeviceSelectionWidget(
///       deviceController: deviceController,
///       de1Controller: de1Controller,
///       onDeviceSelected: (de1) {
///         Navigator.of(context).pop();
///       },
///     ),
///   ),
/// );
/// ```
/// 
/// Usage in a full-screen view:
/// ```dart
/// DeviceSelectionWidget(
///   deviceController: deviceController,
///   de1Controller: de1Controller,
///   showHeader: true,
///   onDeviceSelected: (de1) {
///     Navigator.of(context).pushNamed('/home');
///   },
/// );
/// ```
class DeviceSelectionWidget extends StatefulWidget {
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final Function(De1Interface) onDeviceSelected;
  final bool showHeader;
  final String? headerText;

  const DeviceSelectionWidget({
    super.key,
    required this.deviceController,
    required this.de1Controller,
    required this.onDeviceSelected,
    this.showHeader = false,
    this.headerText,
  });

  @override
  State<DeviceSelectionWidget> createState() => _DeviceSelectionWidgetState();
}

class _DeviceSelectionWidgetState extends State<DeviceSelectionWidget> {
  late StreamSubscription<List<dev.Device>> _discoverySubscription;
  List<De1Interface> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    
    // Get initial devices
    _discoveredDevices = widget.deviceController.devices
        .where((device) => device.type == dev.DeviceType.machine)
        .cast<De1Interface>()
        .toList();
    
    // Listen for additional devices discovered
    _discoverySubscription = widget.deviceController.deviceStream.listen((data) {
      if (mounted) {
        setState(() {
          _discoveredDevices = data
              .where((device) => device.type == dev.DeviceType.machine)
              .cast<De1Interface>()
              .toList();
        });
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
    if (_discoveredDevices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('No DE1 machines found. Please try scanning again.'),
        ),
      );
    }

    final listView = ListView.builder(
      shrinkWrap: true,
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        final de1 = _discoveredDevices[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: ShadCard(
            child: ListTile(
              title: Text(de1.name),
              subtitle: Text("ID: ${de1.deviceId}"),
              trailing: Icon(LucideIcons.chevronRight),
              onTap: () async {
                await widget.de1Controller.connectToDe1(de1);
                widget.onDeviceSelected(de1);
              },
            ),
          ),
        );
      },
    );

    if (widget.showHeader) {
      return Column(
        spacing: 16,
        children: [
          Text(
            widget.headerText ?? "Select DE1 from the list",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Expanded(child: listView),
        ],
      );
    }

    return SizedBox(
      height: 300,
      width: 400,
      child: listView,
    );
  }
}
