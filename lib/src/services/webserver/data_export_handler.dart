import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/data_transfer_result.dart';
import 'package:reaprime/src/services/webserver/data_export/data_transfer_limits.dart';
import 'package:reaprime/src/services/webserver/data_export/streaming_zip_writer.dart';
import 'package:reaprime/src/services/webserver/data_export/streaming_zip_reader.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:reaprime/src/util/incremental_json_parser.dart';
import 'package:reaprime/src/util/temp_archive_files.dart';
import 'package:shelf_plus/shelf_plus.dart';

class InvalidBackupException implements Exception {
  final String message;
  final String reason;
  final Object? cause;

  const InvalidBackupException({
    required this.message,
    required this.reason,
    this.cause,
  });

  @override
  String toString() => 'InvalidBackupException: $reason';
}

class DataExportException implements Exception {
  final String message;
  final Set<String> failedSections;

  DataExportException({
    required this.message,
    required Set<String> failedSections,
  }) : failedSections = Set.unmodifiable(failedSections);

  @override
  String toString() => 'DataExportException: $message';
}

class DataImportOutcome {
  final int recognizedSections;
  final DataTransferPhaseOutcome phase;

  const DataImportOutcome({
    required this.recognizedSections,
    required this.phase,
  });

  Map<String, dynamic> get sectionResults => phase.sectionResults;

  Set<String> get failedSections => phase.sections.entries
      .where((entry) => entry.value.status != DataSectionStatus.complete)
      .map((entry) => entry.key)
      .toSet();

  bool get isPartial => phase.partial;

  bool get isFailed => phase.status == DataTransferStatus.failed;

  bool get hasFailures => !phase.complete;

  Map<String, dynamic> toJson() => sectionResults;
}

class DataExportHandler {
  static const int _currentFormatVersion = 1;

  final List<DataExportSection> _sections;
  final DataTransferLimits _limits;
  final Logger _log = Logger('DataExportHandler');

  DataExportHandler({
    required List<DataExportSection> sections,
    DataTransferLimits limits = const DataTransferLimits(),
  }) : _sections = sections,
       _limits = limits;

  List<String> get sectionKeys => List.unmodifiable(_sections.map(_sectionKey));

