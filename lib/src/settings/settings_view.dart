import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/sample_feature/sample_item_list_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'settings_controller.dart';

/// Displays the various settings that can be customized by the user.
///
/// When a user changes a setting, the SettingsController is updated and
/// Widgets that listen to the SettingsController are rebuilt.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.controller});

  static const routeName = '/settings';

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
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
                ShadSwitch(
                  value: controller.bypassShotController,
                  onChanged: controller.updateBypassShotController,
                ),
                SizedBox(width: 16,),
                Text(
                    "Bypass shot controller (let REAPrime clients stop the shot)"),
              ],
            ),
            Row(
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
                    var docs = await getDownloadsDirectory();
                    final shotsDir = Directory('${docs!.path}/shots');
                    if (!await shotsDir.exists()) {
                      throw "Shots dir ${shotsDir.path} does not exist";
                    }
                    final destination = await FilePicker.platform
                        .getDirectoryPath(dialogTitle: "Pick export dir");

                    final tempFile = File('$destination/R1_shots.zip');
                    try {
                      await ZipFile.createFromDirectory(
                          sourceDir: shotsDir,
                          zipFile: tempFile,
                          includeBaseDirectory: true,
                          recurseSubDirs: true);
                    } catch (e, st) {
                      Logger("Settings").severe("failed to export:", e, st);
                    }
                  },
                ),
                ShadButton(
                  child: Text("Debug view"),
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      SampleItemListView.routeName,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
