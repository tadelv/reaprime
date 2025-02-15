import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/rinse_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/sample_feature/sample_item_list_view.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class StatusTile extends StatelessWidget {
  final De1Interface de1;
  final De1Controller controller;
  final ScaleController scaleController;
  final DeviceController deviceController;
  const StatusTile({
    super.key,
    required this.de1,
    required this.controller,
    required this.scaleController,
    required this.deviceController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _firstRow(),
        SizedBox(height: 8),
        StreamBuilder(
          stream: Rx.combineLatest3(
              controller.steamData,
              controller.hotWaterData,
              controller.rinseData,
              (steam, hotWater, rinse) => [steam, hotWater, rinse]),
          builder: (context, settingsSnapshot) {
            if (settingsSnapshot.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var settings = settingsSnapshot.data!;
            var steamSettings = settings[0] as De1ControllerSteamSettings;
            var hotWaterSettings = settings[1] as De1ControllerHotWaterData;
            var rinseSettings = settings[2] as De1ControllerRinseData;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              spacing: 5,
              children: [
                GestureDetector(
                  onTap: () async {
                    _showRinseSettingsDialog(context, controller);
                  },
                  child: Column(children: [
                    Text("FT: ${rinseSettings.targetTemperature}℃"),
                    Text("FD: ${rinseSettings.duration}s"),
                    Text("FF: ${rinseSettings.flow.toStringAsFixed(1)}ml/s")
                  ]),
                ),
                GestureDetector(
                  onTap: () async {
                    _showHotWaterSettingsDialog(context, controller);
                  },
                  child: Column(children: [
                    Text("HW: ${hotWaterSettings.targetTemperature}℃"),
                    Text(
                        "HW: ${hotWaterSettings.volume}ml | ${hotWaterSettings.duration}s"),
                    Text("HF: ${hotWaterSettings.flow.toStringAsFixed(1)}ml/s")
                  ]),
                ),
                GestureDetector(
                  onTap: () async {
                    await _showSteamSettingsDialog(context, controller);
                  },
                  child: Column(children: [
                    Text("SF: ${steamSettings.flow.toStringAsFixed(1)}ml/s"),
                    Text("ST: ${steamSettings.targetTemperature}℃"),
                    Text("SD: ${steamSettings.duration}s"),
                  ]),
                ),
                ..._scaleWidgets(),
              ],
            );
          },
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

  Future<void> _showSteamSettingsDialog(
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

  Future<void> _showHotWaterSettingsDialog(
    BuildContext context,
    De1Controller controller,
  ) async {
    var hotWaterSettings = await controller.hotWaterSettings();
    if (!context.mounted) {
      return;
    }
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
          title: const Text('Edit Hot Water settings'),
          child: HotWaterForm(
            hotWaterSettings: hotWaterSettings,
            apply: (settings) {
              Navigator.of(context).pop();
              controller.updateHotWaterSettings(settings);
            },
          )),
    );
  }

  Future<void> _showRinseSettingsDialog(
    BuildContext context,
    De1Controller controller,
  ) async {
    var rinseSettings = await controller.rinseData.first;
    if (!context.mounted) {
      return;
    }
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
          title: const Text('Edit Hot Water settings'),
          child: RinseForm(
            rinseSettings: rinseSettings,
            apply: (settings) {
              Navigator.of(context).pop();
              controller.updateFlushSettings(settings);
            },
          )),
    );
  }

  List<Widget> _scaleWidgets() {
    return [
      StreamBuilder(
          stream: scaleController.connectionState,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.active ||
                state.data! != device.ConnectionState.connected) {
// call device controller scan?
              return GestureDetector(
                  onTap: () async {
                    await deviceController.scanForDevices();
                  },
                  child: Text("Waiting"));
            }
            return StreamBuilder(
                stream: scaleController.weightSnapshot,
                builder: (context, weight) {
                  return Column(children: [
                    GestureDetector(
                        onTap: () {
                          scaleController.connectedScale().tare();
                        },
                        child: Text(
                            "W: ${weight.data?.weight.toStringAsFixed(1) ?? 0.0}g")),
                  ]);
                });
          })
    ];
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
                    child: Text("Steam: ${snapshot.steamTemperature}℃"),
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
                child: Text(
                  "Water: ${snapshot.currentPercentage}%",
                  style: TextStyle(
                    color: snapshot.currentPercentage > 50
                        ? Colors.green
                        : snapshot.currentPercentage > 20
                            ? Colors.yellowAccent
                            : Colors.redAccent,
                  ),
                ),
              ),
            ]);
          })
    ]);
  }
}
