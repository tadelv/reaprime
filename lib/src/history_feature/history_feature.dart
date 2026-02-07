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
        _shots = records.sorted(
          (a, b) => a.timestamp.isBefore(b.timestamp) ? 1 : -1,
        );
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
      _filteredShots =
          _shots.where((record) {
            return record.workflow.coffeeData?.name.toLowerCase().contains(
                  text,
                ) ??
                false;
          }).toList();
    });
  }

  Widget body(BuildContext context) {
    return SafeArea(
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [leftColumn(context), rightColumn(context)],
      ),
    );
  }

  Widget leftColumn(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SearchBar(controller: _searchController, hintText: "Search shots"),
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
                          "${record.workflow.doseData.doseIn}g => ${record.workflow.doseData.doseOut}g",
                        ),
                        if (record.workflow.coffeeData != null)
                          Text("${record.workflow.coffeeData!.name}"),
                        Text(
                          "${record.measurements.last.machine.timestamp.difference(record.timestamp).toString()}",
                        ),
                        if (record.shotNotes != null && record.shotNotes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              record.shotNotes!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget rightColumn(BuildContext context) {
    return Expanded(
      flex: 2,
      child:
          _selectedShot != null
              ? shotDetail(context, _selectedShot!)
              : Center(child: Text("No shot selected")),
    );
  }

  Widget shotDetail(BuildContext context, ShotRecord record) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text("Shot ID: ${record.id}", style: Theme.of(context).textTheme.bodySmall)),
                Row(
                  children: [
                    ShadButton(
                      child: Text("Edit"),
                      onPressed: () => _showEditDialog(context, record),
                    ),
                    SizedBox(width: 8),
                    ShadButton(
                      child: Text("Repeat"),
                      onPressed: () {
                        widget.workflowController.setWorkflow(record.workflow.copyWith());
                      },
                    ),
                    SizedBox(width: 8),
                    ShadButton.destructive(
                      child: Text("Delete"),
                      onPressed: () => _confirmDelete(context, record),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            if (record.workflow.grinderData != null)
              Text(
                "Grinder: ${record.workflow.grinderData!.model} - ${record.workflow.grinderData!.setting}",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            SizedBox(height: 8),
            Text(
              "Profile: ${record.workflow.profile.title}",
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: 8),
            if (record.shotNotes != null && record.shotNotes!.isNotEmpty)
              ShadCard(
                title: Text("Notes"),
                child: Text(record.shotNotes!),
              ),
            SizedBox(height: 16),
            ShotChart(
              key: ValueKey(record.id),
              shotSnapshots: record.measurements,
              shotStartTime: record.timestamp,
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, ShotRecord record) {
    final notesController = TextEditingController(text: record.shotNotes ?? '');

    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: Text('Edit Shot'),
        description: Text('Update shot notes'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(
                controller: notesController,
                placeholder: const Text('Add notes about this shot...'),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          ShadButton.outline(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ShadButton(
            child: const Text('Save'),
            onPressed: () async {
              try {
                final updatedShot = record.copyWith(
                  shotNotes: notesController.text.isEmpty ? null : notesController.text,
                );
                await widget.persistenceController.updateShot(updatedShot);
                Navigator.of(context).pop();
                setState(() {
                  _selectedShot = updatedShot;
                });
              } catch (e) {
                _log.severe("Failed to update shot", e);
                // Show error toast
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update shot: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, ShotRecord record) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete Shot'),
        description: Text('Are you sure you want to delete this shot? This action cannot be undone.'),
        actions: [
          ShadButton.outline(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ShadButton.destructive(
            child: const Text('Delete'),
            onPressed: () async {
              try {
                await widget.persistenceController.deleteShot(record.id);
                Navigator.of(context).pop();
                setState(() {
                  _selectedShot = null;
                });
              } catch (e) {
                _log.severe("Failed to delete shot", e);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete shot: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
