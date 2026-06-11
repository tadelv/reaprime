import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/debug_feature/sample_item_details_view.dart';
import 'package:reaprime/src/debug_feature/scale_debug_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart' hide Scale;

/// Displays a list of discovered devices grouped by type, with Inspect and
/// Connect actions.
class SampleItemListView extends StatelessWidget {
  const SampleItemListView({
    super.key,
    required this.controller,
    required this.connectionManager,
  });

  static const routeName = '/debug';

  final DeviceController controller;
  final ConnectionManager connectionManager;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: controller.scanningStream,
      initialData: controller.isScanning,
      builder: (context, scanningSnapshot) {
        final isScanning = scanningSnapshot.data ?? false;

        return StreamBuilder<List<dev.Device>>(
          stream: controller.deviceStream,
          builder: (context, deviceSnapshot) {
            final devices = deviceSnapshot.data ?? [];
            final isEmpty = devices.isEmpty && !isScanning;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, devices.length, isScanning),
                if (isScanning) const ShadProgress(),
                Expanded(
                  child: isEmpty
                      ? _buildEmptyState(context)
                      : _buildGroupedList(context, devices),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Header row with title, device count, and scan button.
  Widget _buildHeader(BuildContext context, int count, bool isScanning) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            'Debug Devices',
            style: theme.textTheme.h4,
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            ShadBadge(
              child: Text('$count'),
            ),
          ],
          const Spacer(),
          if (isScanning)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Scanning…', style: theme.textTheme.muted),
              ],
            )
          else
            ShadButton.ghost(
              leading: const Icon(LucideIcons.radar, size: 16),
              child: const Text('Scan'),
              onPressed: () => controller.scanForDevices(),
            ),
        ],
      ),
    );
  }

  /// Empty state shown when no devices are discovered and not scanning.
  Widget _buildEmptyState(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.radar, size: 48, color: theme.colorScheme.mutedForeground),
            const SizedBox(height: 16),
            Text(
              'No devices discovered',
              style: theme.textTheme.p,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap Scan to search for nearby devices',
              style: theme.textTheme.muted,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the device list grouped by [dev.DeviceType].
  Widget _buildGroupedList(BuildContext context, List<dev.Device> devices) {
    final machines = devices.whereType<De1Interface>().toList();
    final scales = devices.whereType<Scale>().toList();
    final sensors = devices
        .where((d) => d.type != dev.DeviceType.machine && d.type != dev.DeviceType.scale)
        .toList();

    return ListView(
      children: [
        if (machines.isNotEmpty) ...[
          _buildSectionHeader(context, 'Machines'),
          ...machines.map((m) => _buildDeviceRow(context, m)),
        ],
        if (scales.isNotEmpty) ...[
          _buildSectionHeader(context, 'Scales'),
          ...scales.map((s) => _buildDeviceRow(context, s)),
        ],
        if (sensors.isNotEmpty) ...[
          _buildSectionHeader(context, 'Sensors'),
          ...sensors.map((s) => _buildDeviceRow(context, s, showConnect: false)),
        ],
      ],
    );
  }

  /// Section header for a device type group.
  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.small.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }

  /// A single device row with connection-state icon, name, and action buttons.
  Widget _buildDeviceRow(
    BuildContext context,
    dev.Device device, {
    bool showConnect = true,
  }) {
    final theme = ShadTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _navigateToDebugView(context, device, inspect: true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              StreamBuilder<dev.ConnectionState>(
                stream: device.connectionState,
                builder: (context, snapshot) {
                  final cs = snapshot.data;
                  IconData icon;
                  Color? color;
                  if (cs == dev.ConnectionState.connected) {
                    icon = LucideIcons.check;
                    color = theme.colorScheme.primary;
                  } else if (cs == dev.ConnectionState.disconnected) {
                    icon = LucideIcons.x;
                    color = theme.colorScheme.mutedForeground;
                  } else {
                    icon = LucideIcons.scanEye;
                    color = theme.colorScheme.mutedForeground;
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(icon, size: 18, color: color),
                  );
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.name,
                      style: theme.textTheme.small,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      device.deviceId,
                      style: theme.textTheme.muted.copyWith(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                child: const Text('Inspect'),
                onPressed: () =>
                    _navigateToDebugView(context, device, inspect: true),
              ),
              if (showConnect) ...[
                const SizedBox(width: 6),
                ShadButton(
                  size: ShadButtonSize.sm,
                  child: const Text('Connect'),
                  onPressed: () => _onConnect(context, device),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onConnect(BuildContext context, dev.Device device) async {
    try {
      if (device is De1Interface) {
        await connectionManager.connectMachine(device);
      } else if (device is Scale) {
        await connectionManager.connectScale(device);
      }
    } catch (_) {
      // Error already surfaced by ConnectionManager via its status stream.
      // Swallow here so the rethrow doesn't escape the async onPressed
      // into the Flutter error zone (→ Crashlytics fatal).
    }
    if (!context.mounted) return;
    _navigateToDebugView(context, device, inspect: false);
  }

  void _navigateToDebugView(
    BuildContext context,
    dev.Device device, {
    required bool inspect,
  }) {
    if (device is De1Interface) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => De1DebugView(
            machine: device,
            inspect: inspect,
          ),
        ),
      );
    } else if (device is Scale) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScaleDebugView(
            scale: device,
            inspect: inspect,
          ),
        ),
      );
    }
  }
}
