import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';

class ShotRecord {
  final String id;
  final DateTime timestamp;
  final List<ShotSnapshot> measurements;
  final Workflow workflow;
  ShotRecord(
      {required this.id,
      required this.timestamp,
      required this.measurements,
      required this.workflow});

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "timestamp": timestamp.toIso8601String(),
      "measurements": measurements.map((e) => e.toJson()).toList(),
      "workflow": workflow.toJson()
    };
  }

  factory ShotRecord.fromJson(Map<String, dynamic> json) {
    return ShotRecord(
        id: json["id"],
        timestamp: DateTime.parse(json["timestamp"]),
        measurements: (json["measurements"] as List)
            .map((e) => ShotSnapshot.fromJson(e))
            .toList(),
        workflow: Workflow.fromJson(json["workflow"]));
  }
}
