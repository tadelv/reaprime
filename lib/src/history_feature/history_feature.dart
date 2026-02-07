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
  final Logger _log = Logger("HistoryFeature");
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
    final Map<String, dynamic> json = jsonDecode(widget.selectedShot!) as Map<String, dynamic>;
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
        // Search in coffee name
        if (record.workflow.coffeeData?.name.toLowerCase().contains(text) ?? false) {
          return true;
        }
        
        // Search in roaster
        if (record.workflow.coffeeData?.roaster?.toLowerCase().contains(text) ?? false) {
          return true;
        }
        
        // Search in profile title
        if (record.workflow.profile.title.toLowerCase().contains(text)) {
          return true;
        }
        
        // Search in grinder model
        if (record.workflow.grinderData?.model?.toLowerCase().contains(text) ?? false) {
          return true;
        }
        
        // Search in grinder manufacturer
        if (record.workflow.grinderData?.manufacturer?.toLowerCase().contains(text) ?? false) {
          return true;
        }
        
        // Search in shot notes
        if (record.shotNotes?.toLowerCase().contains(text) ?? false) {
          return true;
        }
        
        // Search in metadata values (recursive search through nested structures)
        if (record.metadata != null && _searchInMetadata(record.metadata!, text)) {
          return true;
        }
        
        return false;
      }).toList();
    });
  }

  bool _searchInMetadata(Map<String, dynamic> metadata, String searchText) {
    for (var value in metadata.values) {
      if (value == null) continue;
      
      // Handle string values
      if (value is String && value.toLowerCase().contains(searchText)) {
        return true;
      }
      
      // Handle list values (e.g., tags)
      if (value is List) {
        for (var item in value) {
          if (item is String && item.toLowerCase().contains(searchText)) {
            return true;
          }
          // Handle numeric values in lists
          if (item != null && item.toString().toLowerCase().contains(searchText)) {
            return true;
          }
        }
      }
      
      // Handle nested maps
      if (value is Map<String, dynamic>) {
        if (_searchInMetadata(value, searchText)) {
          return true;
        }
      }
      
      // Handle other types (numbers, booleans) by converting to string
      if (value.toString().toLowerCase().contains(searchText)) {
        return true;
      }
    }
    return false;
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchBar(
                  controller: _searchController,
                  hintText: "Search by coffee, roaster, profile, grinder, or notes...",
                ),
                if (_searchController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                    child: Text(
                      "Found ${_filteredShots.length} shot${_filteredShots.length == 1 ? '' : 's'}",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredShots.length,
              itemBuilder: (context, index) {
                final ShotRecord record = _filteredShots[index];
                final isSelected = _selectedShot?.id == record.id;
                final duration = record.measurements.isNotEmpty
                    ? record.measurements.last.machine.timestamp.difference(record.timestamp)
                    : Duration.zero;
                final durationSeconds = duration.inSeconds;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: TapRegion(
                    onTapUpInside: (_) {
                      setState(() {
                        _selectedShot = record;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                            : null,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ShadCard(
                        backgroundColor: Colors.transparent,
                        padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with time and duration
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                record.shotTime(),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "${durationSeconds}s",
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // Coffee and roaster
                          if (record.workflow.coffeeData != null) ...[
                            Row(
                              children: [
                                Icon(Icons.coffee, size: 14, color: Theme.of(context).colorScheme.secondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    record.workflow.coffeeData!.name,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (record.workflow.coffeeData!.roaster != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 18, top: 2),
                                child: Text(
                                  record.workflow.coffeeData!.roaster!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.secondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            const SizedBox(height: 6),
                          ],
                          
                          // Profile name
                          Row(
                            children: [
                              Icon(Icons.dashboard_customize, size: 14, color: Theme.of(context).colorScheme.secondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  record.workflow.profile.title,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          
                          // Dose ratio
                          Row(
                            children: [
                              Icon(Icons.scale, size: 14, color: Theme.of(context).colorScheme.secondary),
                              const SizedBox(width: 4),
                              Text(
                                "${record.workflow.doseData.doseIn}g → ${record.workflow.doseData.doseOut}g",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "(1:${(record.workflow.doseData.doseOut / record.workflow.doseData.doseIn).toStringAsFixed(1)})",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            ],
                          ),
                          
                          // Grinder info
                          if (record.workflow.grinderData != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.settings, size: 14, color: Theme.of(context).colorScheme.secondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "${record.workflow.grinderData!.model ?? 'Grinder'}: ${record.workflow.grinderData!.setting}",
                                    style: Theme.of(context).textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          
                          // Notes preview
                          if (record.shotNotes != null && record.shotNotes!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.note, size: 12, color: Theme.of(context).colorScheme.secondary),
                                  const SizedBox(width: 4),
                                  Expanded(
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
                          ],
                          
                          // Metadata tags
                          if (record.metadata != null && record.metadata!['tags'] != null) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (var tag in (record.metadata!['tags'] as List).take(3))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      tag.toString(),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      ),
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
    final duration = record.measurements.isNotEmpty
        ? record.measurements.last.machine.timestamp.difference(record.timestamp)
        : Duration.zero;
    final ratio = record.workflow.doseData.doseOut / record.workflow.doseData.doseIn;
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.workflow.coffeeData?.name ?? "Shot Details",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        record.shotTime(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton.outline(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 16),
                          SizedBox(width: 4),
                          Text("Edit"),
                        ],
                      ),
                      onPressed: () => _showEditDialog(context, record),
                    ),
                    ShadButton(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay, size: 16),
                          SizedBox(width: 4),
                          Text("Repeat"),
                        ],
                      ),
                      onPressed: () {
                        widget.workflowController.setWorkflow(record.workflow.copyWith());
                      },
                    ),
                    ShadButton.destructive(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete, size: 16),
                          SizedBox(width: 4),
                          Text("Delete"),
                        ],
                      ),
                      onPressed: () => _confirmDelete(context, record),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 24),
            
            // Quick stats cards
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.timer,
                    label: "Duration",
                    value: "${duration.inSeconds}s",
                    context: context,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.scale,
                    label: "Ratio",
                    value: "1:${ratio.toStringAsFixed(1)}",
                    context: context,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.arrow_forward,
                    label: "Yield",
                    value: "${record.workflow.doseData.doseOut}g",
                    context: context,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            
            // Coffee details section
            ShadCard(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.coffee, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Coffee Details",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _DetailRow(
                    label: "Bean",
                    value: record.workflow.coffeeData?.name ?? "Not specified",
                    context: context,
                  ),
                  if (record.workflow.coffeeData?.roaster != null)
                    _DetailRow(
                      label: "Roaster",
                      value: record.workflow.coffeeData!.roaster!,
                      context: context,
                    ),
                  _DetailRow(
                    label: "Dose In",
                    value: "${record.workflow.doseData.doseIn}g",
                    context: context,
                  ),
                  _DetailRow(
                    label: "Dose Out",
                    value: "${record.workflow.doseData.doseOut}g",
                    context: context,
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            
            // Equipment section
            ShadCard(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Equipment",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _DetailRow(
                    label: "Profile",
                    value: record.workflow.profile.title,
                    context: context,
                  ),
                  if (record.workflow.grinderData != null) ...[
                    _DetailRow(
                      label: "Grinder",
                      value: record.workflow.grinderData!.model ?? "Unknown",
                      context: context,
                    ),
                    if (record.workflow.grinderData!.manufacturer != null)
                      _DetailRow(
                        label: "Brand",
                        value: record.workflow.grinderData!.manufacturer!,
                        context: context,
                      ),
                    _DetailRow(
                      label: "Setting",
                      value: record.workflow.grinderData!.setting,
                      context: context,
                    ),
                  ],
                ],
              ),
            ),
            
            // Notes section
            if (record.shotNotes != null && record.shotNotes!.isNotEmpty) ...[
              SizedBox(height: 16),
              ShadCard(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.note, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Notes",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      record.shotNotes!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
            
            // Metadata section
            if (record.metadata != null && record.metadata!.isNotEmpty) ...[
              SizedBox(height: 16),
              ShadCard(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.label, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Additional Info",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    ...record.metadata!.entries.map((entry) {
                      if (entry.key == 'tags' && entry.value is List) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Tags:",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                              SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (var tag in (entry.value as List))
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        tag.toString(),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }
                      return _DetailRow(
                        label: entry.key,
                        value: entry.value.toString(),
                        context: context,
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
            
            SizedBox(height: 20),
            
            // Chart section
            Text(
              "Shot Profile",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            ShotChart(
              key: ValueKey(record.id),
              shotSnapshots: record.measurements,
              shotStartTime: record.timestamp,
            ),
            
            SizedBox(height: 16),
            // Shot ID footer
            Center(
              child: Text(
                "Shot ID: ${record.id}",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
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

// Helper widgets
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final BuildContext context;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.context,
  });

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final BuildContext context;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.context,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              "$label:",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
