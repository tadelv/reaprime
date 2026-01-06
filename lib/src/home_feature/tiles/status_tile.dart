import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/rinse_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/home_feature/forms/water_levels_form.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
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
            (steam, hotWater, rinse) => [steam, hotWater, rinse],
          ),
          builder: (context, settingsSnapshot) {
            if (settingsSnapshot.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var settings = settingsSnapshot.data!;
            var steamSettings = settings[0] as SteamSettings;
            var hotWaterSettings = settings[1] as HotWaterData;
            var rinseSettings = settings[2] as RinseData;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              spacing: 5,
              children: [
                SizedBox(
                  width: 90,
                  child: GestureDetector(
                    onTap: () async {
                      _showRinseSettingsDialog(context, controller);
                    },
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.showerHead,
                          size: 32.0,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("${rinseSettings.targetTemperature}℃"),
                            Text("${rinseSettings.duration}s"),
                            Text(
                              "${rinseSettings.flow.toStringAsFixed(1)}ml/s",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: GestureDetector(
                    onTap: () async {
                      _showHotWaterSettingsDialog(context, controller);
                    },
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.paintBucket,
                          size: 32.0,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("${hotWaterSettings.targetTemperature}℃"),
                            Text(
                              "${hotWaterSettings.volume}ml | ${hotWaterSettings.duration}s",
                            ),
                            Text(
                              "${hotWaterSettings.flow.toStringAsFixed(1)}ml/s",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: GestureDetector(
                    onTap: () async {
                      await _showSteamSettingsDialog(context, controller);
                    },
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.wind,
                          size: 32.0,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${steamSettings.flow.toStringAsFixed(1)}ml/s",
                            ),
                            Text("${steamSettings.targetTemperature}℃"),
                            Text("${steamSettings.duration}s"),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                ..._scaleWidgets(context),
              ],
            );
          },
        ),
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
      builder:
          (context) => ShadDialog(
            title: const Text('Edit Steam settings'),
            child: SteamForm(
              steamSettings: steamSettings,
              apply: (settings) {
                Navigator.of(context).pop();
                controller.updateSteamSettings(settings);
              },
            ),
          ),
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
      builder:
          (context) => ShadDialog(
            title: const Text('Edit Hot Water Settings'),
            child: HotWaterForm(
              hotWaterSettings: hotWaterSettings,
              apply: (settings) {
                Navigator.of(context).pop();
                controller.updateHotWaterSettings(settings);
              },
            ),
          ),
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
      builder:
          (context) => ShadDialog(
            title: const Text('Edit Flush Settings'),
            child: RinseForm(
              rinseSettings: rinseSettings,
              apply: (settings) {
                Navigator.of(context).pop();
                controller.updateFlushSettings(settings);
              },
            ),
          ),
    );
  }

  Future<void> _showWaterLevelsDialog(
    BuildContext context,
    De1Controller controller,
  ) async {
    var waterLevels = await controller.connectedDe1().waterLevels.first;
    if (!context.mounted) {
      return;
    }
    showShadDialog(
      context: context,
      builder:
          (context) => ShadDialog(
            title: const Text('Edit Water levels settings'),
            child: WaterLevelsForm(
              apply: (newLevels) {
                Navigator.of(context).pop();
                controller.connectedDe1().setWaterLevelWarning(
                  newLevels.warningThresholdPercentage,
                );
              },
              levels: waterLevels,
            ),
          ),
    );
  }

  List<Widget> _scaleWidgets(BuildContext context) {
    return [
      SizedBox(
        width: 110,
        child: Row(
          spacing: 8,
          children: [
            Icon(
              LucideIcons.scale,
              size: 32.0,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            StreamBuilder(
              stream: scaleController.connectionState,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.active ||
                    state.data! != device.ConnectionState.connected) {
                  // call device controller scan?
                  return GestureDetector(
                    onTap: () async {
                      await deviceController.scanForDevices(autoConnect: true);
                    },
                    child: Text("Waiting"),
                  );
                }
                return StreamBuilder(
                  stream: scaleController.weightSnapshot,
                  builder: (context, weight) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () {
                            scaleController.connectedScale().tare();
                          },
                          child: Text(
                            "W: ${weight.data?.weight.toStringAsFixed(1) ?? 0.0}g",
                          ),
                        ),
                        Text("B: ${weight.data?.battery}%"),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    ];
  }

  Widget _firstRow() {
    double boxWidth = 100;
    return Row(
      spacing: 5,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "DE1:",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.thermometer,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      Text("${snapshot.groupTemperature.toStringAsFixed(1)}℃"),
                    ],
                  ),
                ),
                SizedBox(
                  width: boxWidth,
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.wind,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      Text("${snapshot.steamTemperature}℃"),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        StreamBuilder(
          stream: de1.waterLevels,
          builder: (context, waterSnapshot) {
            if (waterSnapshot.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var snapshot = waterSnapshot.data!;
            final theme = Theme.of(context);
            return SizedBox(
              width: boxWidth,
              child: GestureDetector(
                onTap: () {
                  _showWaterLevelsDialog(context, controller);
                },
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.waves,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    Text(
                      "${snapshot.currentPercentage}%",
                      style: TextStyle(
                        color:
                            snapshot.currentPercentage > 50
                                ? theme.colorScheme.primary
                                : snapshot.currentPercentage > 20
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
