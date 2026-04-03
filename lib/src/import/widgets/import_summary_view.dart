import 'package:flutter/material.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shows pre-scan results with item counts and an "Import All" button.
class ImportSummaryView extends StatelessWidget {
  final ScanResult scanResult;
  final VoidCallback onImportAll;
  final VoidCallback onCancel;

  const ImportSummaryView({
    super.key,
    required this.scanResult,
    required this.onImportAll,
    required this.onCancel,
  });

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
              Text('Found in your Decent app folder:', style: theme.textTheme.h4),
              ShadCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    _CountRow(
                      icon: LucideIcons.coffee,
                      label: '${scanResult.shotCount} shot${scanResult.shotCount == 1 ? '' : 's'}',
                    ),
                    _CountRow(
                      icon: LucideIcons.fileText,
                      label: '${scanResult.profileCount} profile${scanResult.profileCount == 1 ? '' : 's'}',
                    ),
                    if (scanResult.hasDyeGrinders)
                      const _CountRow(
                        icon: LucideIcons.settings,
                        label: 'Grinder specs (DYE)',
                      ),
                  ],
                ),
              ),
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: ShadButton(
                      onPressed: onImportAll,
                      child: const Text('Import All'),
                    ),
                  ),
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CountRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      spacing: 8,
      children: [
        Icon(icon, size: 16),
        Text(label, style: theme.textTheme.p),
      ],
    );
  }
}
