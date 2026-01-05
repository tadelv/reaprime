import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/sample_feature/sample_item_list_view.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/plugins_settings_view.dart';
import 'package:reaprime/src/util/shot_exporter.dart';
import 'package:reaprime/src/util/shot_importer.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_controller.dart';

/// Displays the various settings that can be customized by the user.
///
/// When a user changes a setting, the SettingsController is updated and
/// Widgets that listen to the SettingsController are rebuilt.
class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.controller,
    required this.persistenceController,
    required this.webUIService,
  });

  static const routeName = '/settings';

  final SettingsController controller;
  final PersistenceController persistenceController;
  final WebUIService webUIService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        // Glue the SettingsController to the theme selection DropdownButton.
        //
        // When a user selects a theme from the dropdown list, the
        // SettingsController is updated, which rebuilds the MaterialApp.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            DropdownButton<ThemeMode>(
              // Read the selected themeMode from the controller
              value: controller.themeMode,
              // Call the updateThemeMode method any time the user selects a theme.
              onChanged: controller.updateThemeMode,
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
            Row(
              children: [
                DropdownButton<GatewayMode>(
                  value: controller.gatewayMode,
                  onChanged: (v) {
                    if (v != null) {
                      controller.updateGatewayMode(v);
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
                      child: Text('Disabled (Rea has full control'),
                    ),
                  ],
                ),
                SizedBox(width: 16),
                Text(
                  "Gateway mode (let REAPrime clients control the shot, scale and other parameters)",
                ),
              ],
            ),
            Row(
              spacing: 16,
              children: [
                ShadButton(
                  child: Text("Export logs"),
                  onPressed: () async {
                    var docs = await getApplicationDocumentsDirectory();
                    File logFile = File('${docs.path}/log.txt');
                    var bytes = await logFile.readAsBytes();
                    String? outputFile = await FilePicker.platform.saveFile(
                      fileName: "R1-logs.txt",
                      dialogTitle: "Choose where to save logs",
                      bytes: bytes,
                    );
                    if (outputFile != null) {
                      File destination = File(outputFile);
                      await destination.writeAsBytes(bytes);
                    }
                  },
                ),
                ShadButton(
                  child: Text("Export all shots"),
                  onPressed: () async {
                    final exporter = ShotExporter(
                      storage: persistenceController.storageService,
                    );
                    final jsonData = await exporter.exportJson();
                    final tempDir = await getTemporaryDirectory();
                    final source = File("${tempDir.path}/shots.json");
                    await source.writeAsString(jsonData);
                    final destination = await FilePicker.platform
                        .getDirectoryPath(dialogTitle: "Pick export dir");

                    final tempFile = File('$destination/R1_shots.zip');
                    try {
                      await ZipFile.createFromFiles(
                        sourceDir: tempDir,
                        files: [source],
                        zipFile: tempFile,
                      );
                    } catch (e, st) {
                      Logger("Settings").severe("failed to export:", e, st);
                    }
                  },
                ),
                ShadButton(
                  child: Text("Import shots"),
                  onPressed: () async {
                    Logger log = Logger("ShotImport");
                    // TODO: folder, bkp file
                    final importer = ShotImporter(
                      storage: persistenceController.storageService,
                    );

                    final sourceDirPath =
                        await FilePicker.platform.getDirectoryPath();

                    log.fine("importing from $sourceDirPath");
                    if (sourceDirPath == null) {
                      return;
                    }
                    final Directory sourceDir = Directory(sourceDirPath);
                    final files = await sourceDir.list().toList();
                    log.info("listing: ${files}");
                    for (final file in files) {
                      final f = File(file.path);
                      final content = await f.readAsString();
                      try {
                        log.fine("Importing: ${f.path}");
                        importer.importShotJson(content);
                      } catch (e, st) {
                        log.warning("shot import failed:", e, st);
                      }
                    }
                    persistenceController.loadShots();
                  },
                ),
                ShadButton(
                  child: Text("Debug view"),
                  onPressed: () {
                    Navigator.pushNamed(context, SampleItemListView.routeName);
                  },
                ),
              ],
            ),
            DropdownButton<String>(
              value: controller.logLevel,
              onChanged: controller.updateLogLevel,
              items: const [
                DropdownMenuItem(value: "FINE", child: Text('Fine')),
                DropdownMenuItem(value: "INFO", child: Text('Info')),
                DropdownMenuItem(value: "FINEST", child: Text('Finest')),
                DropdownMenuItem(value: "WARNING", child: Text('Warning')),
              ],
            ),
            Row(
              children: [
                ShadSwitch(
                  value: controller.simulatedDevices,
                  enabled: true,
                  onChanged: (v) async {
                    Logger("Settings").info("toggle sim to ${v}");
                    await controller.setSimulatedDevices(v);
                  },
                  label: Text("Show simulated devices"),
                  sublabel: Text(
                    "Whether simulated devices should be shown in scan results",
                  ),
                ),
              ],
            ),
            ShadButton.secondary(
              onPressed: () {
                _pickFolderAndLoadHtml(context);
              },
              child: Text("Load WebUI"),
            ),
            if (webUIService.isServing)
              ShadButton(
                child: Text("Open UI in browser"),
                onPressed: () async {
                  final url = Uri.parse('http://localhost:3000');
                  await launchUrl(url);
                },
              ),
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pushNamed(PluginsSettingsView.routeName);
              },
              child: Text("Plugins"),
            ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Commit: ${BuildInfo.commitShort}'),
                  Text('Branch: ${BuildInfo.branch}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFolderAndLoadHtml(BuildContext context) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final dir = Directory(selectedDirectory);
      Logger(
        "Settings",
      ).finest('list dir: ${dir.listSync(recursive: true).join("\n")}');
      final indexFile = File('$selectedDirectory/index.html');
      final itExists = await indexFile.exists();
      await webUIService.serveFolderAtPath(selectedDirectory);
      if (context.mounted == false) {
        return;
      }
      if (itExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Text('WebUI from $selectedDirectory loaded'),
                Spacer(),
                ShadButton.outline(
                  child: Text("Open"),
                  onPressed: () async {
                    final url = Uri.parse('http://localhost:3000');
                    await launchUrl(url);
                  },
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
