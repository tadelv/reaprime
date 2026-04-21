import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/settings_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsTile extends StatefulWidget {
  final De1Controller controller;
  final ConnectionManager connectionManager;

  const SettingsTile({
    super.key,
    required this.controller,
    required this.connectionManager,
  });

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      explicitChildNodes: true,
      label: 'Machine controls',
      child: Row(
      spacing: 8,
      children: [
        _powerButton(),
        Semantics(
          button: true,
          label: 'Open settings',
          child: ExcludeSemantics(
            child: ShadButton.secondary(
              onPressed: () {
                Navigator.restorablePushNamed(context, SettingsView.routeName);
              },
              child: Icon(
                LucideIcons.settings,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        Expanded(child: _auxFunctions()),
      ],
    ),
    );
  }

  Widget _powerButton() {
    return StreamBuilder<De1Interface?>(
      stream: widget.controller.de1,
      builder: (context, de1State) {
        // Check for active connection and non-null data
        if (!de1State.hasData || de1State.data == null) {
          if (_isScanning) {
            return Semantics(
              label: 'Scanning for machine',
              child: ExcludeSemantics(
                child: ShadButton.secondary(
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
                ),
              ),
            );
          }
          return MergeSemantics(
            child: ShadButton.secondary(
              onPressed: () => _handleScan(context),
              child: Row(
                spacing: 4,
                children: [
                  ExcludeSemantics(child: Icon(LucideIcons.radar, size: 16)),
                  Text("Scan"),
                ],
              ),
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
              return Semantics(
                button: true,
                label: 'Turn on machine',
                child: ExcludeSemantics(
                  child: ShadButton.secondary(
                    onPressed: () async {
                      await de1.requestState(MachineState.idle);
                    },
                    child: Icon(
                      LucideIcons.power,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              );
            }
            return Semantics(
              button: true,
              label: 'Put machine to sleep',
              child: ExcludeSemantics(
                child: ShadButton(
                  onPressed: () async {
                    await de1.requestState(MachineState.sleeping);
                  },
                  child: Icon(LucideIcons.power),
                ),
              ),
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

    showShadDialog(
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
    setState(() => _isScanning = true);
    try {
      await widget.connectionManager.connect();
    } catch (_) {
      // Connection errors surface via the ConnectionManager status stream
      // (banner / status tile). Nothing to do here.
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
    if (!context.mounted) return;
    final status = widget.connectionManager.currentStatus;
    if (status.pendingAmbiguity == AmbiguityReason.machinePicker) {
      _showMachinePicker(context, status.foundMachines);
    }
  }

  void _showMachinePicker(
    BuildContext context,
    List<De1Interface> machines,
  ) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Select Machine'),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: machines
                .map(
                  (machine) => ListTile(
                    title: Text(machine.name),
                    subtitle: Text(machine.deviceId),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.connectionManager.connectMachine(machine);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

enum AuxDialogType { clean, descale }
