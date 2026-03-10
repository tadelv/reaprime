import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:reaprime/src/skin_feature/skin_view.dart';
import 'package:reaprime/src/settings/gateway_mode_info_dialog.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';

class QuickSettingsWidget extends StatefulWidget {
  final WebUIService webUIService;
  final SettingsController settingsController;
  final De1Controller de1controller;
  final WebUIStorage webUIStorage;

  const QuickSettingsWidget({
    super.key,
    required this.de1controller,
    required this.settingsController,
    required this.webUIService,
    required this.webUIStorage,
  });
  @override
  State<StatefulWidget> createState() {
    return _QuickSettingsState();
  }
}

class _QuickSettingsState extends State<QuickSettingsWidget> {
  bool _isServingUI = false;
  String? _errorMessage;

  static const String _selectedSkinPrefKey = 'selected_webui_skin_id';

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text('Quick Glance', style: theme.textTheme.h4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8.0,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text("IP Address:")),
                Flexible(child: Text(widget.webUIService.deviceIp() + ":3000")),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text("Gateway mode")),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  iconSize: 20,
                  onPressed: () => showGatewayModeInfoDialog(context),
                  tooltip: 'Learn more about Gateway mode',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            DropdownButton<GatewayMode>(
              isDense: true,
              isExpanded: true,
              value: widget.settingsController.gatewayMode,
              onChanged: (v) {
                if (v != null) {
                  widget.settingsController.updateGatewayMode(v);
                }
              },
              items: const [
                DropdownMenuItem(value: GatewayMode.full, child: Text('Full')),
                DropdownMenuItem(
                  value: GatewayMode.tracking,
                  child: Text('Tracking'),
                ),
                DropdownMenuItem(
                  value: GatewayMode.disabled,
                  child: Text('Disabled'),
                ),
              ],
            ),
            _buildWebUIControl(context),
          ],
        ),
      ),
    );
  }

  Widget _buildWebUIControl(BuildContext context) {
    return StreamBuilder<De1Interface?>(
      stream: widget.de1controller.de1,
      builder: (context, de1State) {
        // Hide control if no DE1 is connected
        if (!de1State.hasData || de1State.data == null) {
          return SizedBox.shrink();
        }

        // Show error message if there was an error
        if (_errorMessage != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                "WebUI Error:",
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              ShadButton.secondary(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                },
                child: Text("Dismiss"),
              ),
            ],
          );
        }

        // Show loading state while serving
        if (_isServingUI) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text("WebUI:")),
              Flexible(
                child: Row(
                  spacing: 8,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    Text("Starting..."),
                  ],
                ),
              ),
            ],
          );
        }

        // Show status when serving, or start button when not serving
        if (widget.webUIService.isServing) {
          final skinName = widget.webUIService.serverPath().split('/').last;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text("WebUI loaded:")),
              Flexible(
                child: ShadButton(
                  child: Text(
                    "Go to $skinName",
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    // On supported platforms (iOS, Android, macOS), use in-app WebView
                    if (Platform.isIOS ||
                        Platform.isAndroid ||
                        Platform.isMacOS) {
                      Navigator.of(context).pushNamed(SkinView.routeName);
                    } else {
                      // On other platforms, open in external browser
                      final url = Uri.parse('http://localhost:3000');
                      await launchUrl(url);
                    }
                  },
                ),
              ),
            ],
          );
        } else {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text("WebUI:")),
              Flexible(
                child: ShadButton(
                  onPressed: _startWebUI,
                  child: Text("Start WebUI"),
                ),
              ),
            ],
          );
        }
      },
    );
  }

  Future<void> _startWebUI() async {
    setState(() {
      _isServingUI = true;
      _errorMessage = null;
    });

    try {
      // Load previously selected skin preference
      final prefs = await SharedPreferences.getInstance();
      final savedSkinId = prefs.getString(_selectedSkinPrefKey);

      // Get available skins
      final skins = widget.webUIStorage.installedSkins;

      if (skins.isEmpty) {
        throw Exception('No WebUI skins available. Please install a skin.');
      }

      // Try to use saved preference, otherwise use default skin
      WebUISkin? skinToUse;
      if (savedSkinId != null) {
        skinToUse = widget.webUIStorage.getSkin(savedSkinId);
      }
      skinToUse ??= widget.webUIStorage.defaultSkin;

      if (skinToUse == null) {
        throw Exception('No default WebUI skin found.');
      }

      // Serve the selected skin
      await widget.webUIService.serveFolderAtPath(skinToUse.path, port: 3000);

      // Save preference
      await prefs.setString(_selectedSkinPrefKey, skinToUse.id);

      if (mounted) {
        setState(() {
          _isServingUI = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isServingUI = false;
        });
      }
    }
  }
}
