import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/sample_feature/sample_item_details_view.dart';
import 'package:reaprime/src/sample_feature/scale_debug_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart' hide Scale;

/// Displays a list of discovered devices with Inspect and Connect actions.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Items'),
        actions: [
          IconButton(
            onPressed: () async {
              await controller.scanForDevices();
            },
            icon: const Icon(LucideIcons.radar),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: controller.deviceStream,
        builder: (buildContext, data) {
          return ListView.builder(
            restorationId: 'sampleItemListView',
            itemCount: data.data?.length ?? 0,
            itemBuilder: (BuildContext context, int index) {
              final item = controller.devices[index];

              return ListTile(
                title:
                    Text('${item.type.name} ${item.name} : ${item.deviceId}'),
                leading: StreamBuilder(
                  stream: item.connectionState,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.active) {
                      switch (snapshot.data) {
                        case dev.ConnectionState.connected:
                          return Icon(LucideIcons.check);
                        case dev.ConnectionState.disconnected:
                          return Icon(LucideIcons.cross);
                        default:
                          return Icon(LucideIcons.user);
                      }
                    } else {
                      return Icon(LucideIcons.scanEye);
                    }
                  },
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      child: const Text('Inspect'),
                      onPressed: () {
                        _navigateToDebugView(context, item, inspect: true);
                      },
                    ),
                    const SizedBox(width: 8),
                    ShadButton(
                      size: ShadButtonSize.sm,
                      child: const Text('Connect'),
                      onPressed: () async {
                        if (item is De1Interface) {
                          await connectionManager.connectMachine(item);
                        } else if (item is Scale) {
                          await connectionManager.connectScale(item);
                        }
                        if (!context.mounted) return;
                        _navigateToDebugView(context, item, inspect: false);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
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
