import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SkinSelectorPage extends StatefulWidget {
  const SkinSelectorPage({
    super.key,
    required this.settingsController,
    required this.webUIService,
    required this.webUIStorage,
  });

  static const routeName = '/skins';

  final SettingsController settingsController;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;

  @override
  State<SkinSelectorPage> createState() => _SkinSelectorPageState();
}

class _SkinSelectorPageState extends State<SkinSelectorPage>
    with WidgetsBindingObserver {
  String? _selectedSkinId;
  static const String _customSkinId = '__custom__';
  static const String _liveEditSkinId = '__live_edit__';
  final Logger _log = Logger('SkinSelector');
  bool _storagePermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedSkinId = widget.webUIStorage.defaultSkin?.id;
    _checkStoragePermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStoragePermission();
    }
  }

  Future<void> _checkStoragePermission() async {
    if (!Platform.isAndroid || BuildInfo.appStore) return;
    final status = await Permission.manageExternalStorage.status;
    if (mounted && status.isGranted != _storagePermissionGranted) {
      setState(() => _storagePermissionGranted = status.isGranted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Web Interface')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              // Skin selector card
              ShadCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.web_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Active Skin',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select and manage web-based user interface skins',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 16),
                    _buildSkinSelector(),
                    const SizedBox(height: 16),
                    _buildStoragePermissionRow(),
                  ],
                ),
              ),

              // Server controls card
              ShadCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Server',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.webUIService.isServing
                          ? 'WebUI server is running'
                          : 'WebUI server is stopped',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (!widget.webUIService.isServing)
                      _ActionButton(
                        label: 'Start WebUI Server',
                        icon: Icons.play_arrow,
                        onPressed: _startSelectedSkin,
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ActionButton(
                            label: 'Open in Browser',
                            icon: Icons.open_in_browser,
                            onPressed: _openWebUIInBrowser,
                          ),
                          _ActionButton.destructive(
                            label: 'Stop Server',
                            icon: Icons.stop,
                            onPressed: () async {
                              await widget.webUIService.stopServing();
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    if (!BuildInfo.appStore) ...[
                      const SizedBox(height: 12),
                      _ActionButton.outline(
                        label: 'Check for Skin Updates',
                        icon: Icons.update,
                        onPressed: () => _checkForSkinUpdates(context),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkinSelector() {
    final installedSkins = widget.webUIStorage.installedSkins;

    return DropdownButton<String>(
      isExpanded: true,
      value: _selectedSkinId,
      onChanged: (value) async {
        if (value == null) return;

        setState(() => _selectedSkinId = value);

        if (value == _customSkinId) {
          await _pickCustomSkinZip(context);
        } else if (value == _liveEditSkinId) {
          await _pickLiveEditFolder(context);
        } else if (widget.webUIService.isServing) {
          await _restartServerWithSkin(value);
        }
      },
      items: [
        ...installedSkins.map((skin) {
          return DropdownMenuItem(
            value: skin.id,
            child: Row(
              children: [
                Icon(skin.isBundled ? Icons.verified : Icons.folder, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(skin.name, overflow: TextOverflow.ellipsis),
                ),
                if (skin.version != null)
                  Text(
                    ' v${skin.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (!skin.isBundled && !BuildInfo.appStore)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      tooltip: 'Remove ${skin.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        // Close the dropdown first
                        Navigator.of(context).pop();

                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Remove skin?'),
                            content: Text(
                              'Remove "${skin.name}"? This cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        try {
                          await widget.webUIStorage.removeSkin(skin.id);

                          if (_selectedSkinId == skin.id) {
                            _selectedSkinId =
                                widget.webUIStorage.defaultSkin?.id;
                            if (widget.webUIService.isServing) {
                              await widget.webUIService.stopServing();
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to remove skin: $e'),
                              ),
                            );
                          }
                        }

                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          );
        }),
        if (!BuildInfo.appStore)
          const DropdownMenuItem(
            value: _customSkinId,
            child: Row(
              children: [
                Icon(Icons.archive_outlined, size: 16),
                SizedBox(width: 8),
                Text('Install from .zip...'),
              ],
            ),
          ),
        if (!BuildInfo.appStore &&
            (Platform.isMacOS ||
                Platform.isLinux ||
                Platform.isWindows ||
                (Platform.isAndroid &&
                    (_storagePermissionGranted ||
                        _selectedSkinId == _liveEditSkinId))))
          const DropdownMenuItem(
            value: _liveEditSkinId,
            child: Row(
              children: [
                Icon(Icons.folder_open, size: 16),
                SizedBox(width: 8),
                Text('Live-edit from folder...'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStoragePermissionRow() {
    if (!Platform.isAndroid || BuildInfo.appStore) {
      return const SizedBox.shrink();
    }

    if (_storagePermissionGranted) {
      return Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          const Text('Full storage access granted'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grant full storage access to live-edit skins from external folders without copying.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _ActionButton.outline(
          label: 'Grant Storage Access',
          icon: Icons.folder_open,
          onPressed: () async {
            final result = await Permission.manageExternalStorage.request();
            if (result.isPermanentlyDenied) {
              await openAppSettings();
            }
            await _checkStoragePermission();
          },
        ),
      ],
    );
  }

  // MARK: - WebUI Actions

  Future<void> _restartServerWithSkin(String skinId) async {
    try {
      final skin = widget.webUIStorage.getSkin(skinId);
      if (skin == null) throw Exception('Selected skin not found');

      _log.info('Restarting WebUI server with skin: ${skin.name}');

      await widget.webUIService.stopServing();
      await widget.webUIService.serveFolderAtPath(skin.path);

      try {
        await widget.webUIStorage.setDefaultSkin(skin.id);
        _log.info('Set default skin to: ${skin.id}');
      } catch (e) {
        _log.warning('Failed to set default skin: $e');
      }

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WebUI restarted with ${skin.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _log.severe('Failed to restart WebUI server', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restart WebUI: $e')),
        );
      }
    }
  }

  Future<void> _startSelectedSkin() async {
    if (_selectedSkinId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a skin first')),
      );
      return;
    }

    if (_selectedSkinId == _customSkinId) {
      await _pickCustomSkinZip(context);
      return;
    }

    if (_selectedSkinId == _liveEditSkinId) {
      await _pickLiveEditFolder(context);
      return;
    }

    try {
      final skin = widget.webUIStorage.getSkin(_selectedSkinId!);
      if (skin == null) throw Exception('Selected skin not found');

      await widget.webUIService.serveFolderAtPath(skin.path);

      try {
        await widget.webUIStorage.setDefaultSkin(skin.id);
        _log.info('Set default skin to: ${skin.id}');
      } catch (e) {
        _log.warning('Failed to set default skin: $e');
      }

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WebUI started with ${skin.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start WebUI: $e')),
        );
      }
    }
  }

  Future<void> _pickCustomSkinZip(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.isEmpty) {
      setState(() => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
      return;
    }

    final filePath = result.files.single.path;
    if (filePath == null) {
      setState(() => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
      return;
    }

    try {
      final skinId = await widget.webUIStorage.installFromPath(filePath);
      final skin = widget.webUIStorage.getSkin(skinId);
      if (skin == null) {
        throw Exception('Installed skin not found: $skinId');
      }
      await widget.webUIService.serveFolderAtPath(skin.path);
      await widget.webUIStorage.setDefaultSkin(skinId);
      setState(() => _selectedSkinId = skinId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Expanded(child: Text('Custom skin installed and loaded')),
                ShadButton.outline(
                  onPressed: () async {
                    await _openWebUIInBrowser();
                  },
                  child: const Text("Open"),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to install skin: $e')),
        );
      }
      setState(() => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
    }
  }

  Future<void> _pickLiveEditFolder(BuildContext context) async {
    final selectedDirectory = await FilePicker.getDirectoryPath();

    if (selectedDirectory != null) {
      final indexFile = File('$selectedDirectory/index.html');
      final itExists = await indexFile.exists();

      if (itExists) {
        await widget.webUIService.serveFolderAtPath(selectedDirectory);
        setState(() {});

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Expanded(
                    child: Text('Live-editing from $selectedDirectory'),
                  ),
                  ShadButton.outline(
                    onPressed: () async {
                      await _openWebUIInBrowser();
                    },
                    child: const Text("Open"),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('index.html not found in selected folder'),
            ),
          );
        }
        setState(() => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
      }
    } else {
      setState(() => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
    }
  }

  Future<bool> _openWebUIInBrowser() async {
    return await launchUrl(
      Uri.parse(
        'http://localhost:3000?_=${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
  }

  Future<void> _checkForSkinUpdates(BuildContext context) async {
    try {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking for skin updates...')),
      );

      await widget.webUIStorage.downloadRemoteSkins();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Skin updates completed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      _log.severe('Error checking for skin updates', e, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check for skin updates: $e')),
      );
    }
  }
}

/// Small helper for consistent action buttons in the skin selector.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isDestructive;
  final bool isOutline;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isDestructive = false,
    this.isOutline = false,
  });

  factory _ActionButton.destructive(
      {required String label,
      required IconData icon,
      required VoidCallback onPressed}) {
    return _ActionButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      isDestructive: true,
    );
  }

  factory _ActionButton.outline(
      {required String label,
      required IconData icon,
      required VoidCallback onPressed}) {
    return _ActionButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      isOutline: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = isDestructive
        ? ShadButton.destructive(
            leading: Icon(icon, size: 16),
            onPressed: onPressed,
            child: Text(label),
          )
        : isOutline
            ? ShadButton.outline(
                leading: Icon(icon, size: 16),
                onPressed: onPressed,
                child: Text(label),
              )
            : ShadButton(
                leading: Icon(icon, size: 16),
                onPressed: onPressed,
                child: Text(label),
              );

    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(child: button),
    );
  }
}
