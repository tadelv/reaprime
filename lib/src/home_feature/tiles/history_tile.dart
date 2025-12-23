import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/history_feature/history_feature.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/util/shot_chart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HistoryTile extends StatefulWidget {
  final PersistenceController persistenceController;
  final WorkflowController workflowController;

  const HistoryTile({
    super.key,
    required this.persistenceController,
    required this.workflowController,
  });

  @override
  State<HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<HistoryTile> {
  late StreamSubscription<List<ShotRecord>> _recordsSubscription;

  List<ShotRecord> _shotHistory = [];
  int _selectedShotIndex = 0;
  @override
  void initState() {
    super.initState();
    _recordsSubscription = widget.persistenceController.shots.listen((data) {
      setState(() {
        _shotHistory = data.sortedBy((el) => el.timestamp);
        Logger("History")
            .fine("shots: ${_shotHistory.map((e) => e.timestamp)}");
        _selectedShotIndex = _shotHistory.length - 1;
      });
    });
  }

  @override
  void dispose() {
    _recordsSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_shotHistory.length) {
      case 0:
        return Text("No shots yet.");
      default:
        return _body(context);
    }
  }


  Widget _body(BuildContext context) {
    var shot = _shotHistory[_selectedShotIndex];
    var canGoBack = _selectedShotIndex > 0;
    var canGoForward = _selectedShotIndex < _shotHistory.length - 1;
    return Column(
      //key: Key(shot.timestamp.toIso8601String()),
      children: [
        Text(
          shot.shotTime(),
        ),
        TapRegion(
          child: _shotDetails(context, shot),
          onTapInside: (cb) {
            Navigator.pushNamed(context, HistoryFeature.routeName,
                arguments: jsonEncode(shot.toJson()));
          },
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          ShadButton(
            onPressed: () {
              setState(() {
                _selectedShotIndex -= 1;
              });
            },
            enabled: canGoBack,
            child: Icon(LucideIcons.moveLeft),
          ),
          ShadButton(
            onPressed: () {
              widget.workflowController.setWorkflow(shot.workflow);
            },
            child: Text("Repeat"),
          ),
          ShadButton(
            onPressed: () {
              setState(() {
                _selectedShotIndex += 1;
              });
            },
            enabled: canGoForward,
            child: Icon(LucideIcons.moveRight),
          )
        ])
      ],
    );
  }

  Widget _shotDetails(BuildContext context, ShotRecord shot) {
    var shotStart = shot.measurements
        .firstWhere(
            (el) =>
                el.machine.state.substate == MachineSubstate.preinfusion ||
                el.machine.state.substate == MachineSubstate.pouring,
            orElse: () => shot.measurements.first)
        .machine
        .timestamp;
    return Hero(
      tag: "shotHistory",
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: ShotChart(
              shotSnapshots: shot.measurements,
              shotStartTime: shotStart,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${shot.workflow.profile.title}"),
              Text(
                  "${shot.workflow.doseData.doseIn.toStringAsFixed(1)} : ${shot.workflow.doseData.doseOut.toStringAsFixed(1)}"),
              Text(
                  "${shot.measurements.last.scale?.weight.toStringAsFixed(1)}g")
            ],
          ),
          if (shot.workflow.coffeeData != null)
            Row(
              children: [
                Text("${shot.workflow.coffeeData!.name}"),
              ],
            ),
          if (shot.workflow.grinderData != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text("${shot.workflow.grinderData!.model}"),
                Text("${shot.workflow.grinderData!.setting}"),
              ],
            ),
        ],
      ),
    );
  }
}
