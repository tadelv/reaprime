import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Displays detailed information about a SampleItem.
class De1DebugView extends StatefulWidget {
  const De1DebugView({super.key, required this.machine});

  static const routeName = '/debug_details';

  final De1Interface machine;

  @override
  State<De1DebugView> createState() => _De1DebugViewState();
}

class _De1DebugViewState extends State<De1DebugView> {
  var _lastDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Details')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Flex(
            direction: Axis.horizontal,
            children: [
              Expanded(
                child: Column(children: [
                  Text(
                    "Shot snapshot:",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  StreamBuilder(
                    stream: widget.machine.currentSnapshot,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.active) {
                        var diff =
                            snapshot.data?.timestamp.difference(_lastDate) ??
                                Duration.zero;
                        _lastDate = snapshot.data?.timestamp ?? DateTime.now();
                        return Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: machineState(snapshot, diff));
                      } else if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Text("Connecting");
                      }
                      return Text(
                        "Waiting for data: ${snapshot.connectionState}",
                      );
                    },
                  ),
                ]),
              ),
              Expanded(
                child: Column(children: [
                  Text(
                    "Shot settings:",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _shotSettings(widget.machine.shotSettings),
                ]),
              ),
              Expanded(
                child: Column(children: [
                  Text(
                    "Water levels:",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _waterLevels(widget.machine.waterLevels),
                ]),
              ),
              Expanded(
                  child: Column(
                children: [
                  Text(
                    "Machine info:",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  // TODO: firmware version
                  ShadButton(
                    child: const Text("Firmware update"),
                    onTapUp: (_) async {
                      FilePickerResult? result =
                          await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ["dat"],
                      );

                      if (result == null) return;

                      File file = File(result.files.single.path!);
                      final data = await file.readAsBytes();

                      if (!context.mounted) return;

                      double progress = 0.0;
                      final progressNotifier = ValueNotifier<double>(0.0);

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) {
                          return ValueListenableBuilder<double>(
                            valueListenable: progressNotifier,
                            builder: (context, value, _) {
                              return ShadDialog(
                                title: const Text("Updating firmware..."),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LinearProgressIndicator(value: value),
                                      const SizedBox(height: 12),
                                      Text(
                                          "${(value * 100).toStringAsFixed(0)}%"),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );

                      try {
                        await widget.machine.updateFirmware(
                          data,
                          onProgress: (p) {
                            progressNotifier.value = p;
                          },
                        );
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.of(context).pop(); // Close progress dialog
                          showShadDialog(
                            context: context,
                            builder: (context) => ShadDialog(
                              title: const Text("Firmware update failed"),
                              child: Text(e.toString()),
                              actions: [
                                ShadButton(
                                  child: const Text("OK"),
                                  onTapUp: (_) => Navigator.of(context).pop(),
                                )
                              ],
                            ),
                          );
                        }
                        return;
                      }

                      if (context.mounted) {
                        Navigator.of(context).pop(); // Close progress dialog
                      }
                    },
                  ),
                  _serialComms(context)
                ],
              ))
            ],
          ),
        ),
      ),
    );
  }

  final TextEditingController _serialController = TextEditingController();

  Widget _serialComms(BuildContext context) {
    return Column(
      spacing: 8.0,
      children: [
        SizedBox(
          height: 16.0,
        ),
        Text("Send raw command:"),
        Padding(
          padding: EdgeInsetsGeometry.all(8.0),
          child: ShadInput(
            controller: _serialController,
          ),
        ),
        ShadButton(
          child: Text("Send"),
          onTapUp: (e) {
            widget.machine.sendRawMessage(De1RawMessage(
                type: De1RawMessageType.request,
                operation: De1RawOperationType.write,
                characteristicUUID: "",
                payload: _serialController.text));
          },
        )
      ],
    );
  }

  List<Widget> machineState(
    AsyncSnapshot<MachineSnapshot> snapshot,
    Duration diff,
  ) {
    return [
      Text("${snapshot.data?.state.state}: ${snapshot.data?.state.substate}"),
      Text("steam temp: ${snapshot.data?.steamTemperature.toStringAsFixed(2)}"),
      Text("group temp: ${snapshot.data?.groupTemperature.toStringAsFixed(2)}"),
      Text("flow: ${snapshot.data?.flow.toStringAsFixed(2)}"),
      Text("pressure: ${snapshot.data?.pressure.toStringAsFixed(2)}"),
      Text(
        "target mix temp: ${snapshot.data?.targetMixTemperature.toStringAsFixed(2)}",
      ),
      Text(
        "target head temp: ${snapshot.data?.targetGroupTemperature.toStringAsFixed(2)}",
      ),
      Text(
        "target pressure: ${snapshot.data?.targetPressure.toStringAsFixed(2)}",
      ),
      Text("target flow: ${snapshot.data?.flow.toStringAsFixed(2)}"),
      Text("update freq: ${diff.inMilliseconds}ms"),
      _stateButton(snapshot),
    ];
  }

  Widget _stateButton(AsyncSnapshot<MachineSnapshot> snapshot) {
    if (snapshot.data != null) {
      if (snapshot.data!.state.state == MachineState.sleeping) {
        return OutlinedButton(
          onPressed: () {
            widget.machine.requestState(MachineState.idle);
          },
          child: Text("Wake"),
        );
      } else {
        return OutlinedButton(
          onPressed: () {
            widget.machine.requestState(MachineState.sleeping);
          },
          child: Text("Sleep"),
        );
      }
    }
    return SizedBox();
  }

  Widget _shotSettings(Stream<De1ShotSettings> shotSettings) {
    return StreamBuilder(
      stream: shotSettings,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
                "steam setting 0x${snapshot.data!.steamSetting.toRadixString(16).padLeft(2, '0')}"),
            Text(
                "target group temp ${snapshot.data!.groupTemp.toStringAsFixed(1)}")
          ]);
        }
        return Text("Waiting for data ${snapshot.connectionState}");
      },
    );
  }

  Widget _waterLevels(Stream<De1WaterLevels> waterLevels) {
    return StreamBuilder(
      stream: waterLevels,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("water level: ${snapshot.data!.currentPercentage}"),
              Text(
                  "threshold level: ${snapshot.data!.warningThresholdPercentage}"),
            ],
          );
        }
        return Text("Waiting for data ${snapshot.connectionState}");
      },
    );
  }
}