  DataTransferLimits get limits => _limits;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/data/export', _handleExport);
    app.post('/api/v1/data/import', _handleImport);
  }

  // ---------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------

  /// Exports selected sections into a uniquely owned temporary ZIP inside
  /// [tempDir]. The ZIP is complete and valid only when this returns; on any
  /// section or archive failure a [DataExportException] is thrown and no ZIP
  /// is left behind (the caller still owns [tempDir] cleanup).
  Future<File> exportToZipFile(
    Directory tempDir, {
    List<String>? sections,
  }) async {
    final writer = await StreamingZipWriter.create(tempDir, _limits);
    try {
      final metadata = {
        'formatVersion': _currentFormatVersion,
        'appVersion': BuildInfo.version,
        'buildNumber': BuildInfo.buildNumber,
        'commitSha': BuildInfo.commitShort,
        'branch': BuildInfo.branch,
        'exportTimestamp': DateTime.now().toUtc().toIso8601String(),
        'platform': Platform.operatingSystem,
      };
      final metadataEntry = writer.addEntry('metadata.json');
      _writeFragment(metadataEntry, jsonEncode(metadata));
      metadataEntry.close();

      final failedSections = <String>{};

      for (final section in _sections) {
        if (sections != null && !sections.contains(_sectionKey(section))) {
          continue;
        }
        try {
          final entry = writer.addEntry(section.filename);
          final sink = _EntryJsonSink(entry, _limits);
          await section.exportJson(sink);
          entry.close();
        } catch (e, st) {
          _log.severe('Error exporting ${section.filename}', e, st);
          failedSections.add(_sectionKey(section));
        }
      }

      if (failedSections.isNotEmpty) {
        throw DataExportException(
          message: 'Failed to export section(s): ${failedSections.join(', ')}.',
          failedSections: failedSections,
        );
      }

      await writer.close();
      return writer.file;
    } catch (e) {
      await writer.abort();
      rethrow;
    }
  }

  void _writeFragment(ZipEntrySink entry, String fragment) {
    entry.write(Uint8List.fromList(utf8.encode(fragment)));
  }

  Future<Response> _handleExport(Request request) async {
    final tempDir = await TempArchiveDir.create('reaprime-export-');
    try {
      final zipFile = await exportToZipFile(tempDir.directory);
      final length = await zipFile.length();

      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'decent_export_$timestamp.zip';

      return Response.ok(
        _fileStream(zipFile, onDone: tempDir.dispose),
        headers: {
          'Content-Type': 'application/zip',
          'Content-Disposition': 'attachment; filename="$fileName"',
          'Content-Length': '$length',
        },
      );
    } on DataExportException catch (e) {
      await tempDir.dispose();
      return jsonError({
        'error': 'Export failed',
        'message': e.message,
        'sections': e.failedSections.toList(growable: false),
      });
    } catch (e, st) {
      _log.severe('Error in _handleExport', e, st);
      await tempDir.dispose();
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }

  /// Streams [file] to the response, deleting the owning temp directory when
  /// the stream completes, errors, or the consumer cancels.
  Stream<List<int>> _fileStream(
    File file, {
    required Future<void> Function() onDone,
  }) {
    var done = false;
    Future<void> cleanup() async {
      if (done) return;
      done = true;
      await onDone();
    }

    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        file.openRead().listen(
          controller.add,
          onError: (Object e, StackTrace st) {
            controller.addError(e, st);
            cleanup();
          },
          onDone: () {
            controller.close();
            cleanup();
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        await cleanup();
      },
    );
    return controller.stream;
  }

  // ---------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------

  /// Imports from a staged ZIP file. The caller owns [zipFile]'s lifecycle.
  Future<DataImportOutcome> importFromZipFile(
    File zipFile,
    ConflictStrategy strategy, {
    List<String>? sections,
  }) async {
    final StreamingZipReader reader;
    try {
      reader = await StreamingZipReader.open(zipFile, _limits);
    } on ZipReadException catch (e) {
      throw InvalidBackupException(
        message: 'Could not read the backup ZIP archive: ${e.message}',
        reason: e.reason,
        cause: e,
      );
    }

    try {
      final sourcePlatform = await _readMetadata(reader);
      final selectedSectionKeys = _resolveImportSectionKeys(sections);
      final sectionsByKey = {
        for (final section in _sections) _sectionKey(section): section,
      };

      final results = <String, dynamic>{};
      var recognizedSections = 0;

      for (final key in selectedSectionKeys) {
        final section = sectionsByKey[key]!;
        final entry = reader.findEntry(section.filename);
        if (entry == null) continue;
        recognizedSections++;

        try {
          var result = await _importSection(reader, section, entry, strategy);

          if (section.filename == 'settings.json' &&
              sourcePlatform != null &&
              sourcePlatform != Platform.operatingSystem) {
            final warnings = List<String>.from(result.warnings);
            warnings.add(
              'Device preferences imported from \'$sourcePlatform\' may not '
              'work on \'${Platform.operatingSystem}\' — device IDs are '
              'platform-specific. Devices will need to be re-paired.',
            );
            result = SectionImportResult(
              imported: result.imported,
              skipped: result.skipped,
              errors: result.errors,
              warnings: warnings,
            );
          }
          if (result.errors.isNotEmpty &&
              result.imported == 0 &&
              result.skipped == 0) {
            // Preserve the legacy failed-section shape (errors only, no
            // zero counts) for structurally rejected sections.
            results[key] = {'errors': result.errors};
          } else {
            results[key] = result.toJson();
          }
        } catch (e, st) {
          _log.severe('Error importing ${section.filename}', e, st);
          results[key] = {
            'errors': ['Failed to process ${section.filename}: $e'],
          };
        }
      }

      if (recognizedSections == 0) {
        throw const InvalidBackupException(
          message: 'The archive does not contain any recognized data sections.',
          reason: 'no_recognized_sections',
        );
      }

      final expectedSections = sections == null
          ? results.keys.toList(growable: false)
          : selectedSectionKeys;
      final phase = DataTransferPhaseOutcome.fromSections(
        rawSections: results,
        expectedSections: expectedSections,
      );
      return DataImportOutcome(
        recognizedSections: recognizedSections,
        phase: phase,
      );
    } finally {
      await reader.close();
    }
  }

  /// Two-pass section import: a bounded structural validation pass (nothing
  /// imported), then a bounded import pass. Malformed JSON fails the section
  /// without importing any prefix; individually invalid records keep
  /// per-record error accounting.
  Future<SectionImportResult> _importSection(
    StreamingZipReader reader,
    DataExportSection section,
    ZipEntryInfo entry,
    ConflictStrategy strategy,
  ) async {
    // Validation pass.
    try {
      final validator = _EntryJsonInput(reader, entry, _limits);
      await validator.open();
      await for (final _ in validator.valuesAtDepth(section.jsonEventDepth)) {}
    } catch (e, st) {
      _log.warning('Section ${section.filename} failed validation', e, st);
      return SectionImportResult(
        errors: [
          'Failed to process ${section.filename}: ${e is JsonStreamFormatException ? e.message : '$e'}',
        ],
      );
    }

    // Import pass.
    final input = _EntryJsonInput(reader, entry, _limits);
    return section.importJson(input, strategy);
  }

  Future<Response> _handleImport(Request request) async {
    final onConflict = request.url.queryParameters['onConflict'] ?? 'skip';
    final ConflictStrategy strategy;
    switch (onConflict) {
      case 'skip':
        strategy = ConflictStrategy.skip;
      case 'overwrite':
        strategy = ConflictStrategy.overwrite;
      default:
        return jsonBadRequest({
          'error': 'Invalid onConflict value',
          'message': 'Valid values: skip, overwrite',
        });
    }

    final tempDir = await TempArchiveDir.create('reaprime-import-');
    try {
      // Stream the request body into a temp ZIP with a hard byte cap; never
      // buffer the full body.
      final zipFile = File(tempDir.filePath('import.zip'));
      final raf = await zipFile.open(mode: FileMode.write);
      var received = 0;
      try {
        await for (final chunk in request.read()) {
          received += chunk.length;
          if (received > _limits.maxImportRequestBytes) {
            throw const InvalidBackupException(
              message: 'The import archive exceeds the size limit.',
              reason: 'request_too_large',
            );
          }
          raf.writeFromSync(chunk);
        }
      } finally {
        await raf.close();
      }

      final outcome = await importFromZipFile(zipFile, strategy);
      return outcome.hasFailures
          ? jsonMultiStatus(outcome.toJson())
          : jsonOk(outcome.toJson());
    } on InvalidBackupException catch (e) {
      _log.warning('Import rejected: ${e.reason}', e);
      return jsonBadRequest({
        'error': 'Invalid backup archive',
        'message': e.message,
      });
    } catch (e, st) {
      _log.severe('Error in _handleImport', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    } finally {
      await tempDir.dispose();
    }
  }

  // ---------------------------------------------------------------------
  // Metadata and section resolution
  // ---------------------------------------------------------------------

  Future<String?> _readMetadata(StreamingZipReader reader) async {
    final metadataFile = reader.findEntry('metadata.json');
    if (metadataFile == null) {
      _log.warning('Import archive missing metadata.json');
      return null;
    }

    final Uint8List bytes;
    try {
      bytes = await reader.readEntryBytes(
        metadataFile,
        maxBytes: _limits.maxMetadataBytes,
      );
    } on ZipReadException catch (e) {
      throw InvalidBackupException(
        message: 'Could not read the backup metadata: ${e.message}',
        reason: e.reason,
        cause: e,
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (e, st) {
      _log.severe('Error decoding backup metadata', e, st);
      throw InvalidBackupException(
        message: 'The archive metadata is invalid.',
        reason: 'invalid_metadata_json',
        cause: e,
      );
    }

    if (decoded is! Map) {
      throw const InvalidBackupException(
        message: 'The archive metadata is invalid.',
        reason: 'metadata_not_object',
      );
    }

    final metadata = Map<String, dynamic>.from(decoded);
    final formatVersion = metadata['formatVersion'];
    if (formatVersion != null && formatVersion is! int) {
      throw const InvalidBackupException(
        message: 'The archive metadata formatVersion must be an integer.',
        reason: 'invalid_format_version_type',
      );
    }
    if (formatVersion is int && formatVersion > _currentFormatVersion) {
      throw InvalidBackupException(
        message:
            'This archive was created with format version $formatVersion, '
            'but this app only supports up to version $_currentFormatVersion. '
            'Please update the app.',
        reason: 'unsupported_format_version',
      );
    }

    final sourcePlatform = metadata['platform'];
    if (sourcePlatform != null && sourcePlatform is! String) {
      throw const InvalidBackupException(
        message: 'The archive metadata is invalid.',
        reason: 'invalid_platform_type',
      );
    }
    return sourcePlatform as String?;
  }

  List<String> _resolveImportSectionKeys(List<String>? sections) {
    if (sections == null) return sectionKeys;

    final requested = <String>[];
    for (final key in sections) {
      if (!requested.contains(key)) requested.add(key);
    }
    final unknown = requested
        .where((key) => !sectionKeys.contains(key))
        .toList();
    if (unknown.isNotEmpty) {
      throw InvalidBackupException(
        message: 'Unknown requested backup section(s): ${unknown.join(', ')}',
        reason: 'unknown_selected_section',
      );
    }

    return requested;
  }

  String _sectionKey(DataExportSection section) =>
      section.filename.replaceAll('.json', '');
}

/// JSON fragment sink writing into one ZIP entry. Each fragment is capped at
/// the maximum record size so a section cannot smuggle a whole-collection
/// value through a single write.
class _EntryJsonSink implements JsonSink {
  final ZipEntrySink _entry;
  final DataTransferLimits _limits;

  _EntryJsonSink(this._entry, this._limits);

  @override
  void writeRaw(String fragment) {
    if (fragment.length > _limits.maxRecordBytes) {
      throw DataExportException(
        message: 'A data record exceeds the maximum size limit.',
        failedSections: const {},
      );
    }
    _entry.write(Uint8List.fromList(utf8.encode(fragment)));
  }
}

/// Streaming JSON input over one ZIP entry, re-readable per pass.
class _EntryJsonInput implements SectionJsonInput {
  final StreamingZipReader _reader;
  final ZipEntryInfo _entry;
  final DataTransferLimits _limits;

  _EntryJsonInput(this._reader, this._entry, this._limits);

  @override
  Future<JsonContainerKind> open() async {
    await for (final chunk in _reader.readEntryChunks(_entry)) {
      for (final byte in chunk) {
        if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
          continue;
        }
        if (byte == 0x7B) return JsonContainerKind.object;
        if (byte == 0x5B) return JsonContainerKind.array;
        throw const JsonStreamFormatException(
          'The JSON payload must be an object or array.',
        );
      }
    }
    throw const JsonStreamFormatException('The JSON payload is empty.');
  }

  @override
  Stream<JsonValueEvent> valuesAtDepth(int depth) async* {
    final parser = IncrementalJsonParser(
      eventDepth: depth,
      maxValueBytes: _limits.maxRecordBytes,
      maxKeyBytes: _limits.maxKeyBytes,
      maxNestingDepth: _limits.maxNestingDepth,
    );
    try {
      final textStream = utf8.decoder.bind(
        _reader.readEntryChunks(_entry).cast<List<int>>(),
      );
      await for (final text in textStream) {
        parser.feed(text);
        for (final event in parser.drain()) {
          yield event;
        }
      }
      parser.finish();
      for (final event in parser.drain()) {
        yield event;
      }
    } on JsonStreamFormatException {
      rethrow;
    } on ZipReadException {
      rethrow;
    } catch (e) {
      throw JsonStreamFormatException('Failed to parse section JSON: $e');
    }
  }

  @override
  Future<Object?> readWhole() async {
    Object? value;
    var seen = 0;
    await for (final event in valuesAtDepth(0)) {
      value = event.value;
      seen++;
      if (seen > 1) {
        throw const JsonStreamFormatException(
          'The JSON payload must contain a single value.',
        );
      }
    }
    if (seen == 0) {
      throw const JsonStreamFormatException('The JSON payload is empty.');
    }
    return value;
  }
}

/// Extension point: the depth at which each section streams its payload.
/// Array sections use 1 (elements), the KV section uses 3 (namespace-key
/// pairs), singleton sections use 0 (whole value).
extension DataExportSectionJsonDepth on DataExportSection {
  int get jsonEventDepth => switch (filename) {
    'store.json' => 3,
    'settings.json' || 'workflow.json' => 0,
    _ => 1,
  };
}
