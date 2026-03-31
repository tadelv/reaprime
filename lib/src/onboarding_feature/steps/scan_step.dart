import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/device_discovery_feature/device_discovery_view.dart';
import 'package:reaprime/src/home_feature/widgets/device_selection_widget.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/scale.dart' as device_scale;
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../onboarding_controller.dart';
import '../widgets/scan_results_summary.dart';
import '../widgets/troubleshooting_wizard.dart';

final _log = Logger('ScanStep');

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

/// Visible for testing. The scan step widget that drives the scan UI.
@visibleForTesting
class ScanStepView extends StatefulWidget {
  final OnboardingController onboardingController;
  final ConnectionManager connectionManager;
  final DeviceController deviceController;
  final SettingsController settingsController;
  final ScanStateGuardian scanStateGuardian;

  /// Called when user explicitly skips scan to go to dashboard.
  /// If null, falls back to [onboardingController.advance].
  final VoidCallback? onSkipToDashboard;

  /// How long to wait before showing the "taking too long" button.
  @visibleForTesting
  static const scanTooLongThreshold = Duration(seconds: 8);

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
  State<ScanStepView> createState() => ScanStepViewState();
}

class ScanStepViewState extends State<ScanStepView> {
  void _skipToDashboard() {
    if (widget.onSkipToDashboard != null) {
      widget.onSkipToDashboard!();
    } else {
      widget.onboardingController.advance();
    }
  }

  late StreamSubscription<ConnectionStatus> _statusSubscription;
  late StreamSubscription<ScanStateEvent> _guardianSubscription;
  late StreamSubscription<List<dev.Device>> _deviceSubscription;
  ConnectionStatus _status =
      const ConnectionStatus(phase: ConnectionPhase.scanning);
  bool _hasNavigated = false;
  bool _showTakingTooLong = false;
  Timer? _tooLongTimer;

  /// Devices discovered so far during the current scan.
  List<De1Interface> _discoveredMachines = [];
  List<device_scale.Scale> _discoveredScales = [];

  /// Bluetooth adapter error message, set by ScanStateGuardian events.
  String? _adapterError;

  @override
  void initState() {
    super.initState();

    _statusSubscription = widget.connectionManager.status.listen((status) {
      if (!mounted) return;

      if (status.phase == ConnectionPhase.ready && !_hasNavigated) {
        _hasNavigated = true;
        _cancelTooLongTimer();
        widget.onboardingController.advance();
        return;
      }

      // Reset the "taking too long" timer when phase changes away from scanning
      if (status.phase != ConnectionPhase.scanning) {
        _cancelTooLongTimer();
      }

      // Start the timer when entering scanning phase
      if (status.phase == ConnectionPhase.scanning &&
          _status.phase != ConnectionPhase.scanning) {
        _discoveredMachines = [];
        _discoveredScales = [];
        _startTooLongTimer();
      }

      setState(() {
        _status = status;
        // Clear adapter error when scanning resumes
        if (status.phase == ConnectionPhase.scanning) {
          _adapterError = null;
        }
      });
    });

    // Monitor device stream during scanning for live device count
    _deviceSubscription =
        widget.deviceController.deviceStream.listen((devices) {
      if (!mounted || _status.phase != ConnectionPhase.scanning) return;
      setState(() {
        _discoveredMachines = devices.whereType<De1Interface>().toList();
        _discoveredScales =
            devices.whereType<device_scale.Scale>().toList();
      });
    });

    _guardianSubscription =
        widget.scanStateGuardian.events.listen(_onGuardianEvent);

    // Kick off the connection flow
    widget.connectionManager.connect();
    _startTooLongTimer();
  }

  void _startTooLongTimer() {
    _cancelTooLongTimer();
    _showTakingTooLong = false;
    _tooLongTimer = Timer(ScanStepView.scanTooLongThreshold, () {
      if (mounted && _status.phase == ConnectionPhase.scanning) {
        setState(() {
          _showTakingTooLong = true;
        });
      }
    });
  }

  void _cancelTooLongTimer() {
    _tooLongTimer?.cancel();
    _tooLongTimer = null;
    if (_showTakingTooLong) {
      _showTakingTooLong = false;
    }
  }

  void _onGuardianEvent(ScanStateEvent event) {
    if (!mounted) return;
    switch (event) {
      case ScanStateEvent.adapterTurnedOff:
        setState(() {
          _adapterError = 'Bluetooth was turned off';
        });
        break;
      case ScanStateEvent.adapterTurnedOn:
        setState(() {
          _adapterError = null;
        });
        break;
      case ScanStateEvent.scanStateStale:
        // If we're stuck in scanning phase, the scan may have silently finished
        if (_status.phase == ConnectionPhase.scanning) {
          _log.info('Stale scan detected, restarting');
          widget.connectionManager.connect();
        }
        break;
    }
  }

