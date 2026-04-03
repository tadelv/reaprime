import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Two card-style buttons for picking an import source, with an optional skip link.
class ImportSourcePicker extends StatelessWidget {
  final void Function(String folderPath) onDe1appFolderSelected;
  final void Function(String filePath) onZipFileSelected;
  final VoidCallback? onSkip;

  const ImportSourcePicker({
    super.key,
    required this.onDe1appFolderSelected,
    required this.onZipFileSelected,
    this.onSkip,
  });

  Future<void> _pickFolder(BuildContext context) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your de1plus folder',
    );
    if (path != null && context.mounted) {
      onDe1appFolderSelected(path);
    }
  }

  Future<void> _pickZipFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Select a .zip backup file',
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.first.path != null &&
        context.mounted) {
      onZipFileSelected(result.files.first.path!);
    }
  }

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
              Text('Import Your Data', style: theme.textTheme.h3),
              _SourceButton(
                icon: LucideIcons.folder,
                title: 'Import from Decent app',
                subtitle: 'Select your de1plus folder',
                onTap: () => _pickFolder(context),
              ),
              _SourceButton(
                icon: LucideIcons.archiveRestore,
                title: 'Import Bridge backup',
                subtitle: 'Select a .zip backup file',
                onTap: () => _pickZipFile(context),
              ),
              if (onSkip != null)
                Center(
                  child: ShadButton.link(
                    onPressed: onSkip,
                    child: const Text('Skip for now'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadButton.outline(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          spacing: 12,
          children: [
            Icon(icon, size: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.p),
                Text(subtitle, style: theme.textTheme.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
