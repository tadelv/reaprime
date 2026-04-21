import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlusException;
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/connection/disconnect_expectations.dart';
import 'package:reaprime/src/controllers/connection/disconnect_supervisor.dart';
import 'package:reaprime/src/controllers/connection/policy_resolver.dart';
import 'package:reaprime/src/controllers/connection/scan_orchestrator.dart';
import 'package:reaprime/src/controllers/connection/scan_report_builder.dart';
import 'package:reaprime/src/controllers/connection/status_publisher.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device_scanner.dart';
import 'package:reaprime/src/models/device/scale.dart';
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

  /// End-to-end timeout for a single `connectMachine` / `connectScale`
  /// call. Phase 1 bounded the MMR-read hang at 2s; this is the
  /// belt-and-braces that keeps any other transport-level hang from
  /// wedging `_isConnecting` (comms-harden #31). Real-hardware
  /// connect currently observes 3–10s on tablet; 30s leaves ~3x
  /// headroom for slow adapters without feeling sluggish.
  static const _connectTimeout = Duration(seconds: 30);

  // Device-connection state + unexpected-disconnect emission live on
  // DisconnectSupervisor — it owns the two stream subscribers and
  // exposes `isMachineConnected` / `isScaleConnected` as live views
  // of the source streams (no parallel flags).
  bool get _machineConnected => _disconnectSupervisor.isMachineConnected;
  bool get _scaleConnected => _disconnectSupervisor.isScaleConnected;

  late final DisconnectSupervisor _disconnectSupervisor;
  late final ScanOrchestrator _scanOrchestrator;

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
    _disconnectSupervisor = DisconnectSupervisor(
      machineStream: de1Controller.de1,
      scaleStream: scaleController.connectionState,
      statusPublisher: _statusPublisher,
      expectations: _disconnectExpectations,
      isConnectingMachine: () => _isConnectingMachine,
      isConnectingScale: () => _isConnectingScale,
      scaleLastConnectedId: () => scaleController.lastConnectedDeviceId,
      preferredScaleId: () => settingsController.preferredScaleId,
    );
    _scanOrchestrator = ScanOrchestrator(
      scanner: deviceScanner,
      statusPublisher: _statusPublisher,
      connectMachineTracked: _connectMachineTracked,
      connectScaleTracked: _connectScaleTracked,
      isMachineConnected: () => _machineConnected,
      isScaleConnected: () => _scaleConnected,
    );
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

  @visibleForTesting
  void debugNotifyScaleDisconnected(String deviceId) =>
      _disconnectSupervisor.notifyScaleDisconnected(deviceId);

  @visibleForTesting
  void debugNotifyMachineDisconnected(String deviceId) =>
      _disconnectSupervisor.notifyMachineDisconnected(deviceId);

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
    final preferredMachineId =
        scaleOnly ? null : settingsController.preferredMachineId;
    final preferredScaleId = settingsController.preferredScaleId;
    final earlyStopEnabled =
        !scaleOnly && preferredMachineId != null && preferredScaleId != null;

    final scanStartTime = DateTime.now();
    final scanRun = await _scanOrchestrator.runScan(
      preferredMachineId: preferredMachineId,
      preferredScaleId: preferredScaleId,
      earlyStopEnabled: earlyStopEnabled,
      onEarlyAttemptComplete: () => _checkEarlyStop(earlyStopEnabled),
      scanStartTime: scanStartTime,
    );
    if (scanRun == null) {
      // Scan failed catastrophically; orchestrator already emitted
      // the sticky error + phase=idle.
      return;
    }

    final machines = scanRun.machines;
    final scales = scanRun.scales;
    final scanReport = scanRun.reportBuilder;

    if (scaleOnly) {
      _publishStatus(currentStatus.copyWith(foundScales: scales));
      await _applyScalePolicy(scales, preferredScaleId, scanReport);
      _emitScanReport(
        scanReport: scanReport,
        preferredMachineId: null,
        preferredScaleId: preferredScaleId,
        terminationReason: ScanTerminationReason.completed,
      );
      return;
    }

    _publishStatus(
      currentStatus.copyWith(foundMachines: machines, foundScales: scales),
    );

    // If machine is already connected (either from before or
    // early-connect), skip straight to scale phase.
    if (_machineConnected) {
      _log.fine('Machine connected, proceeding to scale phase');
      await _applyScalePolicy(scales, preferredScaleId, scanReport);
      _emitScanReport(
        scanReport: scanReport,
        preferredMachineId: preferredMachineId,
        preferredScaleId: preferredScaleId,
        terminationReason: ScanTerminationReason.completed,
      );
      return;
    }

    // Post-scan machine policy. Early-connect already handled the
    // "preferred found during scan" happy path; what arrives here
    // is everything else.
    final machineAction = resolveMachinePolicy(
      machines: machines,
      preferredMachineId: preferredMachineId,
    );
    switch (machineAction) {
      case ConnectMachineAction(machine: final m):
        await _connectMachineTracked(m, scanReport);
        await _applyScalePolicy(scales, preferredScaleId, scanReport);
      case MachinePickerAction():
        _publishStatus(currentStatus.copyWith(
          phase: ConnectionPhase.idle,
          pendingAmbiguity: () => AmbiguityReason.machinePicker,
        ));
      case NoMachineAction():
        _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
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

  /// Apply the scale-phase policy, tracking attempts on [scanReport].
  Future<void> _applyScalePolicy(
    List<Scale> scales,
    String? preferredScaleId,
    ScanReportBuilder scanReport,
  ) async {
    if (_scaleConnected) {
      _log.fine('Scale already connected, skipping scale phase');
      return;
    }
    _log.fine(
      'Scale phase: ${scales.length} scales, preferredScaleId=$preferredScaleId',
    );
    final action = resolveScalePolicy(
      scales: scales,
      preferredScaleId: preferredScaleId,
    );
    switch (action) {
      case ConnectScaleAction(scale: final s):
        await _connectScaleTracked(s, scanReport);
      case ScalePickerAction():
        _publishStatus(currentStatus.copyWith(
          pendingAmbiguity: () => AmbiguityReason.scalePicker,
        ));
      case NoScaleAction():
        // Nothing to do — idle scale phase.
        break;
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
      await de1Controller
          .connectToDe1(machine)
          .timeout(_connectTimeout);
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
      final timedOut = e is TimeoutException;
      _emit(_buildConnectError(
        kind: ConnectionErrorKind.machineConnectFailed,
        deviceId: machine.deviceId,
        deviceName: machine.name,
        message: timedOut
            ? 'Machine ${machine.name} did not respond within '
                '${_connectTimeout.inSeconds}s.'
            : 'Machine ${machine.name} failed to connect.',
        suggestion: timedOut
            ? 'Try again. If the problem persists, power-cycle the machine.'
            : 'Make sure the DE1 is powered on and in range, then retry.',
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
      await scaleController
          .connectToScale(scale)
          .timeout(_connectTimeout);
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
      final timedOut = e is TimeoutException;
      _emit(_buildConnectError(
        kind: ConnectionErrorKind.scaleConnectFailed,
        deviceId: scale.deviceId,
        deviceName: scale.name,
        message: timedOut
            ? 'Scale ${scale.name} did not respond within '
                '${_connectTimeout.inSeconds}s.'
            : 'Scale ${scale.name} failed to connect.',
        suggestion: timedOut
            ? 'Try again. If the problem persists, power-cycle the scale.'
            : 'Wake the scale and try again. If the problem persists, '
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
    // Pre-null the supervisor's tracked de1 view so its stream listener's
    // `hadMachine` check sees "no machine was connected" by the time
    // it fires on the upcoming null emission — otherwise the supervisor
    // would emit a redundant phase=idle on top of the one below.
    _disconnectSupervisor.markMachineOffline();
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
    _disconnectSupervisor.dispose();
    _adapterSub?.cancel();
    _disconnectExpectations.dispose();
    _statusPublisher.dispose();
    _scanReportSubject.close();
  }
}