  @override
  void dispose() {
    _cancelTooLongTimer();
    _statusSubscription.cancel();
    _guardianSubscription.cancel();
    _deviceSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Adapter error takes precedence
    if (_adapterError != null) {
      return _adapterErrorView(context);
    }

    // Error state from connection manager
    if (_status.error != null && _status.phase == ConnectionPhase.idle) {
      return _errorView(context);
    }

    // Scanning
    if (_status.phase == ConnectionPhase.scanning) {
      return _scanningView(context);
    }

    // Connecting to machine or scale
    if (_status.phase == ConnectionPhase.connectingMachine ||
        _status.phase == ConnectionPhase.connectingScale) {
      return _connectingView(context);
    }

    // Ambiguity: machine or scale picker
    if (_status.pendingAmbiguity == AmbiguityReason.machinePicker ||
        _status.pendingAmbiguity == AmbiguityReason.scalePicker) {
      return _devicePickerView(context);
    }

    // Idle with no machines found
    if (_status.phase == ConnectionPhase.idle &&
        _status.foundMachines.isEmpty) {
      return _noDevicesFoundView(context);
    }

    // Idle with machines but no ambiguity (fallback)
    if (_status.phase == ConnectionPhase.idle &&
        _status.foundMachines.isNotEmpty) {
      return _devicePickerView(context);
    }

    // Default: scanning view
    return _scanningView(context);
  }

  /// Whether devices have been found but the preferred one hasn't.
  bool get _hasDevicesButNotPreferred {
    if (_discoveredMachines.isEmpty && _discoveredScales.isEmpty) return false;
    final preferredMachineId = widget.settingsController.preferredMachineId;
    if (preferredMachineId == null) return false;
    return !_discoveredMachines.any((m) => m.deviceId == preferredMachineId);
  }

  int get _totalDiscovered => _discoveredMachines.length + _discoveredScales.length;

