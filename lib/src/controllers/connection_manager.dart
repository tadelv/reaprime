import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';

enum ConnectionPhase {
  idle,
  scanning,
  connectingMachine,
  connectingScale,
  ready,
}

enum AmbiguityReason {
  machinePicker,
  scalePicker,
}

class ConnectionStatus {
  final ConnectionPhase phase;
  final List<De1Interface> foundMachines;
  final List<Scale> foundScales;
  final AmbiguityReason? pendingAmbiguity;
  final String? error;

  const ConnectionStatus({
    this.phase = ConnectionPhase.idle,
    this.foundMachines = const [],
    this.foundScales = const [],
    this.pendingAmbiguity,
    this.error,
  });

  ConnectionStatus copyWith({
    ConnectionPhase? phase,
    List<De1Interface>? foundMachines,
    List<Scale>? foundScales,
    AmbiguityReason? Function()? pendingAmbiguity,
    String? Function()? error,
  }) {
    return ConnectionStatus(
      phase: phase ?? this.phase,
      foundMachines: foundMachines ?? this.foundMachines,
      foundScales: foundScales ?? this.foundScales,
      pendingAmbiguity:
          pendingAmbiguity != null ? pendingAmbiguity() : this.pendingAmbiguity,
      error: error != null ? error() : this.error,
    );
  }
}

class ConnectionManager {
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final SettingsController settingsController;

  final _log = Logger('ConnectionManager');

  final BehaviorSubject<ConnectionStatus> _statusSubject =
      BehaviorSubject.seeded(const ConnectionStatus());

  Stream<ConnectionStatus> get status => _statusSubject.stream;
  ConnectionStatus get currentStatus => _statusSubject.value;

  bool _isConnectingMachine = false;
  bool _isConnectingScale = false;

  ConnectionManager({
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
    required this.settingsController,
  });

  /// Main entry point: scan for devices and connect based on preference policy.
  ///
  /// 1. Scans for all devices
  /// 2. Applies machine preference policy (auto-connect, picker, or idle)
  /// 3. On successful machine connection, applies scale preference policy
  Future<void> connect() async {
    // Emit scanning phase
    _statusSubject.add(currentStatus.copyWith(
      phase: ConnectionPhase.scanning,
      error: () => null,
      pendingAmbiguity: () => null,
    ));

    // Run full unfiltered scan
    deviceController.scanForDevices();

    // Wait for scan to complete (scanningStream emits false)
    await deviceController.scanningStream.firstWhere((scanning) => !scanning);

    // Collect found devices
    final allDevices = deviceController.devices;
    final machines = allDevices.whereType<De1Interface>().toList();
    final scales = allDevices.whereType<Scale>().toList();

    _log.fine(
        'Scan complete: ${machines.length} machines, ${scales.length} scales');

    // Store found devices in status for UI pickers
    _statusSubject.add(currentStatus.copyWith(
      foundMachines: machines,
      foundScales: scales,
    ));

    // Apply machine preference policy
    final preferredMachineId = settingsController.preferredMachineId;

    if (preferredMachineId != null) {
      // Preferred machine is set
      final preferred = machines
          .where((m) => m.deviceId == preferredMachineId)
          .toList();

      if (preferred.isNotEmpty) {
        // Found preferred machine — connect directly
        await connectMachine(preferred.first);
        await _connectScalePhase(scales);
      } else if (machines.isNotEmpty) {
        // Preferred not found but others available — picker
        _statusSubject.add(currentStatus.copyWith(
          phase: ConnectionPhase.idle,
          pendingAmbiguity: () => AmbiguityReason.machinePicker,
        ));
      } else {
        // No machines at all
        _statusSubject.add(currentStatus.copyWith(
          phase: ConnectionPhase.idle,
        ));
      }
    } else {
      // No preferred machine set
      if (machines.isEmpty) {
        _statusSubject.add(currentStatus.copyWith(
          phase: ConnectionPhase.idle,
        ));
      } else if (machines.length == 1) {
        // Exactly one machine — auto-connect
        await connectMachine(machines.first);
        await _connectScalePhase(scales);
      } else {
        // Multiple machines — picker
        _statusSubject.add(currentStatus.copyWith(
          phase: ConnectionPhase.idle,
          pendingAmbiguity: () => AmbiguityReason.machinePicker,
        ));
      }
    }
  }

  /// Apply scale preference policy after machine connects.
  Future<void> _connectScalePhase(List<Scale> scales) async {
    final preferredScaleId = settingsController.preferredScaleId;

    if (preferredScaleId != null) {
      // Preferred scale is set
      final preferred =
          scales.where((s) => s.deviceId == preferredScaleId).toList();
      if (preferred.isNotEmpty) {
        await connectScale(preferred.first);
      }
      // If preferred not found, do nothing — phase stays ready
    } else {
      // No preferred scale set
      if (scales.length == 1) {
        await connectScale(scales.first);
      }
      // 0 or many scales — skip silently
    }
  }

  Future<void> connectMachine(De1Interface machine) async {
    if (_isConnectingMachine) return;
    _isConnectingMachine = true;

    _statusSubject.add(currentStatus.copyWith(
      phase: ConnectionPhase.connectingMachine,
      error: () => null,
    ));

    try {
      await de1Controller.connectToDe1(machine);
      await settingsController.setPreferredMachineId(machine.deviceId);
      _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
    } catch (e) {
      _statusSubject.add(currentStatus.copyWith(
        phase: ConnectionPhase.idle,
        error: () => e.toString(),
      ));
      rethrow;
    } finally {
      _isConnectingMachine = false;
    }
  }

  Future<void> connectScale(Scale scale) async {
    if (_isConnectingScale) return;
    _isConnectingScale = true;

    _statusSubject.add(currentStatus.copyWith(
      phase: ConnectionPhase.connectingScale,
      error: () => null,
    ));

    try {
      await scaleController.connectToScale(scale);
      await settingsController.setPreferredScaleId(scale.deviceId);
      _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
    } catch (e) {
      // Scale failure is non-blocking — stay at ready if machine connected, else idle
      _statusSubject.add(currentStatus.copyWith(
        phase: ConnectionPhase.ready,
        error: () => null,
      ));
    } finally {
      _isConnectingScale = false;
    }
  }

  void dispose() {
    _statusSubject.close();
  }
}
