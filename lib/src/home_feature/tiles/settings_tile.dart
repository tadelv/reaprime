import 'package:flutter/cupertino.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/settings_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  final De1Controller controller;

  const SettingsTile({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _powerButton(),
      ShadButton.secondary(
        onPressed: () {
          Navigator.restorablePushNamed(
            context,
            SettingsView.routeName,
          );
        },
        child: Icon(
          LucideIcons.settings,
          color: Theme.of(context).colorScheme.primary,
        ),
      )
    ]);
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
              });
        });
  }
}
