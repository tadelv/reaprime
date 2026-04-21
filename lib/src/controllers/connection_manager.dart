import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlusException;
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/connection/disconnect_expectations.dart';
import 'package:reaprime/src/controllers/connection/scan_report_builder.dart';
import 'package:reaprime/src/controllers/connection/status_publisher.dart';
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

  final StatusPublisher _statusPublisher = StatusPublisher();

  final BehaviorSubject<ScanReport> _scanReportSubject = BehaviorSubject();

  Stream<ConnectionStatus> get status => _statusPublisher.stream;
  ConnectionStatus get currentStatus => _statusPublisher.current;

  /// The most recent scan report, or null if no scan has completed yet.
  ScanReport? get lastScanReport => _scanReportSubject.valueOrNull;

  /// Emits a [ScanReport] after each scan + connection cycle completes.
  Stream<ScanReport> get scanReportStream => _scanReportSubject.stream;

  // Re-entry guards for the respective async methods. These prevent
  // concurrent calls from racing each other; they do NOT duplicate
  // device-connection state.
  bool _isConnecting = false;
  bool _isConnectingMachine = false;
  bool _isConnectingScale = false;

  // Device-connection state tracked directly from the streams that own
  // it. `_listenForDisconnects` keeps these in sync; nothing else
  // mutates them, so they cannot drift from the source of truth.
  // Replaces the previous `_machineConnected` / `_scaleConnected`
  // parallel flags (comms-harden #4, #6).
  De1Interface? _latestDe1;
  device.ConnectionState _latestScaleState =
      device.ConnectionState.discovered;

  bool get _machineConnected => _latestDe1 != null;
  bool get _scaleConnected =>
      _latestScaleState == device.ConnectionState.connected;

  StreamSubscription? _machineDisconnectSub;
  StreamSubscription? _scaleDisconnectSub;
  StreamSubscription<AdapterState>? _adapterSub;

  final DisconnectExpectations _disconnectExpectations =
      DisconnectExpectations();

  /// Completer shared by all `connect(scaleOnly: true)` callers that
  /// arrive while another connect is already running. Drained in the
  /// outer connect()'s finally block (comms-harden #9).
  Completer<void>? _queuedScaleOnly;

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
      final hadMachine = _latestDe1 != null;
      _latestDe1 = de1;
      if (de1 != null) {
        lastKnownMachineId = de1.deviceId;
        return;
      }
      if (hadMachine && !_isConnectingMachine) {
        _log.fine('Machine disconnected');
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
      final wasConnected =
          _latestScaleState == device.ConnectionState.connected;
      _latestScaleState = state;
      _log.fine("scale connection update: ${state.name}");
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

  /// Emit a [ConnectionError] onto the status stream without changing
  /// the current phase. Thin proxy over [StatusPublisher.emitError] so
  /// every outbound update goes through the same gatekeeper
  /// (comms-harden #8).
  void _emit(ConnectionError err) => _statusPublisher.emitError(err);

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

  /// Clears the current error. Proxy over [StatusPublisher.clearError]
  /// — called by environmental recovery handlers (adapter on,
  /// permission granted).
  void _clearError() => _statusPublisher.clearError();

  /// Publish a new [ConnectionStatus] with sticky/transient error
  /// gating. Proxy over [StatusPublisher.publish].
  void _publishStatus(ConnectionStatus next) => _statusPublisher.publish(next);

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
    _statusPublisher.publish(currentStatus.copyWith(phase: phase));
  }

  /// Call immediately before an app-initiated disconnect. The next
  /// `disconnected` event for `deviceId` will be treated as expected and
  /// will not emit an error. A 10-second TTL safety timer clears the
  /// expectation if the disconnect event never arrives.
  void markExpectingDisconnect(String deviceId) {
    _disconnectExpectations.mark(deviceId);
  }

  bool _consumeExpectingDisconnect(String deviceId) =>
      _disconnectExpectations.consume(deviceId);

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
  ///
  /// Concurrency: a `scaleOnly` call that arrives while another `connect`
  /// is already running is queued and replayed after the in-flight call
  /// completes. Multiple queued `scaleOnly` calls coalesce into one
  /// replay and share the same returned Future. Non-`scaleOnly` calls
  /// during an in-flight connect are still dropped silently
  /// (comms-harden #9).
  Future<void> connect({bool scaleOnly = false}) async {
    if (_isConnecting) {
      if (scaleOnly) {
        final completer = _queuedScaleOnly ??= Completer<void>();
        return completer.future;
      }
      return;
    }

    // Run the current call, then drain any scale-only requests that
    // queued up while it was running. The drain runs in a `finally`
    // so stranded callers get woken up even if the initial call
    // throws.
    try {
      await _executeConnect(scaleOnly);
    } finally {
      while (_queuedScaleOnly != null) {
        final drain = _queuedScaleOnly!;
        _queuedScaleOnly = null;
        try {
          await _executeConnect(true);
          drain.complete();
        } catch (e, st) {
          drain.completeError(e, st);
        }
      }
    }
  }

  /// One connect iteration — sets `_isConnecting` for the duration so
  /// the concurrency guard in [connect] sees the in-flight state.
  Future<void> _executeConnect(bool scaleOnly) async {
    _isConnecting = true;
    try {
      await _connectImpl(scaleOnly: scaleOnly);
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _connectImpl({required bool scaleOnly}) async {
    final scanStartTime = DateTime.now();

    // Per-scan builder that accumulates attempted/succeeded/failed
    // results and emits the final ScanReport.
    final scanReport = ScanReportBuilder(scanStartTime: scanStartTime);

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
    //
    // Each early-connect is tracked as an explicit (started, pending)
    // pair rather than a nullable Future-as-flag (comms-harden #7, #18).
    // `started` stops the listener from firing a second attempt;
    // `pending` is the awaitable for post-scan synchronisation.
    var earlyMachineStarted = false;
    Future<void>? earlyMachinePending;
    var earlyScaleStarted = false;
    Future<void>? earlyScalePending;
    // The listener only handles early-connect triggering. Per-device
    // tracker entries are seeded once from the authoritative
    // ScanResult after the scan completes (comms-harden #17).
    final sub = deviceScanner.deviceStream.skip(1).listen((devices) {
      if (preferredMachineId != null &&
          !_machineConnected &&
          !earlyMachineStarted) {
        final match =
            devices
                .whereType<De1Interface>()
                .where((m) => m.deviceId == preferredMachineId)
                .firstOrNull;
        if (match != null) {
          _log.fine('Preferred machine found during scan, connecting early');
          earlyMachineStarted = true;
          // Seed the tracker now so the connection attempt + result
          // land on the right entry; the post-scan seed below is
          // idempotent and leaves this seed intact.
          scanReport.seed(match);
          earlyMachinePending = _connectMachineTracked(
            match,
            scanReport,
          ).then((_) {
            _checkEarlyStop(earlyStopEnabled);
          });
        }
      }

      if (preferredScaleId != null &&
          !_scaleConnected &&
          !earlyScaleStarted) {
        final match =
            devices
                .whereType<Scale>()
                .where((m) => m.deviceId == preferredScaleId)
                .firstOrNull;
        if (match != null) {
          _log.fine('Preferred scale found during scan, connecting early');
          earlyScaleStarted = true;
          scanReport.seed(match);
          earlyScalePending = _connectScaleTracked(
            match,
            scanReport,
          ).then((_) {
            _checkEarlyStop(earlyStopEnabled);
          });
        }
      }
    });

    // Run full unfiltered scan. The scanner awaits every service's scan
    // and returns a ScanResult carrying per-service failures; only a
    // catastrophic, scan-wide error throws out of the Future. Classify
    // any such throw into bluetoothPermissionDenied or scanFailed —
    // both are sticky errors that survive phase transitions.
    final ScanResult scanResult;
    try {
      scanResult = await deviceScanner.scanForDevices();
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
    sub.cancel();

    // Sticky-error environmental recovery: reaching a completed scan
    // means permission and scan subsystems are working again. Clear
    // any sticky scan-related error that was hanging on — the
    // _publishStatus gatekeeper would preserve it otherwise.
    //
    // TODO(comms-phase-2 PR B): consult scanResult.failedServices to
    // surface per-transport failures (e.g. BLE permission denied while
    // serial succeeded). Deferred to the error-path unification pass.
    final prevErr = currentStatus.error;
    if (prevErr != null &&
        (prevErr.kind == ConnectionErrorKind.scanFailed ||
            prevErr.kind == ConnectionErrorKind.bluetoothPermissionDenied)) {
      _clearError();
    }

    // Wait for early connections to finish if started
    if (earlyMachinePending != null) {
      try {
        await earlyMachinePending;
      } catch (e, st) {
        // connectMachine already emitted machineConnectFailed and
        // _connectMachineTracked recorded the outcome on the tracker.
        // If an error still slipped out, log for diagnostics.
        _log.fine('Early machine connect slipped past tracker', e, st);
      }
    }

    if (earlyScalePending != null) {
      try {
        await earlyScalePending;
      } catch (e, st) {
        _log.fine('Early scale connect slipped past tracker', e, st);
      }
    }

    // Collect found devices from the authoritative ScanResult rather
    // than re-reading `deviceScanner.devices`. This is the single
    // source of truth for "what the scan turned up" (comms-harden #17).
    final allDevices = scanResult.matchedDevices;
    final machines = allDevices.whereType<De1Interface>().toList();
    final scales = allDevices.whereType<Scale>().toList();

    // Seed tracker entries for every device in the final snapshot.
    // Early-connect paths pre-seeded their targets in the stream
    // listener; ScanReportBuilder.seed is idempotent so those entries
    // stay intact.
    for (final d in allDevices) {
      scanReport.seed(d);
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
      await _connectScalePhase(scales, scanReport);
      _emitScanReport(
        scanReport: scanReport,
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
      await _connectScalePhase(scales, scanReport);
      _emitScanReport(
        scanReport: scanReport,
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
        await _connectMachineTracked(machines.first, scanReport);
        await _connectScalePhase(scales, scanReport);
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
      scanReport: scanReport,
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

  /// Apply scale preference policy after machine connects. If
  /// [scanReport] is provided, the attempt outcome is recorded on it;
  /// otherwise a bare `connectScale` is used (the non-scan-driven
  /// paths don't need tracker bookkeeping).
  Future<void> _connectScalePhase(
    List<Scale> scales, [
    ScanReportBuilder? scanReport,
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
        if (scanReport != null) {
          await _connectScaleTracked(preferred.first, scanReport);
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
        if (scanReport != null) {
          await _connectScaleTracked(scales.first, scanReport);
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
      // `_latestDe1` is populated by the de1Controller.de1 stream
      // listener; by the time connectToDe1 returns, that microtask has
      // fired so `_machineConnected` (which reads `_latestDe1`) is true.
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
      // `_latestScaleState` is populated by the scaleController
      // listener; `_scaleConnected` reads from it.
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

  /// Connect a machine and record the attempt outcome on the scan
  /// report builder.
  Future<void> _connectMachineTracked(
    De1Interface machine,
    ScanReportBuilder scanReport,
  ) async {
    scanReport.markAttempted(machine.deviceId);
    try {
      await connectMachine(machine);
      scanReport.recordResult(
        machine.deviceId,
        const ConnectionResult.succeeded(),
      );
    } catch (e) {
      scanReport.recordResult(
        machine.deviceId,
        ConnectionResult.failed(e.toString()),
      );
    }
  }

  /// Connect a scale and record the attempt outcome on the scan
  /// report builder.
  Future<void> _connectScaleTracked(
    Scale scale,
    ScanReportBuilder scanReport,
  ) async {
    scanReport.markAttempted(scale.deviceId);
    try {
      await connectScale(scale);
      scanReport.recordResult(
        scale.deviceId,
        const ConnectionResult.succeeded(),
      );
    } catch (e) {
      scanReport.recordResult(
        scale.deviceId,
        ConnectionResult.failed(e.toString()),
      );
    }
  }

  /// Build a [ScanReport] from [scanReport] and publish it on the
  /// scan-report stream + log the human-readable form.
  void _emitScanReport({
    required ScanReportBuilder scanReport,
    required String? preferredMachineId,
    required String? preferredScaleId,
    required ScanTerminationReason terminationReason,
  }) {
    final report = scanReport.build(
      preferredMachineId: preferredMachineId,
      preferredScaleId: preferredScaleId,
      terminationReason: terminationReason,
    );
    _scanReportSubject.add(report);
    _log.info(ScanReportBuilder.format(report));
  }

  Future<void> disconnectMachine() async {
    // Pre-null the tracked-latest view so the de1 stream listener's
    // `hadMachine` check sees "no machine was connected" by the time
    // it fires on the upcoming null emission — otherwise the listener
    // would emit a redundant phase=idle on top of the one below.
    _latestDe1 = null;
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
    // No explicit reset of `_latestScaleState` — the scale
    // connectionState listener will observe the upcoming disconnected
    // emission and update it.
  }

  void dispose() {
    _machineDisconnectSub?.cancel();
    _scaleDisconnectSub?.cancel();
    _adapterSub?.cancel();
    _disconnectExpectations.dispose();
    _statusPublisher.dispose();
    _scanReportSubject.close();
  }
}

