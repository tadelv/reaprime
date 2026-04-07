import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/import/de1app_importer.dart';
import 'package:reaprime/src/import/saf_folder_copier.dart';
import 'package:reaprime/src/import/de1app_scanner.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:reaprime/src/import/widgets/import_progress_view.dart';
import 'package:reaprime/src/import/widgets/import_result_view.dart';
import 'package:reaprime/src/import/widgets/import_source_picker.dart';
import 'package:reaprime/src/import/widgets/import_summary_view.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';


enum _ImportPhase {
  pickSource,
  copying, // Android SAF: copying files from external storage to app cache
  scanning,
  summary,
  importing,
  result,
}

/// Creates an [OnboardingStep] that manages the import flow:
/// source picker → scanning → summary → importing → result.
///
/// shouldShow is always true — the caller (app.dart) determines whether the
/// import step is included in the active onboarding flow.
OnboardingStep createImportStep({
  required StorageService storageService,
  required ProfileStorageService profileStorageService,
  required BeanStorageService beanStorageService,
  required GrinderStorageService grinderStorageService,
  required SettingsController settingsController,
  required PersistenceController persistenceController,
}) {
  return OnboardingStep(
    id: 'import',
    shouldShow: () async => true,
    builder: (controller) => _ImportStepView(
      controller: controller,
      storageService: storageService,
      profileStorageService: profileStorageService,
      beanStorageService: beanStorageService,
      grinderStorageService: grinderStorageService,
      settingsController: settingsController,
      persistenceController: persistenceController,
    ),
  );
}

class _ImportStepView extends StatefulWidget {
  final OnboardingController controller;
  final StorageService storageService;
  final ProfileStorageService profileStorageService;
  final BeanStorageService beanStorageService;
  final GrinderStorageService grinderStorageService;
  final SettingsController settingsController;
  final PersistenceController persistenceController;

  const _ImportStepView({
    required this.controller,
    required this.storageService,
    required this.profileStorageService,
    required this.beanStorageService,
    required this.grinderStorageService,
    required this.settingsController,
    required this.persistenceController,
  });

  @override
  State<_ImportStepView> createState() => _ImportStepViewState();
}

class _ImportStepViewState extends State<_ImportStepView> {
  final _log = Logger('ImportStep');
  _ImportPhase _phase = _ImportPhase.pickSource;
  ScanResult? _scanResult;
  ImportProgress _progress = const ImportProgress(current: 0, total: 0, phase: '');
  int _shotsProcessed = 0;
  int _profilesImported = 0;
  ImportResult? _importResult;
  int _filesCopied = 0;
  int _filesToCopy = 0;

  Future<void> _onComplete() async {
    await _cleanupSafStaging();
    await widget.settingsController.setOnboardingCompleted(true);
    widget.controller.advance();
  }

  Future<void> _cleanupSafStaging() async {
    if (Platform.isAndroid) {
      await SafFolderCopier().cleanup();
    }
  }

  @override
  void dispose() {
    _cleanupSafStaging();
    super.dispose();
  }

  Future<void> _onFolderSelected(String folderPathOrUri) async {
    String effectivePath = folderPathOrUri;

    // On Android, folderPathOrUri is a SAF tree URI — copy to local cache first.
    if (Platform.isAndroid) {
      setState(() {
        _phase = _ImportPhase.copying;
        _filesCopied = 0;
        _filesToCopy = 0;
      });

      final copier = SafFolderCopier();
      final localPath = await copier.copyFromUri(
        folderPathOrUri,
        onProgress: (copied, total) {
          if (!mounted) return;
          setState(() {
            _filesCopied = copied;
            _filesToCopy = total;
          });
        },
      );

      if (localPath == null) {
        if (mounted) {
          setState(() => _phase = _ImportPhase.pickSource);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No Decent app data found')),
          );
        }
        return;
      }
      effectivePath = localPath;
    }

    if (!mounted) return;
    setState(() {
      _phase = _ImportPhase.scanning;
    });

    final scanResult = await De1appScanner.scan(effectivePath);

    if (!mounted) return;

    if (scanResult.isEmpty) {
      setState(() {
        _phase = _ImportPhase.pickSource;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Decent app data found')),
      );
      return;
    }

    setState(() {
      _scanResult = scanResult;
      _phase = _ImportPhase.summary;
    });
  }

