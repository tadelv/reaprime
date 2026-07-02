import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/device/sensor.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

/// Native workflow steam settings including stop-at-probe temperature
/// and preferred probe selection (FR-U1, FR-U2).
class SteamWorkflowSettingsPage extends StatefulWidget {
  const SteamWorkflowSettingsPage({
    super.key,
    required this.workflowController,
    required this.de1Controller,
    required this.sensorController,
    required this.settingsController,
  });

  static const routeName = '/settings/steam-workflow';

  final WorkflowController workflowController;
  final De1Controller de1Controller;
  final SensorController sensorController;
  final SettingsController settingsController;

  @override
  State<SteamWorkflowSettingsPage> createState() =>
      _SteamWorkflowSettingsPageState();
}

class _SteamWorkflowSettingsPageState extends State<SteamWorkflowSettingsPage> {
  SteamFormSettings? _initialSettings;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final machineSettings = await widget.de1Controller.steamSettings();
      final workflowSteam =
          widget.workflowController.currentWorkflow.steamSettings;
      final preferredProbeId =
          widget.settingsController.preferredSteamProbeId;

      if (!mounted) {
        return;
      }
      setState(() {
        _initialSettings = SteamFormSettings.fromSteamSettings(
          workflowSteam.copyWith(
            targetTemperature: machineSettings.targetTemp,
            duration: machineSettings.targetDuration,
            flow: machineSettings.targetFlow,
          ),
          steamEnabled: machineSettings.steamEnabled,
          preferredProbeId: preferredProbeId,
        );
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = e;
      });
    }
  }

  List<SteamProbeOption> _probeOptions() {
    return widget.sensorController.sensors.values
        .map(
          (Sensor sensor) => SteamProbeOption(
            deviceId: sensor.deviceId,
            label: sensor.info.name.isNotEmpty ? sensor.info.name : sensor.name,
          ),
        )
        .toList();
  }

  Future<void> _apply(SteamFormSettings settings) async {
    final updatedSteam = settings.toSteamSettings();
    widget.workflowController.updateWorkflow(steamSettings: updatedSteam);
    await widget.settingsController
        .setPreferredSteamProbeId(settings.preferredProbeId);
    await widget.de1Controller.updateSteamSettings(settings);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Steam settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Steam workflow')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Connect a machine to edit steam settings.\n$_loadError',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final initial = _initialSettings;
    if (initial == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SteamForm(
        steamSettings: initial,
        probeOptions: _probeOptions(),
        apply: _apply,
      ),
    );
  }
}
