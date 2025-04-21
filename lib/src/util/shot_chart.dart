import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';

class ShotChart extends StatelessWidget {
  final List<ShotSnapshot> _shotSnapshots;
  final DateTime _shotStartTime;

  const ShotChart({
    super.key,
    required shotSnapshots,
    required shotStartTime,
  })  : _shotStartTime = shotStartTime,
        _shotSnapshots = shotSnapshots;

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
            clipData: FlClipData.all(),
          ),
          duration: Duration(milliseconds: 500),
          // curve: Curves.fastLinearToSlowEaseIn,
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
    return snapshot.difference(_shotStartTime).inMilliseconds.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return _shotChart(context);
  }
}
