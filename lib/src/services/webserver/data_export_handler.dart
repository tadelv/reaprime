import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
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
  final Map<String, dynamic> sectionResults;
  final Map<String, DataOutcomeStatus> sectionStatuses;
  final int recognizedSections;
  final Set<String> failedSections;

  DataImportOutcome({
    required Map<String, dynamic> sectionResults,
    required Map<String, DataOutcomeStatus> sectionStatuses,
    required this.recognizedSections,
    required Set<String> failedSections,
  }) : sectionResults = Map.unmodifiable(sectionResults),
       sectionStatuses = Map.unmodifiable(sectionStatuses),
       failedSections = Set.unmodifiable(failedSections);

  bool get isPartial => failedSections.isNotEmpty;

  DataOutcomeStatus get status {
    if (failedSections.isEmpty) return DataOutcomeStatus.complete;
    return sectionStatuses.values.every(
          (status) => status == DataOutcomeStatus.failed,
        )
        ? DataOutcomeStatus.failed
        : DataOutcomeStatus.partial;
  }

  bool get isFailed => status == DataOutcomeStatus.failed;

  Map<String, dynamic> toJson() => sectionResults;

  Map<String, dynamic> toSyncJson() => {
    'phaseStatus': status.name,
    ...sectionResults,
  };
}

class DataExportHandler {
  static const int _currentFormatVersion = 1;

  final List<DataExportSection> _sections;
  final Logger _log = Logger('DataExportHandler');

  DataExportHandler({required List<DataExportSection> sections})
    : _sections = sections;

  List<String> get sectionKeys => List.unmodifiable(_sections.map(_sectionKey));

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/data/export', _handleExport);
    app.post('/api/v1/data/import', _handleImport);
  }

  /// Exports data as ZIP bytes.
  ///
  /// If [sections] is provided, only sections whose filename (without .json)
  /// matches an entry in the list are included.
  Future<List<int>> exportToBytes({List<String>? sections}) async {
    final archive = Archive();
    final failedSections = <String>{};

    final metadata = {
      'formatVersion': _currentFormatVersion,
      'appVersion': BuildInfo.version,
      'buildNumber': BuildInfo.buildNumber,
      'commitSha': BuildInfo.commitShort,
      'branch': BuildInfo.branch,
      'exportTimestamp': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
    };
    _addJsonToArchive(archive, 'metadata.json', metadata);

    for (final section in _sections) {
      if (sections != null && !sections.contains(_sectionKey(section))) {
        continue;
      }
      try {
        final data = await section.export();
        _addJsonToArchive(archive, section.filename, data);
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

    return ZipEncoder().encode(archive);
  }

  Future<Response> _handleExport(Request request) async {
    try {
      final zipBytes = await exportToBytes();

      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;

      return Response.ok(
        zipBytes,
        headers: {
          'Content-Type': 'application/zip',
          'Content-Disposition':
              'attachment; filename="decent_export_$timestamp.zip"',
        },
      );
    } catch (e, st) {
      if (e is DataExportException) {
        return jsonError({
          'error': 'Export failed',
          'message': e.message,
          'sections': e.failedSections.toList(growable: false),
        });
      }
      _log.severe('Error in _handleExport', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }

  /// Imports data from ZIP bytes.
  ///
  /// If [sections] is provided, only sections whose filename (without .json)
  /// matches an entry in the list are processed.
  ///
  Future<DataImportOutcome> importFromBytes(
    List<int> zipBytes,
    ConflictStrategy strategy, {
    List<String>? sections,
    bool strictSections = false,
  }) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e, st) {
      _log.severe('Error decoding backup archive', e, st);
      throw InvalidBackupException(
        message: 'Could not read the backup ZIP archive.',
        reason: 'invalid_zip',
        cause: e,
      );
    }

    final sourcePlatform = _readMetadata(archive);
    final selectedSections = _resolveImportSections(sections);

    final results = <String, dynamic>{};
    final sectionStatuses = <String, DataOutcomeStatus>{};
    final failedSections = <String>{};
    var recognizedSections = 0;

    for (final section in selectedSections) {
      final key = _sectionKey(section);
      final file = archive.findFile(section.filename);
      if (file == null) {
        if (strictSections) {
          final result = SectionImportResult(
            errors: ['Missing requested section: ${section.filename}.'],
          );
          results[key] = result.toJson();
          sectionStatuses[key] = result.status;
          failedSections.add(key);
        }
        continue;
      }
      recognizedSections++;

      try {
        final data = jsonDecode(utf8.decode(file.content));
        var result = await section.import(data, strategy);

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
        results[key] = result.toJson();
        sectionStatuses[key] = result.status;
        if (result.errors.isNotEmpty) failedSections.add(key);
      } catch (e, st) {
        _log.severe('Error importing ${section.filename}', e, st);
        final result = SectionImportResult(
          errors: ['Failed to process ${section.filename}: $e'],
        );
        results[key] = result.toJson();
        sectionStatuses[key] = result.status;
        failedSections.add(key);
      }
    }

    if (recognizedSections == 0 &&
        (!strictSections || selectedSections.isEmpty)) {
      throw const InvalidBackupException(
        message: 'The archive does not contain any recognized data sections.',
        reason: 'no_recognized_sections',
      );
    }

    return DataImportOutcome(
      sectionResults: results,
      sectionStatuses: sectionStatuses,
      recognizedSections: recognizedSections,
      failedSections: failedSections,
    );
  }

  Future<Response> _handleImport(Request request) async {
    try {
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

      final bytes = await request.read().expand((b) => b).toList();
      final outcome = await importFromBytes(bytes, strategy);
      return outcome.isPartial
          ? jsonMultiStatus(outcome.toJson())
          : jsonOk(outcome.toJson());
    } on InvalidBackupException catch (e) {
      return jsonBadRequest({
        'error': 'Invalid backup archive',
        'message': e.message,
      });
    } catch (e, st) {
      _log.severe('Error in _handleImport', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }

  void _addJsonToArchive(Archive archive, String filename, dynamic data) {
    final jsonStr = jsonEncode(data);
    archive.addFile(ArchiveFile.string(filename, jsonStr));
  }

  String _sectionKey(DataExportSection section) =>
      section.filename.replaceAll('.json', '');

  String? _readMetadata(Archive archive) {
    final metadataFile = archive.findFile('metadata.json');
    if (metadataFile == null) {
      _log.warning('Import archive missing metadata.json');
      return null;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(metadataFile.content));
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

  List<DataExportSection> _resolveImportSections(List<String>? sections) {
    if (sections == null) return _sections;

    final requested = sections.toSet();
    final unknown = requested
        .where(
          (key) => !_sections.any((section) => _sectionKey(section) == key),
        )
        .toList(growable: false);
    if (unknown.isNotEmpty) {
      throw InvalidBackupException(
        message: 'Unknown requested backup section(s): ${unknown.join(', ')}',
        reason: 'unknown_selected_section',
      );
    }

    return _sections
        .where((section) => requested.contains(_sectionKey(section)))
        .toList(growable: false);
  }
}
