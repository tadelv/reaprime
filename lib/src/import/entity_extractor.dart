import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';
import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/models/data/grinder.dart';

/// Result of extracting and deduplicating entities from a list of [ParsedShot]s.
class ExtractionResult {
  final List<Bean> beans;
  final List<BeanBatch> batches;
  final List<Grinder> grinders;

  /// Maps shot index → BeanBatch ID (null if shot had no bean info).
  final Map<int, String?> shotBeanBatchIds;

  /// Maps shot index → Grinder ID (null if shot had no grinder info).
  final Map<int, String?> shotGrinderIds;

  const ExtractionResult({
    required this.beans,
    required this.batches,
    required this.grinders,
    required this.shotBeanBatchIds,
    required this.shotGrinderIds,
  });
}

/// Extracts and deduplicates [Bean], [BeanBatch], and [Grinder] entities from
/// a list of [ParsedShot] objects, recording the mapping from each shot index
/// to its associated entity IDs.
class EntityExtractor {
  /// Extract deduplicated entities from parsed shots.
  ExtractionResult extract(List<ParsedShot> shots) {
    // bean key → Bean
    final beansByKey = <String, Bean>{};
    // (beanKey, roastDate) → BeanBatch
    final batchesByKey = <String, BeanBatch>{};
    // grinderModel.toLowerCase() → Grinder
    final grindersByModel = <String, Grinder>{};

    final shotBeanBatchIds = <int, String?>{};
    final shotGrinderIds = <int, String?>{};

    for (var i = 0; i < shots.length; i++) {
      final parsed = shots[i];

      // --- Bean + BeanBatch ---
      final brand = _normalize(parsed.beanBrand);
      final type = _normalize(parsed.beanType);

      if (brand != null && type != null) {
        final beanKey = '$brand\x00$type';

        // Find or create Bean.
        final bean = beansByKey.putIfAbsent(
          beanKey,
          () => Bean.create(
            roaster: parsed.beanBrand!,
            name: parsed.beanType!,
            notes: parsed.beanNotes,
          ),
        );

        // Find or create BeanBatch keyed by (beanKey, roastDate).
        final roastDate = _normalize(parsed.roastDate) ?? '';
        final batchKey = '$beanKey\x00$roastDate';

        final batch = batchesByKey.putIfAbsent(
          batchKey,
          () => BeanBatch.create(
            beanId: bean.id,
            roastDate: _parseDate(parsed.roastDate),
            roastLevel: parsed.roastLevel,
          ),
        );

        shotBeanBatchIds[i] = batch.id;
      } else {
        shotBeanBatchIds[i] = null;
      }

      // --- Grinder ---
      final model = _normalize(parsed.grinderModel);

      if (model != null) {
        final grinder = grindersByModel.putIfAbsent(
          model,
          () => Grinder.create(model: parsed.grinderModel!),
        );
        shotGrinderIds[i] = grinder.id;
      } else {
        shotGrinderIds[i] = null;
      }
    }

    return ExtractionResult(
      beans: beansByKey.values.toList(),
      batches: batchesByKey.values.toList(),
      grinders: grindersByModel.values.toList(),
      shotBeanBatchIds: shotBeanBatchIds,
      shotGrinderIds: shotGrinderIds,
    );
  }

  /// Merge DYE grinder specs into grinders extracted from shots.
  ///
  /// - If a DYE grinder matches an existing shot grinder by model name
  ///   (case-insensitive), the existing grinder is enriched with DYE metadata
  ///   (burrs, settingType, settingSmallStep, settingBigStep). The existing
  ///   grinder ID is preserved.
  /// - DYE grinders with no matching shot grinder are appended as new entries.
  List<Grinder> mergeGrinderSpecs(
    List<Grinder> fromShots,
    List<Grinder> fromDye,
  ) {
    // Work with a mutable copy keyed by normalised model name.
    final byModel = <String, Grinder>{
      for (final g in fromShots) g.model.toLowerCase(): g,
    };

    for (final dye in fromDye) {
      final key = dye.model.toLowerCase();

      if (byModel.containsKey(key)) {
        // Enrich the existing grinder with DYE specs, preserving its ID.
        byModel[key] = byModel[key]!.copyWith(
          burrs: dye.burrs,
          settingType: dye.settingType,
          settingSmallStep: dye.settingSmallStep,
          settingBigStep: dye.settingBigStep,
        );
      } else {
        // DYE-only grinder — add it as a new entry.
        byModel[key] = dye;
      }
    }

    return byModel.values.toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the trimmed, lower-cased string, or null if blank.
  String? _normalize(String? value) {
    if (value == null) return null;
    final s = value.trim();
    return s.isEmpty ? null : s.toLowerCase();
  }

  /// Attempts to parse a roast-date string into a [DateTime].
  /// Returns null if parsing fails or the string is blank.
  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }
}
