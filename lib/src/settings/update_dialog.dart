import 'package:flutter/material.dart';
import 'package:reaprime/src/services/android_updater.dart';

/// Dialog that shows update information and allows downloading/installing
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final String currentVersion;
  final Future<String> Function(UpdateInfo) onDownload;
  final Future<bool> Function(String) onInstall;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.currentVersion,
    required this.onDownload,
    required this.onInstall,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  bool _isInstalling = false;
  String? _downloadedPath;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update Available'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${widget.updateInfo.version}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            Text(
              'Current version: ${widget.currentVersion}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.updateInfo.isPrerelease) ...[
              SizedBox(height: 8),
              Chip(
                label: Text('Pre-release'),
                backgroundColor: Colors.orange.withOpacity(0.2),
              ),
            ],
            SizedBox(height: 16),
            if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
              Text(
                'Release Notes:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: 8),
              Container(
                constraints: BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    widget.updateInfo.releaseNotes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
            if (_isDownloading) ...[
              SizedBox(height: 16),
              LinearProgressIndicator(),
              SizedBox(height: 8),
              Text('Downloading update...'),
            ],
            if (_isInstalling) ...[
              SizedBox(height: 16),
              LinearProgressIndicator(),
              SizedBox(height: 8),
              Text('Installing update...'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading || _isInstalling
              ? null
              : () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        if (_downloadedPath == null)
          ElevatedButton(
            onPressed: _isDownloading ? null : _handleDownload,
            child: Text('Download'),
          )
        else
          ElevatedButton(
            onPressed: _isInstalling ? null : _handleInstall,
            child: Text('Install'),
          ),
      ],
    );
  }

  Future<void> _handleDownload() async {
    setState(() {
      _isDownloading = true;
      _error = null;
    });

    try {
      final path = await widget.onDownload(widget.updateInfo);
      setState(() {
        _downloadedPath = path;
        _isDownloading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Download failed: $e';
        _isDownloading = false;
      });
    }
  }

  Future<void> _handleInstall() async {
    if (_downloadedPath == null) return;

    setState(() {
      _isInstalling = true;
      _error = null;
    });

    try {
      final success = await widget.onInstall(_downloadedPath!);
      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Update installation started. Please follow the on-screen prompts.',
              ),
            ),
          );
        }
      } else {
        setState(() {
          _error = 'Installation permission required. Please grant permission and try again.';
          _isInstalling = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Installation failed: $e';
        _isInstalling = false;
      });
    }
  }
}
