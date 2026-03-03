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
import 'package:reaprime/src/models/data/workflow_context.dart';
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
          "Changing profile to: ${widget.workflowController.currentWorkflow.profile.title}",
        );
        loadedProfile = widget.workflowController.currentWorkflow.profile;
        widget.de1controller.connectedDe1().setProfile(loadedProfile!);
        _log.fine('Loaded profile: ${loadedProfile!.title}');
        _log.fine('Target weight: ${loadedProfile!.targetWeight}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadCard(child: _body(context));
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
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['json'],
              allowMultiple: false,
            );
            if (result != null) {
              File file = File(result.files.single.path!);
              var json = jsonDecode(await file.readAsString());
              setState(() {
                var newProfile = Profile.fromJson(json);
                final currentCtx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();
                final newWorkflow = widget.workflowController.currentWorkflow
                    .copyWith(
                      profile: newProfile,
                      context: currentCtx.copyWith(targetYield: newProfile.targetWeight ?? 36.0),
                    );

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
    return [Text(profile.author)];
  }

  List<Widget> _profileChart(BuildContext context) {
    if (loadedProfile == null) {
      return [];
    }
    var profile = loadedProfile!;
    var profileTime = profile.steps.fold(0.0, (d, s) => d + s.seconds);
    var profileMaxVal = profile.steps.fold(
      0.0,
      (m, s) => max(m, max(s.getTarget(), s.limiter?.value ?? 0.0)),
    );
    return [
      SizedBox(
        height: 250,
        child: LineChart(
          LineChartData(
            lineBarsData: [..._profileChartData(profile)],
            minY: 0,
            maxY: profileMaxVal > 10 ? 12 : 10,
            titlesData: FlTitlesData(
              // Hide the top and left/right titles if not needed.
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
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
            _grinderDialog(context),
            _coffeeDialog(context),
          ],
        ),
      ),
    ];
  }

  final temperaturePopoverController = ShadPopoverController();

  ShadPopover _temperaturePopover(BuildContext context) {
    final profile = widget.workflowController.currentWorkflow.profile;
    final startTemp = profile.steps.first.temperature;
    var endTemp = startTemp;
    var textController = TextEditingController(
      text: endTemp.toStringAsFixed(1),
    );
    return ShadPopover(
      controller: temperaturePopoverController,
      popover:
          (context) => SizedBox(
            width: 288,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadInput(
                  textAlign: TextAlign.center,
                  decoration: ShadDecoration(),
                  controller: textController,
                  keyboardType: TextInputType.number,
                  leading: ShadButton.ghost(
                    child: Text("-"),
                    onPressed: () {
                      endTemp -= 1.0;
                      textController.text = endTemp.toStringAsFixed(1);
                    },
                  ),
                  trailing: ShadButton.ghost(
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
                      profile: profile.adjustTemperature(endTemp - startTemp),
                    );
                    widget.workflowController.setWorkflow(workflow);
                    temperaturePopoverController.toggle();
                  },
                  child: Text("Apply"),
                ),
              ],
            ),
          ),
      child: ShadButton.link(
        child: Text("${startTemp.toStringAsFixed(1)}℃"),
        onPressed: () {
          temperaturePopoverController.toggle();
        },
      ),
    );
  }

  final weightPopoverController = ShadPopoverController();

  ShadPopover _weightPopover(BuildContext context) {
    final ctx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();
    final doseWeight = ctx.targetDoseWeight ?? 16.0;
    final yield_ = ctx.targetYield ?? 36.0;
    final ratio = doseWeight > 0 ? yield_ / doseWeight : 0.0;
    var doseIn = doseWeight.toStringAsFixed(1);
    var doseOut = yield_.toStringAsFixed(1);
    return ShadPopover(
      anchor: ShadAnchorAuto(offset: Offset(0, 0), followTargetOnResize: true),
      controller: weightPopoverController,
      popover:
          (context) => SizedBox(
            width: 288,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text("Input dose"),
                    Expanded(
                      child: ShadInput(
                        key: Key(doseWeight.toString()),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        initialValue: doseWeight.toStringAsFixed(1),
                        onSubmitted: (val) {
                          setState(() {
                            final newDoseWeight = double.parse(val);
                            final newYield = newDoseWeight * ratio;
                            final newCtx = ctx.copyWith(
                              targetDoseWeight: newDoseWeight,
                              targetYield: newYield,
                            );
                            widget.workflowController.setWorkflow(
                              widget.workflowController.currentWorkflow.copyWith(context: newCtx),
                            );
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
                        key: Key(ratio.toString()),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        initialValue: ratio.toStringAsFixed(1),
                        onSubmitted: (val) {
                          setState(() {
                            final newRatio = double.parse(val);
                            final newYield = doseWeight * newRatio;
                            final newCtx = ctx.copyWith(targetYield: newYield);
                            widget.workflowController.setWorkflow(
                              widget.workflowController.currentWorkflow.copyWith(context: newCtx),
                            );
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
                        key: Key(yield_.toString()),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        initialValue: yield_.toStringAsFixed(1),
                        onSubmitted: (val) {
                          setState(() {
                            final newYield = double.parse(val);
                            final newCtx = ctx.copyWith(targetYield: newYield);
                            widget.workflowController.setWorkflow(
                              widget.workflowController.currentWorkflow.copyWith(context: newCtx),
                            );
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

  Widget _grinderDialog(BuildContext context) {
    final ctx = widget.workflowController.currentWorkflow.context;
    final hasGrinder = ctx?.grinderSetting != null || ctx?.grinderModel != null;
    return ShadButton.link(
      onPressed: () {
        showShadDialog(
          context: context,
          builder:
              (context) => ShadDialog(
                title: const Text("Grinder Settings"),
                child: Dialog(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 16,
                    children: [
                      grinderDataForm(context),
                      ShadButton(
                        child: Text("Done"),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
        );
      },
      child: Text(
        !hasGrinder
            ? "Grind settings"
            : '${ctx?.grinderModel ?? ""} ${ctx?.grinderSetting ?? ""}',
      ),
    );
  }

  Column grinderDataForm(BuildContext context) {
    final ctx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 16,
          children: [
            Text("Grind setting"),
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (TextEditingValue val) {
                  if (val.text.isEmpty) return const [];
                  final options =
                      widget.persistenceController
                          .grinderOptions()
                          .where(
                            (el) => el.setting.toLowerCase().contains(
                              val.text.toLowerCase(),
                            ),
                          )
                          .map((e) => e.setting)
                          .toSet()
                          .toList();
                  if (!options.contains(val.text)) {
                    return [val.text, ...options];
                  }
                  return options;
                },
                key: Key(ctx.grinderSetting ?? ""),
                initialValue: TextEditingValue(text: ctx.grinderSetting ?? ""),
                onSelected: (val) {
                  setState(() {
                    widget.workflowController.setWorkflow(
                      widget.workflowController.currentWorkflow.copyWith(
                        context: ctx.copyWith(grinderSetting: val),
                      ),
                    );
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
              child: Autocomplete<String>(
                optionsBuilder: (TextEditingValue val) {
                  if (val.text.isEmpty) return const [];
                  final options =
                      widget.persistenceController
                          .grinderOptions()
                          .where(
                            (e) =>
                                e.model?.toLowerCase().contains(
                                  val.text.toLowerCase(),
                                ) ??
                                false,
                          )
                          .fold(<String>[], (r, e) {
                            if (e.model != null) {
                              r.add(e.model!);
                            }
                            return r;
                          })
                          .toSet()
                          .toList();
                  if (!options.contains(val.text)) {
                    return [val.text, ...options];
                  }
                  return options;
                },
                key: Key(ctx.grinderModel ?? ""),
                initialValue: TextEditingValue(text: ctx.grinderModel ?? ""),
                onSelected: (val) {
                  setState(() {
                    widget.workflowController.setWorkflow(
                      widget.workflowController.currentWorkflow.copyWith(
                        context: ctx.copyWith(grinderModel: val),
                      ),
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _coffeeDialog(BuildContext context) {
    final ctx = widget.workflowController.currentWorkflow.context;
    final coffeeName = ctx?.coffeeName;

    return ShadButton.link(
      onPressed: () {
        showShadDialog(
          context: context,
          builder:
              (context) => ShadDialog(
                title: const Text("Coffee data"),
                child: Dialog(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 16,
                    children: [
                      _coffeeDataForm(),
                      ShadButton(
                        child: Text("Done"),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
        );
      },
      child: Text(coffeeName == null || coffeeName.isEmpty ? "Coffee settings" : coffeeName),
    );
  }

  Column _coffeeDataForm() {
    final ctx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 16,
          children: [
            Text("Coffee name"),
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (TextEditingValue val) {
                  if (val.text.isEmpty) return const [];
                  final options =
                      widget.persistenceController
                          .coffeeOptions()
                          .where(
                            (e) => e.name.toLowerCase().contains(
                              val.text.toLowerCase(),
                            ),
                          )
                          .map((e) => e.name)
                          .toSet()
                          .toList();
                  if (!options.contains(val.text)) {
                    return [val.text, ...options];
                  }
                  return options;
                },
                key: Key(ctx.coffeeName ?? ""),
                initialValue: TextEditingValue(text: ctx.coffeeName ?? ""),
                onSelected: (val) {
                  setState(() {
                    widget.workflowController.setWorkflow(
                      widget.workflowController.currentWorkflow.copyWith(
                        context: ctx.copyWith(coffeeName: val),
                      ),
                    );
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
                  if (val.text.isEmpty) return const [];
                  final options =
                      widget.persistenceController
                          .coffeeOptions()
                          .where(
                            (e) =>
                                e.roaster?.toLowerCase().contains(
                                  val.text.toLowerCase(),
                                ) ??
                                false,
                          )
                          .fold(<String>[], (r, e) {
                            if (e.roaster != null) {
                              r.add(e.roaster!);
                            }
                            return r;
                          })
                          .toSet()
                          .toList();
                  if (!options.contains(val.text)) {
                    return [val.text, ...options];
                  }
                  return options;
                },
                key: Key(ctx.coffeeRoaster ?? ""),
                initialValue: TextEditingValue(text: ctx.coffeeRoaster ?? ""),
                onSelected: (val) {
                  setState(() {
                    widget.workflowController.setWorkflow(
                      widget.workflowController.currentWorkflow.copyWith(
                        context: ctx.copyWith(coffeeRoaster: val),
                      ),
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