  Widget _scanningView(BuildContext context) {
    final hasDevicesNotPreferred = _hasDevicesButNotPreferred;
    final deviceCount = _totalDiscovered;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 200, child: ShadProgress()),
          const SizedBox(height: 16),
          if (hasDevicesNotPreferred && _showTakingTooLong) ...[
            Text(
              '$deviceCount device${deviceCount == 1 ? '' : 's'} found, but not your preferred one.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Still scanning...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            Text(
              DeviceDiscoveryView.getRandomCoffeeMessage(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 24),
          AnimatedOpacity(
            opacity: _showTakingTooLong ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: IgnorePointer(
              ignoring: !_showTakingTooLong,
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _showTakingTooLongSheet,
                child: Text(hasDevicesNotPreferred
                    ? 'View found devices'
                    : 'This is taking a while...'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectingView(BuildContext context) {
    final label = _status.phase == ConnectionPhase.connectingMachine
        ? 'Connecting to your machine...'
        : 'Connecting to your scale...';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          SizedBox(width: 200, child: ShadProgress()),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _devicePickerView(BuildContext context) {
    final isConnecting = _status.phase == ConnectionPhase.connectingMachine ||
        _status.phase == ConnectionPhase.connectingScale;
    final connectingDeviceId = isConnecting
        ? (_status.foundMachines.isNotEmpty
            ? _status.foundMachines.first.deviceId
            : null)
        : null;

    // Check if preferred device is configured but not among found devices
    final preferredMachineId =
        widget.settingsController.preferredMachineId;
    final preferredMachineNotFound = preferredMachineId != null &&
        _status.foundMachines.isNotEmpty &&
        !_status.foundMachines
            .any((m) => m.deviceId == preferredMachineId);

    final preferredScaleId = widget.settingsController.preferredScaleId;
    final preferredScaleNotFound = preferredScaleId != null &&
        _status.foundScales.isNotEmpty &&
        !_status.foundScales
            .any((s) => s.deviceId == preferredScaleId);

    final machineHeader = preferredMachineNotFound
        ? "Your preferred machine wasn't found, but we discovered these:"
        : 'Machines';
    final scaleHeader = preferredScaleNotFound
        ? "Your preferred scale wasn't found, but we discovered these:"
        : 'Scales';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 460),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DeviceSelectionWidget(
                    deviceController: widget.deviceController,
                    deviceType: dev.DeviceType.machine,
                    showHeader: true,
                    headerText: machineHeader,
                    connectingDeviceId: connectingDeviceId,
                    errorMessage: _status.error,
                    selectedDeviceId: null,
                    preferredDeviceId:
                        widget.settingsController.preferredMachineId,
                    onPreferredChanged: (id) =>
                        widget.settingsController.setPreferredMachineId(id),
                    onDeviceTapped: (device) {
                      if (device is De1Interface) {
                        widget.connectionManager.connectMachine(device);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DeviceSelectionWidget(
                    deviceController: widget.deviceController,
                    deviceType: dev.DeviceType.scale,
                    showHeader: true,
                    headerText: scaleHeader,
                    selectedDeviceId: null,
                    preferredDeviceId:
                        widget.settingsController.preferredScaleId,
                    onPreferredChanged: (id) =>
                        widget.settingsController.setPreferredScaleId(id),
                    onDeviceTapped: (device) {
                      widget.connectionManager
                          .connectScale(device as device_scale.Scale);
                    },
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              if (!isConnecting)
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () => widget.connectionManager.connect(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      const Icon(LucideIcons.refreshCw, size: 14),
                      const Text('ReScan'),
                    ],
                  ),
                ),
              ShadButton(
                size: ShadButtonSize.sm,
                onPressed: null,
                child: isConnecting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const Text('Connecting...'),
                        ],
                      )
                    : const Text('Select a machine'),
              ),
              if (!isConnecting)
                ShadButton.secondary(
                  size: ShadButtonSize.sm,
                  onPressed: _skipToDashboard,
                  child: const Text('Dashboard'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Icon(LucideIcons.triangleAlert,
              size: 48, color: theme.colorScheme.destructive),
          Text('Connection Error', style: theme.textTheme.h4),
          Text(
            _status.error ?? 'An unknown error occurred.',
            style: theme.textTheme.muted,
            textAlign: TextAlign.center,
          ),
          ShadButton(
            onPressed: () => widget.connectionManager.connect(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                const Icon(LucideIcons.refreshCw, size: 16),
                const Text('Retry'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adapterErrorView(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Icon(LucideIcons.bluetoothOff,
              size: 48, color: theme.colorScheme.destructive),
          Text('Bluetooth Unavailable', style: theme.textTheme.h4),
          Text(
            _adapterError!,
            style: theme.textTheme.muted,
            textAlign: TextAlign.center,
          ),
          ShadButton(
            onPressed: () {
              setState(() {
                _adapterError = null;
              });
              widget.connectionManager.connect();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                const Icon(LucideIcons.refreshCw, size: 16),
                const Text('Try Again'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noDevicesFoundView(BuildContext context) {
    final report = widget.connectionManager.lastScanReport;
    if (report == null) {
      // Fallback if no report is available yet
      return Center(
        child: ShadButton(
          onPressed: () => widget.connectionManager.connect(),
          child: const Text('Scan Again'),
        ),
      );
    }

    return Center(
      child: ScanResultsSummary(
        report: report,
        onScanAgain: () => widget.connectionManager.connect(),
        onTroubleshoot: () => showTroubleshootingWizard(
          context: context,
          adapterState: widget.scanStateGuardian.currentAdapterState,
        ),
        onExportLogs: _exportLogs,
        onContinueToDashboard: _skipToDashboard,
      ),
    );
  }

  /// Stops the scan and forces the device picker to show with currently
  /// discovered devices.
  void _stopScanAndShowDevices() {
    widget.deviceController.stopScan();
  }

  void _showTakingTooLongSheet() {
    final hasDevices = _totalDiscovered > 0;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasDevices)
              ListTile(
                leading: const Icon(LucideIcons.list),
                title: Text(
                    'View $_totalDiscovered found device${_totalDiscovered == 1 ? '' : 's'}'),
                onTap: () {
                  Navigator.pop(context);
                  _stopScanAndShowDevices();
                },
              ),
            ListTile(
              leading: const Icon(LucideIcons.refreshCw),
              title: const Text('Re-start scan'),
              onTap: () {
                Navigator.pop(context);
                widget.connectionManager.connect();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.wrench),
              title: const Text('Troubleshoot'),
              onTap: () {
                Navigator.pop(context);
                showTroubleshootingWizard(
                  context: context,
                  adapterState:
                      widget.scanStateGuardian.currentAdapterState,
                );
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.fileText),
              title: const Text('Export logs'),
              onTap: () {
                Navigator.pop(context);
                _exportLogs();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.layoutDashboard),
              title: const Text('Continue to Dashboard'),
              onTap: () {
                Navigator.pop(context);
                _skipToDashboard();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportLogs() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final logFile = File('${docs.path}/log.txt');

      if (!await logFile.exists()) {
        if (mounted) {
          showShadDialog(
            context: context,
            builder: (context) => ShadDialog(
              title: const Text('No Logs Found'),
              description: const Text('Log file does not exist yet.'),
              actions: [
                ShadButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final bytes = await logFile.readAsBytes();
      final outputFile = await FilePicker.platform.saveFile(
        fileName: 'R1-logs-${DateTime.now().millisecondsSinceEpoch}.txt',
        dialogTitle: 'Choose where to save logs',
        bytes: bytes,
      );

      if (outputFile != null) {
        if (mounted) {
          showShadDialog(
            context: context,
            builder: (context) => ShadDialog(
              title: const Text('Logs Exported'),
              description: Text(
                'Logs have been successfully exported to:\n$outputFile',
              ),
              actions: [
                ShadButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showShadDialog(
          context: context,
          builder: (context) => ShadDialog(
            title: const Text('Export Failed'),
            description: Text('Failed to export logs: $e'),
            actions: [
              ShadButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}
