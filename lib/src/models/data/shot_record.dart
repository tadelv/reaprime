import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ShotRecord {
  final String id;
  final DateTime timestamp;
  final List<ShotSnapshot> measurements;
  final Workflow workflow;
  final String? shotNotes;
  
  ShotRecord({
    required this.id,
    required this.timestamp,
    required this.measurements,
    required this.workflow,
    this.shotNotes,
  });

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "timestamp": timestamp.toIso8601String(),
      "measurements": measurements.map((e) => e.toJson()).toList(),
      "workflow": workflow.toJson(),
      if (shotNotes != null) "shotNotes": shotNotes,
    };
  }

  factory ShotRecord.fromJson(Map<String, dynamic> json) {
    return ShotRecord(
      id: json["id"],
      timestamp: DateTime.parse(json["timestamp"]),
      measurements: (json["measurements"] as List)
          .map((e) => ShotSnapshot.fromJson(e))
          .toList(),
      workflow: Workflow.fromJson(json["workflow"]),
      shotNotes: json["shotNotes"] as String?,
    );
  }

  String shotTime() {
    // final now = DateTime.now();
    // if (record.timestamp.isSameDay(now)) {
    //     return "${record.timestamp.difference(now).}"
    //   }
    final dateFormat = DateFormat.yMd();
    final timeFormat = DateFormat('jm');
    return "${dateFormat.format(timestamp)}, ${timeFormat.format(timestamp)}";
  }

  ShotRecord copyWith({
    String? id,
    DateTime? timestamp,
    List<ShotSnapshot>? measurements,
    Workflow? workflow,
    String? shotNotes,
  }) {
    return ShotRecord(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      measurements: measurements ?? this.measurements,
      workflow: workflow ?? this.workflow,
      shotNotes: shotNotes ?? this.shotNotes,
    );
  }
}
