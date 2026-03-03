import 'package:reaprime/src/models/data/utils.dart';

/// Post-shot annotations replacing ShotRecord.shotNotes and ShotRecord.metadata.
/// All fields nullable — populated progressively after a shot.
class ShotAnnotations {
  // Actuals (post-shot measurements)
  final double? actualDoseWeight;
  final double? actualYield;

  // Extraction science
  final double? drinkTds;
  final double? drinkEy;

  // Rating & notes
  final double? enjoyment;
  final String? espressoNotes;

  // Plugin data channel
  final Map<String, dynamic>? extras;

  const ShotAnnotations({
    this.actualDoseWeight,
    this.actualYield,
    this.drinkTds,
    this.drinkEy,
    this.enjoyment,
    this.espressoNotes,
    this.extras,
  });

  factory ShotAnnotations.fromJson(Map<String, dynamic> json) {
    return ShotAnnotations(
      actualDoseWeight: parseOptionalDouble(json['actualDoseWeight']),
      actualYield: parseOptionalDouble(json['actualYield']),
      drinkTds: parseOptionalDouble(json['drinkTds']),
      drinkEy: parseOptionalDouble(json['drinkEy']),
      enjoyment: parseOptionalDouble(json['enjoyment']),
      espressoNotes: json['espressoNotes'] as String?,
      extras: json['extras'] as Map<String, dynamic>?,
    );
  }

  /// Creates ShotAnnotations from legacy ShotRecord JSON that has
  /// shotNotes and metadata fields.
  factory ShotAnnotations.fromLegacyJson(Map<String, dynamic> shotJson) {
    return ShotAnnotations(
      espressoNotes: shotJson['shotNotes'] as String?,
      extras: shotJson['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (actualDoseWeight != null) 'actualDoseWeight': actualDoseWeight,
      if (actualYield != null) 'actualYield': actualYield,
      if (drinkTds != null) 'drinkTds': drinkTds,
      if (drinkEy != null) 'drinkEy': drinkEy,
      if (enjoyment != null) 'enjoyment': enjoyment,
      if (espressoNotes != null) 'espressoNotes': espressoNotes,
      if (extras != null) 'extras': extras,
    };
  }

  ShotAnnotations copyWith({
    double? actualDoseWeight,
    double? actualYield,
    double? drinkTds,
    double? drinkEy,
    double? enjoyment,
    String? espressoNotes,
    Map<String, dynamic>? extras,
  }) {
    return ShotAnnotations(
      actualDoseWeight: actualDoseWeight ?? this.actualDoseWeight,
      actualYield: actualYield ?? this.actualYield,
      drinkTds: drinkTds ?? this.drinkTds,
      drinkEy: drinkEy ?? this.drinkEy,
      enjoyment: enjoyment ?? this.enjoyment,
      espressoNotes: espressoNotes ?? this.espressoNotes,
      extras: extras ?? this.extras,
    );
  }

  @override
  String toString() => 'ShotAnnotations('
      'dose: $actualDoseWeight→$actualYield, '
      'tds: $drinkTds, ey: $drinkEy, '
      'enjoyment: $enjoyment)';
}
