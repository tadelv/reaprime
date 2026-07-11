import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/device_discovery_feature/device_discovery_view.dart';
import 'package:reaprime/src/home_feature/widgets/device_selection_widget.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/scale.dart' as device_scale;
import 'package:reaprime/src/services/telemetry/boot_timing.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:reaprime/src/widgets/accessible_button.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../onboarding_feature/widgets/scan_results_summary.dart';
import '../onboarding_feature/widgets/troubleshooting_wizard.dart';

final _log = Logger('ScanFlow');

/// Callback-driven scan flow widget.
///
/// Shows progress with coffee messages during scanning, a "taking too long"
/// button after a threshold, device pickers when ambiguity arises, and invokes
/// [onConnected] when connection is ready. Used by both onboarding (via
/// [ScanStepView]) and the launcher scan page.
class ScanFlowView extends StatefulWidget {
  final ConnectionManager connectionManager;
  final DeviceController deviceController;
  final SettingsController settingsController;
  final ScanStateGuardian scanStateGuardian;

  /// When true, auto-connect to the first discovered machine/scale instead
  /// of showing a picker on ambiguity.
  final bool directConnect;

  /// Invoked once when the connection phase first reaches `ready`.
  final VoidCallback onConnected;

  /// Invoked when the user chooses to leave the scan without connecting.
  final VoidCallback onExit;

  /// Button copy for the exit affordance (e.g. 'Dashboard', 'Cancel').
  final String exitLabel;

  /// How long to wait before showing the "taking too long" button.
  static const scanTooLongThreshold = Duration(seconds: 16);

  const ScanFlowView({
    super.key,
    required this.connectionManager,
    required this.deviceController,
    required this.settingsController,
    required this.scanStateGuardian,
    this.directConnect = false,
    required this.onConnected,
    required this.onExit,
    this.exitLabel = 'Dashboard',
  });

  @override
  State<ScanFlowView> createState() => ScanFlowViewState();
}

class ScanFlowViewState extends State<ScanFlowView> {
  void _skipToDashboard() => widget.onExit();

  void _clearAdapterErrorAndRetry() {
    setState(() {
      _adapterError = null;
    });
    widget.connectionManager.connect();
  }

  void _clearAdapterErrorAndTryDemo() {
    setState(() {
      _adapterError = null;
    });
    widget.settingsController.enableSimulatedDevicesForSession(
      {SimulatedDevicesTypes.machine, SimulatedDevicesTypes.scale},
    );
    widget.connectionManager.connect();
  }

  void _tryDemoModeFromNoDevices() {
    widget.settingsController.enableSimulatedDevicesForSession(
      {SimulatedDevicesTypes.machine, SimulatedDevicesTypes.scale},
    );
    widget.connectionManager.connect();
  }

  late StreamSubscription<ConnectionStatus> _statusSubscription;
  late StreamSubscription<ScanStateEvent> _guardianSubscription;
  late StreamSubscription<List<dev.Device>> _deviceSubscription;
  ConnectionStatus _status =
      const ConnectionStatus(phase: ConnectionPhase.scanning);
  bool _hasNavigated = false;
  bool _showTakingTooLong = false;
  Timer? _tooLongTimer;

  /// Prevents re-triggering auto-connect on subsequent status emissions
  /// when --direct is active.
  bool _directAutoConnected = false;

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

      // Boot-timing: record each phase transition once.
      if (status.phase != _status.phase) {
        BootTiming.mark('connect_${status.phase.name}');
      }

      if (status.phase == ConnectionPhase.ready && !_hasNavigated) {
        _hasNavigated = true;
        _cancelTooLongTimer();
        BootTiming.mark('scan_ready');
        widget.onConnected();
        return;
      }

