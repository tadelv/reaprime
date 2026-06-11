import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/device_discovery_feature/scan_flow_view.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

/// Full-screen scan page launched from the launcher's connect-hero. Reuses
/// the shared [ScanFlowView]; pops back to the launcher on connect or cancel.
class LauncherScanPage extends StatelessWidget {
  static const routeName = '/launcher-scan';

  const LauncherScanPage({
    super.key,
    required this.connectionManager,
    required this.deviceController,
    required this.settingsController,
    required this.scanStateGuardian,
  });

  final ConnectionManager connectionManager;
  final DeviceController deviceController;
  final SettingsController settingsController;
  final ScanStateGuardian scanStateGuardian;

  @override
  Widget build(BuildContext context) {
    return ScanFlowView(
      connectionManager: connectionManager,
      deviceController: deviceController,
      settingsController: settingsController,
      scanStateGuardian: scanStateGuardian,
      onConnected: () => Navigator.of(context).pop(),
      onExit: () {
        deviceController.stopScan();
        Navigator.of(context).pop();
      },
      exitLabel: 'Cancel',
    );
  }
}
