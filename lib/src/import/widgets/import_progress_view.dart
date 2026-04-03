import 'package:flutter/material.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Determinate progress bar showing import phase and running counts.
class ImportProgressView extends StatelessWidget {
  final ImportProgress progress;
  final int shotsImported;
  final int profilesImported;

  const ImportProgressView({
    super.key,
    required this.progress,
    required this.shotsImported,
    required this.profilesImported,
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
              Text('Importing Your Data...', style: theme.textTheme.h4),
              ShadProgress(value: progress.fraction),
              Text(
                '${progress.current} of ${progress.total} ${progress.phase}',
                style: theme.textTheme.muted,
                textAlign: TextAlign.center,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    '$shotsImported shot${shotsImported == 1 ? '' : 's'} processed',
                    style: theme.textTheme.muted,
                  ),
                  Text(
                    '$profilesImported profile${profilesImported == 1 ? '' : 's'} imported',
                    style: theme.textTheme.muted,
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
