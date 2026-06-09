import 'package:flutter/material.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/settings/common.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:reaprime/src/services/foreground_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:io';

import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/gateway_mode_info_dialog.dart';

class AdvancedPage extends StatelessWidget {
  const AdvancedPage({
    super.key,
    required this.controller,
  });

  static const routeName = '/advanced';

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return ListView(
            children: [
              // Log Level
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text('Log Level')),
                    DropdownButton<String>(
                      value: controller.logLevel,
                      onChanged: controller.updateLogLevel,
                      items: const [
                        DropdownMenuItem(value: 'FINE', child: Text('Fine')),
                        DropdownMenuItem(value: 'INFO', child: Text('Info')),
                        DropdownMenuItem(
                          value: 'FINEST',
                          child: Text('Finest'),
                        ),
                        DropdownMenuItem(
                          value: 'WARNING',
                          child: Text('Warning'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SettingsDivider(),

              SettingsTile(
                icon: Icons.settings_remote_outlined,
                label: 'Gateway Mode',
                trailing: Text(_gatewayModeLabel(controller.gatewayMode)),
                onTap: () => _showGatewayModePicker(context),
              ),
              const SettingsDivider(),

              // Simulated devices
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'Simulated Devices',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final type in SimulatedDevicesTypes.values)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ShadSwitch(
                    value: controller.simulatedDevices.contains(type),
                    onChanged: (v) async {
                      final current = Set<SimulatedDevicesTypes>.from(
                        controller.simulatedDevices,
                      );
                      if (v) {
                        current.add(type);
                      } else {
                        current.remove(type);
                      }
                      await controller.setSimulatedDevices(current);
                    },
                    label: Text(
                      type.name[0].toUpperCase() + type.name.substring(1),
                    ),
                  ),
                ),
              const SettingsDivider(),

              // Exit
              if (!BuildInfo.appStore)
                ListTile(
                  leading: Icon(
                    LucideIcons.logOut,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Exit Decent',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    if (Platform.isAndroid) {
                      ForegroundTaskService.stop();
                    }
                    exit(0);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  static String _gatewayModeLabel(GatewayMode mode) {
    switch (mode) {
      case GatewayMode.full:
        return 'Full';
      case GatewayMode.tracking:
        return 'Tracking';
      case GatewayMode.disabled:
        return 'Disabled';
    }
  }

  void _showGatewayModePicker(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (dialogContext) {
        return ShadDialog(
          title: const Text('Gateway Mode'),
          description: const Text(
            'Control how external clients interact with the machine',
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                showGatewayModeInfoDialog(context);
              },
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Learn more'),
            ),
          ],
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...GatewayMode.values.map((mode) {
                  String subtitle;
                  switch (mode) {
                    case GatewayMode.full:
                      subtitle = 'App has no control';
                    case GatewayMode.tracking:
                      subtitle =
                          'App will stop shot if target weight is reached';
                    case GatewayMode.disabled:
                      subtitle = 'App has full control';
                  }
                  return ListTile(
                    title: Text(
                      mode.name[0].toUpperCase() + mode.name.substring(1),
                    ),
                    subtitle: Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: controller.gatewayMode == mode
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      controller.updateGatewayMode(mode);
                      Navigator.of(dialogContext).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
