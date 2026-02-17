import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/widgets/device_connecting_indicator.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Reusable widget for displaying a list of discovered DE1 machines.
///
/// This is a pure display widget — it does not own connection state.
/// The parent is responsible for managing connection logic and passing
/// [connectingDeviceId] and [errorMessage] as props.
class DeviceSelectionWidget extends StatefulWidget {
  final DeviceController deviceController;
  final SettingsController? settingsController;
  final Function(De1Interface) onDeviceTapped;
  final bool showHeader;
  final String? headerText;
  final String? connectingDeviceId;
  final String? errorMessage;

  const DeviceSelectionWidget({
    super.key,
    required this.deviceController,
    required this.onDeviceTapped,
    this.settingsController,
    this.showHeader = false,
    this.headerText,
    this.connectingDeviceId,
    this.errorMessage,
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
    final isAnyConnecting = widget.connectingDeviceId != null;

    final listView = ListView.builder(
      shrinkWrap: true,
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        final de1 = _discoveredDevices[index];
        final isPreferred = preferredMachineId == de1.deviceId;
        final isConnecting = widget.connectingDeviceId == de1.deviceId;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: ShadCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(de1.name),
                  subtitle: Text("ID: ${de1.deviceId.length > 8 ? de1.deviceId.substring(de1.deviceId.length - 8) : de1.deviceId}"),
                  trailing: DeviceConnectingIndicator(
                    isConnecting: isConnecting,
                  ),
                  enabled: !isAnyConnecting,
                  onTap: isAnyConnecting
                      ? null
                      : () => widget.onDeviceTapped(de1),
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
          if (widget.errorMessage != null)
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
                          widget.errorMessage!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
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
        if (widget.errorMessage != null)
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
                        widget.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
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