  Future<void> _onZipSelected(String filePath) async {
    setState(() {
      _phase = _ImportPhase.importing;
      _progress = const ImportProgress(current: 0, total: 1, phase: 'backup');
    });

    try {
      final bytes = await File(filePath).readAsBytes();

      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://localhost:8080/api/v1/data/import?onConflict=skip'),
        );
        request.headers.contentType = ContentType('application', 'zip');
        request.add(bytes);
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode != 200) {
          throw Exception('Server returned ${response.statusCode}: $responseBody');
        }

        final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;
        final result = _zipResponseToImportResult(responseJson);

        widget.persistenceController.notifyShotsChanged();

        if (mounted) {
          setState(() {
            _importResult = result;
            _phase = _ImportPhase.result;
          });
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _log.warning('Failed to import ZIP backup', e);
      if (mounted) {
        setState(() {
          _importResult = ImportResult(
            errors: [
              ImportError(
                filename: filePath.split('/').last,
                reason: 'ZIP import failed',
                details: e.toString(),
              ),
            ],
          );
          _phase = _ImportPhase.result;
        });
      }
    }
  }

  ImportResult _zipResponseToImportResult(Map<String, dynamic> json) {
    int imported(String key) =>
        (json[key] is Map ? json[key]['imported'] as int? : null) ?? 0;
    int skipped(String key) =>
        (json[key] is Map ? json[key]['skipped'] as int? : null) ?? 0;

    return ImportResult(
      shotsImported: imported('shots'),
      shotsSkipped: skipped('shots'),
      profilesImported: imported('profiles'),
      profilesSkipped: skipped('profiles'),
      beansCreated: imported('beans'),
      beansSkipped: skipped('beans'),
      grindersCreated: imported('grinders'),
      grindersSkipped: skipped('grinders'),
    );
  }

  Future<void> _onImportAll() async {
    final scanResult = _scanResult;
    if (scanResult == null) return;

    setState(() {
      _phase = _ImportPhase.importing;
      _progress = const ImportProgress(current: 0, total: 0, phase: '');
      _shotsProcessed = 0;
      _profilesImported = 0;
    });

    final importer = De1appImporter(
      storageService: widget.storageService,
      profileStorageService: widget.profileStorageService,
      beanStorageService: widget.beanStorageService,
      grinderStorageService: widget.grinderStorageService,
    );

    try {
      final result = await importer.import(
        scanResult,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            if (progress.phase == 'shots') {
              _shotsProcessed = progress.current;
            } else if (progress.phase == 'profiles') {
              _profilesImported = progress.current;
            }
          });
        },
      );
      if (mounted) {
        setState(() {
          _importResult = result;
          _phase = _ImportPhase.result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importResult = ImportResult(
            errors: [
              ImportError(
                filename: 'import',
                reason: 'Fatal error',
                details: e.toString(),
              ),
            ],
          );
          _phase = _ImportPhase.result;
        });
      }
    }
  }

  void _onCancelFromSummary() {
    setState(() {
      _scanResult = null;
      _phase = _ImportPhase.pickSource;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_phase) {
        _ImportPhase.pickSource => ImportSourcePicker(
            onDe1appFolderSelected: _onFolderSelected,
            onZipFileSelected: _onZipSelected,
            onSkip: _onComplete,
          ),
        _ImportPhase.copying => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                if (_filesToCopy > 0)
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: _filesCopied / _filesToCopy,
                    ),
                  )
                else
                  const CircularProgressIndicator(),
                Text(
                  _filesToCopy > 0
                      ? 'Copying files... $_filesCopied / $_filesToCopy'
                      : 'Preparing import...',
                ),
              ],
            ),
          ),
        _ImportPhase.scanning => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                CircularProgressIndicator(),
                Text('Scanning folder...'),
              ],
            ),
          ),
        _ImportPhase.summary => ImportSummaryView(
            scanResult: _scanResult!,
            onImportAll: _onImportAll,
            onCancel: _onCancelFromSummary,
          ),
        _ImportPhase.importing => ImportProgressView(
            progress: _progress,
            shotsImported: _shotsProcessed,
            profilesImported: _profilesImported,
          ),
        _ImportPhase.result => ImportResultView(
            result: _importResult!,
            onContinue: _onComplete,
          ),
      },
    );
  }
}
