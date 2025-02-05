import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';

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
  @override
  initState() {
    super.initState();
    _shotController = ShotController(
      de1controller: widget.de1controller,
      scaleController: widget.scaleController,
    );
    _shotSubscription = _shotController.shotData.listen((event) {
      print(event);
      setState(() {
        _shotSnapshots.add(event);
      });
    });
  }

  @override
  void dispose() {
    _shotSubscription.cancel();
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
              SizedBox(
                height: 500,
                child: LineChart(
                  LineChartData(
                    lineBarsData: [...shotChartData()],
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
            .map((e) => FlSpot(
                e.machine.timestamp.millisecondsSinceEpoch.toDouble(),
                e.machine.flow))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.green,
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(
                e.machine.timestamp.millisecondsSinceEpoch.toDouble(),
                e.machine.pressure))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.red,
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(
                e.machine.timestamp.millisecondsSinceEpoch.toDouble(),
                e.machine.groupTemperature))
            .toList(),
      ),
      LineChartBarData(
        color: Colors.orange,
        dashArray: [5, 5],
        dotData: FlDotData(show: false),
        spots: _shotSnapshots
            .map((e) => FlSpot(
                e.machine.timestamp.millisecondsSinceEpoch.toDouble(),
                e.machine.mixTemperature))
            .toList(),
      ),
    ];
  }
}
