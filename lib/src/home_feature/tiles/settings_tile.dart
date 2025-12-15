import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/settings_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  final De1Controller controller;

  const SettingsTile({super.key, required this.controller});

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
        _auxFunctions(),
      ],
    );
  }

  Widget _powerButton() {
    return StreamBuilder(
      stream: controller.de1,
      builder: (context, de1State) {
        if (de1State.connectionState != ConnectionState.active ||
            de1State.data == null) {
          return Text("Waiting to connect");
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
    return StreamBuilder(
      stream: controller.de1,
      builder: (context, de1State) {
        if (de1State.connectionState != ConnectionState.active ||
            de1State.data == null) {
          return Text("Waiting to connect");
        }
        var de1 = de1State.data!;
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
                  Spacer(),
                  ShadButton.secondary(
                    onPressed: () async {
                      // TODO: clean exit
                      await (await controller.de1.first)?.disconnect();
                      exit(0);
                    },
                    child: Text("Quit"),
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
              children: [
                Text(
                  'Instructions:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('1. Prepare the machine as instructed above'),
                Text('2. Press Start to begin the process'),
                Text('3. The machine will transition to the appropriate state'),
              ],
            ),
          ),
    );
  }
}

enum AuxDialogType { clean, descale }
