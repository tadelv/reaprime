import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/device_discovery_feature/scan_flow_view.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import '../onboarding_controller.dart';

/// Creates an [OnboardingStep] that scans for devices and connects.
///
/// Shows progress with coffee messages during scanning, a "taking too long"
/// button after 8 seconds, device pickers when ambiguity arises, and
/// auto-advances when connection is ready.
OnboardingStep createScanStep({
  required ConnectionManager connectionManager,
  required DeviceController deviceController,
  required SettingsController settingsController,
  required ScanStateGuardian scanStateGuardian,
  VoidCallback? onSkipToDashboard,
}) {
  return OnboardingStep(
    id: 'scan',
    shouldShow: () async => true,
    builder: (controller) => ScanStepView(
      onboardingController: controller,
      connectionManager: connectionManager,
      deviceController: deviceController,
      settingsController: settingsController,
      scanStateGuardian: scanStateGuardian,
      onSkipToDashboard: onSkipToDashboard,
    ),
  );
}

/// Visible for testing. Thin onboarding wrapper around [ScanFlowView].
@visibleForTesting
class ScanStepView extends StatelessWidget {
  final OnboardingController onboardingController;
  final ConnectionManager connectionManager;
  final DeviceController deviceController;
  final SettingsController settingsController;
  final ScanStateGuardian scanStateGuardian;
  final VoidCallback? onSkipToDashboard;

  /// Preserved for existing tests that pump this threshold.
  @visibleForTesting
  static const scanTooLongThreshold = ScanFlowView.scanTooLongThreshold;

  const ScanStepView({
    super.key,
    required this.onboardingController,
    required this.connectionManager,
    required this.deviceController,
    required this.settingsController,
    required this.scanStateGuardian,
    this.onSkipToDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return ScanFlowView(
      connectionManager: connectionManager,
      deviceController: deviceController,
      settingsController: settingsController,
      scanStateGuardian: scanStateGuardian,
      onConnected: onboardingController.advance,
      onExit: onSkipToDashboard ?? onboardingController.advance,
      exitLabel: 'Dashboard',
    );
  }
}
