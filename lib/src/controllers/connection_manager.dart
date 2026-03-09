import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
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

enum AmbiguityReason { machinePicker, scalePicker }

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

  bool _isConnecting = false;
  bool _isConnectingMachine = false;
  bool _isConnectingScale = false;
  bool _machineConnected = false;
  bool _scaleConnected = false;

  StreamSubscription? _machineDisconnectSub;
  StreamSubscription? _scaleDisconnectSub;

  ConnectionManager({
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
    required this.settingsController,
  }) {
    _listenForDisconnects();
  }

  void _listenForDisconnects() {
    // Watch de1Controller.de1 stream — null means machine disconnected.
    // Ignore null emissions while actively connecting (connectToDe1 calls
    // _onDisconnect() at the start, which emits null transiently).
    _machineDisconnectSub = de1Controller.de1.listen((de1) {
      if (de1 == null && _machineConnected && !_isConnectingMachine) {
        _log.fine('Machine disconnected');
        _machineConnected = false;
        _statusSubject.add(
          currentStatus.copyWith(phase: ConnectionPhase.idle),
        );
      }
    });

    // Watch scaleController.connectionState — disconnected resets flag
    _scaleDisconnectSub = scaleController.connectionState.listen((state) {
      if (state == device.ConnectionState.disconnected && _scaleConnected) {
        _log.fine('Scale disconnected');
        _scaleConnected = false;
      }
    });
  }

  /// Main entry point: scan for devices and connect based on preference policy.
  ///
  /// 1. Scans for all devices
  /// 2. Applies machine preference policy (auto-connect, picker, or idle)
  /// 3. On successful machine connection, applies scale preference policy
  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      await _connectImpl();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _connectImpl() async {
    // Emit scanning phase
    _statusSubject.add(
      currentStatus.copyWith(
        phase: ConnectionPhase.scanning,
        error: () => null,
        pendingAmbiguity: () => null,
      ),
    );

    final preferredMachineId = settingsController.preferredMachineId;
    final preferredScaleId = settingsController.preferredScaleId;

    // Watch device stream during scan — connect preferred devices immediately
    // as they appear, rather than waiting for the full scan to complete.
    Future<void>? earlyMachineConnect;
    Future<void>? earlyScaleConnect;
    final sub = deviceController.deviceStream.listen((devices) {
      if (preferredMachineId != null &&
          !(_machineConnected || earlyMachineConnect != null)) {
        final match =
            devices
                .whereType<De1Interface>()
                .where((m) => m.deviceId == preferredMachineId)
                .firstOrNull;
        if (match != null) {
          _log.fine('Preferred machine found during scan, connecting early');
          earlyMachineConnect = connectMachine(match);
        }
      }

      if (preferredScaleId != null) {
        if (_scaleConnected || earlyScaleConnect != null) {
          return;
        }

        final match =
            devices
                .whereType<Scale>()
                .where((m) => m.deviceId == preferredScaleId)
                .firstOrNull;
        if (match != null) {
          _log.fine('Preferred scale found during scan, connecting early');
          earlyScaleConnect = connectScale(match);
        }
      }
    });

    // Run full unfiltered scan
    deviceController.scanForDevices();

    // Ensure we observe the scan starting before waiting for it to end.
    // scanForDevices() synchronously emits true, but guard against future
    // changes that might add an await before the emission.
    await deviceController.scanningStream.firstWhere((s) => s);
    await deviceController.scanningStream.firstWhere((s) => !s);
    sub.cancel();

    // Wait for early machine connection to finish if one was started
    if (earlyMachineConnect != null) {
      try {
        await earlyMachineConnect;
      } catch (_) {
        // connectMachine already handled the error and updated status
      }
    }

    if (earlyScaleConnect != null) {
      try {
        await earlyScaleConnect;
      } catch (_) {}
    }

    // Collect found devices
    final allDevices = deviceController.devices;
    final machines = allDevices.whereType<De1Interface>().toList();
    final scales = allDevices.whereType<Scale>().toList();

    _log.fine(
      'Scan complete: ${machines.length} machines, ${scales.length} scales',
    );

    // Store found devices in status for UI pickers
    _statusSubject.add(
      currentStatus.copyWith(foundMachines: machines, foundScales: scales),
    );

    // If machine is already connected (either from before or early connect),
    // skip straight to scale phase
    if (_machineConnected) {
      _log.fine('Machine connected, proceeding to scale phase');
      await _connectScalePhase(scales);
      return;
    }

    // Apply machine preference policy for remaining cases
    if (preferredMachineId != null) {
      // Preferred was set but not found during scan
      if (machines.isNotEmpty) {
        _statusSubject.add(
          currentStatus.copyWith(
            phase: ConnectionPhase.idle,
            pendingAmbiguity: () => AmbiguityReason.machinePicker,
          ),
        );
      } else {
        _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.idle));
      }
    } else {
      // No preferred machine set
      if (machines.isEmpty) {
        _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.idle));
      } else if (machines.length == 1) {
        // Exactly one machine — auto-connect
        await connectMachine(machines.first);
        await _connectScalePhase(scales);
      } else {
        // Multiple machines — picker
        _statusSubject.add(
          currentStatus.copyWith(
            phase: ConnectionPhase.idle,
            pendingAmbiguity: () => AmbiguityReason.machinePicker,
          ),
        );
      }
    }
  }

  /// Scan for scales only and apply scale preference policy.
  /// Use this when the machine is already connected and only a scale
  /// reconnect is needed (e.g., after machine wakes from sleep).
  Future<void> scanAndConnectScale() async {
    if (_isConnecting) {
      _log.fine('scanAndConnectScale: connect already in progress, skipping');
      return;
    }

    _log.fine('scanAndConnectScale: scanning for scales only');

    deviceController.scanForDevices();
    try {
      await deviceController.scanningStream
          .firstWhere((s) => s)
          .timeout(const Duration(seconds: 5));
      await deviceController.scanningStream
          .firstWhere((s) => !s)
          .timeout(const Duration(seconds: 35));
    } on TimeoutException {
      _log.warning('scanAndConnectScale: scan timed out');
      return;
    }

    final scales = deviceController.devices.whereType<Scale>().toList();
    _log.fine('scanAndConnectScale: found ${scales.length} scales');

    // Update found scales in status
    _statusSubject.add(
      currentStatus.copyWith(foundScales: scales),
    );

    await _connectScalePhase(scales);
  }

  /// Apply scale preference policy after machine connects.
  Future<void> _connectScalePhase(List<Scale> scales) async {
    if (_scaleConnected) {
      _log.fine('Scale already connected, skipping scale phase');
      return;
    }
    _log.fine('Scale phase: ${scales.length} scales found');
    final preferredScaleId = settingsController.preferredScaleId;
    _log.fine('Scale phase: preferredScaleId=$preferredScaleId');

    if (preferredScaleId != null) {
      // Preferred scale is set
      final preferred =
          scales.where((s) => s.deviceId == preferredScaleId).toList();
      if (preferred.isNotEmpty) {
        await connectScale(preferred.first);
      } else if (scales.isNotEmpty) {
        // Preferred not found but others available — picker
        _log.fine('Scale phase: preferred not found, showing picker');
        _statusSubject.add(
          currentStatus.copyWith(
            pendingAmbiguity: () => AmbiguityReason.scalePicker,
          ),
        );
      }
    } else {
      // No preferred scale set
      if (scales.length == 1) {
        await connectScale(scales.first);
      } else if (scales.length > 1) {
        // Multiple scales — picker
        _statusSubject.add(
          currentStatus.copyWith(
            pendingAmbiguity: () => AmbiguityReason.scalePicker,
          ),
        );
      }
    }
  }

  Future<void> connectMachine(De1Interface machine) async {
    if (_isConnectingMachine) {
      _log.fine('connectMachine: already connecting, skipping');
      return;
    }
    _isConnectingMachine = true;
    _log.fine(
      'connectMachine: connecting to ${machine.name} (${machine.deviceId})',
    );

    _statusSubject.add(
      currentStatus.copyWith(
        phase: ConnectionPhase.connectingMachine,
        pendingAmbiguity: () => null,
        error: () => null,
      ),
    );

    try {
      await de1Controller.connectToDe1(machine);
      await settingsController.setPreferredMachineId(machine.deviceId);
      _machineConnected = true;
      _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
    } catch (e) {
      _statusSubject.add(
        currentStatus.copyWith(
          phase: ConnectionPhase.idle,
          error: () => e.toString(),
        ),
      );
      rethrow;
    } finally {
      _isConnectingMachine = false;
    }
  }

  Future<void> connectScale(Scale scale) async {
    if (_isConnectingScale) {
      _log.fine('connectScale: already connecting, skipping');
      return;
    }
    _isConnectingScale = true;
    _log.fine('connectScale: connecting to ${scale.name} (${scale.deviceId})');

    _statusSubject.add(
      currentStatus.copyWith(
        phase: ConnectionPhase.connectingScale,
        pendingAmbiguity: () => null,
        error: () => null,
      ),
    );

    try {
      await scaleController.connectToScale(scale);
      await settingsController.setPreferredScaleId(scale.deviceId);
      _scaleConnected = true;
      _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
    } catch (e) {
      // Scale failure is non-blocking — stay at ready if machine connected, else idle
      _statusSubject.add(
        currentStatus.copyWith(
          phase:
              _machineConnected ? ConnectionPhase.ready : ConnectionPhase.idle,
          error: () => null,
        ),
      );
    } finally {
      _isConnectingScale = false;
    }
  }

  Future<void> disconnectMachine() async {
    // Reset flag before disconnect to prevent the disconnect listener from
    // also emitting idle (which would cause a double emission).
    _machineConnected = false;
    _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.idle));
    final de1 = await de1Controller.de1.first;
    if (de1 != null) {
      await de1.disconnect();
    }
  }

  Future<void> disconnectScale() async {
    try {
      final scale = scaleController.connectedScale();
      await scale.disconnect();
    } catch (_) {
      // No scale connected — nothing to disconnect
    }
    _scaleConnected = false;
  }

  void dispose() {
    _machineDisconnectSub?.cancel();
    _scaleDisconnectSub?.cancel();
    _statusSubject.close();
  }
}
