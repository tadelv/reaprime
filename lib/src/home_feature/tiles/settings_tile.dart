import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/home_feature/widgets/device_selection_widget.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/settings_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsTile extends StatefulWidget {
  final De1Controller controller;
  final DeviceController deviceController;

  const SettingsTile({
    super.key,
    required this.controller,
    required this.deviceController,
  });

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        _powerButton(),
        ShadButton.secondary(
          onPressed: () {
            Navigator.restorablePushNamed(context, SettingsView.routeName);
          },
          child: Icon(
            LucideIcons.settings,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Expanded(child: _auxFunctions()),
        Spacer(),
        ShadButton.secondary(
          onPressed: () async {
            // TODO: clean exit
            await (await widget.controller.de1.first)?.disconnect();
            exit(0);
          },
          child: Text("Quit"),
        ),
      ],
    );
  }

  Widget _powerButton() {
    return StreamBuilder<De1Interface?>(
      stream: widget.controller.de1,
      builder: (context, de1State) {
        // Check for active connection and non-null data
        if (!de1State.hasData || de1State.data == null) {
          if (_isScanning) {
            return ShadButton.secondary(
              onPressed: null,
              child: Row(
                spacing: 4,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Text("Scanning..."),
                ],
              ),
            );
          }
          return ShadButton.secondary(
            onPressed: () => _handleScan(context),
            child: Row(
              spacing: 4,
              children: [Icon(LucideIcons.radar, size: 16), Text("Scan")],
            ),
          );
        }
        var de1 = de1State.data!;
        return StreamBuilder(
          stream: de1.currentSnapshot,
          builder: (context, snapshotData) {
            if (snapshotData.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var snapshot = snapshotData.data!;
            if (snapshot.state.state == MachineState.sleeping) {
              return ShadButton.secondary(
                onPressed: () async {
                  await de1.requestState(MachineState.idle);
                },
                child: Icon(
                  LucideIcons.power,
                  color: Theme.of(context).colorScheme.primary,
                ),
              );
            }
            return ShadButton(
              onPressed: () async {
                await de1.requestState(MachineState.sleeping);
              },
              child: Icon(LucideIcons.power),
            );
          },
        );
      },
    );
  }

  Widget _auxFunctions() {
    return StreamBuilder<De1Interface?>(
      stream: widget.controller.de1,
      builder: (context, de1State) {
        // Check for active connection and non-null data
        if (!de1State.hasData || de1State.data == null) {
          return Text("Waiting to connect");
        }
        final de1 = de1State.data!;
        return StreamBuilder(
          stream: de1.currentSnapshot,
          builder: (context, snapshotData) {
            if (snapshotData.connectionState != ConnectionState.active) {
              return SizedBox();
            }
            var snapshot = snapshotData.data!;
            if (snapshot.state.state == MachineState.idle) {
              return Row(
                spacing: 8,
                children: [
                  ShadButton.secondary(
                    onPressed: () async {
                      await de1.requestState(MachineState.steamRinse);
                    },
                    child: Text("Steam rinse"),
                  ),
                  ShadButton.secondary(
                    onPressed: () async {
                      _showDialog(context, AuxDialogType.clean, de1);
                    },
                    child: Text("Clean"),
                  ),
                  ShadButton.secondary(
                    onPressed: () async {
                      _showDialog(context, AuxDialogType.descale, de1);
                    },
                    child: Text("Descale"),
                  ),
                ],
              );
            }
            if (snapshot.state.state == MachineState.sleeping) {
              return SizedBox();
            }
            return Row(
              spacing: 8,
              children: [
                ShadButton(
                  onPressed: () async {
                    await de1.requestState(MachineState.idle);
                  },
                  child: Text("Cancel ${snapshot.state.state.name}"),
                ),
                Text(
                  "${snapshot.state.state.name} status: ${snapshot.state.substate.name}",
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDialog(BuildContext context, AuxDialogType type, Machine de1) {
    final title =
        type == AuxDialogType.clean ? 'Clean Machine' : 'Descale Machine';
    final description =
        type == AuxDialogType.clean
            ? 'Cleaning instructions'
            : 'Descaling instructions';

    showDialog(
      context: context,
      builder:
          (context) => ShadDialog(
            title: Text(title),
            description: Text(description),
            actions: [
              ShadButton.outline(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('Cancel'),
              ),
              ShadButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Transition to appropriate state based on dialog type
                  final targetState =
                      type == AuxDialogType.clean
                          ? MachineState.cleaning
                          : MachineState.descaling;
                  await de1.requestState(targetState);
                },
                child: Text('Start'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  type == AuxDialogType.descale
                      ? _descalingBody(context)
                      : _cleaningBody(context),
            ),
          ),
    );
  }

  List<Widget> _descalingBody(BuildContext context) {
    return [
      // Text(
      //   'Instructions:',
      //   style: TextStyle(fontWeight: FontWeight.bold),
      // ),
      ShadButton.link(
        child: Text("Follow the guide on Basecamp"),
        onPressed: () async {
          //
          final url = Uri.parse(
            'https://3.basecamp.com/3671212/buckets/7351439/documents/7743429669#__recording_9357315560',
          );
          await launchUrl(url);
        },
      ),
      Text("- Use a 5% citric acid solution"),
      Text("- Remove drip tray cover"),
      Text("- Remove the portafilter"),
      Text("- Remove the steam wand tip"),
      SizedBox(height: 8),
      Text('1. Prepare the machine as instructed above'),
      Text('2. Press Start to begin the process'),
      Text('3. The machine will transition to the appropriate state'),
    ];
  }

  List<Widget> _cleaningBody(BuildContext context) {
    return [
      Text("Prepare blind basket"),
      Text("Add cafiza if needed"),
      Text('2. Press Start to begin the process'),
      Text('3. The machine will transition to the appropriate state'),
    ];
  }

  Future<void> _handleScan(BuildContext context) async {
    // Step 1: Check if DE1 controller already has a connected device
    final currentDe1 = await widget.controller.de1.first;
    if (currentDe1 != null) {
      final connectionState = await currentDe1.connectionState.first;
      if (connectionState == dev.ConnectionState.connected) {
        // Already connected, nothing to do
        setState(() {});
        return;
      }
    }

    // Step 2: Check if there are already discovered DE1 devices in DeviceController
    List<De1Interface> de1Machines =
        widget.deviceController.devices
            .where((device) => device.type == dev.DeviceType.machine)
            .cast<De1Interface>()
            .toList();

    if (de1Machines.isNotEmpty) {
      // Found available DE1(s), connect to first one
      // TODO: In the future, check for preferred machine ID here
      final de1 = de1Machines.first;
      await widget.controller.connectToDe1(de1);
      return;
    }

    // Step 3: No DE1 available, trigger device scan
    setState(() {
      _isScanning = true;
    });

    try {
      // Trigger scan
      await widget.deviceController.scanForDevices(autoConnect: false);

      // Wait for devices to be discovered and interrogated (10 seconds)
      // DE1 machines need to be connected to and interrogated for model type
      await Future.delayed(Duration(seconds: 10));

      // Get all DE1 machines
      de1Machines =
          widget.deviceController.devices
              .where((device) => device.type == dev.DeviceType.machine)
              .cast<De1Interface>()
              .toList();

      if (!context.mounted) return;

      if (de1Machines.isEmpty) {
        // No DE1s found, show message
        showShadDialog(
          context: context,
          builder:
              (context) => ShadDialog(
                title: Text('No DE1 Found'),
                description: Text(
                  'No DE1 machines were found during the scan. Make sure your DE1 is powered on and Bluetooth is enabled.',
                ),
                actions: [
                  ShadButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('OK'),
                  ),
                ],
              ),
        );
      } else if (de1Machines.length == 1) {
        // Single DE1 found, auto-connect
        final de1 = de1Machines.first;
        await widget.controller.connectToDe1(de1);
      } else {
        // Multiple DE1s found, show selection dialog
        // TODO: In the future, filter by preferred machine ID
        showShadDialog(
          context: context,
          builder:
              (context) => ShadDialog(
                title: Text('Select DE1'),
                description: Text(
                  'Multiple DE1 machines found. Select one to connect:',
                ),
                child: DeviceSelectionWidget(
                  deviceController: widget.deviceController,
                  de1Controller: widget.controller,
                  onDeviceSelected: (de1) {
                    Navigator.of(context).pop();
                  },
                ),
              ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }
}

enum AuxDialogType { clean, descale }
