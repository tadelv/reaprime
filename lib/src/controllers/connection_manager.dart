import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlusException;
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/device_scanner.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/models/scan_report.dart';
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
  final ConnectionError? error;

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
    ConnectionError? Function()? error,
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
  final DeviceScanner deviceScanner;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final SettingsController settingsController;

  final _log = Logger('ConnectionManager');

  final BehaviorSubject<ConnectionStatus> _statusSubject =
      BehaviorSubject.seeded(const ConnectionStatus());

  final BehaviorSubject<ScanReport> _scanReportSubject = BehaviorSubject();

  Stream<ConnectionStatus> get status => _statusSubject.stream;
  ConnectionStatus get currentStatus => _statusSubject.value;

  /// The most recent scan report, or null if no scan has completed yet.
  ScanReport? get lastScanReport => _scanReportSubject.valueOrNull;

  /// Emits a [ScanReport] after each scan + connection cycle completes.
  Stream<ScanReport> get scanReportStream => _scanReportSubject.stream;

  bool _isConnecting = false;
  bool _isConnectingMachine = false;
  bool _isConnectingScale = false;
  bool _machineConnected = false;
  bool _scaleConnected = false;

  StreamSubscription? _machineDisconnectSub;
  StreamSubscription? _scaleDisconnectSub;
  StreamSubscription<AdapterState>? _adapterSub;

  final Set<String> _expectingDisconnectFor = {};
  final Map<String, Timer> _expectingDisconnectTimers = {};

  ConnectionManager({
    required this.deviceScanner,
    required this.de1Controller,
    required this.scaleController,
    required this.settingsController,
  }) {
    _listenForDisconnects();
    _listenForAdapter();
  }

  void _listenForAdapter() {
    _adapterSub = deviceScanner.adapterStateStream.listen((state) {
      if (state == AdapterState.poweredOff) {
        _emit(ConnectionError(
          kind: ConnectionErrorKind.adapterOff,
          severity: ConnectionErrorSeverity.error,
          timestamp: DateTime.now().toUtc(),
          message: 'Bluetooth is turned off.',
          suggestion: 'Turn Bluetooth on to scan for devices.',
        ));
      } else if (state == AdapterState.poweredOn &&
          currentStatus.error?.kind == ConnectionErrorKind.adapterOff) {
        _clearError();
      }
    });
  }

  void _listenForDisconnects() {
    // Watch de1Controller.de1 stream — null means machine disconnected.
    // Ignore null emissions while actively connecting (connectToDe1 calls
    // _onDisconnect() at the start, which emits null transiently).
    String? lastKnownMachineId;
    _machineDisconnectSub = de1Controller.de1.listen((de1) {
      if (de1 != null) {
        lastKnownMachineId = de1.deviceId;
        return;
      }
      if (_machineConnected && !_isConnectingMachine) {
        _log.fine('Machine disconnected');
        _machineConnected = false;
        _publishStatus(
          currentStatus.copyWith(phase: ConnectionPhase.idle),
        );
        final id = lastKnownMachineId;
        if (id != null) {
          _handleMachineDisconnect(id);
        }
      }
    });

    // Watch scaleController.connectionState — emit scaleDisconnected on a
    // connected → disconnected transition (unless marked expected).
    _scaleDisconnectSub = scaleController.connectionState.listen((state) {
      final wasConnected = _scaleConnected;
      _scaleConnected = state == device.ConnectionState.connected;
      _log.fine("scale connection update: $_scaleConnected");
      if (wasConnected &&
          state == device.ConnectionState.disconnected &&
          !_isConnectingScale) {
        final id = scaleController.lastConnectedDeviceId ??
            settingsController.preferredScaleId;
        if (id != null) {
          _handleScaleDisconnect(id);
        }
      }
    });
  }

  void _emit(ConnectionError err) {
    final msg = 'emit error: kind=${err.kind} message=${err.message} '
        'deviceId=${err.deviceId}';
    if (err.severity == ConnectionErrorSeverity.error) {
      _log.severe(msg);
    } else {
      _log.warning(msg);
    }
    _statusSubject.add(currentStatus.copyWith(error: () => err));
  }

  /// Build a [ConnectionError] for a failed connect attempt. Pulls out
  /// `fbp_code` / `fbp_description` when the caught exception is a
  /// [FlutterBluePlusException]; otherwise stashes the stringified
  /// exception under `details.exception`.
  ConnectionError _buildConnectError({
    required String kind,
    required String deviceId,
    required String deviceName,
    required String message,
    String? suggestion,
    required Object exception,
  }) {
    Map<String, dynamic>? details;
    if (exception is FlutterBluePlusException) {
      final map = <String, dynamic>{
        if (exception.code != null) 'fbp_code': exception.code,
        if (exception.description != null)
          'fbp_description': exception.description,
        if (exception.function.isNotEmpty) 'fbp_function': exception.function,
      };
      details = map.isEmpty ? null : map;
    } else {
      details = {'exception': exception.toString()};
    }
    return ConnectionError(
      kind: kind,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.now().toUtc(),
      deviceId: deviceId,
      deviceName: deviceName,
      message: message,
      suggestion: suggestion,
      details: details,
    );
  }

  /// Map a scan-start exception to a [ConnectionErrorKind]. Checks the
  /// exception type first (for the known [PermissionDeniedException]
  /// type); falls back to a lowercase substring match on the message
  /// so platforms that surface permission failures as generic exceptions
  /// still route to the right kind.
  String _classifyScanError(Object e) {
    if (e is PermissionDeniedException) {
      return ConnectionErrorKind.bluetoothPermissionDenied;
    }
    final msg = e.toString().toLowerCase();
    if (msg.contains('permission')) {
      return ConnectionErrorKind.bluetoothPermissionDenied;
    }
    return ConnectionErrorKind.scanFailed;
  }

  /// Clears the current error. Called by environmental recovery handlers
  /// (adapter on, permission granted).
  void _clearError() {
    if (currentStatus.error == null) return;
    _statusSubject.add(currentStatus.copyWith(error: () => null));
  }

  void _publishStatus(ConnectionStatus next) {
    final prev = _statusSubject.value;
    // Auto-clear transient errors on phase transitions that start a new
    // operation or reach a stable good state.
    const clearingPhases = {
      ConnectionPhase.scanning,
      ConnectionPhase.connectingMachine,
      ConnectionPhase.connectingScale,
      ConnectionPhase.ready,
    };

    ConnectionError? effectiveError = next.error;
    final movingIntoClearingPhase =
        prev.phase != next.phase && clearingPhases.contains(next.phase);

    if (effectiveError == null &&
        prev.error != null &&
        ConnectionErrorKind.sticky.contains(prev.error!.kind)) {
      // Caller published null but a sticky error was active — keep it.
      // Sticky errors only clear via explicit environmental-recovery handlers.
      effectiveError = prev.error;
    } else if (effectiveError != null &&
        movingIntoClearingPhase &&
        !ConnectionErrorKind.sticky.contains(effectiveError.kind)) {
      // A new status that carries a transient error into a clearing phase
      // means the caller is re-publishing an old error — strip it.
      effectiveError = null;
    } else if (prev.error != null &&
        // copyWith preserves the error reference when the caller does not
        // pass `error:`, so `identical` is the right identity check here.
        identical(next.error, prev.error) &&
        movingIntoClearingPhase &&
        !ConnectionErrorKind.sticky.contains(prev.error!.kind)) {
      effectiveError = null;
    }

    _statusSubject.add(next.copyWith(error: () => effectiveError));
  }

  @visibleForTesting
  void debugEmitError({
    required String kind,
    required String severity,
    required String message,
    String? deviceId,
    String? deviceName,
    String? suggestion,
    Map<String, dynamic>? details,
    DateTime? timestamp,
  }) {
    _emit(ConnectionError(
      kind: kind,
      severity: severity,
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      message: message,
      deviceId: deviceId,
      deviceName: deviceName,
      suggestion: suggestion,
      details: details,
    ));
  }

  @visibleForTesting
  void debugSetPhase(ConnectionPhase phase) {
    _statusSubject.add(currentStatus.copyWith(phase: phase));
  }

  /// Call immediately before an app-initiated disconnect. The next
  /// `disconnected` event for `deviceId` will be treated as expected and
  /// will not emit an error. A 10-second TTL safety timer clears the
  /// expectation if the disconnect event never arrives.
  void markExpectingDisconnect(String deviceId) {
    _expectingDisconnectFor.add(deviceId);
    _expectingDisconnectTimers[deviceId]?.cancel();
    _expectingDisconnectTimers[deviceId] =
        Timer(const Duration(seconds: 10), () {
      _expectingDisconnectFor.remove(deviceId);
      _expectingDisconnectTimers.remove(deviceId);
    });
  }

  bool _consumeExpectingDisconnect(String deviceId) {
    final wasExpecting = _expectingDisconnectFor.remove(deviceId);
    if (wasExpecting) {
      _expectingDisconnectTimers.remove(deviceId)?.cancel();
    }
    return wasExpecting;
  }

  void _handleScaleDisconnect(String deviceId) {
    if (_consumeExpectingDisconnect(deviceId)) {
      _log.fine('Scale $deviceId: expected disconnect, suppressing error');
      return;
    }
    _emit(ConnectionError(
      kind: ConnectionErrorKind.scaleDisconnected,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.now().toUtc(),
      deviceId: deviceId,
      message: 'Scale disconnected unexpectedly.',
      suggestion:
          'The scale may have powered off or moved out of range. '
          'Wake the scale and reconnect.',
    ));
  }

  void _handleMachineDisconnect(String deviceId) {
    if (_consumeExpectingDisconnect(deviceId)) {
      _log.fine('Machine $deviceId: expected disconnect, suppressing error');
      return;
    }
    _emit(ConnectionError(
      kind: ConnectionErrorKind.machineDisconnected,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.now().toUtc(),
      deviceId: deviceId,
      message: 'Machine disconnected unexpectedly.',
      suggestion:
          'Check the machine is powered on and in range, then '
          'reconnect.',
    ));
  }

  @visibleForTesting
  void debugNotifyScaleDisconnected(String deviceId) {
    _handleScaleDisconnect(deviceId);
  }

  @visibleForTesting
  void debugNotifyMachineDisconnected(String deviceId) {
    _handleMachineDisconnect(deviceId);
  }

  /// Scan for devices and connect based on preference policy.
  ///
  /// When [scaleOnly] is false (default):
  /// 1. Scans for all devices
  /// 2. Applies machine preference policy (auto-connect, picker, or idle)
  /// 3. On successful machine connection, applies scale preference policy
  ///
  /// When [scaleOnly] is true:
  /// Skips machine policy entirely — use when the machine is already
  /// connected and only a scale reconnect is needed (e.g., after wake).
  ///
  /// Early-stop: if both preferred machine and preferred scale are set,
  /// the scan stops early once both are connected. If only one (or neither)
  /// preference is set, the full scan runs to discover all available devices.
  Future<void> connect({bool scaleOnly = false}) async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      await _connectImpl(scaleOnly: scaleOnly);
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _connectImpl({required bool scaleOnly}) async {
    final scanStartTime = DateTime.now();

    // Track matched devices and their connection results
    final matchedDeviceResults = <String, _MatchedDeviceTracker>{};

    // Emit scanning phase. Do not explicitly clear `error` — the gatekeeper
    // strips transient errors on phase transitions into clearing phases and
    // preserves sticky ones (e.g. adapterOff).
    _publishStatus(
      currentStatus.copyWith(
        phase: ConnectionPhase.scanning,
        pendingAmbiguity: () => null,
      ),
    );

    final preferredMachineId =
        scaleOnly ? null : settingsController.preferredMachineId;
    final preferredScaleId = settingsController.preferredScaleId;

    // Early-stop is only enabled when both preferences are set (and not scaleOnly).
    final earlyStopEnabled =
        !scaleOnly && preferredMachineId != null && preferredScaleId != null;

    // Watch device stream during scan — connect preferred devices immediately
    // as they appear, rather than waiting for the full scan to complete.
    // Skip(1) avoids the BehaviorSubject replay of stale (disconnected) devices;
    // we only want to react to fresh discoveries from the active scan.
    Future<void>? earlyMachineConnect;
    Future<void>? earlyScaleConnect;
    final sub = deviceScanner.deviceStream.skip(1).listen((devices) {
      // Track all matched devices as they appear
      for (final d in devices) {
        matchedDeviceResults.putIfAbsent(
          d.deviceId,
          () => _MatchedDeviceTracker(
            deviceName: d.name,
            deviceId: d.deviceId,
            deviceType: d.type,
          ),
        );
      }

      if (preferredMachineId != null &&
          !(_machineConnected || earlyMachineConnect != null)) {
        final match =
            devices
                .whereType<De1Interface>()
                .where((m) => m.deviceId == preferredMachineId)
                .firstOrNull;
        if (match != null) {
          _log.fine('Preferred machine found during scan, connecting early');
          earlyMachineConnect = _connectMachineTracked(
            match,
            matchedDeviceResults,
          ).then((_) {
            _checkEarlyStop(earlyStopEnabled);
          });
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
          earlyScaleConnect = _connectScaleTracked(
            match,
            matchedDeviceResults,
          ).then((_) {
            _checkEarlyStop(earlyStopEnabled);
          });
        }
      }
    });

    // Run full unfiltered scan. Classify any throw from scan-start
    // into bluetoothPermissionDenied or scanFailed. Both are sticky
    // errors — they survive phase transitions and only clear when the
    // environment recovers (see the success path below).
    try {
      // Start the scan and subscribe to scanningStream concurrently so we
      // can race the "scanning started" signal against an error from
      // scanForDevices() (which may reject asynchronously on permission /
      // adapter failures). Without the race, awaiting scanForDevices first
      // would miss the scanning=true emission, and awaiting the stream
      // first would hang if the scan never started.
      final scanFuture = deviceScanner.scanForDevices();
      // Swallow a late rejection from scanFuture if the stream wins the
      // race — otherwise Future.any leaves it as an unhandled async error.
      // A real classify-and-emit still fires via the catch below because
      // scanFuture rejects BEFORE firstWhere sees scanning=true in that
      // failure case; this only guards the already-started path.
      scanFuture.catchError((_) {});
      await Future.any<Object?>([
        deviceScanner.scanningStream.firstWhere((s) => s),
        scanFuture,
      ]);
    } catch (e) {
      sub.cancel();
      final kind = _classifyScanError(e);
      // DO NOT REORDER — same rationale as connectScale: publish idle
      // first, then _emit the error (which bypasses the phase-change
      // error-stripping gatekeeper) so the sticky error is preserved.
      _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
      _emit(ConnectionError(
        kind: kind,
        severity: ConnectionErrorSeverity.error,
        timestamp: DateTime.now().toUtc(),
        message: kind == ConnectionErrorKind.bluetoothPermissionDenied
            ? 'Bluetooth permission was denied.'
            : 'Failed to start Bluetooth scan.',
        suggestion: kind == ConnectionErrorKind.bluetoothPermissionDenied
            ? 'Grant Bluetooth permission in system settings and retry.'
            : 'Check that Bluetooth is enabled and retry.',
        details: {'exception': e.toString()},
      ));
      return;
    }

    // Past this point, scan actually started. Sticky-error environmental
    // recovery: a successful scan-start means permission and scan
    // subsystems are working again. Clear any sticky scan-related error
    // that was hanging on — _publishStatus' gatekeeper would preserve
    // it otherwise.
    final prevErr = currentStatus.error;
    if (prevErr != null &&
        (prevErr.kind == ConnectionErrorKind.scanFailed ||
            prevErr.kind == ConnectionErrorKind.bluetoothPermissionDenied)) {
      _clearError();
    }

    await deviceScanner.scanningStream.firstWhere((s) => !s);
    sub.cancel();

    // Wait for early connections to finish if started
    if (earlyMachineConnect != null) {
      try {
        await earlyMachineConnect;
      } catch (e, st) {
        // connectMachine already emitted machineConnectFailed and
        // _connectMachineTracked recorded the outcome on the tracker.
        // If an error still slipped out, log for diagnostics.
        _log.fine('Early machine connect slipped past tracker', e, st);
      }
    }

    if (earlyScaleConnect != null) {
      try {
        await earlyScaleConnect;
      } catch (e, st) {
        _log.fine('Early scale connect slipped past tracker', e, st);
      }
    }

    // Collect found devices
    final allDevices = deviceScanner.devices;
    final machines = allDevices.whereType<De1Interface>().toList();
    final scales = allDevices.whereType<Scale>().toList();

    // Ensure all final devices are tracked (in case some weren't seen mid-scan)
    for (final d in allDevices) {
      matchedDeviceResults.putIfAbsent(
        d.deviceId,
        () => _MatchedDeviceTracker(
          deviceName: d.name,
          deviceId: d.deviceId,
          deviceType: d.type,
        ),
      );
    }

    _log.fine(
      'Scan complete: ${machines.length} machines, ${scales.length} scales',
    );

    if (scaleOnly) {
      // Update found scales in status
      _publishStatus(
        currentStatus.copyWith(foundScales: scales),
      );
      // Apply scale preference policy only
      await _connectScalePhase(scales, matchedDeviceResults);
      _emitScanReport(
        scanStartTime: scanStartTime,
        matchedDeviceResults: matchedDeviceResults,
        preferredMachineId: null,
        preferredScaleId: preferredScaleId,
        terminationReason: ScanTerminationReason.completed,
      );
      return;
    }

    // Store found devices in status for UI pickers
    _publishStatus(
      currentStatus.copyWith(foundMachines: machines, foundScales: scales),
    );

    // If machine is already connected (either from before or early connect),
    // skip straight to scale phase
    if (_machineConnected) {
      _log.fine('Machine connected, proceeding to scale phase');
      await _connectScalePhase(scales, matchedDeviceResults);
      _emitScanReport(
        scanStartTime: scanStartTime,
        matchedDeviceResults: matchedDeviceResults,
        preferredMachineId: preferredMachineId,
        preferredScaleId: preferredScaleId,
        terminationReason: ScanTerminationReason.completed,
      );
      return;
    }

    // Apply machine preference policy for remaining cases
    if (preferredMachineId != null) {
      // Preferred was set but not found during scan
      if (machines.isNotEmpty) {
        _publishStatus(
          currentStatus.copyWith(
            phase: ConnectionPhase.idle,
            pendingAmbiguity: () => AmbiguityReason.machinePicker,
          ),
        );
      } else {
        _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
      }
    } else {
      // No preferred machine set
      if (machines.isEmpty) {
        _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
      } else if (machines.length == 1) {
        // Exactly one machine — auto-connect
        await _connectMachineTracked(machines.first, matchedDeviceResults);
        await _connectScalePhase(scales, matchedDeviceResults);
      } else {
        // Multiple machines — picker
        _publishStatus(
          currentStatus.copyWith(
            phase: ConnectionPhase.idle,
            pendingAmbiguity: () => AmbiguityReason.machinePicker,
          ),
        );
      }
    }

    _emitScanReport(
      scanStartTime: scanStartTime,
      matchedDeviceResults: matchedDeviceResults,
      preferredMachineId: preferredMachineId,
      preferredScaleId: preferredScaleId,
      terminationReason: ScanTerminationReason.completed,
    );
  }

  /// Stop scan early when both preferred devices are connected.
  void _checkEarlyStop(bool earlyStopEnabled) {
    if (earlyStopEnabled && _machineConnected && _scaleConnected) {
      _log.fine('Both preferred devices connected, stopping scan early');
      deviceScanner.stopScan();
    }
  }

  /// Apply scale preference policy after machine connects.
  Future<void> _connectScalePhase(
    List<Scale> scales, [
    Map<String, _MatchedDeviceTracker>? matchedDeviceResults,
  ]) async {
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
        if (matchedDeviceResults != null) {
          await _connectScaleTracked(preferred.first, matchedDeviceResults);
        } else {
          await connectScale(preferred.first);
        }
      } else if (scales.isNotEmpty) {
        // Preferred not found but others available — picker
        _log.fine('Scale phase: preferred not found, showing picker');
        _publishStatus(
          currentStatus.copyWith(
            pendingAmbiguity: () => AmbiguityReason.scalePicker,
          ),
        );
      }
    } else {
      // No preferred scale set
      if (scales.length == 1) {
        if (matchedDeviceResults != null) {
          await _connectScaleTracked(scales.first, matchedDeviceResults);
        } else {
          await connectScale(scales.first);
        }
      } else if (scales.length > 1) {
        // Multiple scales — picker
        _publishStatus(
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

    // Do not explicitly clear `error` — the gatekeeper handles it.
    _publishStatus(
      currentStatus.copyWith(
        phase: ConnectionPhase.connectingMachine,
        pendingAmbiguity: () => null,
      ),
    );

    try {
      await de1Controller.connectToDe1(machine);
      await settingsController.setPreferredMachineId(machine.deviceId);
      _machineConnected = true;
      _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.ready));
    } catch (e) {
      // Unlike connectScale, this path reverts to `idle` (not a clearing
      // phase), so the _publishStatus/_emit ordering isn't load-bearing —
      // kept consistent with connectScale for readability.
      _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
      _emit(_buildConnectError(
        kind: ConnectionErrorKind.machineConnectFailed,
        deviceId: machine.deviceId,
        deviceName: machine.name,
        message: 'Machine ${machine.name} failed to connect.',
        suggestion:
            'Make sure the DE1 is powered on and in range, then retry.',
        exception: e,
      ));
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

    // Do not explicitly clear `error` — the gatekeeper handles it.
    _publishStatus(
      currentStatus.copyWith(
        phase: ConnectionPhase.connectingScale,
        pendingAmbiguity: () => null,
      ),
    );

    try {
      await scaleController.connectToScale(scale);
      await settingsController.setPreferredScaleId(scale.deviceId);
      _scaleConnected = true;
      // Only emit ready if machine is also connected — scale alone isn't enough
      if (_machineConnected) {
        _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.ready));
      }
    } catch (e) {
      // Scale failure is non-blocking — stay at ready if machine connected, else idle.
      _publishStatus(
        currentStatus.copyWith(
          phase:
              _machineConnected ? ConnectionPhase.ready : ConnectionPhase.idle,
        ),
      );
      // DO NOT REORDER — `ready` is a clearing phase and `scaleConnectFailed`
      // is transient, so emitting first and then publishing `ready` would
      // run the error through the gatekeeper's strip rule. Publishing the
      // phase first (no error present) then calling `_emit` (bypasses the
      // gatekeeper) is the only order that keeps the error visible.
      _emit(_buildConnectError(
        kind: ConnectionErrorKind.scaleConnectFailed,
        deviceId: scale.deviceId,
        deviceName: scale.name,
        message: 'Scale ${scale.name} failed to connect.',
        suggestion: 'Wake the scale and try again. If the problem persists, '
            'toggle Bluetooth off and on.',
        exception: e,
      ));
    } finally {
      _isConnectingScale = false;
    }
  }

  /// Connect a machine and track the result for the scan report.
  Future<void> _connectMachineTracked(
    De1Interface machine,
    Map<String, _MatchedDeviceTracker> trackers,
  ) async {
    final tracker = trackers[machine.deviceId];
    if (tracker != null) {
      tracker.connectionAttempted = true;
    }
    try {
      await connectMachine(machine);
      tracker?.connectionResult = const ConnectionResult.succeeded();
    } catch (e) {
      tracker?.connectionResult = ConnectionResult.failed(e.toString());
    }
  }

  /// Connect a scale and track the result for the scan report.
  Future<void> _connectScaleTracked(
    Scale scale,
    Map<String, _MatchedDeviceTracker> trackers,
  ) async {
    final tracker = trackers[scale.deviceId];
    if (tracker != null) {
      tracker.connectionAttempted = true;
    }
    try {
      await connectScale(scale);
      tracker?.connectionResult = const ConnectionResult.succeeded();
    } catch (e) {
      tracker?.connectionResult = ConnectionResult.failed(e.toString());
    }
  }

  /// Build and emit a [ScanReport] from the collected scan data.
  void _emitScanReport({
    required DateTime scanStartTime,
    required Map<String, _MatchedDeviceTracker> matchedDeviceResults,
    required String? preferredMachineId,
    required String? preferredScaleId,
    required ScanTerminationReason terminationReason,
  }) {
    final scanDuration = DateTime.now().difference(scanStartTime);
    final matchedDevices =
        matchedDeviceResults.values.map((t) => t.toMatchedDevice()).toList();

    final report = ScanReport(
      totalBleDevicesSeen: matchedDevices.length,
      matchedDevices: matchedDevices,
      scanDuration: scanDuration,
      adapterStateAtStart: AdapterState.unknown,
      adapterStateAtEnd: AdapterState.unknown,
      scanTerminationReason: terminationReason,
      preferredMachineId: preferredMachineId,
      preferredScaleId: preferredScaleId,
    );

    _scanReportSubject.add(report);
    _log.info(_formatScanReport(report));
  }

  String _formatScanReport(ScanReport report) {
    final buf = StringBuffer('Scan report: ');
    buf.write('${report.matchedDevices.length} devices matched, ');
    buf.write('duration=${report.scanDuration.inMilliseconds}ms, ');
    buf.write('termination=${report.scanTerminationReason.name}');

    if (report.preferredMachineId != null) {
      final found = report.matchedDevices
          .any((d) => d.deviceId == report.preferredMachineId);
      buf.write(
        ', preferred machine ${report.preferredMachineId} '
        '${found ? "found" : "NOT found"}',
      );
    }
    if (report.preferredScaleId != null) {
      final found = report.matchedDevices
          .any((d) => d.deviceId == report.preferredScaleId);
      buf.write(
        ', preferred scale ${report.preferredScaleId} '
        '${found ? "found" : "NOT found"}',
      );
    }

    for (final d in report.matchedDevices) {
      buf.write('\n  ${d.deviceName} (${d.deviceId}, ${d.deviceType.name})');
      if (d.connectionAttempted) {
        final result = d.connectionResult;
        if (result == null) {
          buf.write(' — connection attempted, no result');
        } else if (result.success) {
          buf.write(' — connected');
        } else if (result.error != null) {
          buf.write(' — connection failed: ${result.error}');
        } else {
          buf.write(' — skipped');
        }
      }
    }

    return buf.toString();
  }

  Future<void> disconnectMachine() async {
    // Reset flag before disconnect to prevent the disconnect listener from
    // also emitting idle (which would cause a double emission).
    _machineConnected = false;
    _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
    final de1 = await de1Controller.de1.first;
    if (de1 != null) {
      markExpectingDisconnect(de1.deviceId);
      await de1.disconnect();
    }
  }

  Future<void> disconnectScale() async {
    try {
      final scale = scaleController.connectedScale();
      markExpectingDisconnect(scale.deviceId);
      await scale.disconnect();
    } catch (_) {
      // No scale connected — nothing to disconnect
    }
    _scaleConnected = false;
  }

  void dispose() {
    _machineDisconnectSub?.cancel();
    _scaleDisconnectSub?.cancel();
    _adapterSub?.cancel();
    for (final t in _expectingDisconnectTimers.values) {
      t.cancel();
    }
    _expectingDisconnectTimers.clear();
    _expectingDisconnectFor.clear();
    _statusSubject.close();
    _scanReportSubject.close();
  }
}

/// Mutable tracker used during a scan to accumulate connection attempt results
/// before building the immutable [MatchedDevice].
class _MatchedDeviceTracker {
  final String deviceName;
  final String deviceId;
  final device.DeviceType deviceType;
  bool connectionAttempted = false;
  ConnectionResult? connectionResult;

  _MatchedDeviceTracker({
    required this.deviceName,
    required this.deviceId,
    required this.deviceType,
  });

  MatchedDevice toMatchedDevice() => MatchedDevice(
        deviceName: deviceName,
        deviceId: deviceId,
        deviceType: deviceType,
        connectionAttempted: connectionAttempted,
        connectionResult: connectionResult,
      );
}
