import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/home_feature/tiles/history_tile.dart';
import 'package:reaprime/src/home_feature/tiles/profile_tile.dart';
import 'package:reaprime/src/home_feature/tiles/settings_tile.dart';
import 'package:reaprime/src/home_feature/tiles/status_tile.dart';
import 'package:reaprime/src/home_feature/widgets/quick_settings_widget.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    this.beanStorage,
    this.grinderStorage,
    required this.connectionManager,
  });

  final DeviceController deviceController;
  final De1Controller de1controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;
  final SettingsController settingsController;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;
  final BeanStorageService? beanStorage;
  final GrinderStorageService? grinderStorage;
  final ConnectionManager connectionManager;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
      body: SafeArea(
        child: Semantics(
          explicitChildNodes: true,
          label: 'Espresso machine dashboard',
          child: _home(context),
        ),
      ),
    );
  }

  Widget _home(BuildContext context) {
    // Use LayoutBuilder to adapt to screen size
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;
        final isDesktop =
            Platform.isMacOS || Platform.isLinux || Platform.isWindows;

        if (isWideScreen) {
          // Desktop/tablet layout: two columns side by side
          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: isDesktop,
            child: SingleChildScrollView(
              controller: _scrollController,
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
            ),
          );
        } else {
          // Mobile/narrow layout: single column, stacked vertically
          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: isDesktop,
            child: SingleChildScrollView(
              controller: _scrollController,
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
        beanStorage: widget.beanStorage,
        grinderStorage: widget.grinderStorage,
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
          connectionManager: widget.connectionManager,
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
              connectionManager: widget.connectionManager,
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
            HistoryTile(
              persistenceController: widget.persistenceController,
              workflowController: widget.workflowController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickSettingsCard(BuildContext context) {
    return QuickSettingsWidget(
      de1controller: widget.de1controller,
      settingsController: widget.settingsController,
      webUIService: widget.webUIService,
      webUIStorage: widget.webUIStorage,
    );
  }
}
