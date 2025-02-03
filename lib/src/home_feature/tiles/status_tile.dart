import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/sample_feature/sample_item_list_view.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class StatusTile extends StatelessWidget {
  final De1Interface de1;
  final De1Controller controller;
  final Scale? scale;
  const StatusTile(
      {super.key, required this.de1, required this.controller, this.scale});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _firstRow(),
        SizedBox(height: 8),
        StreamBuilder(
          stream: Rx.combineLatest2(controller.steamData,
              controller.hotWaterData, (steam, hotWater) => [steam, hotWater]),
          builder: (context, settingsSnapshot) {
            if (settingsSnapshot.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var settings = settingsSnapshot.data!;
            var steamSettings = settings[0] as De1ControllerSteamSettings;
            var hotWaterSettings = settings[1] as De1ControllerHotWaterData;
            return GestureDetector(
              onTap: () async {
                await _showShotSettingsDialog(context, controller);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                spacing: 5,
                children: [
                  Column(children: [
                    Text("HW: ${hotWaterSettings.targetTemperature}℃"),
                    Text(
                        "HW: ${hotWaterSettings.volume}ml | ${hotWaterSettings.duration}s"),
                    Text("HF: ${hotWaterSettings.flow}ml/s")
                  ]),
                  Column(children: [
                    Text("SF: ${steamSettings.flow.toStringAsFixed(1)}ml/s"),
                    Text("ST: ${steamSettings.targetTemperature}℃"),
                    Text("SD: ${steamSettings.duration}s"),
                  ]),
                ],
              ),
            );
          },
        ),
        if (scale != null)
          Text(
            "Scale",
            style: TextStyle(
              fontSize: 16,
              color: Colors.blueGrey,
            ),
          ),
        SizedBox(height: 8),
        Row(children: [
          _powerButton(),
          ShadButton.secondary(
            onPressed: () {
              Navigator.restorablePushNamed(
                  context, SampleItemListView.routeName);
            },
            child: Icon(
              LucideIcons.settings,
              color: Theme.of(context).colorScheme.primary,
            ),
          )
        ]),
      ],
    );
  }

  Future<void> _showShotSettingsDialog(
    BuildContext context,
    De1Controller controller,
  ) async {
    var steamSettings = await controller.steamSettings();
    if (!context.mounted) {
      return;
    }
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
          title: const Text('Edit Steam settings'),
          child: SteamForm(
            steamSettings: steamSettings,
            apply: (settings) {
              Navigator.of(context).pop();
              controller.updateSteamSettings(settings);
            },
          )),
    );
  }

  Widget _powerButton() {
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
  }

  Widget _firstRow() {
    double boxWidth = 100;
    return Row(spacing: 5, children: [
      Text(
        "DE1:",
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      StreamBuilder(
          stream: de1.currentSnapshot,
          builder: (context, snapshotData) {
            if (snapshotData.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var snapshot = snapshotData.data!;
            return Row(
                //mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                spacing: 50,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text("${snapshot.state.state.name}"),
                  ),
                  SizedBox(
                    width: boxWidth,
                    child: Text(
                        "Group: ${snapshot.groupTemperature.toStringAsFixed(1)}℃"),
                  ),
                  SizedBox(
                    width: boxWidth,
                    child: Text(
                        "Steam: ${snapshot.steamTemperature.toStringAsFixed(1)}℃"),
                  ),
                ]);
          }),
      StreamBuilder(
          stream: de1.waterLevels,
          builder: (context, waterSnapshot) {
            if (waterSnapshot.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var snapshot = waterSnapshot.data!;
            return Row(children: [
              SizedBox(
                width: boxWidth,
                child: Text("Water: ${snapshot.currentPercentage}%"),
              ),
            ]);
          })
    ]);
  }
}
