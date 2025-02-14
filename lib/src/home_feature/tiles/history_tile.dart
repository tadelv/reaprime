import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HistoryTile extends StatefulWidget {
  final PersistenceController persistenceController;

  const HistoryTile({
    super.key,
    required this.persistenceController,
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
        var shot = _shotHistory[_selectedShotIndex];
        return _shotDetails(context, shot);
    }
  }

  Widget _shotDetails(BuildContext context, ShotRecord shot) {
    return Column(
      children: [
        Row(
          children: [
            Text("${shot.workflow.profile.title}"),
            Text(
                "${shot.workflow.doseData.doseIn} : ${shot.workflow.doseData.doseOut}"),
            Text("${shot.measurements.last.scale?.weight.toStringAsFixed(1)}g")
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
            children: [
              Text("${shot.workflow.grinderData!.model}"),
              Text("${shot.workflow.grinderData!.setting}"),
            ],
          ),
      ],
    );
  }
}
