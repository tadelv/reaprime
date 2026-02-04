import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/widgets/device_connecting_indicator.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/settings/settings_controller.dart';
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
  final SettingsController? settingsController;
  final Function(De1Interface) onDeviceSelected;
  final bool showHeader;
  final String? headerText;
  final String? autoConnectingDeviceId;

  const DeviceSelectionWidget({
    super.key,
    required this.deviceController,
    required this.de1Controller,
    this.settingsController,
    required this.onDeviceSelected,
    this.showHeader = false,
    this.headerText,
    this.autoConnectingDeviceId,
  });

  @override
  State<DeviceSelectionWidget> createState() => _DeviceSelectionWidgetState();
}

class _DeviceSelectionWidgetState extends State<DeviceSelectionWidget> {
  late StreamSubscription<List<dev.Device>> _discoverySubscription;
  List<De1Interface> _discoveredDevices = [];
  String? _connectingDeviceId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // Get initial devices
    _discoveredDevices =
        widget.deviceController.devices
            .where((device) => device.type == dev.DeviceType.machine)
            .cast<De1Interface>()
            .toList();

    // Listen for additional devices discovered
    _discoverySubscription = widget.deviceController.deviceStream.listen((
      data,
    ) {
      if (mounted) {
        setState(() {
          _discoveredDevices =
              data
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
          child: Text('No machines found. Please try scanning again.'),
        ),
      );
    }

    final preferredMachineId = widget.settingsController?.preferredMachineId;

    final listView = ListView.builder(
      shrinkWrap: true,
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        final de1 = _discoveredDevices[index];
        final isPreferred = preferredMachineId == de1.deviceId;
        final isAutoConnecting = widget.autoConnectingDeviceId == de1.deviceId;
        final isManualConnecting = _connectingDeviceId == de1.deviceId;
        final isConnecting = isAutoConnecting || isManualConnecting;
        final isAnyConnecting =
            widget.autoConnectingDeviceId != null ||
            _connectingDeviceId != null;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: ShadCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(de1.name),
                  subtitle: Text("ID: ${de1.deviceId}"),
                  trailing: DeviceConnectingIndicator(
                    isConnecting: isConnecting,
                  ),
                  enabled: !isAnyConnecting,
                  onTap:
                      isAnyConnecting
                          ? null
                          : () async {
                            setState(() {
                              _connectingDeviceId = de1.deviceId;
                              _errorMessage = null;
                            });

                            try {
                              await widget.de1Controller.connectToDe1(de1);
                              if (mounted) {
                                widget.onDeviceSelected(de1);
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _connectingDeviceId = null;
                                  _errorMessage = 'Failed to connect: $e';
                                });
                              }
                            }
                          },
                ),
                if (widget.settingsController != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isPreferred,
                          onChanged: (value) async {
                            if (value == true) {
                              await widget.settingsController!
                                  .setPreferredMachineId(de1.deviceId);
                            } else {
                              await widget.settingsController!
                                  .setPreferredMachineId(null);
                            }
                            setState(() {});
                          },
                        ),
                        Expanded(
                          child: Text(
                            'Auto-connect to this machine',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.showHeader) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Text(
            widget.headerText ?? "Select a machine from the list",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ShadCard(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.info,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(LucideIcons.x, size: 16),
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          listView,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ShadCard(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.info,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.x, size: 16),
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        SizedBox(height: 300, width: 400, child: listView),
      ],
    );
  }
}

