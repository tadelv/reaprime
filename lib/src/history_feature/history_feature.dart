import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/util/shot_chart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HistoryFeature extends StatefulWidget {
  static const routeName = '/history';

  const HistoryFeature({
    super.key,
    required this.persistenceController,
    required this.workflowController,
    this.selectedShot,
  });

  final PersistenceController persistenceController;
  final WorkflowController workflowController;
  final String? selectedShot;

  @override
  State<StatefulWidget> createState() => _HistoryFeatureState();
}

class _HistoryFeatureState extends State<HistoryFeature> {
  Logger _log = Logger("HistoryFeature");
  final TextEditingController _searchController = TextEditingController();

  List<ShotRecord> _shots = [];
  List<ShotRecord> _filteredShots = [];
  late StreamSubscription<List<ShotRecord>> _shotsSubscription;

  ShotRecord? _selectedShot;

  @override
  void initState() {
    _shotsSubscription = widget.persistenceController.shots.listen((records) {
      setState(() {
        _shots = records
            .sorted((a, b) => a.timestamp.isBefore(b.timestamp) ? 1 : -1);
        if (_searchController.text.isEmpty) {
          _filteredShots = _shots;
        }
      });
    });
    _searchController.addListener(searchTextUpdate);
    if (widget.selectedShot != null) {
      setSelectedShot("");
    }
    super.initState();
  }

  void setSelectedShot(String id) {
    final json = jsonDecode(widget.selectedShot!);
    final shot = ShotRecord.fromJson(json);
    _selectedShot = shot;
  }

  @override
  void dispose() {
    _shotsSubscription.cancel();
    _searchController.removeListener(searchTextUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("History")),
      body: body(context),
    );
  }

  searchTextUpdate() {
    final text = _searchController.text.toLowerCase();
    if (text.isEmpty) {
      setState(() {
        _filteredShots = _shots;
      });
      return;
    }
    setState(() {
      _filteredShots = _shots.where((record) {
        return record.workflow.coffeeData?.name.toLowerCase().contains(text) ??
            false;
      }).toList();
    });
  }

  Widget body(BuildContext context) {
    return SafeArea(
        child: Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leftColumn(context),
        rightColumn(context),
      ],
    ));
  }

  Widget leftColumn(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SearchBar(
            controller: _searchController,
            hintText: "Search shots",
          ),
          Expanded(
            child: ListView.builder(
                itemCount: _filteredShots.length,
                itemBuilder: (context, index) {
                  final ShotRecord record = _filteredShots[index];
                  return TapRegion(
                    onTapUpInside: (_) {
                      setState(() {
                        _selectedShot = record;
                      });
                    },
                    child: ShadCard(
                        title: Text(record.shotTime()),
                        description: Text(record.workflow.name),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                "${record.workflow.doseData.doseIn}g => ${record.workflow.doseData.doseOut}g"),
                            if (record.workflow.coffeeData != null)
                              Text("${record.workflow.coffeeData!.name}"),
                            Text(
                                "${record.measurements.last.machine.timestamp.difference(record.timestamp).toString()}")
                          ],
                        )),
                  );
                }),
          )
        ],
      ),
    );
  }

  Widget rightColumn(BuildContext context) {
    return Expanded(
        flex: 2,
        child: _selectedShot != null
            ? shotDetail(context, _selectedShot!)
            : Center(child: Text("No shot selected")));
  }

  Widget shotDetail(BuildContext context, ShotRecord record) {
    return Column(
      children: [
        Text("${record.id}"),
        if (record.workflow.grinderData != null)
          Text(
              "${record.workflow.grinderData!.model}: ${record.workflow.grinderData!.setting}"),
        Text("Profile: ${record.workflow.profile.title}"),
        ShadButton(
          child: Text("Repeat"),
          onPressed: () {
            widget.workflowController.setWorkflow(
              record.workflow.copyWith(),
            );
          },
        ),
        Hero(
          tag: "shotHistory",
          child: ShotChart(
            shotSnapshots: record.measurements,
            shotStartTime: record.timestamp,
          ),
        ),
      ],
    );
  }
}
