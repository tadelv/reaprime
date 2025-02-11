import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:reaprime/src/models/data/shot_parameters.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ProfileTile extends StatefulWidget {
  final De1Controller de1controller;
  final WorkflowController workflowController;

  const ProfileTile(
      {super.key,
      required this.de1controller,
      required this.workflowController});

  @override
  State<StatefulWidget> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileTile> {
  Profile? loadedProfile;
  TargetShotParameters shotParameters = TargetShotParameters(targetWeight: 0.0);

  final Logger _log = Logger('ProfileTile');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            ShadButton.link(
              child: Text(loadedProfile != null
                  ? loadedProfile!.title
                  : "Load profile"),
              onPressed: () async {
                FilePickerResult? result =
                    await FilePicker.platform.pickFiles();
                if (result != null) {
                  File file = File(result.files.single.path!);
                  var json = jsonDecode(await file.readAsString());
                  setState(() {
                    loadedProfile = Profile.fromJson(json);
                    widget.de1controller
                        .connectedDe1()
                        .setProfile(loadedProfile!);
                    widget.workflowController.loadedProfile = loadedProfile;
                    shotParameters = TargetShotParameters(
                        targetWeight: loadedProfile!.targetWeight ?? 0.0);
                    widget.workflowController.targetShotParameters =
                        shotParameters;
                    _log.fine('Loaded profile: ${loadedProfile!.title}');
                    _log.fine('Target weight: ${loadedProfile!.targetWeight}');
                  });
                }
              },
            ),
            ..._profileStats(),
          ],
        ),
        ..._profileChart(context),
        ..._workflow(context),
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
            maxY: profileMaxVal > 10 ? 12 : profileMaxVal + 2,
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
    ];
  }

  List<Widget> _workflow(BuildContext context) {
    return [
      SizedBox(
        height: 64,
        child: Row(
          children: [
            _weightPopover(context),
          ],
        ),
      )
    ];
  }

  final weightPopoverController = ShadPopoverController();

  ShadPopover _weightPopover(BuildContext context) {
    return ShadPopover(
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
                    initialValue: 0.0.toStringAsFixed(1),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text("Ratio 1:"),
                Expanded(
                  child: ShadInput(
                    initialValue: 0.0.toStringAsFixed(1),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text("Target weight"),
                Expanded(
                  child: ShadInput(
                    initialValue: 0.0.toStringAsFixed(1),
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
        child: Text(
            "${widget.workflowController.targetShotParameters?.targetWeight.toStringAsFixed(1)}"),
      ),
    );
  }
}
