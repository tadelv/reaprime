import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ProfileTile extends StatefulWidget {
  final De1Controller de1controller;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;

  const ProfileTile({
    super.key,
    required this.de1controller,
    required this.workflowController,
    required this.persistenceController,
  });

  @override
  State<StatefulWidget> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileTile> {
  Profile? loadedProfile;

  final Logger _log = Logger('ProfileTile');

  @override
  void initState() {
    loadedProfile = widget.workflowController.currentWorkflow.profile;
    widget.workflowController.addListener(_workflowChange);
    super.initState();
  }

  @override
  void dispose() {
    widget.workflowController.removeListener(_workflowChange);
    super.dispose();
  }

  _workflowChange() {
    setState(() {
      if (loadedProfile != widget.workflowController.currentWorkflow.profile) {
        _log.info(
            "Changing profile to: ${widget.workflowController.currentWorkflow.profile.title}");
        loadedProfile = widget.workflowController.currentWorkflow.profile;
        widget.de1controller.connectedDe1().setProfile(loadedProfile!);
        _log.fine('Loaded profile: ${loadedProfile!.title}');
        _log.fine('Target weight: ${loadedProfile!.targetWeight}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      children: [
        DefaultTextStyle(
          style: Theme.of(context).textTheme.titleMedium!,
          child: _title(context),
        ),
        ..._workflow(context),
        ..._profileChart(context),
      ],
    );
  }

  Widget _title(BuildContext context) {
    return Row(
      //mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ShadButton.link(
          size: ShadButtonSize.sm,
          child: Text(
            loadedProfile != null ? loadedProfile!.title : "Load profile",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () async {
            FilePickerResult? result = await FilePicker.platform.pickFiles();
            if (result != null) {
              File file = File(result.files.single.path!);
              var json = jsonDecode(await file.readAsString());
              setState(() {
                var newProfile = Profile.fromJson(json);
                //widget.de1controller.connectedDe1().setProfile(loadedProfile!);
                final newWorkflow =
                    widget.workflowController.currentWorkflow.copyWith(
                  profile: newProfile,
                );
                newWorkflow.doseData.doseOut = newProfile.targetWeight ?? 36.0;

                widget.workflowController.setWorkflow(newWorkflow);
              });
            }
          },
        ),
        ..._profileStats(),
      ],
    );
  }

  List<Widget> _profileStats() {
    if (loadedProfile == null) {
      return [];
    }
    var profile = loadedProfile!;
    return [
      Text(profile.author),
    ];
  }

  List<Widget> _profileChart(BuildContext context) {
    if (loadedProfile == null) {
      return [];
    }
    var profile = loadedProfile!;
    var profileTime = profile.steps.fold(0.0, (d, s) => d + s.seconds);
    var profileMaxVal = profile.steps.fold(
        0.0, (m, s) => max(m, max(s.getTarget(), s.limiter?.value ?? 0.0)));
    return [
      SizedBox(
        height: 250,
        child: LineChart(
          LineChartData(
            lineBarsData: [
              ..._profileChartData(profile),
            ],
            minY: 0,
            maxY: profileMaxVal > 10 ? 12 : 10,
            titlesData: FlTitlesData(
              // Hide the top and left/right titles if not needed.
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  // You can adjust the interval as desired (e.g., 5 seconds).
                  interval: 5,
                  // The function to build your custom widget label for each tick.
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final int seconds = value.ceil().toInt();
                    String text;

                    if (profileTime < 60) {
                      // For less than 60 seconds, show ticks every 5 seconds with just seconds.
                      if (seconds % 5 == 0) {
                        text = '$seconds s';
                      } else {
                        return Container(); // return an empty widget for non-tick values
                      }
                    } else if (profileTime <= 120) {
                      // For 60 seconds or more, display minutes and seconds.
                      final int minutes = seconds ~/ 60;
                      final int remainingSeconds = seconds % 60;
                      if (seconds % 15 == 0) {
                        // Format the seconds with two digits.
                        text =
                            '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
                      } else {
                        return Container();
                      }
                    } else {
                      final int minutes = seconds ~/ 60;
                      if (seconds % 60 == 0) {
                        text = '$minutes:00';
                      } else {
                        return Container();
                      }
                    }
                    // Style the text as needed.
                    return SideTitleWidget(
                      meta: meta,
                      space: 8.0,
                      child: Text(
                        text,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<LineChartBarData> _profileChartData(Profile profile) {
    List<FlSpot> flowData = [];
    List<FlSpot> pressureData = [];
    List<FlSpot> flowLimitData = [];
    List<FlSpot> pressureLimitData = [];
    List<FlSpot> temperatureData = [];
    double seconds = 0;
    double previousTarget = 0.0;
    bool previousFlow = false;
    for (final (index, step) in profile.steps.indexed) {
      final isFlow = step is ProfileStepFlow;
      final isFast = step.transition == TransitionType.fast;
      final flow = isFlow ? step.getTarget() : 0.0;
      final pressure = isFlow ? 0.0 : step.getTarget();
      final flowLimit = isFlow ? 0.0 : step.limiter?.value ?? 0.0;
      final pressureLimit = isFlow ? step.limiter?.value ?? 0.0 : 0.0;
      final isSwitched = (isFlow && !previousFlow) || (!isFlow && previousFlow);
      if (isFast) {
        previousTarget = isFlow ? flow : pressure;
      }
      if (isFlow && previousFlow) {
        flowData.add(FlSpot(seconds, previousTarget));
        pressureLimitData.add(FlSpot(seconds, pressureLimit));
        previousTarget = flow;
      } else if (isFlow) {
        flowData.add(FlSpot(seconds, flow));
        pressureLimitData.add(FlSpot(seconds, pressureLimit));
        previousTarget = flow;
      } else if (previousFlow) {
        pressureData.add(FlSpot(seconds, pressure));
        flowLimitData.add(FlSpot(seconds, flowLimit));
        previousTarget = pressure;
      } else {
        pressureData.add(FlSpot(seconds, previousTarget));
        flowLimitData.add(FlSpot(seconds, flowLimit));
        previousTarget = pressure;
      }

      temperatureData.add(FlSpot(seconds, step.temperature / 10.0));

      seconds += step.seconds;
      //seconds += step.seconds - 1;
      //if (step.seconds < 2 || isSwitched) {
      //  seconds++;
      //}
      if (isFlow) {
        flowData.add(FlSpot(seconds, flow));
        pressureLimitData.add(FlSpot(seconds, pressureLimit));
      } else {
        pressureData.add(FlSpot(seconds, pressure));
        flowLimitData.add(FlSpot(seconds, flowLimit));
      }

      temperatureData.add(FlSpot(seconds, step.temperature / 10.0));
      //if (step.seconds > 2 && !isSwitched) {
      //  seconds++;
      //}
      previousFlow = isFlow;
    }
    return [
      LineChartBarData(
        spots: flowData,
        color: Colors.blue,
        dotData: FlDotData(show: false),
      ),
      LineChartBarData(
        spots: pressureData,
        color: Colors.green,
        dotData: FlDotData(show: false),
      ),
      LineChartBarData(
        spots: flowLimitData,
        color: Colors.lightBlue,
        dashArray: [5, 5],
        dotData: FlDotData(show: false),
      ),
      LineChartBarData(
        spots: pressureLimitData,
        color: Colors.green,
        dashArray: [5, 5],
        dotData: FlDotData(show: false),
      ),
      LineChartBarData(
        spots: temperatureData,
        color: Colors.redAccent,
        dotData: FlDotData(show: false),
      ),
    ];
  }

  List<Widget> _workflow(BuildContext context) {
    return [
      SizedBox(
        height: 64,
        child: Row(
          children: [
            _temperaturePopover(context),
            _weightPopover(context),
            _grinderPopover(context),
            _coffeePopover(context),
          ],
        ),
      )
    ];
  }

  final temperaturePopoverController = ShadPopoverController();

  ShadPopover _temperaturePopover(BuildContext context) {
    final profile = widget.workflowController.currentWorkflow.profile;
    final startTemp = profile.steps.first.temperature;
    var endTemp = startTemp;
    var textController =
        TextEditingController(text: endTemp.toStringAsFixed(1));
    return ShadPopover(
      controller: temperaturePopoverController,
      popover: (context) => SizedBox(
        width: 288,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ShadInput(
              textAlign: TextAlign.center,
              decoration: ShadDecoration(merge: false),
              controller: textController,
              keyboardType: TextInputType.number,
              prefix: ShadButton.ghost(
                child: Text("-"),
                onPressed: () {
                  endTemp -= 1.0;
                  textController.text = endTemp.toStringAsFixed(1);
                },
              ),
              suffix: ShadButton.ghost(
                child: Text("+"),
                onPressed: () {
                  endTemp += 1.0;
                  textController.text = endTemp.toStringAsFixed(1);
                },
              ),
            ),
            ShadButton(
              onPressed: () {
                var workflow = widget.workflowController.currentWorkflow;
                workflow = workflow.copyWith(
                    profile: profile.adjustTemperature(endTemp - startTemp));
                widget.workflowController.setWorkflow(workflow);
                temperaturePopoverController.toggle();
              },
              child: Text("Apply"),
            )
          ],
        ),
      ),
      child: ShadButton.link(
        child: Text(
          "${startTemp.toStringAsFixed(1)}℃",
        ),
        onPressed: () {
          temperaturePopoverController.toggle();
        },
      ),
    );
  }

  final weightPopoverController = ShadPopoverController();

  ShadPopover _weightPopover(BuildContext context) {
    var doseIn = widget.workflowController.currentWorkflow.doseData.doseIn
        .toStringAsFixed(1);
    var doseOut = widget.workflowController.currentWorkflow.doseData.doseOut
        .toStringAsFixed(1);
    return ShadPopover(
      anchor: ShadAnchorAuto(
          verticalOffset: 0, preferBelow: true, followTargetOnResize: true),
      controller: weightPopoverController,
      popover: (context) => SizedBox(
        width: 288,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text("Input dose"),
                Expanded(
                  child: ShadInput(
                    key: Key(widget
                        .workflowController.currentWorkflow.doseData.doseIn
                        .toString()),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    initialValue: widget
                        .workflowController.currentWorkflow.doseData.doseIn
                        .toStringAsFixed(1),
                    onSubmitted: (val) {
                      setState(() {
                        var ratio = widget
                            .workflowController.currentWorkflow.doseData.ratio;
                        widget.workflowController.currentWorkflow.doseData
                            .doseIn = double.parse(val);
                        widget.workflowController.currentWorkflow.doseData
                            .setRatio(ratio);
                        var doseData =
                            widget.workflowController.currentWorkflow.doseData;
                        var newWorkflow = widget
                            .workflowController.currentWorkflow
                            .copyWith(doseData: doseData);
                        widget.workflowController.setWorkflow(newWorkflow);
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text("Ratio 1:"),
                Expanded(
                  child: ShadInput(
                    key: Key(widget
                        .workflowController.currentWorkflow.doseData.ratio
                        .toString()),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    initialValue: widget
                        .workflowController.currentWorkflow.doseData.ratio
                        .toStringAsFixed(1),
                    onSubmitted: (val) {
                      setState(() {
                        widget.workflowController.currentWorkflow.doseData
                            .setRatio(double.parse(val));
                        var doseData =
                            widget.workflowController.currentWorkflow.doseData;
                        var newWorkflow = widget
                            .workflowController.currentWorkflow
                            .copyWith(doseData: doseData);
                        widget.workflowController.setWorkflow(newWorkflow);
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text("Target weight"),
                Expanded(
                  child: ShadInput(
                    key: Key(widget
                        .workflowController.currentWorkflow.doseData.doseOut
                        .toString()),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    initialValue: widget
                        .workflowController.currentWorkflow.doseData.doseOut
                        .toStringAsFixed(1),
                    onSubmitted: (val) {
                      setState(() {
                        widget.workflowController.currentWorkflow.doseData
                            .doseOut = double.parse(val);
                        var doseData =
                            widget.workflowController.currentWorkflow.doseData;
                        var newWorkflow = widget
                            .workflowController.currentWorkflow
                            .copyWith(doseData: doseData);
                        widget.workflowController.setWorkflow(newWorkflow);
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      child: ShadButton.link(
        onPressed: () {
          weightPopoverController.toggle();
        },
        child: Text("$doseIn : $doseOut"),
      ),
    );
  }

  final ShadPopoverController _grinderPopoverController =
      ShadPopoverController();

  ShadPopover _grinderPopover(BuildContext context) {
    var data = widget.workflowController.currentWorkflow.grinderData;

    return ShadPopover(
      anchor: ShadAnchorAuto(
          verticalOffset: 0, preferBelow: true, followTargetOnResize: true),
      controller: _grinderPopoverController,
      popover: (context) => SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              spacing: 16,
              children: [
                Text("Grind setting"),
                Expanded(
                  child: Autocomplete(
                    optionsBuilder: (TextEditingValue val) {
                      final options = widget.persistenceController
                          .grinderOptions()
                          .where((el) => el.setting
                              .toLowerCase()
                              .contains(val.text.toLowerCase()))
                          .map((e) => e.setting)
                          .toSet();
                      if (options.isEmpty) {
                        return [val.text];
                      }
                      return options;
                    },
                    key: Key(
                      widget.workflowController.currentWorkflow.grinderData
                              ?.setting ??
                          "",
                    ),
                    initialValue: TextEditingValue(
                        text: widget.workflowController.currentWorkflow
                                .grinderData?.setting ??
                            ""),
                    onSelected: (val) {
                      //_log.shout("selected: $val");
                      setState(() {
                        if (widget.workflowController.currentWorkflow
                                .grinderData ==
                            null) {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                              grinderData: GrinderData(
                                setting: val,
                              ),
                            ),
                          );
                        } else {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                                grinderData: widget.workflowController
                                    .currentWorkflow.grinderData!
                                  ..setting = val),
                          );
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              spacing: 16,
              children: [
                Text("Grinder model"),
                Expanded(
                  child: Autocomplete(
                    optionsBuilder: (TextEditingValue val) {
                      final options = widget.persistenceController
                          .grinderOptions()
                          .where((e) =>
                              e.model
                                  ?.toLowerCase()
                                  .contains(val.text.toLowerCase()) ??
                              false)
                          .fold(<String>[], (r, e) {
                        if (e.model != null) {
                          r.add(e.model!);
                        }
                        return r;
                      }).toSet();
                      if (options.isEmpty) {
                        return [val.text];
                      }
                      return options;
                    },
                    key: Key(widget.workflowController.currentWorkflow
                            .grinderData?.model ??
                        ""),
                    initialValue: TextEditingValue(
                        text: widget.workflowController.currentWorkflow
                                .grinderData?.model ??
                            ""),
                    onSelected: (val) {
                      setState(() {
                        if (widget.workflowController.currentWorkflow
                                .grinderData ==
                            null) {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                              grinderData: GrinderData(
                                model: val,
                              ),
                            ),
                          );
                        } else {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                                grinderData: widget.workflowController
                                    .currentWorkflow.grinderData!
                                  ..model = val),
                          );
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              spacing: 16,
              children: [
                Text("Grinder manufacturer"),
                Expanded(
                  child: Autocomplete(
                    optionsBuilder: (TextEditingValue val) {
                      final options = widget.persistenceController
                          .grinderOptions()
                          .where((e) =>
                              e.manufacturer
                                  ?.toLowerCase()
                                  .contains(val.text.toLowerCase()) ??
                              false)
                          .fold(<String>[], (r, e) {
                        if (e.manufacturer != null) {
                          r.add(e.manufacturer!);
                        }
                        return r;
                      }).toSet();
                      if (options.isEmpty) {
                        return [val.text];
                      }
                      return options;
                    },
                    key: Key(widget.workflowController.currentWorkflow
                            .grinderData?.manufacturer ??
                        ""),
                    initialValue: TextEditingValue(
                        text: widget.workflowController.currentWorkflow
                                .grinderData?.manufacturer ??
                            ""),
                    onSelected: (val) {
                      setState(() {
                        if (widget.workflowController.currentWorkflow
                                .grinderData ==
                            null) {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                              grinderData: GrinderData(
                                manufacturer: val,
                              ),
                            ),
                          );
                        } else {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                                grinderData: widget.workflowController
                                    .currentWorkflow.grinderData!
                                  ..manufacturer = val),
                          );
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      child: ShadButton.link(
        onPressed: () {
          _grinderPopoverController.toggle();
        },
        child: Text(data == null
            ? "Grind settings"
            : '${data.model == null ? "" : data.model!} ${data.setting}'),
      ),
    );
  }

  final ShadPopoverController _coffeePopoverController =
      ShadPopoverController();

  ShadPopover _coffeePopover(BuildContext context) {
    var data = widget.workflowController.currentWorkflow.coffeeData;

    return ShadPopover(
      anchor: ShadAnchorAuto(
          verticalOffset: 0, preferBelow: true, followTargetOnResize: true),
      controller: _coffeePopoverController,
      popover: (context) => SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              spacing: 16,
              children: [
                Text("Coffee name"),
                Expanded(
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue val) {
                      final options = widget.persistenceController
                          .coffeeOptions()
                          .where((e) => e.name
                              .toLowerCase()
                              .contains(val.text.toLowerCase()))
                          .map((e) => e.name)
                          .toSet();
                      if (options.isEmpty) {
                        return [val.text];
                      }
                      return options;
                    },
                    key: Key(
                      widget.workflowController.currentWorkflow.coffeeData
                              ?.name ??
                          "",
                    ),
                    initialValue: TextEditingValue(
                        text: widget.workflowController.currentWorkflow
                                .coffeeData?.name ??
                            ""),
                    onSelected: (val) {
                      setState(() {
                        if (widget.workflowController.currentWorkflow
                                .coffeeData ==
                            null) {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                              coffeeData: CoffeeData(
                                name: val,
                              ),
                            ),
                          );
                        } else {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                                coffeeData: widget.workflowController
                                    .currentWorkflow.coffeeData!
                                  ..name = val),
                          );
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              spacing: 16,
              children: [
                Text("Roaster"),
                Expanded(
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue val) {
                      final options = widget.persistenceController
                          .coffeeOptions()
                          .where((e) =>
                              e.roaster
                                  ?.toLowerCase()
                                  .contains(val.text.toLowerCase()) ??
                              false)
                          .fold(<String>[], (r, e) {
                        if (e.roaster != null) {
                          r.add(e.roaster!);
                        }
                        return r;
                      }).toSet();
                      if (options.isEmpty) {
                        return [val.text];
                      }
                      return options;
                    },
                    key: Key(widget.workflowController.currentWorkflow
                            .coffeeData?.roaster ??
                        ""),
                    initialValue: TextEditingValue(
                        text: widget.workflowController.currentWorkflow
                                .coffeeData?.roaster ??
                            ""),
                    onSelected: (val) {
                      setState(() {
                        if (widget.workflowController.currentWorkflow
                                .coffeeData ==
                            null) {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                              coffeeData: CoffeeData(
                                roaster: val,
                              ),
                            ),
                          );
                        } else {
                          widget.workflowController.setWorkflow(
                            widget.workflowController.currentWorkflow.copyWith(
                                coffeeData: widget.workflowController
                                    .currentWorkflow.coffeeData!
                                  ..roaster = val),
                          );
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      child: ShadButton.link(
        onPressed: () {
          _coffeePopoverController.toggle();
        },
        child: Text(data == null ? "Coffee settings" : "${data.name}"),
      ),
    );
  }
}
