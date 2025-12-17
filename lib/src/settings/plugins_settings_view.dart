import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';

// LucideIcons is exported by shadcn_ui

// Plugins list and settings
// Shows a list of all available plugins,
// has an icon indicating which plugin is currently loaded (on the list)
// has an icon to edit plugin settings - which opens a new dialog for editing
// lists permissions for each plugin, as well as other details such as author, plugin name, version
// also has buttons for adding/installing a plugin as well as removing a specific plugin
class PluginsSettingsView extends StatefulWidget {
  const PluginsSettingsView({super.key, required this.pluginLoaderService});

  static const routeName = '/plugins';

  final PluginLoaderService pluginLoaderService;

  @override
  State<PluginsSettingsView> createState() => _PluginsSettingsViewState();
}

class _PluginsSettingsViewState extends State<PluginsSettingsView> {
  List<PluginManifest> _plugins = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlugins();
  }

  Future<void> _loadPlugins() async {
    setState(() {
      _isLoading = true;
    });

    // Get the list of available plugins
    final plugins = widget.pluginLoaderService.availablePlugins;

    setState(() {
      _plugins = plugins;
      _isLoading = false;
    });
  }

  void _refreshPlugins() {
    _loadPlugins();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _refreshPlugins,
            tooltip: 'Refresh Plugins',
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _installPlugin(context),
            tooltip: 'Install Plugin',
          ),
        ],
      ),
      body: _buildPluginList(),
    );
  }

  Widget _buildPluginList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.puzzle, size: 64),
            const SizedBox(height: 16),
            const Text('No plugins installed', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Click the + button to install a plugin',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _plugins.length,
      itemBuilder: (context, index) {
        final plugin = _plugins[index];
        final isLoaded = widget.pluginLoaderService.isPluginLoaded(plugin.id);
        return _buildPluginCard(context, plugin, isLoaded);
      },
    );
  }

  Widget _buildPluginCard(
    BuildContext context,
    PluginManifest plugin,
    bool isLoaded,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'by ${plugin.author} • v${plugin.version}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      isLoaded ? LucideIcons.check : LucideIcons.circle,
                      color: isLoaded ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Icon(LucideIcons.ellipsisVertical),
                      onSelected:
                          (value) =>
                              _handlePluginAction(context, value, plugin.id),
                      itemBuilder:
                          (context) => [
                            PopupMenuItem<String>(
                              value: isLoaded ? 'unload' : 'load',
                              child: Text(isLoaded ? 'Unload' : 'Load'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'settings',
                              child: Text('Settings'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'reload',
                              child: Text('Reload'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'remove',
                              child: Text(
                                'Remove',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (plugin.permissions.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Permissions:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children:
                        plugin.permissions
                            .map(
                              (permission) => Chip(
                                label: Text(permission),
                                backgroundColor: Colors.blue[50],
                                labelStyle: const TextStyle(fontSize: 12),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            FutureBuilder<bool>(
              future: widget.pluginLoaderService.shouldAutoLoad(plugin.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                final shouldAutoLoad = snapshot.data ?? false;
                return Row(
                  children: [
                    Switch(
                      value: shouldAutoLoad,
                      onChanged: (value) async {
                        try {
                          await widget.pluginLoaderService.setPluginAutoLoad(
                            plugin.id,
                            value,
                          );
                          _showSnackBar(
                            context,
                            value
                                ? 'Plugin will auto-load on startup'
                                : 'Plugin will not auto-load on startup',
                          );
                          setState(() {});
                        } catch (e, st) {
                          Logger(
                            'PluginsSettingsView',
                          ).warning('Failed to set auto-load', e, st);
                          if (mounted) {
                            _showSnackBar(
                              context,
                              'Failed to set auto-load: $e',
                              isError: true,
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text('Auto-load on startup'),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.secondary(
                  onPressed:
                      () => _handlePluginAction(
                        context,
                        isLoaded ? 'unload' : 'load',
                        plugin.id,
                      ),
                  child: Text(isLoaded ? 'Unload' : 'Load'),
                ),
                const SizedBox(width: 8),
                ShadButton(
                  onPressed:
                      () => _handlePluginAction(context, 'settings', plugin.id),
                  child: const Text('Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePluginAction(
    BuildContext context,
    String action,
    String pluginId,
  ) async {
    final logger = Logger('PluginsSettingsView');
    try {
      switch (action) {
        case 'load':
          await widget.pluginLoaderService.loadPlugin(pluginId);
          if (context.mounted) {
            _showSnackBar(context, 'Plugin loaded successfully');
          }
          _refreshPlugins();
          break;
        case 'unload':
          await widget.pluginLoaderService.unloadPlugin(pluginId);
          if (context.mounted) {
            _showSnackBar(context, 'Plugin unloaded');
          }
          _refreshPlugins();
          break;
        case 'reload':
          await widget.pluginLoaderService.reloadPlugin(pluginId);
          if (context.mounted) {
            _showSnackBar(context, 'Plugin reloaded');
          }
          _refreshPlugins();
          break;
        case 'settings':
          await _showPluginSettings(context, pluginId);
          break;
        case 'remove':
          await _confirmRemovePlugin(context, pluginId);
          break;
      }
    } catch (e, st) {
      logger.warning('Failed to $action plugin $pluginId', e, st);
      if (context.mounted) {
        _showSnackBar(context, 'Failed to $action plugin: $e', isError: true);
      }
    }
  }

  Future<void> _installPlugin(BuildContext context) async {
    final logger = Logger('PluginsSettingsView');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        // file variable is not used yet since installation is not implemented
        // final file = result.files.first;
        final tempDir = await Directory.systemTemp.createTemp();
        // zipFile variable is not used yet, commented out for now
        // final zipFile = File(file.path!);

        // TODO: Extract zip file and install plugin
        // For now, we'll just show a message
        if (context.mounted) {
          _showSnackBar(context, 'Plugin installation not yet implemented');
        }

        // Clean up temp directory
        await tempDir.delete(recursive: true);
      }
    } catch (e, st) {
      logger.warning('Failed to install plugin', e, st);
      if (context.mounted) {
        _showSnackBar(context, 'Failed to install plugin: $e', isError: true);
      }
    }
  }

  Future<void> _confirmRemovePlugin(
    BuildContext context,
    String pluginId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remove Plugin'),
            content: Text(
              'Are you sure you want to remove plugin "$pluginId"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await widget.pluginLoaderService.removePlugin(pluginId);
        if (context.mounted) {
          _showSnackBar(context, 'Plugin removed successfully');
        }
        _refreshPlugins();
      } catch (e, st) {
        Logger('PluginsSettingsView').warning('Failed to remove plugin', e, st);
        if (context.mounted) {
          _showSnackBar(context, 'Failed to remove plugin: $e', isError: true);
        }
      }
    }
  }

  Future<void> _showPluginSettings(
    BuildContext context,
    String pluginId,
  ) async {
    final manifest = widget.pluginLoaderService.getPluginManifest(pluginId);
    if (manifest == null) return;

    final settings = await widget.pluginLoaderService.pluginSettings(pluginId);
    final settingsSchema = manifest.settings;

    if (settingsSchema.isEmpty) {
      if (context.mounted) {
        _showSnackBar(context, 'This plugin has no configurable settings');
      }
      return;
    }

    final Map<String, dynamic> newSettings = Map.from(settings);
    if (context.mounted == false) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('${manifest.name} Settings'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView(
                    shrinkWrap: true,
                    children:
                        settingsSchema.entries.map((entry) {
                          final key = entry.key;
                          final schema = entry.value;
                          final currentValue = newSettings[key];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (schema['type'] == 'boolean')
                                  Row(
                                    children: [
                                      Switch(
                                        value:
                                            currentValue ??
                                            schema['default'] ??
                                            false,
                                        onChanged: (value) {
                                          setState(() {
                                            newSettings[key] = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Text(schema['description'] ?? ''),
                                    ],
                                  )
                                else if (schema['type'] == 'number')
                                  TextField(
                                    decoration: InputDecoration(
                                      hintText: schema['description'] ?? '',
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) {
                                      final numValue = num.tryParse(value);
                                      if (numValue != null) {
                                        setState(() {
                                          newSettings[key] = numValue;
                                        });
                                      }
                                    },
                                  )
                                else
                                  TextField(
                                    decoration: InputDecoration(
                                      hintText: schema['description'] ?? '',
                                      border: const OutlineInputBorder(),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        newSettings[key] = value;
                                      });
                                    },
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await widget.pluginLoaderService.savePluginSettings(
                          pluginId,
                          newSettings,
                        );
                        if (context.mounted == false) {
                          return;
                        }
                        // The dialog context is still valid here since we're in the dialog
                        _showSnackBar(context, 'Settings saved');
                        Navigator.pop(context);
                      } catch (e, st) {
                        Logger(
                          'PluginsSettingsView',
                        ).warning('Failed to save settings', e, st);
                        if (context.mounted) {
                          _showSnackBar(
                            context,
                            'Failed to save settings: $e',
                            isError: true,
                          );
                        }
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}
