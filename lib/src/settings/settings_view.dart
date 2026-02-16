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
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:reaprime/src/settings/update_dialog.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/services/update_check_service.dart';
import 'package:reaprime/src/util/shot_exporter.dart';
import 'package:reaprime/src/feedback_feature/feedback_view.dart';
import 'package:reaprime/src/util/shot_importer.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_controller.dart';

/// Displays the various settings that can be customized by the user.
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.controller,
    required this.persistenceController,
    required this.webUIService,
    required this.webUIStorage,
    this.updateCheckService,
  });

  static const routeName = '/settings';

  final SettingsController controller;
  final PersistenceController persistenceController;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;
  final UpdateCheckService? updateCheckService;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String? _selectedSkinId;
  static const String _customSkinId = '__custom__';
  final Logger _log = Logger("Settings");

  @override
  void initState() {
    super.initState();
    _selectedSkinId = widget.webUIStorage.defaultSkin?.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            _buildAppearanceSection(),
            _buildGatewaySection(),
            _buildDeviceManagementSection(),
            _buildDataManagementSection(),
            _buildWebUISection(),
            _buildAdvancedSection(),
            _buildAboutSection(),
          ],
        ),
      ),
    );
  }

  // MARK: - Section Builders

  Widget _buildAppearanceSection() {
    return _SettingsSection(
      title: 'Appearance',
      icon: Icons.palette_outlined,
      description: 'Customize the visual appearance of the app',
      children: [
        _SettingRow(
          label: 'Theme',
          child: DropdownButton<ThemeMode>(
            isExpanded: true,
            value: widget.controller.themeMode,
            onChanged: widget.controller.updateThemeMode,
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('System Theme')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light Theme')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark Theme')),
            ],
          ),
        ),
        if (Platform.isMacOS || Platform.isLinux || Platform.isWindows)
          _SettingRow(
            label: 'Skin Exit Button',
            child: DropdownButton<SkinExitButtonPosition>(
              isExpanded: true,
              value: widget.controller.skinExitButtonPosition,
              onChanged: (position) {
                if (position != null) {
                  widget.controller.setSkinExitButtonPosition(position);
                }
              },
              items: const [
                DropdownMenuItem(value: SkinExitButtonPosition.topLeft, child: Text('Top Left')),
                DropdownMenuItem(value: SkinExitButtonPosition.topRight, child: Text('Top Right')),
                DropdownMenuItem(value: SkinExitButtonPosition.bottomLeft, child: Text('Bottom Left')),
                DropdownMenuItem(value: SkinExitButtonPosition.bottomRight, child: Text('Bottom Right')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildGatewaySection() {
    return _SettingsSection(
      title: 'Gateway & Control',
      icon: Icons.settings_remote_outlined,
      description: 'Configure how external clients can control the machine',
      onInfoPressed: () => showGatewayModeInfoDialog(context),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gateway Mode',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            DropdownButton<GatewayMode>(
              isExpanded: true,
              value: widget.controller.gatewayMode,
              onChanged: (v) {
                if (v != null) widget.controller.updateGatewayMode(v);
              },
              items: const [
                DropdownMenuItem(
                  value: GatewayMode.full,
                  child: Text('Full (Rea has no control)'),
                ),
                DropdownMenuItem(
                  value: GatewayMode.tracking,
                  child: Text('Tracking (Rea will stop shot if target weight is reached)'),
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
    );
  }

  Widget _buildDeviceManagementSection() {
    return _SettingsSection(
      title: 'Device Management',
      icon: Icons.devices_outlined,
      description: 'Configure device connections and simulation options',
      children: [
        // Auto-Connect Device
        Row(
          children: [
            Expanded(
              child: Text(
                'Auto-Connect Device',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => _showPreferredDeviceInfo(context),
              tooltip: 'Learn more',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.controller.preferredMachineId != null) ...[
          Text(
            'Device ID: ${widget.controller.preferredMachineId}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ShadButton.destructive(
            onPressed: () async {
              await widget.controller.setPreferredMachineId(null);
            },
            child: const Text('Clear Auto-Connect Device'),
          ),
        ] else ...[
          Text(
            'No auto-connect device set',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'To set an auto-connect device, check the "Auto-connect to this machine" checkbox when selecting a device during startup.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const Divider(height: 32),
        // Simulated Devices
        ShadSwitch(
          value: widget.controller.simulatedDevices,
          onChanged: (v) async {
            _log.info("toggle sim to $v");
            await widget.controller.setSimulatedDevices(v);
          },
          label: const Text("Show simulated devices"),
          sublabel: const Text(
            "Whether simulated devices should be shown in scan results",
          ),
        ),
      ],
    );
  }

  Widget _buildDataManagementSection() {
    return _SettingsSection(
      title: 'Data Management',
      icon: Icons.storage_outlined,
      description: 'Import, export, and manage your shot data and logs',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ShadButton.outline(
              onPressed: _exportLogs,
              child: const Text("Export logs"),
            ),
            ShadButton.outline(
              onPressed: _exportShots,
              child: const Text("Export all shots"),
            ),
            ShadButton.outline(
              onPressed: () => _showImportDialog(context),
              child: const Text("Import shots"),
            ),
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
      ],
    );
  }

  Widget _buildWebUISection() {
    return _SettingsSection(
      title: 'Web Interface',
      icon: Icons.web_outlined,
      description: 'Select and manage web-based user interface skins',
      children: [
        _SettingRow(
          label: 'Skin',
          child: _buildSkinSelector(),
        ),
        const Divider(height: 24),
        if (!widget.webUIService.isServing)
          ShadButton(
            onPressed: _startSelectedSkin,
            child: const Text("Start WebUI Server"),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ShadButton(
                onPressed: () async {
                  await launchUrl(Uri.parse('http://localhost:3000'));
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
          ),
        const Divider(height: 24),
        ShadButton.outline(
          onPressed: () => _checkForSkinUpdates(context),
          child: const Text("Check for Skin Updates"),
        ),
      ],
    );
  }

  Widget _buildAdvancedSection() {
    return _SettingsSection(
      title: 'Advanced',
      icon: Icons.tune_outlined,
      description: 'Developer tools and advanced configuration',
      children: [
        ShadSwitch(
          value: widget.controller.telemetryConsent,
          onChanged: (v) async {
            await widget.controller.setTelemetryConsent(v);
            setState(() {});
          },
          label: const Text("Anonymous crash reporting"),
          sublabel: const Text(
            "Share anonymized crash reports and diagnostics to help fix connectivity issues",
          ),
        ),
        const Divider(height: 24),
        _SettingRow(
          label: 'Log Level',
          child: DropdownButton<String>(
            isExpanded: true,
            value: widget.controller.logLevel,
            onChanged: widget.controller.updateLogLevel,
            items: const [
              DropdownMenuItem(value: "FINE", child: Text('Fine')),
              DropdownMenuItem(value: "INFO", child: Text('Info')),
              DropdownMenuItem(value: "FINEST", child: Text('Finest')),
              DropdownMenuItem(value: "WARNING", child: Text('Warning')),
            ],
          ),
        ),
        const Divider(height: 24),
        ShadSwitch(
          value: widget.controller.automaticUpdateCheck,
          onChanged: (v) async {
            await widget.controller.setAutomaticUpdateCheck(v);
            if (v) {
              await widget.updateCheckService?.enableAutomaticChecks();
            } else {
              await widget.updateCheckService?.disableAutomaticChecks();
            }
          },
          label: const Text("Automatic update checks"),
          sublabel: const Text(
            "Check for updates every 12 hours",
          ),
        ),
        const SizedBox(height: 16),
        if (widget.updateCheckService?.hasAvailableUpdate == true) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.system_update,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Update available: ${widget.updateCheckService?.availableUpdate?.version}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pushNamed(PluginsSettingsView.routeName),
              child: const Text("Plugins"),
            ),
            ShadButton.outline(
              onPressed: () => Navigator.pushNamed(context, SampleItemListView.routeName),
              child: const Text("Debug view"),
            ),
            ShadButton.outline(
              onPressed: () => _checkForUpdates(context),
              child: const Text("Check for updates"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return _SettingsSection(
      title: 'About',
      icon: Icons.info_outline,
      description: 'Version and build information',
      children: [
        _InfoRow('Version', BuildInfo.version),
        _InfoRow('Commit', BuildInfo.commitShort),
        _InfoRow('Branch', BuildInfo.branch),
        const Divider(height: 24),
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
        const SizedBox(height: 12),
        ShadButton.outline(
          onPressed: () async {
            await launchUrl(Uri.parse('https://www.gnu.org/licenses/gpl-3.0.html'));
          },
          child: const Text('View GPL v3 License'),
        ),
      ],
    );
  }

  // MARK: - Helper Widgets

  Widget _buildSkinSelector() {
    final installedSkins = widget.webUIStorage.installedSkins;

    return DropdownButton<String>(
      isExpanded: true,
      value: _selectedSkinId,
      onChanged: (value) async {
        if (value == null) return;

        setState(() => _selectedSkinId = value);

        if (value == _customSkinId) {
          await _pickCustomSkinFolder(context);
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
                Icon(
                  skin.isBundled ? Icons.verified : Icons.folder,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(skin.name, overflow: TextOverflow.ellipsis),
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

  // MARK: - Data Management Actions

  Future<void> _exportLogs() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final logFile = File('${docs.path}/log.txt');
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
        final archiveFile = ArchiveFile('shots.json', sourceBytes.length, sourceBytes);
        archive.addFile(archiveFile);

        final zipData = ZipEncoder().encode(archive);
        await tempFile.writeAsBytes(zipData!);

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
      await _pickCustomSkinFolder(context);
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

  Future<void> _pickCustomSkinFolder(BuildContext context) async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath();

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
                    child: Text('Custom WebUI from $selectedDirectory loaded'),
                  ),
                  ShadButton.outline(
                    onPressed: () async {
                      await launchUrl(Uri.parse('http://localhost:3000'));
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

  // MARK: - Update Actions

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

  Future<void> _checkForUpdates(BuildContext context) async {
    try {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking for updates...')),
      );

      // Check for app updates
      final updateInfo = await widget.updateCheckService?.checkForUpdate();

      if (!context.mounted) return;

      if (updateInfo != null) {
        if (Platform.isAndroid) {
          // On Android, show download/install dialog
          final updater = AndroidUpdater(owner: 'tadelv', repo: 'reaprime');
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
          // On other platforms, show dialog and open browser
          final releaseUrl = widget.updateCheckService?.getReleaseUrl();
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Update Available'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version ${updateInfo.version} is available'),
                  const SizedBox(height: 8),
                  Text('Current version: ${BuildInfo.version}'),
                  if (updateInfo.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Release Notes:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Text(updateInfo.releaseNotes),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    if (releaseUrl != null) {
                      await launchUrl(Uri.parse(releaseUrl));
                    }
                  },
                  child: const Text('Download'),
                ),
              ],
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version')),
        );
      }

      // Also update WebUI skins
      await widget.webUIStorage.downloadRemoteSkins();
    } catch (e, stackTrace) {
      _log.severe('Error checking for updates', e, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check for updates: $e')),
      );
    }
  }

  // MARK: - Import Actions

  Future<void> _showImportDialog(BuildContext context) async {
    final result = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Import Shots'),
        description: const Text('Choose how you want to import your shots'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadButton(
              onPressed: () => Navigator.of(context).pop('file'),
              child: const Text('Import from JSON file'),
            ),
            ShadButton.secondary(
              onPressed: () => Navigator.of(context).pop('folder'),
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

  Future<void> _importFromFile(BuildContext context) async {
    final importer = ShotImporter(
      storage: widget.persistenceController.storageService,
    );

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: "Select shots JSON file",
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) {
      _log.warning("File path is null");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to access file')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    _showProgressDialog(context, 'Importing shots');

    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final decoded = jsonDecode(content);

      int count = 0;
      if (decoded is List) {
        count = await importer.importShotsJson(content);
      } else {
        await importer.importShotJson(content);
        count = 1;
      }

      widget.persistenceController.loadShots();

      if (context.mounted) Navigator.of(context).pop();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $count shot${count == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      _log.severe("Shot import failed", e, st);
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importFromFolder(BuildContext context) async {
    final importer = ShotImporter(
      storage: widget.persistenceController.storageService,
    );

    final sourceDirPath = await FilePicker.platform.getDirectoryPath();
    if (sourceDirPath == null) return;

    if (!context.mounted) return;
    _showProgressDialog(context, 'Importing shots from folder');

    try {
      final sourceDir = Directory(sourceDirPath);
      final files = await sourceDir.list().toList();

      int successCount = 0;
      int failCount = 0;

      for (final file in files) {
        if (file is! File) continue;
        final f = File(file.path);
        if (!f.path.endsWith('.json')) continue;

        try {
          final content = await f.readAsString();
          await importer.importShotJson(content);
          successCount++;
        } catch (e, st) {
          _log.warning("Shot import failed", e, st);
          failCount++;
        }
      }

      widget.persistenceController.loadShots();

      if (context.mounted) Navigator.of(context).pop();

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
      _log.severe("Folder import failed", e, st);
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // MARK: - Info Dialogs

  void _showPreferredDeviceInfo(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Auto-Connect Device'),
        description: const Text('Automatically connect to your preferred machine on startup'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(
              'When you set an auto-connect device, ReaPrime will:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            _InfoPoint(
              icon: Icons.bluetooth_searching,
              text: 'Scan for devices on startup',
            ),
            _InfoPoint(
              icon: Icons.link,
              text: 'Automatically connect to your preferred machine when found',
            ),
            _InfoPoint(
              icon: Icons.speed,
              text: 'Skip the device selection screen for faster startup',
            ),
            const Divider(height: 20),
            Text(
              'How to set:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            Text(
              'During device selection at startup, check the "Auto-connect to this machine" checkbox next to your preferred device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'How to change:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            Text(
              'Clear the current auto-connect device using the button above, then restart the app and select a different device with the checkbox.',
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
}

// MARK: - Helper Widgets

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? description;
  final VoidCallback? onInfoPressed;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    this.description,
    this.onInfoPressed,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              if (onInfoPressed != null)
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 18),
                  onPressed: onInfoPressed,
                  tooltip: 'Learn more',
                ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
            ),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingRow({
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall,
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
      ),
    );
  }
}

class _InfoPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPoint({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}



