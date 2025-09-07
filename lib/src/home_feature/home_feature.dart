import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/home_feature/tiles/history_tile.dart';
import 'package:reaprime/src/home_feature/tiles/profile_tile.dart';
import 'package:reaprime/src/home_feature/tiles/settings_tile.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/home_feature/tiles/status_tile.dart';

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
  });

  final DeviceController deviceController;
  final De1Controller de1controller;
  final ScaleController scaleController;
  final WorkflowController workflowController;
  final PersistenceController persistenceController;
  final SettingsController settingsController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final double _leftColumWidth = 400;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        //appBar: AppBar(
        //  title: Text('ReaPrime'),
        //),
        body: SafeArea(child: _home(context)));
  }

  Widget _home(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
          padding: EdgeInsets.only(top: 12, bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              SizedBox(
                width: 16,
              ),
              _leftColumn(context),
              SizedBox(
                width: 16,
              ),
              _rightColumn(context),
              SizedBox(
                width: 16,
              ),
            ],
          )),
    );
  }

  Widget _leftColumn(BuildContext context) {
    return Column(
      spacing: 12,
      children: [
        _historyCard(context),
        _quickSettingsCard(context),
      ],
    );
  }

  Widget _rightColumn(BuildContext context) {
    return Expanded(
      child: Column(
        spacing: 12,
        children: [
          SizedBox(
            width: double.infinity,
            child: ProfileTile(
              de1controller: widget.de1controller,
              workflowController: widget.workflowController,
              persistenceController: widget.persistenceController,
            ),
          ),
          _statusCard(context),
          _settingsCard(context),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    return SizedBox(
        width: double.infinity, child: ShadCard(child: _de1Status(context)));
  }

  Widget _settingsCard(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ShadCard(
        child: SettingsTile(
          controller: widget.de1controller,
        ),
      ),
    );
  }

  Widget _de1Status(BuildContext context) {
    return StreamBuilder(
      stream: widget.de1controller.de1,
      builder: (context, de1Available) {
        if (de1Available.hasData) {
          return SizedBox(
            child: StatusTile(
              de1: de1Available.data!,
              controller: widget.de1controller,
              scaleController: widget.scaleController,
              deviceController: widget.deviceController,
            ),
          );
        } else {
          return Text("Connecting to DE1");
        }
      },
    );
  }

  Widget _historyCard(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
        width: _leftColumWidth,
        title: Text(
          'Last shot',
          style: theme.textTheme.h4,
        ),
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
                  }),
            ],
          ),
        ));
  }

  Widget _quickSettingsCard(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
        width: _leftColumWidth,
        title: Text(
          'Quick Settings',
          style: theme.textTheme.h4,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Gateway mode"),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButton<GatewayMode>(
                    isDense: true,
                    menuWidth: 200,
                    value: widget.settingsController.gatewayMode,
                    onChanged: (v) {
                      if (v != null) {
                        widget.settingsController.updateGatewayMode(v);
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
                            'Tracking (Rea will stop shot if target weight is reached)'),
                      ),
                      DropdownMenuItem(
                        value: GatewayMode.disabled,
                        child: Text('Disabled (Rea has full control'),
                      ),
                    ]),
              ),
            ],
          ),
        ));
  }
}
