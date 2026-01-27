import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/home_feature/tiles/history_tile.dart';
import 'package:reaprime/src/home_feature/tiles/profile_tile.dart';
import 'package:reaprime/src/home_feature/tiles/settings_tile.dart';
import 'package:reaprime/src/home_feature/tiles/status_tile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  static const routeName = '/home';
  const HomeScreen({
    super.key,
    required this.deviceController,
    required this.de1controller,
    required this.scaleController,
    required this.workflowController,
    required this.persistenceController,
    required this.settingsController,
    required this.webUIService,
    required this.webUIStorage,
  });

  final DeviceController deviceController;
  final De1Controller de1controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;
  final SettingsController settingsController;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isServingUI = false;
  String? _errorMessage;

  static const String _selectedSkinPrefKey = 'selected_webui_skin_id';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes from background, trigger a rebuild to reconnect StreamBuilders
    if (state == AppLifecycleState.resumed) {
      setState(() {
        // This will cause the entire widget tree to rebuild,
        // reconnecting all StreamBuilders to their streams
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //appBar: AppBar(
      //  title: Text('ReaPrime'),
      //),
      body: SafeArea(child: _home(context)),
    );
  }

  Widget _home(BuildContext context) {
    // Use LayoutBuilder to adapt to screen size
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          // Desktop/tablet layout: two columns side by side
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(top: 12, bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  SizedBox(width: 16),
                  Flexible(flex: 2, child: _leftColumn(context)),
                  SizedBox(width: 16),
                  Flexible(flex: 3, child: _rightColumn(context)),
                  SizedBox(width: 16),
                ],
              ),
            ),
          );
        } else {
          // Mobile/narrow layout: single column, stacked vertically
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  ..._rightColumnWidgets(context),
                  ..._leftColumnWidgets(context),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  // Helper methods to get widgets as lists for mobile layout
  List<Widget> _leftColumnWidgets(BuildContext context) {
    return [_historyCard(context), _quickSettingsCard(context)];
  }

  List<Widget> _rightColumnWidgets(BuildContext context) {
    return [
      ProfileTile(
        de1controller: widget.de1controller,
        workflowController: widget.workflowController,
        persistenceController: widget.persistenceController,
      ),
      _statusCard(context),
      _settingsCard(context),
    ];
  }

  Widget _leftColumn(BuildContext context) {
    return Column(spacing: 12, children: _leftColumnWidgets(context));
  }

  Widget _rightColumn(BuildContext context) {
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _rightColumnWidgets(context),
    );
  }

  Widget _statusCard(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ShadCard(child: _de1Status(context)),
    );
  }

  Widget _settingsCard(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ShadCard(
        child: SettingsTile(
          controller: widget.de1controller,
          deviceController: widget.deviceController,
        ),
      ),
    );
  }

  Widget _de1Status(BuildContext context) {
    return StreamBuilder<De1Interface?>(
      stream: widget.de1controller.de1,
      builder: (context, de1Available) {
        // Check both that we have data AND that the data is not null
        if (de1Available.hasData && de1Available.data != null) {
          return SizedBox(
            child: StatusTile(
              de1: de1Available.data!,
              controller: widget.de1controller,
              scaleController: widget.scaleController,
              deviceController: widget.deviceController,
              workflowController: widget.workflowController,
            ),
          );
        } else {
          return Text("Connecting to Machine");
        }
      },
    );
  }

  Widget _historyCard(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text('Last shot', style: theme.textTheme.h4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StreamBuilder(
              stream: widget.persistenceController.shots,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (snapshot.hasData) {
                  return Center(
                    child: HistoryTile(
                      persistenceController: widget.persistenceController,
                      workflowController: widget.workflowController,
                    ),
                  );
                }
                return Center(child: Text('No data found.'));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickSettingsCard(BuildContext context) {
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
                Flexible(child: Text(widget.webUIService.deviceIp())),
              ],
            ),
            Text("Gateway mode"),
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
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text("WebUI loaded:")),
              Flexible(
                child: ShadButton(
                  child: Text(
                    widget.webUIService.serverPath().split('/').last,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    final url = Uri.parse('http://localhost:3000');
                    await launchUrl(url);
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
