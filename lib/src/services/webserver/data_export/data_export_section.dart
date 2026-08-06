import 'dart:convert';

import 'package:reaprime/src/util/incremental_json_parser.dart';

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

/// Receives pre-encoded JSON fragments for one section's payload.
///
/// Sections write their payload incrementally (array/object markers, one
/// record at a time) so the handler never holds a whole section in memory.
/// Each [writeRaw] fragment is capped at the maximum record size; exceeding
/// it throws and aborts the section export.
abstract class JsonSink {
  void writeRaw(String fragment);
}

/// Streaming input for one section's JSON payload during import.
///
/// The handler guarantees the payload is structurally valid JSON before the
/// import pass runs (a bounded validation pass precedes it). Sections read
/// values at a depth matching their payload shape:
///
/// * array sections (`shots`, `steams`, `beans`, `grinders`, `profiles`)
///   read elements at depth 1 via [valuesAtDepth];
/// * the KV store section reads `{"namespaces": {ns: {k: v}}}` values at
///   depth 3;
/// * singleton sections (settings, workflow) read the whole payload via
///   [readWhole].
abstract class SectionJsonInput {
  /// The top-level container kind of the payload (array or object).
  Future<JsonContainerKind> open();

  /// Yields complete values at [depth] (see [IncrementalJsonParser]).
  ///
  /// The stream throws [JsonStreamFormatException] if the payload is
  /// structurally malformed; in that case no partial import happens because
  /// the caller validates first.
  Stream<JsonValueEvent> valuesAtDepth(int depth);

  /// Reads the entire payload as one decoded value (depth 0).
  Future<Object?> readWhole();
}

/// Incremental writer for a JSON array payload: writes `[`, elements, `]`
/// one element at a time so only one encoded record is live at any moment.
class JsonArrayEmitter {
  final JsonSink _sink;
  bool _first = true;

  JsonArrayEmitter(this._sink) {
    _sink.writeRaw('[');
  }

  /// Appends one element (encoded with [jsonEncode]).
  void add(Object? value) {
    _sink.writeRaw(_first ? '' : ',');
    _sink.writeRaw(jsonEncode(value));
    _first = false;
  }

  void end() => _sink.writeRaw(']');
}

/// A single section of the data export archive.
///
/// Each section corresponds to one JSON file in the ZIP. Implementations
/// stream their payload through [exportJson] and read it back through
/// [importJson], never materializing the whole section.
///
/// To add a new data type to the export:
/// 1. Create a class implementing DataExportSection
/// 2. Register it in DataExportHandler's constructor
abstract class DataExportSection {
  /// The filename for this section in the ZIP archive (e.g., 'profiles.json').
  String get filename;

  /// Streams this section's JSON payload to [output] incrementally.
  ///
  /// Must write exactly one JSON value (array, object, or scalar). Each
  /// [JsonSink.writeRaw] call is bounded by the maximum record size.
  Future<void> exportJson(JsonSink output);

  /// Imports this section's payload from [input].
  ///
  /// [input] is structurally valid; records that are individually invalid
  /// are reported through [SectionImportResult.errors] while valid records
  /// still import (per-record accounting preserved).
  Future<SectionImportResult> importJson(
    SectionJsonInput input,
    ConflictStrategy strategy,
  );
}
