import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ProfileTile extends StatefulWidget {
  final De1Controller de1controller;

  const ProfileTile({super.key, required this.de1controller});

  @override
  State<StatefulWidget> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileTile> {
  Profile? loadedProfile;

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
                  });
                }
              },
            ),
            ..._profileStats(),
          ],
        ),
        ..._profileChart(context),
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
		var profileMaxVal = profile.steps.fold(0.0, (m, s) => max(m, s.getTarget()));
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
                    final int seconds = value.toInt();
                    String text;

                    if (profileTime < 60) {
                      // For less than 60 seconds, show ticks every 5 seconds with just seconds.
                      if (seconds % 5 == 0) {
                        text = '$seconds s';
                      } else {
                        return Container(); // return an empty widget for non-tick values
                      }
                    } else if (profileTime < 120) {
                      // For 60 seconds or more, display minutes and seconds.
                      final int minutes = seconds ~/ 60;
                      final int remainingSeconds = seconds % 60;
                      if (seconds % 5 == 0) {
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
    double seconds = 0;
    for (var step in profile.steps) {
      if (step is ProfileStepFlow) {
        flowData.add(FlSpot(seconds, step.getTarget()));
        pressureData.add(FlSpot(seconds, step.limiter?.value ?? 0));
      } else {
        pressureData.add(FlSpot(seconds, step.getTarget()));
        flowData.add(FlSpot(seconds, step.limiter?.value ?? 0));
      }
      seconds += step.seconds;

      if (step is ProfileStepFlow) {
        flowData.add(FlSpot(seconds, step.getTarget()));
        pressureData.add(FlSpot(seconds, step.limiter?.value ?? 0));
      } else {
        pressureData.add(FlSpot(seconds, step.getTarget()));
        flowData.add(FlSpot(seconds, step.limiter?.value ?? 0));
      }
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
    ];
  }
}
