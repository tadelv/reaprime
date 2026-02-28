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

  Future<Response> _handleExport(Request request) async {
    try {
      final archive = Archive();

      // Add metadata.json
      final metadata = {
        'formatVersion': _currentFormatVersion,
        'appVersion': BuildInfo.version,
        'commitSha': BuildInfo.commitShort,
        'branch': BuildInfo.branch,
        'exportTimestamp': DateTime.now().toUtc().toIso8601String(),
        'platform': Platform.operatingSystem,
      };
      _addJsonToArchive(archive, 'metadata.json', metadata);

      // Export each registered section
      for (final section in _sections) {
        try {
          final data = await section.export();
          _addJsonToArchive(archive, section.filename, data);
        } catch (e, st) {
          _log.severe('Error exporting ${section.filename}', e, st);
        }
      }

      final zipBytes = ZipEncoder().encode(archive);

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

  Future<Response> _handleImport(Request request) async {
    try {
      // Parse conflict strategy
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

      // Read and decode ZIP
      final bytes = await request.read().expand((b) => b).toList();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Parse metadata.json (optional)
      String? sourcePlatform;
      final metadataFile = archive.findFile('metadata.json');
      if (metadataFile != null) {
        final metadataJson = jsonDecode(utf8.decode(metadataFile.content));
        final formatVersion = metadataJson['formatVersion'] as int?;
        if (formatVersion != null &&
            formatVersion > _currentFormatVersion) {
          return jsonBadRequest({
            'error': 'Unsupported export format',
            'message':
                'This archive was created with format version $formatVersion, '
                'but this app only supports up to version $_currentFormatVersion. '
                'Please update the app.',
          });
        }
        sourcePlatform = metadataJson['platform'] as String?;
      } else {
        _log.warning('Import archive missing metadata.json');
      }

      // Import each section
      final results = <String, dynamic>{};

      for (final section in _sections) {
        final file = archive.findFile(section.filename);
        if (file == null) continue;

        try {
          final data = jsonDecode(utf8.decode(file.content));
          final result = await section.import(data, strategy);

          // Add platform mismatch warning for settings
          if (section.filename == 'settings.json' &&
              sourcePlatform != null &&
              sourcePlatform != Platform.operatingSystem) {
            final warnings = List<String>.from(result.warnings);
            warnings.add(
              'Device preferences imported from \'$sourcePlatform\' may not '
              'work on \'${Platform.operatingSystem}\' — device IDs are '
              'platform-specific. Devices will need to be re-paired.',
            );
            results[_sectionKey(section)] = SectionImportResult(
              imported: result.imported,
              skipped: result.skipped,
              errors: result.errors,
              warnings: warnings,
            ).toJson();
          } else {
            results[_sectionKey(section)] = result.toJson();
          }
        } catch (e, st) {
          _log.severe('Error importing ${section.filename}', e, st);
          results[_sectionKey(section)] = {
            'errors': ['Failed to process ${section.filename}: $e'],
          };
        }
      }

      return jsonOk(results);
    } on ArchiveException catch (e) {
      return jsonBadRequest({
        'error': 'Invalid archive',
        'message': 'Could not read ZIP file: $e',
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
