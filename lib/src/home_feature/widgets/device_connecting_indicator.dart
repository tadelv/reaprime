import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Reusable widget for displaying connection progress indicator
///
/// This widget is used in device selection lists to show when a device
/// is in the process of connecting. It displays a small circular progress
/// indicator that replaces the normal trailing icon.
///
/// Usage:
/// ```dart
/// trailing: DeviceConnectingIndicator(
///   isConnecting: _connectingDeviceId == device.deviceId,
/// ),
/// ```
class DeviceConnectingIndicator extends StatelessWidget {
  final bool isConnecting;

  const DeviceConnectingIndicator({super.key, required this.isConnecting});

  @override
  Widget build(BuildContext context) {
    if (isConnecting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return const Icon(LucideIcons.chevronRight);
  }
}
