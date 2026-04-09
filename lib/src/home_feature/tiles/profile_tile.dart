import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/models/data/grinder.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ProfileTile extends StatefulWidget {
  final De1Controller de1controller;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;
  final BeanStorageService? beanStorage;
  final GrinderStorageService? grinderStorage;

  const ProfileTile({
    super.key,
    required this.de1controller,
    required this.workflowController,
    required this.persistenceController,
    this.beanStorage,
    this.grinderStorage,
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
    return Semantics(
      explicitChildNodes: true,
      label: 'Profile and workflow',
      child: Column(
        children: [
          DefaultTextStyle(
            style: Theme.of(context).textTheme.titleMedium!,
            child: _title(context),
          ),
          ..._workflow(context),
          ..._profileChart(context),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) {
    return Row(
      //mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: loadedProfile != null
              ? 'Load profile, current: ${loadedProfile!.title}'
              : 'Load profile',
          child: ExcludeSemantics(
            child: ShadButton.link(
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
          ),
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
      Semantics(
        label: 'Profile chart for ${profile.title}',
        child: ExcludeSemantics(
          child: SizedBox(
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
    final startTemp = profile.steps.firstOrNull?.temperature ?? 0.0;
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
      child: Semantics(
        button: true,
        label: 'Adjust start temperature, currently ${startTemp.toStringAsFixed(1)} degrees',
        child: ExcludeSemantics(
          child: ShadButton.link(
            child: Text("${startTemp.toStringAsFixed(1)}℃"),
            onPressed: () {
              temperaturePopoverController.toggle();
            },
          ),
        ),
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
                MergeSemantics(
                  child: Row(
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
                ),
                MergeSemantics(
                  child: Row(
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
                ),
                MergeSemantics(
                  child: Row(
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
                ),
              ],
            ),
          ),
      child: Semantics(
        button: true,
        label: 'Adjust dose weight, $doseIn grams in, $doseOut grams out',
        child: ExcludeSemantics(
          child: ShadButton.link(
            onPressed: () {
              weightPopoverController.toggle();
            },
            child: Text("$doseIn : $doseOut"),
          ),
        ),
      ),
    );
  }

  Widget _grinderDialog(BuildContext context) {
    final ctx = widget.workflowController.currentWorkflow.context;
    final hasGrinder = ctx?.grinderSetting != null || ctx?.grinderModel != null;
    final grinderLabel = hasGrinder
        ? 'Grinder settings, ${ctx?.grinderModel ?? ""} ${ctx?.grinderSetting ?? ""}'
        : 'Set grinder';
    return Semantics(
      button: true,
      label: grinderLabel,
      child: ExcludeSemantics(
        child: ShadButton.link(
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
                          _grinderDataFormWithPicker(context),
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
        ),
      ),
    );
  }

  Widget _grinderDataFormWithPicker(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return FutureBuilder<List<Grinder>>(
          future: widget.grinderStorage?.getAllGrinders() ?? Future.value([]),
          builder: (context, snapshot) {
            final grinders = snapshot.data ?? [];
            final ctx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();
            final selectedGrinder = ctx.grinderId != null
                ? grinders.where((g) => g.id == ctx.grinderId).firstOrNull
                : null;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.grinderStorage != null && grinders.isNotEmpty) ...[
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Select grinder',
                            isDense: true,
                          ),
                          value: selectedGrinder?.id,
                          hint: const Text('Choose a grinder...'),
                          isExpanded: true,
                          items: grinders.map((g) {
                            final subtitle = [
                              if (g.burrs != null) g.burrs,
                              if (g.burrSize != null) '${g.burrSize}mm',
                            ].join(' ');
                            return DropdownMenuItem<String>(
                              value: g.id,
                              child: Text(
                                subtitle.isNotEmpty ? '${g.model} ($subtitle)' : g.model,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (grinderId) {
                            final grinder = grinders.firstWhere((g) => g.id == grinderId);
                            setState(() {
                              widget.workflowController.setWorkflow(
                                widget.workflowController.currentWorkflow.copyWith(
                                  context: ctx.copyWith(
                                    grinderId: grinder.id,
                                    grinderModel: grinder.model,
                                  ),
                                ),
                              );
                            });
                            setDialogState(() {});
                          },
                        ),
                      ),
                      if (selectedGrinder != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          tooltip: 'Clear grinder selection',
                          onPressed: () {
                            setState(() {
                              widget.workflowController.setWorkflow(
                                widget.workflowController.currentWorkflow.copyWith(
                                  context: ctx.clearGrinder(),
                                ),
                              );
                            });
                            setDialogState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                ],
                _grinderFreeformFields(context, ctx, setDialogState),
              ],
            );
          },
        );
      },
    );
  }

  Widget _grinderFreeformFields(BuildContext context, WorkflowContext ctx, StateSetter setDialogState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MergeSemantics(
          child: Row(
            spacing: 16,
            children: [
              Text("Grind setting"),
              Expanded(
                child: Autocomplete<String>(
                  // TODO: Grinder setting autocomplete was previously sourced from shot history.
                  // Now that the in-memory cache is removed, setting suggestions are not available.
                  // Consider adding a distinct grinder_setting query to ShotDao.
                  optionsBuilder: (TextEditingValue val) {
                    if (val.text.isEmpty) return const [];
                    return [val.text];
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
                    setDialogState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        MergeSemantics(
          child: Row(
            spacing: 16,
            children: [
              Text("Grinder model"),
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (TextEditingValue val) async {
                    if (val.text.isEmpty || widget.grinderStorage == null) return const <String>[];
                    final grinders = await widget.grinderStorage!.getAllGrinders();
                    final matches = grinders
                        .where((g) => g.model.toLowerCase().contains(val.text.toLowerCase()))
                        .map((g) => g.model)
                        .toSet()
                        .toList();
                    if (!matches.contains(val.text)) {
                      return [val.text, ...matches];
                    }
                    return matches;
                  },
                  key: Key(ctx.grinderModel ?? ""),
                  initialValue: TextEditingValue(text: ctx.grinderModel ?? ""),
                  onSelected: (val) {
                    setState(() {
                      // Clear grinderId when freeform model is manually edited
                      final newCtx = ctx.grinderId != null
                          ? ctx.clearGrinder().copyWith(grinderModel: val)
                          : ctx.copyWith(grinderModel: val);
                      widget.workflowController.setWorkflow(
                        widget.workflowController.currentWorkflow.copyWith(
                          context: newCtx,
                        ),
                      );
                    });
                    setDialogState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Keep for backward compatibility (used in tests)
  Column grinderDataForm(BuildContext context) {
    final ctx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _grinderFreeformFields(context, ctx, (fn) => fn()),
      ],
    );
  }

  Widget _coffeeDialog(BuildContext context) {
    final ctx = widget.workflowController.currentWorkflow.context;
    final coffeeName = ctx?.coffeeName;
    final coffeeLabel = coffeeName != null && coffeeName.isNotEmpty
        ? 'Coffee settings, $coffeeName'
        : 'Set coffee';

    return Semantics(
      button: true,
      label: coffeeLabel,
      child: ExcludeSemantics(
        child: ShadButton.link(
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
                          _coffeeDataFormWithPicker(context),
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
        ),
      ),
    );
  }

  Widget _coffeeDataFormWithPicker(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return FutureBuilder<List<Bean>>(
          future: widget.beanStorage?.getAllBeans() ?? Future.value([]),
          builder: (context, snapshot) {
            final beans = snapshot.data ?? [];
            final ctx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.beanStorage != null && beans.isNotEmpty) ...[
                  _beanBatchPicker(context, ctx, beans, setDialogState),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                ],
                _coffeeFreeformFields(ctx, setDialogState),
              ],
            );
          },
        );
      },
    );
  }

  Widget _beanBatchPicker(
    BuildContext context,
    WorkflowContext ctx,
    List<Bean> beans,
    StateSetter setDialogState,
  ) {
    // Find current bean from beanBatchId
    return _BeanBatchPickerWidget(
      beans: beans,
      beanStorage: widget.beanStorage!,
      currentBatchId: ctx.beanBatchId,
      onBatchSelected: (bean, batch) {
        setState(() {
          widget.workflowController.setWorkflow(
            widget.workflowController.currentWorkflow.copyWith(
              context: ctx.copyWith(
                beanBatchId: batch.id,
                coffeeName: bean.name,
                coffeeRoaster: bean.roaster,
              ),
            ),
          );
        });
        setDialogState(() {});
      },
      onBeanSelectedNoBatch: (bean) {
        setState(() {
          widget.workflowController.setWorkflow(
            widget.workflowController.currentWorkflow.copyWith(
              context: ctx.copyWith(
                coffeeName: bean.name,
                coffeeRoaster: bean.roaster,
              ),
            ),
          );
        });
        setDialogState(() {});
      },
      onCleared: () {
        setState(() {
          widget.workflowController.setWorkflow(
            widget.workflowController.currentWorkflow.copyWith(
              context: ctx.clearBeanBatch(),
            ),
          );
        });
        setDialogState(() {});
      },
    );
  }

  Widget _coffeeFreeformFields(WorkflowContext ctx, StateSetter setDialogState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MergeSemantics(
          child: Row(
            spacing: 16,
            children: [
              Text("Coffee name"),
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (TextEditingValue val) async {
                    if (val.text.isEmpty || widget.beanStorage == null) return const <String>[];
                    final beans = await widget.beanStorage!.getAllBeans();
                    final matches = beans
                        .where((b) => b.name.toLowerCase().contains(val.text.toLowerCase()))
                        .map((b) => b.name)
                        .toSet()
                        .toList();
                    if (!matches.contains(val.text)) {
                      return [val.text, ...matches];
                    }
                    return matches;
                  },
                  key: Key(ctx.coffeeName ?? ""),
                  initialValue: TextEditingValue(text: ctx.coffeeName ?? ""),
                  onSelected: (val) {
                    setState(() {
                      // Clear beanBatchId when freeform is manually edited
                      final newCtx = ctx.beanBatchId != null
                          ? ctx.clearBeanBatch().copyWith(coffeeName: val)
                          : ctx.copyWith(coffeeName: val);
                      widget.workflowController.setWorkflow(
                        widget.workflowController.currentWorkflow.copyWith(
                          context: newCtx,
                        ),
                      );
                    });
                    setDialogState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        MergeSemantics(
          child: Row(
            spacing: 16,
            children: [
              Text("Roaster"),
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (TextEditingValue val) async {
                    if (val.text.isEmpty || widget.beanStorage == null) return const <String>[];
                    final beans = await widget.beanStorage!.getAllBeans();
                    final matches = beans
                        .where((b) => b.roaster.toLowerCase().contains(val.text.toLowerCase()))
                        .map((b) => b.roaster)
                        .toSet()
                        .toList();
                    if (!matches.contains(val.text)) {
                      return [val.text, ...matches];
                    }
                    return matches;
                  },
                  key: Key(ctx.coffeeRoaster ?? ""),
                  initialValue: TextEditingValue(text: ctx.coffeeRoaster ?? ""),
                  onSelected: (val) {
                    setState(() {
                      // Clear beanBatchId when freeform is manually edited
                      final newCtx = ctx.beanBatchId != null
                          ? ctx.clearBeanBatch().copyWith(coffeeRoaster: val)
                          : ctx.copyWith(coffeeRoaster: val);
                      widget.workflowController.setWorkflow(
                        widget.workflowController.currentWorkflow.copyWith(
                          context: newCtx,
                        ),
                      );
                    });
                    setDialogState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Keep for backward compatibility (used in tests)
  Column _coffeeDataForm() {
    final ctx = widget.workflowController.currentWorkflow.context ?? WorkflowContext();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _coffeeFreeformFields(ctx, (fn) => fn()),
      ],
    );
  }
}

/// Two-step bean → batch picker widget with its own state for batch loading.
class _BeanBatchPickerWidget extends StatefulWidget {
  final List<Bean> beans;
  final BeanStorageService beanStorage;
  final String? currentBatchId;
  final void Function(Bean bean, BeanBatch batch) onBatchSelected;
  final void Function(Bean bean) onBeanSelectedNoBatch;
  final VoidCallback onCleared;

  const _BeanBatchPickerWidget({
    required this.beans,
    required this.beanStorage,
    required this.currentBatchId,
    required this.onBatchSelected,
    required this.onBeanSelectedNoBatch,
    required this.onCleared,
  });

  @override
  State<_BeanBatchPickerWidget> createState() => _BeanBatchPickerWidgetState();
}

class _BeanBatchPickerWidgetState extends State<_BeanBatchPickerWidget> {
  String? _selectedBeanId;
  List<BeanBatch> _batches = [];
  bool _loadingBatches = false;

  @override
  void initState() {
    super.initState();
    // If there's a current batch ID, find which bean it belongs to
    if (widget.currentBatchId != null) {
      _resolveCurrentBatch();
    }
  }

  Future<void> _resolveCurrentBatch() async {
    final batch = await widget.beanStorage.getBatchById(widget.currentBatchId!);
    if (batch != null && mounted) {
      setState(() {
        _selectedBeanId = batch.beanId;
      });
      await _loadBatches(batch.beanId);
    }
  }

  Future<void> _loadBatches(String beanId) async {
    setState(() => _loadingBatches = true);
    final batches = await widget.beanStorage.getBatchesForBean(beanId);
    if (mounted) {
      setState(() {
        _batches = batches;
        _loadingBatches = false;
      });
      // Auto-select if only one batch
      if (batches.length == 1) {
        final bean = widget.beans.firstWhere((b) => b.id == beanId);
        widget.onBatchSelected(bean, batches.first);
      }
    }
  }

  Widget _buildSelectedBatchInfo() {
    final selectedBatch = widget.currentBatchId != null
        ? _batches.where((b) => b.id == widget.currentBatchId).firstOrNull
        : null;
    if (selectedBatch == null) return const SizedBox.shrink();

    final details = <String>[];
    if (selectedBatch.roastLevel != null) details.add(selectedBatch.roastLevel!);
    if (selectedBatch.roastDate != null) {
      details.add('roasted ${selectedBatch.roastDate!.toLocal().toString().split(' ').first}');
    }
    if (selectedBatch.weightRemaining != null) {
      details.add('${selectedBatch.weightRemaining!.toStringAsFixed(0)}g remaining');
    } else if (selectedBatch.weight != null) {
      details.add('${selectedBatch.weight!.toStringAsFixed(0)}g');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            details.join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (selectedBatch.notes != null && selectedBatch.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                selectedBatch.notes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _batchDisplayText(BeanBatch batch) {
    final parts = <String>[];
    if (batch.roastLevel != null) parts.add(batch.roastLevel!);
    if (batch.roastDate != null) {
      parts.add('roasted ${batch.roastDate!.toLocal().toString().split(' ').first}');
    }
    if (batch.weightRemaining != null) {
      parts.add('${batch.weightRemaining!.toStringAsFixed(0)}g left');
    } else if (batch.weight != null) {
      parts.add('${batch.weight!.toStringAsFixed(0)}g');
    }
    return parts.isEmpty ? batch.id.substring(0, 8) : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = widget.currentBatchId != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bean dropdown
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Select coffee bean',
                  isDense: true,
                ),
                value: _selectedBeanId,
                hint: const Text('Choose a bean...'),
                isExpanded: true,
                items: widget.beans.map((b) {
                  return DropdownMenuItem<String>(
                    value: b.id,
                    child: Text(
                      '${b.name} — ${b.roaster}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (beanId) {
                  if (beanId == null) return;
                  setState(() {
                    _selectedBeanId = beanId;
                    _batches = [];
                  });
                  final bean = widget.beans.firstWhere((b) => b.id == beanId);
                  widget.onBeanSelectedNoBatch(bean);
                  _loadBatches(beanId);
                },
              ),
            ),
            if (hasSelection)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                tooltip: 'Clear coffee selection',
                onPressed: () {
                  setState(() {
                    _selectedBeanId = null;
                    _batches = [];
                  });
                  widget.onCleared();
                },
              ),
          ],
        ),
        // Batch dropdown (only when a bean is selected)
        if (_selectedBeanId != null) ...[
          const SizedBox(height: 8),
          if (_loadingBatches)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_batches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('No batches for this bean'),
            )
          else if (_batches.length > 1)
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Select batch',
                isDense: true,
              ),
              value: widget.currentBatchId != null &&
                      _batches.any((b) => b.id == widget.currentBatchId)
                  ? widget.currentBatchId
                  : null,
              hint: const Text('Choose a batch...'),
              isExpanded: true,
              items: _batches.map((batch) {
                return DropdownMenuItem<String>(
                  value: batch.id,
                  child: Text(
                    _batchDisplayText(batch),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (batchId) {
                if (batchId == null) return;
                final batch = _batches.firstWhere((b) => b.id == batchId);
                final bean = widget.beans.firstWhere((b) => b.id == _selectedBeanId);
                widget.onBatchSelected(bean, batch);
              },
            ),
          // Show selected batch info
          if (!_loadingBatches && _batches.isNotEmpty)
            _buildSelectedBatchInfo(),
        ],
      ],
    );
  }
}
