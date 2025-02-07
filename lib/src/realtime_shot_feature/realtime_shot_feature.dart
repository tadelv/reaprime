import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/util/moving_average.dart';

class RealtimeShotFeature extends StatefulWidget {
  static const routeName = '/shot';

  final De1Controller de1controller;
  final ScaleController scaleController;

  const RealtimeShotFeature(
      {super.key, required this.de1controller, required this.scaleController});

  @override
  State<StatefulWidget> createState() => _RealtimeShotFeatureState();
}

class _RealtimeShotFeatureState extends State<RealtimeShotFeature> {
  late ShotController _shotController;
  final List<ShotSnapshot> _shotSnapshots = [];
  late StreamSubscription<ShotSnapshot> _shotSubscription;
  late StreamSubscription<bool> _resetCommandSubscription;
  @override
  initState() {
    super.initState();
    _shotController = ShotController(
      de1controller: widget.de1controller,
      scaleController: widget.scaleController,
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
  }

  @override
  void dispose() {
    _shotSubscription.cancel();
    _resetCommandSubscription.cancel();
    _shotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Realtime Shot'),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'Realtime Shot Feature',
                style: TextStyle(fontSize: 24),
              ),
              Text(
                  "State: ${_shotSnapshots.lastOrNull?.machine.state.state.name}"),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  height: 500,
                  child: LineChart(
                    LineChartData(
                      lineBarsData: [...shotChartData()],
                      minY: 0,
                      maxY: 11,
                      titlesData: FlTitlesData(
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                //interval: 5,
                                getTitlesWidget:
                                    (double value, TitleMeta meta) {
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  );
                                })),
                      ),
                    ),
                    duration: Duration(milliseconds: 0),
                    curve: Curves.easeInOutCubic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<LineChartBarData> shotChartData() {
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
    final MovingAverage weightAverage = MovingAverage(10);
    double previousWeight = 0.0;
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
          var weightDiff = e.scale!.weight - previousWeight;
          previousWeight = e.scale!.weight;
          weightAverage.add(weightDiff);
          var weightFlow = weightAverage.average;
          return FlSpot(_timestamp(e.machine.timestamp), weightFlow);
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
}
