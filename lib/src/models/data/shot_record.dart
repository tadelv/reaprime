import 'package:reaprime/src/models/data/shot_annotations.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ShotRecord {
  final String id;
  final DateTime timestamp;
  final List<ShotSnapshot> measurements;
  final Workflow workflow;
  final ShotAnnotations? annotations;

  // Legacy fields kept for backward compatibility during migration.
  final String? _shotNotes;
  final Map<String, dynamic>? _metadata;

  ShotRecord({
    required this.id,
    required this.timestamp,
    required this.measurements,
    required this.workflow,
    this.annotations,
    String? shotNotes,
    Map<String, dynamic>? metadata,
  })  : _shotNotes = shotNotes ?? annotations?.espressoNotes,
        _metadata = metadata ?? annotations?.extras;

  /// Synthesized from annotations when available, otherwise from legacy field.
  @Deprecated('Use annotations?.espressoNotes instead')
  String? get shotNotes => _shotNotes;

  @Deprecated('Use annotations?.extras instead')
  Map<String, dynamic>? get metadata => _metadata;

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "timestamp": timestamp.toIso8601String(),
      "measurements": measurements.map((e) => e.toJson()).toList(),
      "workflow": workflow.toJson(),
      if (annotations != null) "annotations": annotations!.toJson(),
      // Write legacy fields too for backward compat with older app versions
      if (_shotNotes != null) "shotNotes": _shotNotes,
      if (_metadata != null) "metadata": _metadata,
    };
  }

  factory ShotRecord.fromJson(Map<String, dynamic> json) {
    // Read annotations from new format, or synthesize from legacy fields
    ShotAnnotations? ann;
    if (json['annotations'] != null) {
      ann = ShotAnnotations.fromJson(json['annotations']);
    } else if (json['shotNotes'] != null || json['metadata'] != null) {
      ann = ShotAnnotations.fromLegacyJson(json);
    }

    return ShotRecord(
      id: json["id"],
      timestamp: DateTime.parse(json["timestamp"]),
      measurements: (json["measurements"] as List)
          .map((e) => ShotSnapshot.fromJson(e))
          .toList(),
      workflow: Workflow.fromJson(json["workflow"]),
      annotations: ann,
      // Still parse legacy fields for backward compat with old callers
      shotNotes: json["shotNotes"] as String?,
      metadata: json["metadata"] as Map<String, dynamic>?,
    );
  }

  String shotTime() {
    final dateFormat = DateFormat.yMd();
    final timeFormat = DateFormat('jm');
    return "${dateFormat.format(timestamp)}, ${timeFormat.format(timestamp)}";
  }

  ShotRecord copyWith({
    String? id,
    DateTime? timestamp,
    List<ShotSnapshot>? measurements,
    Workflow? workflow,
    ShotAnnotations? annotations,
    String? shotNotes,
    Map<String, dynamic>? metadata,
  }) {
    return ShotRecord(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      measurements: measurements ?? this.measurements,
      workflow: workflow ?? this.workflow,
      annotations: annotations ?? this.annotations,
      shotNotes: shotNotes ?? _shotNotes,
      metadata: metadata ?? _metadata,
    );
  }
}
