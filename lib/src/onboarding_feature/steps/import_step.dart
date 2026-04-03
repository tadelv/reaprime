import 'package:flutter/material.dart';
import 'package:reaprime/src/import/de1app_importer.dart';
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
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum _ImportPhase {
  pickSource,
  scanning,
  summary,
  importing,
  result,
  zipImport,
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

  const _ImportStepView({
    required this.controller,
    required this.storageService,
    required this.profileStorageService,
    required this.beanStorageService,
    required this.grinderStorageService,
    required this.settingsController,
  });

  @override
  State<_ImportStepView> createState() => _ImportStepViewState();
}

class _ImportStepViewState extends State<_ImportStepView> {
  _ImportPhase _phase = _ImportPhase.pickSource;
  ScanResult? _scanResult;
  ImportProgress _progress = const ImportProgress(current: 0, total: 0, phase: '');
  int _shotsImported = 0;
  int _profilesImported = 0;
  ImportResult? _importResult;

  Future<void> _onComplete() async {
    await widget.settingsController.setOnboardingCompleted(true);
    widget.controller.advance();
  }

  Future<void> _onFolderSelected(String folderPath) async {
    setState(() {
      _phase = _ImportPhase.scanning;
    });

    final scanResult = await De1appScanner.scan(folderPath);

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

  void _onZipSelected(String filePath) {
    setState(() {
      _phase = _ImportPhase.zipImport;
    });
  }

  Future<void> _onImportAll() async {
    final scanResult = _scanResult;
    if (scanResult == null) return;

    setState(() {
      _phase = _ImportPhase.importing;
      _progress = const ImportProgress(current: 0, total: 0, phase: '');
      _shotsImported = 0;
      _profilesImported = 0;
    });

    final importer = De1appImporter(
      storageService: widget.storageService,
      profileStorageService: widget.profileStorageService,
      beanStorageService: widget.beanStorageService,
      grinderStorageService: widget.grinderStorageService,
    );

    final result = await importer.import(
      scanResult,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          if (progress.phase == 'shots') {
            _shotsImported = progress.current;
          } else if (progress.phase == 'profiles') {
            _profilesImported = progress.current;
          }
        });
      },
    );

    if (!mounted) return;

    setState(() {
      _importResult = result;
      _phase = _ImportPhase.result;
    });
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
            shotsImported: _shotsImported,
            profilesImported: _profilesImported,
          ),
        _ImportPhase.result => ImportResultView(
            result: _importResult!,
            onContinue: _onComplete,
          ),
        _ImportPhase.zipImport => _ZipImportPlaceholder(onContinue: _onComplete),
      },
    );
  }
}

class _ZipImportPlaceholder extends StatelessWidget {
  final VoidCallback onContinue;

  const _ZipImportPlaceholder({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Text('ZIP Import', style: theme.textTheme.h4),
              Text(
                'ZIP backup import will be processed after setup completes. '
                'You can also import backups anytime from Settings > Data Management.',
                style: theme.textTheme.p,
              ),
              ShadButton(
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