      // --direct: auto-connect to first discovered machine/scale on ambiguity.
      if (widget.directConnect && !_directAutoConnected) {
        if (status.pendingAmbiguity == AmbiguityReason.machinePicker &&
            _discoveredMachines.isNotEmpty) {
          _directAutoConnected = true;
          _log.info('--direct: auto-connecting to ${_discoveredMachines.first.name}');
          unawaited(widget.connectionManager
              .connectMachine(_discoveredMachines.first));
          return;
        }
        if (status.pendingAmbiguity == AmbiguityReason.scalePicker &&
            _discoveredScales.isNotEmpty) {
          _directAutoConnected = true;
          _log.info('--direct: auto-connecting to scale ${_discoveredScales.first.name}');
          unawaited(widget.connectionManager
              .connectScale(_discoveredScales.first));
          return;
        }
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
    _tooLongTimer = Timer(ScanFlowView.scanTooLongThreshold, () {
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
    final Widget content;

    // Adapter error takes precedence -- but only while nothing that works
    // WITHOUT Bluetooth is in flight. USB/serial discovery keeps running
    // with the adapter off, so found machines, an active
    // connect, or a pending picker keep the normal flow visible and a
    // wired-only setup can reach the skin. `ready` navigates away above
    // regardless.
    final busyWithoutBle =
        _status.phase == ConnectionPhase.connectingMachine ||
        _status.phase == ConnectionPhase.connectingScale ||
        _status.pendingAmbiguity != null ||
        _status.foundMachines.isNotEmpty ||
        _discoveredMachines.isNotEmpty;
    if (_adapterError != null && !busyWithoutBle) {
      content = _adapterErrorView(context);
    }
    // Error state from connection manager. The sticky adapter-off error
    // gets the same treatment as the guardian view above: it must not
    // hide machines that were found WITHOUT Bluetooth (USB/serial), or
    // a wired-only setup can never reach its picker.
    else if (_status.error != null &&
        _status.phase == ConnectionPhase.idle &&
        !(busyWithoutBle &&
            _status.error!.kind == ConnectionErrorKind.adapterOff)) {
      content = _errorView(context);
    }
    // Scanning
    else if (_status.phase == ConnectionPhase.scanning) {
      content = _scanningView(context);
    }
    // Connecting to machine or scale
    else if (_status.phase == ConnectionPhase.connectingMachine ||
        _status.phase == ConnectionPhase.connectingScale) {
      content = _connectingView(context);
    }
    // Ambiguity: machine or scale picker
    else if (_status.pendingAmbiguity == AmbiguityReason.machinePicker ||
        _status.pendingAmbiguity == AmbiguityReason.scalePicker) {
      content = _devicePickerView(context);
    }
    // Idle with no machines found
    else if (_status.phase == ConnectionPhase.idle &&
        _status.foundMachines.isEmpty) {
      content = _noDevicesFoundView(context);
    }
    // Idle with machines but no ambiguity (fallback)
    else if (_status.phase == ConnectionPhase.idle &&
        _status.foundMachines.isNotEmpty) {
      content = _devicePickerView(context);
    }
    // Default: scanning view
    else {
      content = _scanningView(context);
    }

    return Scaffold(body: content);
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

    return Column(
      children: [
        // Progress bar + text centered in available space
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Scanning for devices',
                  child: SizedBox(width: 200, child: ShadProgress()),
                ),
                const SizedBox(height: 16),
                if (hasDevicesNotPreferred && _showTakingTooLong) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '$deviceCount device${deviceCount == 1 ? '' : 's'} found, but not your preferred one.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Still scanning...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ] else
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      DeviceDiscoveryView.getRandomCoffeeMessage(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // "Taking too long" button pinned to bottom, doesn't affect center position
        ExcludeSemantics(
          excluding: !_showTakingTooLong,
          child: AnimatedOpacity(
            opacity: _showTakingTooLong ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: IgnorePointer(
              ignoring: !_showTakingTooLong,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: AccessibleButton(
                label: hasDevicesNotPreferred
                    ? 'View found devices'
                    : 'This is taking a while...',
                onTap: _showTakingTooLongSheet,
                child: ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _showTakingTooLongSheet,
                  child: Text(hasDevicesNotPreferred
                      ? 'View found devices'
                      : 'This is taking a while...'),
                ),
              ),
            ),
          ),
          ),
        ),
      ],
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
          Semantics(
            label: 'Connecting to device',
            child: SizedBox(width: 200, child: ShadProgress()),
          ),
          Semantics(
            liveRegion: true,
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
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

    return Material(
      type: MaterialType.transparency,
      child: Center(
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
                    errorMessage: _status.error?.message,
                    selectedDeviceId: null,
                    preferredDeviceId:
                        widget.settingsController.preferredMachineId,
                    onPreferredChanged: (id) =>
                        widget.settingsController.setPreferredMachineId(id),
                    onDeviceTapped: (device) {
                      setState(() {});
                      widget.settingsController.setPreferredMachineId(device.deviceId);
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
                      setState(() {});
                      widget.settingsController.setPreferredScaleId(device.deviceId);
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
                AccessibleButton(
                  label: 'ReScan',
                  onTap: () => widget.connectionManager.connect(),
                  child: ShadButton.outline(
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
                ),
              AccessibleButton(
                label: isConnecting
                    ? 'Connecting'
                    : widget.settingsController.preferredMachineId != null
                        ? 'Connect'
                        : 'Select a machine',
                onTap: isConnecting
                    ? null
                    : widget.settingsController.preferredMachineId != null
                        ? () => widget.connectionManager.connect()
                        : null,
                child: ShadButton(
                  size: ShadButtonSize.sm,
                  onPressed: isConnecting
                      ? null
                      : widget.settingsController.preferredMachineId != null
                          ? () => widget.connectionManager.connect()
                          : null,
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
                      : Text(widget.settingsController.preferredMachineId != null
                          ? 'Connect'
                          : 'Select a machine'),
                ),
              ),
              if (!isConnecting)
                AccessibleButton(
                  label: widget.exitLabel,
                  onTap: _skipToDashboard,
                  child: ShadButton.secondary(
                    size: ShadButtonSize.sm,
                    onPressed: _skipToDashboard,
                    child: Text(widget.exitLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
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
          ExcludeSemantics(
            child: Icon(LucideIcons.triangleAlert,
                size: 48, color: theme.colorScheme.destructive),
          ),
          Text('Connection Error', style: theme.textTheme.h4),
          Text(
            _status.error?.message ?? 'An unknown error occurred.',
            style: theme.textTheme.muted,
            textAlign: TextAlign.center,
          ),
          AccessibleButton(
            label: 'Retry',
            onTap: () => widget.connectionManager.connect(),
            child: ShadButton(
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
          ExcludeSemantics(
            child: Icon(LucideIcons.bluetoothOff,
                size: 48, color: theme.colorScheme.destructive),
          ),
          Text('Bluetooth Unavailable', style: theme.textTheme.h4),
          Text(
            _adapterError!,
            style: theme.textTheme.muted,
            textAlign: TextAlign.center,
          ),
          Text(
            'USB connections keep working: plug the machine in over USB '
            'and it will be found without Bluetooth.',
            style: theme.textTheme.muted,
            textAlign: TextAlign.center,
          ),
          AccessibleButton(
            label: 'Try Again',
            onTap: _clearAdapterErrorAndRetry,
            child: ShadButton(
              onPressed: _clearAdapterErrorAndRetry,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  const Icon(LucideIcons.refreshCw, size: 16),
                  const Text('Try Again'),
                ],
              ),
            ),
          ),
          AccessibleButton(
            label: 'Try Demo Mode',
            onTap: _clearAdapterErrorAndTryDemo,
            child: ShadButton.outline(
              onPressed: _clearAdapterErrorAndTryDemo,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  const Icon(LucideIcons.gamepad2, size: 16),
                  const Text('Try Demo Mode'),
                ],
              ),
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
        child: AccessibleButton(
          label: 'Scan Again',
          onTap: () => widget.connectionManager.connect(),
          child: ShadButton(
            onPressed: () => widget.connectionManager.connect(),
            child: const Text('Scan Again'),
          ),
        ),
      );
    }

    return Center(
      child: ScanResultsSummary(
        report: report,
        onScanAgain: () => widget.connectionManager.connect(),
        onTryDemoMode: _tryDemoModeFromNoDevices,
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
              title: Text(widget.exitLabel == 'Dashboard'
                  ? 'Continue to Dashboard'
                  : widget.exitLabel),
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
                AccessibleButton(
                  label: 'OK',
                  onTap: () => Navigator.of(context).pop(),
                  child: ShadButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      final bytes = await logFile.readAsBytes();
      final outputFile = await FilePicker.saveFile(
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
                AccessibleButton(
                  label: 'OK',
                  onTap: () => Navigator.of(context).pop(),
                  child: ShadButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
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
              AccessibleButton(
                label: 'OK',
                onTap: () => Navigator.of(context).pop(),
                child: ShadButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        );
      }
    }
  }
}
