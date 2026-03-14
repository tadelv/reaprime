import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

class DataExportHandler {
  static const int _currentFormatVersion = 1;

  final List<DataExportSection> _sections;
  final Logger _log = Logger('DataExportHandler');

  DataExportHandler({required List<DataExportSection> sections})
      : _sections = sections;

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
      }
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
              'attachment; filename="streamline_bridge_export_$timestamp.zip"',
        },
      );
    } catch (e, st) {
      _log.severe('Error in _handleExport', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }

  /// Imports data from ZIP bytes.
  ///
  /// If [sections] is provided, only sections whose filename (without .json)
  /// matches an entry in the list are processed.
  ///
  /// Throws [FormatException] if the archive format version is unsupported.
  /// Throws [ArchiveException] if the ZIP is invalid.
  Future<Map<String, dynamic>> importFromBytes(
    List<int> zipBytes,
    ConflictStrategy strategy, {
    List<String>? sections,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // Parse metadata
    String? sourcePlatform;
    final metadataFile = archive.findFile('metadata.json');
    if (metadataFile != null) {
      final metadataJson = jsonDecode(utf8.decode(metadataFile.content));
      final formatVersion = metadataJson['formatVersion'] as int?;
      if (formatVersion != null && formatVersion > _currentFormatVersion) {
        throw FormatException(
          'This archive was created with format version $formatVersion, '
          'but this app only supports up to version $_currentFormatVersion. '
          'Please update the app.',
        );
      }
      sourcePlatform = metadataJson['platform'] as String?;
    } else {
      _log.warning('Import archive missing metadata.json');
    }

    final results = <String, dynamic>{};

    for (final section in _sections) {
      final key = _sectionKey(section);
      if (sections != null && !sections.contains(key)) continue;

      final file = archive.findFile(section.filename);
      if (file == null) continue;

      try {
        final data = jsonDecode(utf8.decode(file.content));
        final result = await section.import(data, strategy);

        if (section.filename == 'settings.json' &&
            sourcePlatform != null &&
            sourcePlatform != Platform.operatingSystem) {
          final warnings = List<String>.from(result.warnings);
          warnings.add(
            'Device preferences imported from \'$sourcePlatform\' may not '
            'work on \'${Platform.operatingSystem}\' — device IDs are '
            'platform-specific. Devices will need to be re-paired.',
          );
          results[key] = SectionImportResult(
            imported: result.imported,
            skipped: result.skipped,
            errors: result.errors,
            warnings: warnings,
          ).toJson();
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

    return results;
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
      final results = await importFromBytes(bytes, strategy);
      return jsonOk(results);
    } on ArchiveException catch (e) {
      return jsonBadRequest({
        'error': 'Invalid archive',
        'message': 'Could not read ZIP file: $e',
      });
    } on FormatException catch (e) {
      return jsonBadRequest({
        'error': 'Unsupported export format',
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
}
