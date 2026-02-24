import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/rinse_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/home_feature/forms/water_levels_form.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class StatusTile extends StatefulWidget {
  final De1Interface de1;
  final De1Controller controller;
  final ScaleController scaleController;
  final DeviceController deviceController;
  final WorkflowController workflowController;
  const StatusTile({
    super.key,
    required this.de1,
    required this.controller,
    required this.scaleController,
    required this.deviceController,
    required this.workflowController,
  });

  @override
  State<StatusTile> createState() => _StatusTileState();
}

class _StatusTileState extends State<StatusTile> {
  MachineSnapshot? _machineSnapshot;
  WeightSnapshot? _weightSnapshot;
  De1WaterLevels? _waterLevels;
  StreamSubscription? _tickSub;

  // Cache the combined settings stream so it isn't recreated on every build.
  late final Stream<List<dynamic>> _settingsStream;

  @override
  void initState() {
    super.initState();
    _settingsStream = Rx.combineLatest3(
      widget.controller.steamData,
      widget.controller.hotWaterData,
      widget.controller.rinseData,
      (steam, hotWater, rinse) => [steam, hotWater, rinse],
    );
    // Merge all high-frequency streams into one tick, throttle once.
    // Each source updates its cached value; the throttled merge triggers
    // a single synchronized setState at ~10Hz.
    _tickSub = Rx.merge([
      widget.de1.currentSnapshot.map((s) { _machineSnapshot = s; }),
      widget.scaleController.weightSnapshot.map((w) { _weightSnapshot = w; }),
      widget.de1.waterLevels.map((w) { _waterLevels = w; }),
    ]).throttleTime(const Duration(milliseconds: 100)).listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _firstRow(),
        SizedBox(height: 8),
        StreamBuilder(
          stream: _settingsStream,
          builder: (context, settingsSnapshot) {
            if (settingsSnapshot.connectionState != ConnectionState.active ||
                !settingsSnapshot.hasData) {
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
                      _showRinseSettingsDialog(context, widget.controller);
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
                      _showHotWaterSettingsDialog(context, widget.controller);
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
                      await _showSteamSettingsDialog(
                        context,
                        widget.controller,
                      );
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
                widget.workflowController.updateWorkflow(
                  steamSettings: SteamSettings(
                    targetTemperature: settings.targetTemp,
                    duration: settings.targetDuration,
                    flow: settings.targetFlow,
                  ),
                );
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
                widget.workflowController.updateWorkflow(
                  hotWaterData: HotWaterData(
                    targetTemperature: settings.targetTemperature,
                    duration: settings.duration,
                    volume: settings.volume,
                    flow: settings.flow,
                  ),
                );
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
                widget.workflowController.updateWorkflow(
                  rinseData: RinseData(
                    targetTemperature: settings.targetTemperature,
                    duration: settings.duration,
                    flow: settings.flow,
                  ),
                );
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
                controller.connectedDe1().setRefillLevel(newLevels.refillLevel.toInt());
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
              stream: widget.scaleController.connectionState,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.active ||
                    !state.hasData ||
                    state.data != device.ConnectionState.connected) {
                  return GestureDetector(
                    onTap: () async {
                      await widget.deviceController.scanForDevices(
                        autoConnect: true,
                      );
                    },
                    child: Text("Waiting"),
                  );
                }
                return _weightSnapshot == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [Text("W: --g"), Text("B: --%")],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: () {
                              widget.scaleController.connectedScale().tare();
                            },
                            child: Text(
                              "W: ${_weightSnapshot!.weight.toStringAsFixed(1)}g",
                            ),
                          ),
                          Text("B: ${_weightSnapshot!.battery ?? 0}%"),
                        ],
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
          "Machine:",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (_machineSnapshot == null)
          Text("Waiting")
        else
          Row(
            spacing: 50,
            children: [
              SizedBox(
                width: 100,
                child: Text("${_machineSnapshot!.state.state.name}"),
              ),
              SizedBox(
                width: boxWidth,
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.thermometer,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    Text("${_machineSnapshot!.groupTemperature.toStringAsFixed(1)}℃"),
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
                    Text("${_machineSnapshot!.steamTemperature}℃"),
                  ],
                ),
              ),
            ],
          ),
        if (_waterLevels == null)
          Text("Waiting")
        else
          SizedBox(
            width: boxWidth,
            child: GestureDetector(
              onTap: () {
                _showWaterLevelsDialog(context, widget.controller);
              },
              child: Row(
                children: [
                  Icon(
                    LucideIcons.waves,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  Text(
                    "${_waterLevels!.currentLevel.toStringAsFixed(1)}mm",
                    style: TextStyle(
                      color:
                          _waterLevels!.currentLevel > 10
                              ? Theme.of(context).colorScheme.primary
                              : _waterLevels!.currentLevel > 5
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}






