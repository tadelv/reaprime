/// Strategy for handling conflicts during import.
enum ConflictStrategy { skip, overwrite }

/// Result of importing a single section.
class SectionImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;
  final List<String> warnings;

  const SectionImportResult({
    this.imported = 0,
    this.skipped = 0,
    this.errors = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
        'imported': imported,
        'skipped': skipped,
        if (errors.isNotEmpty) 'errors': errors,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };
}

/// A single section of the data export archive.
///
/// Each section corresponds to one JSON file in the ZIP.
/// Implementations handle exporting and importing their specific data type.
///
/// To add a new data type to the export:
/// 1. Create a class implementing DataExportSection
/// 2. Register it in DataExportHandler's constructor
abstract class DataExportSection {
  /// The filename for this section in the ZIP archive (e.g., 'profiles.json').
  String get filename;

  /// Export this section's data as a JSON-serializable object.
  Future<dynamic> export();

  /// Import data for this section.
  ///
  /// [data] is the parsed JSON from the archive file.
  /// [strategy] controls how conflicts (duplicate IDs) are handled.
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  );
}
