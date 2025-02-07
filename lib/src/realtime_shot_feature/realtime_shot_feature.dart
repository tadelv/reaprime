import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RealtimeShotFeature extends StatefulWidget {
  static const routeName = '/shot';

  final De1Controller de1controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;

  const RealtimeShotFeature({
    super.key,
    required this.de1controller,
    required this.scaleController,
    required this.workflowController,
  });

  @override
  State<StatefulWidget> createState() => _RealtimeShotFeatureState();
}

class _RealtimeShotFeatureState extends State<RealtimeShotFeature> {
  late ShotController _shotController;
  final List<ShotSnapshot> _shotSnapshots = [];
  late StreamSubscription<ShotSnapshot> _shotSubscription;
  late StreamSubscription<bool> _resetCommandSubscription;
  late StreamSubscription<ShotState> _stateSubscription;
  bool backEnabled = false;
  @override
  initState() {
    super.initState();
    _shotController = ShotController(
      de1controller: widget.de1controller,
      scaleController: widget.scaleController,
			targetShot: widget.workflowController.targetShotParameters,
    );
    _resetCommandSubscription = _shotController.resetCommand.listen((event) {
      setState(() {
        _shotSnapshots.clear();
      });
    });
    _shotSubscription = _shotController.shotData.listen((event) {
      setState(() {
        _shotSnapshots.add(event);
      });
    });
    _stateSubscription = _shotController.state.listen((state) {
      if (state == ShotState.finished || state == ShotState.idle) {
        backEnabled = true;
      } else {
        backEnabled = false;
      }
    });
  }

  @override
  void dispose() {
    _shotSubscription.cancel();
    _resetCommandSubscription.cancel();
    _stateSubscription.cancel();
    _shotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              _shotStats(context),
              _shotChart(context),
              _buttons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shotStats(BuildContext context) {
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.titleMedium!,
      child: Row(
        children: [
          Spacer(),
          Text(
              "Time: ${DateTime.now().difference(_shotController.shotStartTime).inSeconds}s"),
          Spacer(),
          Text(
              "Status: ${_shotSnapshots.lastOrNull?.machine.state.substate.name}"),
          Spacer(),
          Text("Step: ${_currentStep()}"),
          Spacer(),
          Text(
              "Flow: ${_shotSnapshots.lastOrNull?.machine.flow.toStringAsFixed(1)}"),
          Spacer(),
          Text(
              "Pressure: ${_shotSnapshots.lastOrNull?.machine.pressure.toStringAsFixed(1)}"),
          Spacer(),
          Text(
              "Group Temp: ${_shotSnapshots.lastOrNull?.machine.groupTemperature.toStringAsFixed(1)}"),
          Spacer(),
          if (_shotSnapshots.lastOrNull?.scale != null)
            Text(
                "Scale Weight: ${_shotSnapshots.lastOrNull?.scale?.weight.toStringAsFixed(1)}"),
          if (_shotSnapshots.lastOrNull?.scale != null)
            Text(
                "Scale Weight Flow: ${_shotSnapshots.lastOrNull?.scale?.weightFlow.toStringAsFixed(1)}"),
          Spacer(),
        ],
      ),
    );
  }

  String _currentStep() {
    if (widget.workflowController.loadedProfile == null ||
        _shotSnapshots.lastOrNull == null) {
      return "Unknown";
    }
    Profile profile = widget.workflowController.loadedProfile!;
    int lastFrame = _shotSnapshots.lastOrNull!.machine.profileFrame;
    return profile.steps[lastFrame].name;
  }

  Padding _shotChart(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        height: 500,
        child: LineChart(
          LineChartData(
            lineBarsData: [..._shotChartData()],
            minY: 0,
            maxY: 11,
            titlesData: FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                      showTitles: true,
                      //interval: 5,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final int seconds = (value / 1000).toInt();
                        String text;

                        if (value / 1000 < 60) {
                          // For less than 60 seconds, show ticks every 5 seconds with just seconds.
                          if (value.toInt() % 1000 == 0) {
                            text = '$seconds s';
                          } else {
                            return Container(); // return an empty widget for non-tick values
                          }
                        } else if (value / 1000 <= 120) {
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
                      })),
            ),
          ),
          duration: Duration(milliseconds: 0),
          curve: Curves.easeInOutCubic,
        ),
      ),
    );
  }

  List<LineChartBarData> _shotChartData() {
    return [
      LineChartBarData(
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(_timestamp(e.machine.timestamp), e.machine.flow))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.green,
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) =>
                FlSpot(_timestamp(e.machine.timestamp), e.machine.pressure))
            .toList(),
      ),
      LineChartBarData(
        dotData: FlDotData(show: false),
        dashArray: [5, 5],
        spots: _shotSnapshots
            .map((e) =>
                FlSpot(_timestamp(e.machine.timestamp), e.machine.targetFlow))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.green,
        dashArray: [5, 5],
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(
                _timestamp(e.machine.timestamp), e.machine.targetPressure))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.red,
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(_timestamp(e.machine.timestamp),
                e.machine.groupTemperature / 10.0))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.orange,
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(_timestamp(e.machine.timestamp),
                e.machine.mixTemperature / 10.0))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.red,
        dashArray: [5, 5],
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(_timestamp(e.machine.timestamp),
                e.machine.targetGroupTemperature / 10.0))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.orange,
        dashArray: [5, 5],
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(_timestamp(e.machine.timestamp),
                e.machine.targetMixTemperature / 10.0))
            .toList(),
      ),
      ..._scaleData(),
    ];
  }

  List<LineChartBarData> _scaleData() {
    if (_shotSnapshots.firstOrNull?.scale == null) {
      return [];
    }
    return [
      LineChartBarData(
        color: Colors.purpleAccent,
        dashArray: [5, 5],
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) =>
                FlSpot(_timestamp(e.machine.timestamp), e.scale!.weight / 10.0))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.purple,
        dotData: FlDotData(show: false),
        spots: _shotSnapshots.map((e) {
          return FlSpot(_timestamp(e.machine.timestamp), e.scale!.weightFlow);
        }).toList(),
      ),
    ];
  }

  double _timestamp(DateTime snapshot) {
    return snapshot
        .difference(_shotController.shotStartTime)
        .inMilliseconds
        .toDouble();
  }

  Widget _buttons(BuildContext context) {
    return Row(
      children: [
        ShadButton(
          enabled: backEnabled,
          icon: Icon(Icons.home),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        Spacer(),
        ShadButton.destructive(
          enabled: !backEnabled,
          onPressed: () {
            widget.de1controller.connectedDe1().requestState(MachineState.idle);
          },
          child: Text('Stop Shot'),
        ),
        ShadButton.secondary(
          enabled: !backEnabled,
          onPressed: () {
            widget.de1controller
                .connectedDe1()
                .requestState(MachineState.skipStep);
          },
          child: Text('Skip Step'),
        ),
        Spacer(),
      ],
    );
  }
}
