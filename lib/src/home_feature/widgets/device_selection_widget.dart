import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/widgets/device_connecting_indicator.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:shadcn_ui/shadcn_ui.dart';

/// Reusable widget for displaying a list of discovered devices of a given type.
///
/// This is a pure display widget — it does not own connection state.
/// The parent is responsible for managing connection logic and passing
/// [connectingDeviceId] and [errorMessage] as props.
class DeviceSelectionWidget extends StatefulWidget {
  final DeviceController deviceController;
  final dev.DeviceType deviceType;
  final Function(dev.Device) onDeviceTapped;
  final String? selectedDeviceId;
  final String? preferredDeviceId;
  final Function(String?)? onPreferredChanged;
  final bool showHeader;
  final String? headerText;
  final String? connectingDeviceId;
  final String? errorMessage;

  const DeviceSelectionWidget({
    super.key,
    required this.deviceController,
    required this.deviceType,
    required this.onDeviceTapped,
    this.selectedDeviceId,
    this.preferredDeviceId,
    this.onPreferredChanged,
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
  List<dev.Device> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();

    // Get initial devices
    _discoveredDevices =
        widget.deviceController.devices
            .where((device) => device.type == widget.deviceType)
            .toList();

    // Listen for additional devices discovered
    _discoverySubscription = widget.deviceController.deviceStream.listen((
      data,
    ) {
      if (mounted) {
        setState(() {
          _discoveredDevices =
              data
                  .where((device) => device.type == widget.deviceType)
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
      final label = widget.deviceType == dev.DeviceType.machine
          ? 'machines'
          : 'scales';
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('No $label found. Please try scanning again.'),
        ),
      );
    }

    final isAnyConnecting = widget.connectingDeviceId != null;

    final listView = ListView.builder(
      shrinkWrap: true,
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        final device = _discoveredDevices[index];
        final isPreferred = widget.preferredDeviceId == device.deviceId;
        final isConnecting = widget.connectingDeviceId == device.deviceId;
        final isSelected = widget.selectedDeviceId == device.deviceId;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
          child: ShadCard(
            border: isSelected
                ? ShadBorder.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(device.name),
                  subtitle: Text("ID: ${device.deviceId.length > 8 ? device.deviceId.substring(device.deviceId.length - 8) : device.deviceId}"),
                  trailing: DeviceConnectingIndicator(
                    isConnecting: isConnecting,
                  ),
                  enabled: !isAnyConnecting,
                  onTap: isAnyConnecting
                      ? null
                      : () => widget.onDeviceTapped(device),
                ),
                if (widget.onPreferredChanged != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8.0,
                      right: 8.0,
                      bottom: 4.0,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isPreferred,
                          onChanged: (value) {
                            widget.onPreferredChanged?.call(
                              value == true ? device.deviceId : null,
                            );
                            setState(() {});
                          },
                        ),
                        Expanded(
                          child: Text(
                            widget.deviceType == dev.DeviceType.machine
                                ? 'Auto-connect to this machine'
                                : 'Auto-connect to this scale',
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
        spacing: 8,
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
