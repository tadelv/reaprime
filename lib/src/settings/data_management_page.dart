import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/feedback_feature/feedback_view.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/util/shot_exporter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final Logger _log = Logger("DataManagement");

class DataManagementPage extends StatefulWidget {
  const DataManagementPage({
    super.key,
    required this.controller,
    required this.persistenceController,
  });

  final SettingsController controller;
  final PersistenceController persistenceController;

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Management')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  _buildExportBackupSection(),
                  _buildImportRestoreSection(),
                  _buildPrivacyFeedbackSection(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // MARK: - Section Builders

  Widget _buildExportBackupSection() {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_download_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Export & Backup',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Create backups of your data or export specific items',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ShadButton.outline(
                onPressed: _exportFullBackup,
                child: const Text('Export Full Backup'),
              ),
              ShadButton.outline(
                onPressed: _exportLogs,
                child: const Text('Export Logs'),
              ),
              ShadButton.outline(
                onPressed: _exportShots,
                child: const Text('Export Shots'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportRestoreSection() {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Import & Restore',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Restore data from a previous backup',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 16),
          ShadButton.outline(
            onPressed: _importFullBackup,
            child: const Text('Import Full Backup'),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyFeedbackSection() {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Privacy & Feedback',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Control data sharing and send feedback',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 16),
          ShadSwitch(
            value: widget.controller.telemetryConsent,
            onChanged: (v) async {
              await widget.controller.setTelemetryConsent(v);
            },
            label: const Text("Anonymous crash reporting"),
            sublabel: const Text(
              "Share anonymized crash reports and diagnostics to help fix connectivity issues",
            ),
          ),
          const SizedBox(height: 12),
          ShadButton.outline(
            onPressed: () => showFeedbackDialog(
              context,
              githubToken: const String.fromEnvironment(
                'GITHUB_FEEDBACK_TOKEN',
                defaultValue: '',
              ),
            ),
            child: const Text("Send Feedback"),
          ),
        ],
      ),
    );
  }

  // MARK: - Export Actions

  Future<void> _exportFullBackup() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing full backup...')),
        );
      }

      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://localhost:8080/api/v1/data/export'),
        );
        final response = await request.close();
        final responseBytes =
            await response.fold<List<int>>([], (bytes, chunk) {
          bytes.addAll(chunk);
          return bytes;
        });

        final timestamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .split('.')
            .first;
        final fileName = 'streamline_bridge_export_$timestamp.zip';

        final outputFile = await FilePicker.platform.saveFile(
          fileName: fileName,
          dialogTitle: 'Choose where to save backup',
          bytes: Uint8List.fromList(responseBytes),
        );

        if (outputFile != null) {
          await File(outputFile).writeAsBytes(responseBytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Full backup exported successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _log.severe("Failed to export full backup", e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export full backup: $e')),
        );
      }
    }
  }

  Future<void> _exportLogs() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final logFile = File('${docs.path}/log.txt');
      if (!await logFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No log file found')),
          );
        }
        return;
      }
      final bytes = await logFile.readAsBytes();
      final outputFile = await FilePicker.platform.saveFile(
        fileName: "R1-logs.txt",
        dialogTitle: "Choose where to save logs",
        bytes: bytes,
      );
      if (outputFile != null) {
        await File(outputFile).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logs exported successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _log.severe("Failed to export logs", e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export logs: $e')),
        );
      }
    }
  }

  Future<void> _exportShots() async {
    try {
      final exporter = ShotExporter(
        storage: widget.persistenceController.storageService,
      );
      final jsonData = await exporter.exportJson();
      final tempDir = await getTemporaryDirectory();
      final source = File("${tempDir.path}/shots.json");
      await source.writeAsString(jsonData);
      final destination = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "Pick export dir",
      );
      if (destination != null) {
        final tempFile = File('$destination/R1_shots.zip');
        final archive = Archive();
        final sourceBytes = await source.readAsBytes();
        final archiveFile =
            ArchiveFile('shots.json', sourceBytes.length, sourceBytes);
        archive.addFile(archiveFile);
        final zipData = ZipEncoder().encode(archive);
        await tempFile.writeAsBytes(zipData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Shots exported successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e, st) {
      _log.severe("Failed to export shots", e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export shots: $e')),
        );
      }
    }
  }

  // MARK: - Import Actions

  Future<void> _importFullBackup() async {
    // Ask for conflict strategy
    final strategy = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Import Backup'),
        description:
            const Text('Choose how to handle data that already exists'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton(
                  onPressed: () => Navigator.of(context).pop('skip'),
                  child: const Text('Skip existing'),
                ),
                const SizedBox(width: 8),
                ShadButton.secondary(
                  onPressed: () => Navigator.of(context).pop('overwrite'),
                  child: const Text('Overwrite existing'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (strategy == null) return;

    // Pick file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;

    if (!mounted) return;

    // Show progress dialog
    _showProgressDialog(context, 'Importing backup...');

    try {
      final file = result.files.first;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();

      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse(
            'http://localhost:8080/api/v1/data/import?onConflict=$strategy',
          ),
        );
        request.headers.contentType =
            ContentType('application', 'zip');
        request.add(bytes);
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode != 200) {
          throw Exception('Server returned ${response.statusCode}: $responseBody');
        }

        final responseJson =
            jsonDecode(responseBody) as Map<String, dynamic>;

        if (!mounted) return;

        // Pop progress dialog
        Navigator.of(context).pop();

        if (!mounted) return;

        // Show result summary
        await _showImportResultDialog(responseJson);

        // Refresh shot data
        await widget.persistenceController.loadShots();
      } finally {
        client.close();
      }
    } catch (e) {
      _log.severe("Failed to import backup", e);
      if (mounted) {
        Navigator.of(context).pop(); // Pop progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import backup: $e')),
        );
      }
    }
  }

  void _showProgressDialog(BuildContext context, String message) {
    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShadDialog(
        title: Text(message),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Please wait...'),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportResultDialog(Map<String, dynamic> response) async {
    final sections = <Widget>[];

    for (final entry in response.entries) {
      if (entry.value is Map<String, dynamic>) {
        final data = entry.value as Map<String, dynamic>;
        final imported = data['imported'] ?? 0;
        final skipped = data['skipped'] ?? 0;
        final errors = data['errors'] as List<dynamic>? ?? [];

        sections.add(
          Text(
            '${entry.key}: $imported imported, $skipped skipped',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );

        for (final error in errors) {
          sections.add(
            Text(
              '  Warning: $error',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          );
        }
      }
    }

    await showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Import Complete'),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            ...sections,
          ],
        ),
      ),
    );
  }
}
