import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/sample_feature/sample_item_list_view.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/gateway_mode_info_dialog.dart';
import 'package:reaprime/src/settings/plugins_settings_view.dart';
import 'package:reaprime/src/settings/update_dialog.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/util/shot_exporter.dart';
import 'package:reaprime/src/util/shot_importer.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_controller.dart';

/// Displays the various settings that can be customized by the user.
///
/// When a user changes a setting, the SettingsController is updated and
/// Widgets that listen to the SettingsController are rebuilt.
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.controller,
    required this.persistenceController,
    required this.webUIService,
    required this.webUIStorage,
  });

  static const routeName = '/settings';

  final SettingsController controller;
  final PersistenceController persistenceController;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String? _selectedSkinId;
  static const String _customSkinId = '__custom__';

  @override
  void initState() {
    super.initState();
    // Initialize with default skin if available
    _selectedSkinId = widget.webUIStorage.defaultSkin?.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive padding based on screen width
            final horizontalPadding = constraints.maxWidth > 600 ? 16.0 : 12.0;
            final cardSpacing = constraints.maxWidth > 600 ? 12.0 : 10.0;

            return Padding(
              padding: EdgeInsets.all(horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Appearance Section
                  _buildSectionCard(
                    context: context,
                    title: 'Appearance',
                    icon: Icons.palette_outlined,
                    footnote: 'Customize the visual appearance of the app',
                    children: [
                      Row(
                        children: [
                          Text(
                            'Theme',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButton<ThemeMode>(
                              isExpanded: true,
                              value: widget.controller.themeMode,
                              onChanged: widget.controller.updateThemeMode,
                              items: const [
                                DropdownMenuItem(
                                  value: ThemeMode.system,
                                  child: Text('System Theme'),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.light,
                                  child: Text('Light Theme'),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.dark,
                                  child: Text('Dark Theme'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Skin Exit Button',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButton<SkinExitButtonPosition>(
                                isExpanded: true,
                                value: widget.controller.skinExitButtonPosition,
                                onChanged: (position) {
                                  if (position != null) {
                                    widget.controller.setSkinExitButtonPosition(position);
                                  }
                                },
                                items: const [
                                  DropdownMenuItem(
                                    value: SkinExitButtonPosition.topLeft,
                                    child: Text('Top Left'),
                                  ),
                                  DropdownMenuItem(
                                    value: SkinExitButtonPosition.topRight,
                                    child: Text('Top Right'),
                                  ),
                                  DropdownMenuItem(
                                    value: SkinExitButtonPosition.bottomLeft,
                                    child: Text('Bottom Left'),
                                  ),
                                  DropdownMenuItem(
                                    value: SkinExitButtonPosition.bottomRight,
                                    child: Text('Bottom Right'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: cardSpacing),

                  // Gateway & Control Section
                  _buildSectionCard(
                    context: context,
                    title: 'Gateway & Control',
                    icon: Icons.settings_remote_outlined,
                    infoButton: () => showGatewayModeInfoDialog(context),
                    footnote:
                        'Configure how external clients can control the machine',
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Text(
                            'Gateway Mode',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          DropdownButton<GatewayMode>(
                            isExpanded: true,
                            value: widget.controller.gatewayMode,
                            onChanged: (v) {
                              if (v != null) {
                                widget.controller.updateGatewayMode(v);
                              }
                            },
                            items: const [
                              DropdownMenuItem(
                                value: GatewayMode.full,
                                child: Text('Full (Rea has no control)'),
                              ),
                              DropdownMenuItem(
                                value: GatewayMode.tracking,
                                child: Text(
                                  'Tracking (Rea will stop shot if target weight is reached)',
                                ),
                              ),
                              DropdownMenuItem(
                                value: GatewayMode.disabled,
                                child: Text('Disabled (Rea has full control)'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: cardSpacing),

                  // Device Management Section
                  _buildSectionCard(
                    context: context,
                    title: 'Device Management',
                    icon: Icons.devices_outlined,
                    footnote:
                        'Configure device connections and simulation options',
                    children: [
                      // Auto-Connect Device
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Auto-Connect Device',
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.info_outline),
                                iconSize: 18,
                                onPressed:
                                    () => _showPreferredDeviceInfo(context),
                                tooltip: 'Learn more',
                                padding: EdgeInsets.all(4),
                                constraints: BoxConstraints(),
                              ),
                            ],
                          ),
                          if (widget.controller.preferredMachineId != null) ...[
                            Text(
                              'Device ID: ${widget.controller.preferredMachineId}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 6),
                            ShadButton.destructive(
                              onPressed: () async {
                                await widget.controller.setPreferredMachineId(null);
                              },
                              child: const Text('Clear Auto-Connect Device'),
                            ),
                          ] else ...[
                            Text(
                              'No auto-connect device set',
                              style:
                                  Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'To set an auto-connect device, check the "Auto-connect to this machine" checkbox when selecting a device during startup.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                      const Divider(height: 24),
                      // Simulated Devices
                      ShadSwitch(
                        value: widget.controller.simulatedDevices,
                        enabled: true,
                        onChanged: (v) async {
                          Logger("Settings").info("toggle sim to $v");
                          await widget.controller.setSimulatedDevices(v);
                        },
                        label: const Text("Show simulated devices"),
                        sublabel: const Text(
                          "Whether simulated devices should be shown in scan results",
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: cardSpacing),

                  // Data Management Section
                  _buildSectionCard(
                    context: context,
                    title: 'Data Management',
                    icon: Icons.storage_outlined,
                    footnote:
                        'Import, export, and manage your shot data and logs',
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ShadButton(
                            onPressed: () async {
                              var docs =
                                  await getApplicationDocumentsDirectory();
                              File logFile = File('${docs.path}/log.txt');
                              var bytes = await logFile.readAsBytes();
                              String? outputFile =
                                  await FilePicker.platform.saveFile(
                                fileName: "R1-logs.txt",
                                dialogTitle: "Choose where to save logs",
                                bytes: bytes,
                              );
                              if (outputFile != null) {
                                File destination = File(outputFile);
                                await destination.writeAsBytes(bytes);
                              }
                            },
                            child: const Text("Export logs"),
                          ),
                          ShadButton(
                            onPressed: () async {
                              final exporter = ShotExporter(
                                storage: widget.persistenceController.storageService,
                              );
                              final jsonData = await exporter.exportJson();
                              final tempDir = await getTemporaryDirectory();
                              final source = File("${tempDir.path}/shots.json");
                              await source.writeAsString(jsonData);
                              final destination =
                                  await FilePicker.platform.getDirectoryPath(
                                dialogTitle: "Pick export dir",
                              );

                              final tempFile = File('$destination/R1_shots.zip');
                              try {
                                // Create zip archive using archive package
                                final archive = Archive();
                                final sourceBytes = await source.readAsBytes();
                                final archiveFile = ArchiveFile(
                                  'shots.json',
                                  sourceBytes.length,
                                  sourceBytes,
                                );
                                archive.addFile(archiveFile);

                                // Encode to zip and write to file
                                final zipData = ZipEncoder().encode(archive);
                                await tempFile.writeAsBytes(zipData!);
                              } catch (e, st) {
                                Logger("Settings")
                                    .severe("failed to export:", e, st);
                              }
                            },
                            child: const Text("Export all shots"),
                          ),
                          ShadButton(
                            onPressed: () => _showImportDialog(context),
                            child: const Text("Import shots"),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: cardSpacing),

                  // WebUI Section
                  _buildSectionCard(
                    context: context,
                    title: 'Web Interface',
                    icon: Icons.web_outlined,
                    footnote:
                        'Select and manage web-based user interface skins',
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          // Skin selector
                          Row(
                            children: [
                              Text(
                                'Skin',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSkinSelector(),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          // Server controls
                          if (!widget.webUIService.isServing)
                            ShadButton.secondary(
                              onPressed: () => _startSelectedSkin(),
                              child: const Text("Start WebUI Server"),
                            )
                          else ...[
                            ShadButton(
                              onPressed: () async {
                                final url = Uri.parse('http://localhost:3000');
                                await launchUrl(url);
                              },
                              child: const Text("Open UI in browser"),
                            ),
                            ShadButton.destructive(
                              onPressed: () async {
                                await widget.webUIService.stopServing();
                                setState(() {});
                              },
                              child: const Text("Stop WebUI Server"),
                            ),
                          ],
                          const Divider(height: 20),
                          ShadButton.outline(
                            onPressed: () => _checkForSkinUpdates(context),
                            child: const Text("Check for Skin Updates"),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: cardSpacing),

                  // Advanced Section
                  _buildSectionCard(
                    context: context,
                    title: 'Advanced',
                    icon: Icons.tune_outlined,
                    footnote: 'Developer tools and advanced configuration',
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          // Log Level
                          Row(
                            children: [
                              Text(
                                'Log Level',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: widget.controller.logLevel,
                                  onChanged: widget.controller.updateLogLevel,
                                  items: const [
                                    DropdownMenuItem(
                                      value: "FINE",
                                      child: Text('Fine'),
                                    ),
                                    DropdownMenuItem(
                                      value: "INFO",
                                      child: Text('Info'),
                                    ),
                                    DropdownMenuItem(
                                      value: "FINEST",
                                      child: Text('Finest'),
                                    ),
                                    DropdownMenuItem(
                                      value: "WARNING",
                                      child: Text('Warning'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          // Plugins Button
                          ShadButton.secondary(
                            onPressed: () {
                              Navigator.of(context)
                                  .pushNamed(PluginsSettingsView.routeName);
                            },
                            child: const Text("Plugins"),
                          ),
                          // Debug View Button
                          ShadButton.secondary(
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                SampleItemListView.routeName,
                              );
                            },
                            child: const Text("Debug view"),
                          ),
                          // Updates Button
                          ShadButton.secondary(
                            onPressed: () => _checkForUpdates(context),
                            child: const Text("Check for updates"),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: cardSpacing),

                  // About Section
                  _buildSectionCard(
                    context: context,
                    title: 'About',
                    icon: Icons.info_outline,
                    footnote: 'Version and build information',
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          _buildInfoRow(
                            context,
                            'Version',
                            BuildInfo.version,
                          ),
                          _buildInfoRow(
                            context,
                            'Commit',
                            BuildInfo.commitShort,
                          ),
                          _buildInfoRow(
                            context,
                            'Branch',
                            BuildInfo.branch,
                          ),
                          const Divider(height: 20),
                          Text(
                            'License',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Copyright © 2025-2026 Decent Espresso',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Licensed under GNU General Public License v3.0',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          ShadButton.outline(
                            onPressed: () async {
                              final url = Uri.parse('https://www.gnu.org/licenses/gpl-3.0.html');
                              await launchUrl(url);
                            },
                            child: const Text('View GPL v3 License'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: horizontalPadding),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    VoidCallback? infoButton,
    String? footnote,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        // Header
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (infoButton != null)
              IconButton(
                icon: const Icon(Icons.info_outline),
                iconSize: 18,
                onPressed: infoButton,
                tooltip: 'Learn more',
                padding: EdgeInsets.all(4),
                constraints: BoxConstraints(),
              ),
          ],
        ),
        // Content
        ...children,
        // Footnote
        if (footnote != null) ...[
          const SizedBox(height: 4),
          Text(
            footnote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withOpacity(0.6),
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
        // Divider after each section
        const Divider(height: 24),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkinSelector() {
    final installedSkins = widget.webUIStorage.installedSkins;
    
    return DropdownButton<String>(
      isExpanded: true,
      value: _selectedSkinId,
      onChanged: (value) {
        setState(() {
          _selectedSkinId = value;
        });
        
        // If custom is selected, open folder picker
        if (value == _customSkinId) {
          _pickCustomSkinFolder(context);
        }
      },
      items: [
        // Installed skins
        ...installedSkins.map((skin) {
          return DropdownMenuItem(
            value: skin.id,
            child: Row(
              children: [
                if (skin.isBundled)
                  const Icon(Icons.verified, size: 16)
                else
                  const Icon(Icons.folder, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skin.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (skin.version != null)
                  Text(
                    ' v${skin.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          );
        }),
        // Custom folder option
        const DropdownMenuItem(
          value: _customSkinId,
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16),
              SizedBox(width: 8),
              Text('Load custom folder...'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _startSelectedSkin() async {
    if (_selectedSkinId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a skin first')),
      );
      return;
    }

    if (_selectedSkinId == _customSkinId) {
      await _pickCustomSkinFolder(context);
      return;
    }

    try {
      final skin = widget.webUIStorage.getSkin(_selectedSkinId!);
      if (skin == null) {
        throw Exception('Selected skin not found');
      }

      await widget.webUIService.serveFolderAtPath(skin.path);
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

  Future<void> _pickCustomSkinFolder(BuildContext context) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final dir = Directory(selectedDirectory);
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
                  Text('Custom WebUI from $selectedDirectory loaded'),
                  const Spacer(),
                  ShadButton.outline(
                    onPressed: () async {
                      final url = Uri.parse('http://localhost:3000');
                      await launchUrl(url);
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
        // Reset selection back to previous valid skin
        setState(() {
          _selectedSkinId = widget.webUIStorage.defaultSkin?.id;
        });
      }
    } else {
      // User cancelled, reset to default
      setState(() {
        _selectedSkinId = widget.webUIStorage.defaultSkin?.id;
      });
    }
  }

  void _showPreferredDeviceInfo(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Auto-Connect Device'),
        description: const Text(
          'Automatically connect to your preferred machine on startup',
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            Text(
              'When you set an auto-connect device, ReaPrime will:',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            _buildInfoPoint(
              context,
              Icons.bluetooth_searching,
              'Scan for devices on startup',
            ),
            _buildInfoPoint(
              context,
              Icons.link,
              'Automatically connect to your preferred machine when found',
            ),
            _buildInfoPoint(
              context,
              Icons.speed,
              'Skip the device selection screen for faster startup',
            ),
            const Divider(),
            Text(
              'How to set:',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              '1. During device selection at startup, check the "Auto-connect to this machine" checkbox next to your preferred device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'How to change:',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              '1. Clear the current auto-connect device using the button above.\n2. Restart the app and select a different device with the checkbox.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPoint(BuildContext context, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }

  Future<void> _checkForSkinUpdates(BuildContext context) async {
    final log = Logger('SettingsView');

    try {
      // Show loading indicator
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking for skin updates...')),
      );

      // Check for skin updates
      await widget.webUIStorage.downloadRemoteSkins();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Skin updates completed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      log.severe('Error checking for skin updates', e, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check for skin updates: $e')),
      );
    }
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final log = Logger('SettingsView');

    try {
      // Show loading indicator
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Checking for updates...')));

      // Check for app updates (Android only for now)
      if (Platform.isAndroid) {
        final updater = AndroidUpdater(owner: 'tadelv', repo: 'reaprime');

        final updateInfo = await updater.checkForUpdate(
          BuildInfo.version,
          channel: UpdateChannel.stable, // TODO: Make this configurable
        );

        if (!context.mounted) return;

        if (updateInfo != null) {
          // Show update dialog
          showDialog(
            context: context,
            builder: (context) => UpdateDialog(
              updateInfo: updateInfo,
              currentVersion: BuildInfo.version,
              onDownload: (info) => updater.downloadUpdate(info),
              onInstall: (path) => updater.installUpdate(path),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are on the latest version')),
          );
        }

        // Also check for WebUI updates
        await widget.webUIStorage.downloadRemoteSkins();
      } else {
        // Non-Android platforms: just check for WebUI updates
        await widget.webUIStorage.downloadRemoteSkins();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('WebUI is up to date')));
      }
    } catch (e, stackTrace) {
      log.severe('Error checking for updates', e, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check for updates: $e')),
      );
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final result = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Import Shots'),
        description: const Text('Choose how you want to import your shots'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadButton(
              onPressed: () {
                Navigator.of(context).pop('file');
              },
              child: const Text('Import from JSON file'),
            ),
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pop('folder');
              },
              child: const Text('Import from folder'),
            ),
          ],
        ),
      ),
    );

    if (result == 'file') {
      await _importFromFile(context);
    } else if (result == 'folder') {
      await _importFromFolder(context);
    }
  }

  Future<void> _showProgressDialog(BuildContext context, String message) async {
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

  Future<void> _importFromFile(BuildContext context) async {
    final log = Logger("ShotImport");
    final importer = ShotImporter(
      storage: widget.persistenceController.storageService,
    );

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: "Select shots JSON file",
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final filePath = result.files.single.path;
    if (filePath == null) {
      log.warning("File path is null");
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to access file')));
      }
      return;
    }

    log.fine("importing from $filePath");

    if (!context.mounted) return;

    // Show progress dialog
    _showProgressDialog(context, 'Importing shots');

    try {
      final file = File(filePath);
      final content = await file.readAsString();

      // Try to parse to determine if it's a single shot or array
      final decoded = jsonDecode(content);

      int count = 0;
      if (decoded is List) {
        // Multiple shots in array format
        count = await importer.importShotsJson(content);
        log.info("Imported $count shots");
      } else {
        // Single shot object
        await importer.importShotJson(content);
        count = 1;
        log.info("Imported 1 shot");
      }

      widget.persistenceController.loadShots();

      // Close progress dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully imported $count shot${count == 1 ? '' : 's'}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      log.severe("Shot import failed:", e, st);

      // Close progress dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importFromFolder(BuildContext context) async {
    final log = Logger("ShotImport");
    final importer = ShotImporter(
      storage: widget.persistenceController.storageService,
    );

    final sourceDirPath = await FilePicker.platform.getDirectoryPath();

    log.fine("importing from $sourceDirPath");
    if (sourceDirPath == null) {
      return;
    }

    if (!context.mounted) return;

    // Show progress dialog
    _showProgressDialog(context, 'Importing shots from folder');

    try {
      final Directory sourceDir = Directory(sourceDirPath);
      final files = await sourceDir.list().toList();
      log.info("listing: $files");

      int successCount = 0;
      int failCount = 0;

      for (final file in files) {
        if (file is! File) continue;

        final f = File(file.path);
        if (!f.path.endsWith('.json')) continue;

        try {
          final content = await f.readAsString();
          log.fine("Importing: ${f.path}");
          await importer.importShotJson(content);
          successCount++;
        } catch (e, st) {
          log.warning("shot import failed:", e, st);
          failCount++;
        }
      }

      widget.persistenceController.loadShots();

      // Close progress dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Show result message
      if (context.mounted) {
        final hasFailures = failCount > 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              successCount > 0
                  ? 'Imported $successCount shot${successCount == 1 ? '' : 's'}${hasFailures ? ' ($failCount failed)' : ''}'
                  : 'No shots imported${hasFailures ? ' ($failCount files failed)' : ''}',
            ),
            backgroundColor: successCount > 0
                ? (hasFailures ? Colors.orange : Colors.green)
                : Colors.red,
          ),
        );
      }
    } catch (e, st) {
      log.severe("Folder import failed:", e, st);

      // Close progress dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFolderAndLoadHtml(BuildContext context) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final dir = Directory(selectedDirectory);
      Logger("Settings")
          .finest('list dir: ${dir.listSync(recursive: true).join("\n")}');
      final indexFile = File('$selectedDirectory/index.html');
      final itExists = await indexFile.exists();
      await widget.webUIService.serveFolderAtPath(selectedDirectory);
      if (context.mounted == false) {
        return;
      }
      if (itExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Text('WebUI from $selectedDirectory loaded'),
                const Spacer(),
                ShadButton.outline(
                  onPressed: () async {
                    final url = Uri.parse('http://localhost:3000');
                    await launchUrl(url);
                  },
                  child: const Text("Open"),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('index.html not found in selected folder'),
          ),
        );
      }
    }
  }
}
