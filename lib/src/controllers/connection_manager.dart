import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/connection/attach_reconnect_coordinator.dart';
import 'package:reaprime/src/controllers/connection/disconnect_expectations.dart';
import 'package:reaprime/src/controllers/connection/disconnect_supervisor.dart';
import 'package:reaprime/src/controllers/connection/policy_resolver.dart';
import 'package:reaprime/src/controllers/connection/scale_watch.dart';
import 'package:reaprime/src/controllers/connection/scan_orchestrator.dart';
import 'package:reaprime/src/controllers/connection/scan_report_builder.dart';
import 'package:reaprime/src/controllers/connection/status_publisher.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/remembered_devices_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/transport/ble_connect_exception.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_virtual_scale.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_attach_notifier.dart';
import 'package:reaprime/src/models/device/device_scanner.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/scan_report.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';

/// High-level phase of the [ConnectionManager] state machine.
///
/// Transitions are documented in `doc/DeviceManagement.md` →
/// "Phase transitions" (comms-harden #30). All writes route through
/// `StatusPublisher.publish`.
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

  /// Remembered-device registry for quick-connect. Nullable so existing
  /// tests and wiring without a registry still work — null disables
  /// quick-connect and falls through to the scan path.
  final RememberedDevicesController? rememberedDevices;

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
  bool _activeScaleOnlyScan = false;

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
  bool get _scaleReconnectBlockedByPowerMode =>
      settingsController.scalePowerMode == ScalePowerMode.disconnect &&
      _latestMachineState == MachineState.sleeping;

  late final DisconnectSupervisor _disconnectSupervisor;
  late final ScanOrchestrator _scanOrchestrator;
  late final ScaleWatch _scaleWatch;

  StreamSubscription<AdapterState>? _adapterSub;
  AttachReconnectCoordinator? _attachReconnectCoordinator;

  final DisconnectExpectations _disconnectExpectations =
      DisconnectExpectations();

  /// Completer shared by all `connect(scaleOnly: true)` callers that
  /// arrive while another connect is already running. Drained in the
  /// outer connect()'s finally block (comms-harden #9).
  Completer<void>? _queuedScaleOnly;

  /// Deferred scale-only rescan armed when the preferred machine
  /// connects but no preferred scale is configured. The initial scan
  /// stops the instant the machine connects (see [_checkEarlyStop]), so
  /// a scale that advertises a beat later is missed; this recovers it.
  Timer? _deferredScaleScan;

  /// Preferred-scale reconnect retry while a machine is connected but the
  /// configured scale is missing. BLE advertisements are only observed during
  /// scans, so this gives a powered-on scale a chance to appear without user
  /// interaction.
  Timer? _preferredScaleReconnect;

  /// Consecutive scale-reconnect failures for exponential backoff.
  /// Reset on successful scale connect or machine disconnect.
  int _scaleReconnectFailures = 0;

  /// Compute exponential backoff delay: 5s → 10s → 20s → 40s → 60s cap.
  Duration get _scaleReconnectBackoff {
    final base = 5;
    final seconds = base * (1 << _scaleReconnectFailures).clamp(1, 12);
    // 5*1=5, 5*2=10, 5*4=20, 5*8=40, 5*12=60
    return Duration(seconds: seconds.clamp(5, 60));
  }

  /// Machine auto-reconnect (recovery mode). Armed by an *unexpected*
  /// machine disconnect when a preferred machine is configured; retries
  /// full `connect()` scans with the same 5s→60s backoff the scale loop
  /// uses, and reschedules itself after every attempt that ends without
  /// a machine. Cleared on machine connect, deliberate disconnect, and
  /// dispose. Motivated by a power-outage incident where the app sat
  /// "disconnected" for six hours because nothing ever rescanned — see
  /// doc/plans/machine-connection-recovery.md.
  bool _machineRecoveryActive = false;
  Timer? _machineReconnect;
  int _machineReconnectFailures = 0;

  /// Base delay for the machine-reconnect backoff. Overridable in tests.
  @visibleForTesting
  Duration machineReconnectBaseDelay = const Duration(seconds: 5);

  Duration get _machineReconnectBackoff {
    final multiplier = (1 << _machineReconnectFailures).clamp(1, 12);
    final delay = machineReconnectBaseDelay * multiplier;
    const cap = Duration(seconds: 60);
    return delay > cap ? cap : delay;
  }

  MachineState? _latestMachineState;
  StreamSubscription<MachineSnapshot>? _machineSnapshotSub;

  /// Snapshot-staleness watchdog: if a connected machine stops pushing
  /// snapshot frames for this long, the push channel is presumed dead
  /// (live-link + dead-push — the field incident of 2026-07-07). A clean
  /// forced reconnect re-establishes notifications. See Fix #1.
  /// Overridable in tests so the watchdog can be driven without a real
  /// 10s wait.
  @visibleForTesting
  Duration snapshotStalenessTimeout = const Duration(seconds: 10);

  Timer? _stateWatchdog;
  int _watchdogGeneration = 0;

  /// Number of times the staleness watchdog forced a machine reconnect.
  /// Incremented once per force action — tests assert on this instead of
  /// driving the full disconnect+connect cycle through fake_async.
  @visibleForTesting
  int snapshotStalenessReconnects = 0;

  /// Set true by [_checkEarlyStop] when it actually cut the scan short on
  /// machine-connect with no preferred scale. Distinguishes that case
  /// from a full scan that simply completed without a scale — only the
  /// former warrants a deferred rescan. Reset at the start of each full
  /// connect.
  bool _earlyStopFired = false;

  /// Delay before the deferred scale rescan fires. Mirrors the post-wake
  /// reconnect in `De1StateManager`: starting another scan immediately
  /// after the DE1 connect starves the shared Android BLE radio and
  /// risks LINK_SUPERVISION_TIMEOUT on the DE1, so we let the link
  /// stabilise first. Overridable in tests to avoid a real wait.
  @visibleForTesting
  Duration deferredScaleScanDelay = const Duration(seconds: 3);

  /// Whether the scanner supports the persistent background scale watch
  /// (Android). De1StateManager consults this to skip its wake-time
  /// scale-only burst scan when the watch already covers reacquisition.
  bool get supportsBackgroundScaleWatch => deviceScanner.supportsBackgroundWatch;

  ConnectionManager({
    required this.deviceScanner,
    required this.de1Controller,
    required this.scaleController,
    required this.settingsController,
    this.rememberedDevices,
    Duration deviceAttachSettleDelay = const Duration(milliseconds: 500),
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
      onMachineConnected: _handleMachineConnected,
      onMachineDisconnected: _handleMachineDisconnected,
      onUnexpectedMachineDisconnect: _startMachineRecovery,
      onScaleConnected: _cancelScaleReacquisition,
      onScaleDisconnected: _ensureScaleReacquisition,
    );
    _scaleWatch = ScaleWatch(
      scanner: deviceScanner,
      // The Bengle clause covers arm time AND the post-connect
      // continuation: a Bengle's integrated scale owns the scale slot
      // (the rule _runScalePhase enforces on the burst path), so a
      // refused external-scale sighting must end the watch cycle, not
      // restart the scan indefinitely.
      shouldWatch: () =>
          _shouldRetryPreferredScale() &&
          _disconnectSupervisor.latestMachine is! BengleInterface,
      preferredScaleId: () => settingsController.preferredScaleId,
      connectScale: _connectScaleFromWatch,
      onWatchUnavailable: _maybeSchedulePreferredScaleReconnect,
    );
    _scanOrchestrator = ScanOrchestrator(
      scanner: deviceScanner,
      statusPublisher: _statusPublisher,
      connectMachineTracked: _connectMachineTracked,
      connectScaleTracked: _connectScaleTrackedGated,
      isMachineConnected: () => _machineConnected,
      isScaleConnected: () => _scaleConnected,
    );
    _listenForAdapter();
    final attachNotifier = deviceScanner is DeviceAttachNotifier
        ? deviceScanner as DeviceAttachNotifier
        : null;
    _attachReconnectCoordinator = attachNotifier == null
        ? null
        : AttachReconnectCoordinator(
            attachEvents: attachNotifier.deviceAttached,
            settleDelay: deviceAttachSettleDelay,
            shouldAttempt: _shouldAttemptAttachReconnect,
            attempt: _attemptAttachReconnect,
            recover: _ensureMachineRecoveryArmed,
          );
  }

  bool _shouldAttemptAttachReconnect() {
    final preferredMachineId = settingsController.preferredMachineId;
    return !_machineConnected &&
        preferredMachineId != null &&
        preferredMachineId.isNotEmpty;
  }

  Future<bool> _attemptAttachReconnect() async {
    _machineReconnect?.cancel();
    _machineReconnect = null;
    _machineReconnectFailures = 0;
    try {
      await connect();
    } catch (e, st) {
      _log.fine('Attach-triggered connect failed', e, st);
    }
    return _machineConnected;
  }

  void _ensureMachineRecoveryArmed() {
    if (!_shouldAttemptAttachReconnect()) return;
    if (!_machineRecoveryActive) {
      _machineRecoveryActive = true;
    }
    _maybeScheduleMachineReconnect();
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
      } else if (state == AdapterState.unauthorized) {
        _emit(ConnectionError(
          kind: ConnectionErrorKind.bluetoothPermissionDenied,
          severity: ConnectionErrorSeverity.error,
          timestamp: DateTime.now().toUtc(),
          message: 'Bluetooth permission was denied.',
          suggestion:
              'Go to Settings > Privacy & Security > Bluetooth and enable '
              'permission for Decent.app.',
        ));
      } else if (state == AdapterState.poweredOn &&
          (currentStatus.error?.kind == ConnectionErrorKind.adapterOff ||
              currentStatus.error?.kind ==
                  ConnectionErrorKind.bluetoothPermissionDenied)) {
        _clearError();
      }
    });
  }

  /// Emit a [ConnectionError] onto the status stream without changing
  /// the current phase. Thin proxy over [StatusPublisher.emitError] so
  /// every outbound update goes through the same gatekeeper
  /// (comms-harden #8).
  void _emit(ConnectionError err) => _statusPublisher.emitError(err);

  /// Surface an out-of-band [ConnectionError] on the status stream —
  /// for collaborators outside the connect flow (`WorkflowDeviceSync`'s
  /// profile-upload failure). Routes through the same
  /// [StatusPublisher] gatekeeper as internal emits.
  void reportError(ConnectionError err) => _emit(err);

  /// Clear the current status error iff it is of [kind]. Lets an
  /// out-of-band reporter retract its own error on recovery without
  /// stomping an unrelated one that has since replaced it.
  void clearErrorOfKind(String kind) {
    if (currentStatus.error?.kind == kind) {
      _clearError();
    }
  }

  /// Build a [ConnectionError] for a failed connect attempt. Pulls out
  /// `ble_code` / `ble_description` when the caught exception is a
  /// [BleConnectException] (the domain type transports map their native
  /// BLE error into); otherwise stashes the stringified exception under
  /// `details.exception`.
  ConnectionError _buildConnectError({
    required String kind,
    required String deviceId,
    required String deviceName,
    required String message,
    String? suggestion,
    required Object exception,
  }) {
    Map<String, dynamic>? details;
    if (exception is BleConnectException) {
      final map = <String, dynamic>{
        if (exception.code != null) 'ble_code': exception.code,
        if (exception.description != null)
          'ble_description': exception.description,
        if (exception.function != null) 'ble_function': exception.function,
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
  /// Early-stop: if a preferred machine is set, the scan stops early once
  /// the machine connects (when no preferred scale is configured) or once
  /// both preferred devices connect (when a preferred scale is set). With
  /// no preferred machine, the full scan runs to discover all devices.
  /// When the scan stops on machine-connect with no preferred scale, a
  /// deferred (fire-and-forget) scale-only rescan is armed to pick up a
  /// scale that advertised after the early stop — see
  /// [_maybeArmDeferredScaleScan].
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
    if (scaleOnly) {
      _activeScaleOnlyScan = true;
    }
    try {
      await _connectImpl(scaleOnly: scaleOnly);
    } finally {
      if (scaleOnly) {
        _activeScaleOnlyScan = false;
      }
      _isConnecting = false;
    }
  }

  /// Attempt to quick-connect the preferred machine from remembered
  /// metadata. Returns the adopted [De1Interface], or null on failure.
  Future<De1Interface?> _tryQuickConnectMachine() async {
    final registry = rememberedDevices;
    if (registry == null) return null;
    final machineId = settingsController.preferredMachineId;
    if (machineId == null || machineId.isEmpty) return null;
    final remembered = registry.remembered
        .firstWhereOrNull((d) => d.id == machineId);
    if (remembered == null) return null;
    try {
      final device = await deviceScanner.tryQuickConnect(remembered);
      if (device is De1Interface) {
        de1Controller.adoptDevice(device);
        // Phase (connectingMachine) was already published by _connectImpl
        // before calling this method — no need to re-publish here.
        _log.info('Quick-connect: machine adopted (${device.deviceId})');
        return device;
      }
    } catch (e, st) {
      _log.warning('Quick-connect: machine attempt failed', e, st);
    }
    return null;
  }

  Future<void> _connectImpl({required bool scaleOnly}) async {
    // Also disarms the watch: during a full scan EarlyConnectWatcher
    // observes the same deviceStream and owns preferred-scale connects —
    // a live watch would race it. Re-armed at the end-of-connect sites.
    _cancelScaleReacquisition();
    if (scaleOnly && _scaleReconnectBlockedByPowerMode) {
      _log.fine(
        'Skipping scale-only scan while machine is sleeping and scale '
        'power mode is disconnect',
      );
      return;
    }
    if (!scaleOnly) {
      // A fresh full connect supersedes any pending deferred rescan.
      _deferredScaleScan?.cancel();
      _deferredScaleScan = null;
      _earlyStopFired = false;
    }

    // Quick-connect: try direct connection to the preferred machine from
    // remembered metadata. Scales are excluded — the machine-only critical
    // path publishes ready immediately after adoption, then kicks off
    // background scale discovery.
    if (!scaleOnly && rememberedDevices != null) {
      _publishStatus(currentStatus.copyWith(
          phase: ConnectionPhase.connectingMachine));
      final qcMachine = await _tryQuickConnectMachine();
      if (qcMachine != null) {
        _log.info('Quick-connect: machine connected, proceeding to ready');
        if (qcMachine is BengleInterface) {
          await _attachBengleVirtualScale(qcMachine);
        } else if (!_scaleConnected) {
          if (settingsController.preferredScaleId != null) {
            // Route through the reacquisition selector: on watch-capable
            // platforms the background scale watch (also armed by the
            // machine-connected handler) owns this — scheduling the
            // legacy backoff here would run radio-starving bursts
            // alongside it.
            _ensureScaleReacquisition();
          } else {
            _armPostQuickConnectScaleScan();
          }
        }
        _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.ready));
        return;
      }
    }

    final preferredMachineId =
        scaleOnly ? null : settingsController.preferredMachineId;
    final preferredScaleId = settingsController.preferredScaleId;
    // Early stop is enabled for any full (non-scaleOnly) connect.
    // Previously gated on preferredMachineId != null, which meant
    // auto-discovered machines never stopped the scan early even
    // with both devices found and connected.
    final earlyStopEnabled = !scaleOnly;

    final scanStartTime = DateTime.now();

    // Build a filtered scan for Android scaleOnly path to bypass
    // background throttling. Full connect stays unfiltered.
    final scaleFilter = scaleOnly && Platform.isAndroid
        ? ScanFilter(
            preferredDeviceId: preferredScaleId,
            deviceTypes: {DeviceType.scale},
          )
        : null;

    final scanRun = await _scanOrchestrator.runScan(
      preferredMachineId: preferredMachineId,
      preferredScaleId: preferredScaleId,
      earlyStopEnabled: earlyStopEnabled,
      onEarlyAttemptComplete: () => _checkEarlyStop(earlyStopEnabled),
      scanStartTime: scanStartTime,
      scaleFilter: scaleFilter,
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
      await _runScalePhase(
        _disconnectSupervisor.latestMachine,
        scales,
        preferredScaleId,
        scanReport,
      );
      // runScan published `scanning`. `connectScale` resolves the phase
      // to `ready` when a scale connects; when the scale phase was a
      // no-op (no scale found) settle it from machine state so the UI
      // doesn't stay stuck on `scanning`.
      if (currentStatus.phase == ConnectionPhase.scanning) {
        _publishStatus(currentStatus.copyWith(
          phase:
              _machineConnected ? ConnectionPhase.ready : ConnectionPhase.idle,
        ));
      }
      _emitScanReport(
        scanReport: scanReport,
        preferredMachineId: null,
        preferredScaleId: preferredScaleId,
        terminationReason: ScanTerminationReason.completed,
      );
      _ensureScaleReacquisition();
      return;
    }

    _publishStatus(
      currentStatus.copyWith(foundMachines: machines, foundScales: scales),
    );

    // If machine is already connected (either from before or
    // early-connect), skip straight to scale phase.
    if (_machineConnected) {
      _log.fine('Machine connected, proceeding to scale phase');
      await _runScalePhase(
        _disconnectSupervisor.latestMachine,
        scales,
        preferredScaleId,
        scanReport,
      );
      _maybeArmDeferredScaleScan();
      _ensureScaleReacquisition();
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
        await _runScalePhase(m, scales, preferredScaleId, scanReport);
        _maybeArmDeferredScaleScan();
        _ensureScaleReacquisition();
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

  /// Stop scan early when all preferred devices are connected.
  ///
  /// Three branches ordered from most-specific to least:
  /// 1. Preferred machine + preferred scale → both must be connected.
  /// 2. Preferred machine only → stop on machine connect.
  /// 3. No preferences → stop when at least one machine + one scale
  ///    are connected (the common auto-discovered case).
  void _checkEarlyStop(bool earlyStopEnabled) {
    if (!earlyStopEnabled) return;
    final preferredMachineId = settingsController.preferredMachineId;
    final preferredScaleId = settingsController.preferredScaleId;
    if (preferredMachineId != null && preferredScaleId != null) {
      // Both preferred — wait for both.
      if (_machineConnected && _scaleConnected) {
        _log.fine('Both preferred devices connected, stopping scan early');
        _earlyStopFired = true;
        deviceScanner.stopScan();
      }
    } else if (preferredMachineId != null) {
      // Machine only — stop on machine connect.
      if (_machineConnected) {
        _log.fine(
          'Preferred machine connected (no preferred scale), '
          'stopping scan early',
        );
        _earlyStopFired = true;
        deviceScanner.stopScan();
      }
    } else if (preferredScaleId != null) {
      // Scale only (auto-discovered machine) — stop when both connect.
      if (_machineConnected && _scaleConnected) {
        _log.fine(
          'Preferred scale connected (auto machine), stopping scan early',
        );
        _earlyStopFired = true;
        deviceScanner.stopScan();
      }
    } else {
      // No preferences — stop when at least one of each type connects.
      if (_machineConnected && _scaleConnected) {
        _log.fine(
          'Machine and scale connected (no preferences), stopping scan early',
        );
        _earlyStopFired = true;
        deviceScanner.stopScan();
      }
    }
  }

  /// Arm a deferred scale-only scan after machine quick-connect when the
  /// user has no preferred scale configured. Unlike
  /// [_maybeArmDeferredScaleScan], this path is independent of
  /// [_earlyStopFired] — quick-connect skips the scan entirely, so there
  /// is no early-stop flag to gate on.
  void _armPostQuickConnectScaleScan() {
    if (_scaleConnected) return;
    if (_scaleReconnectBlockedByPowerMode) return;
    _log.fine(
      'Quick-connected machine without a scale; '
      'arming deferred scale scan in ${deferredScaleScanDelay.inSeconds}s',
    );
    _deferredScaleScan?.cancel();
    _deferredScaleScan = Timer(deferredScaleScanDelay, () {
      _deferredScaleScan = null;
      if (_scaleConnected) return;
      if (!_machineConnected || _scaleReconnectBlockedByPowerMode) return;
      connect(scaleOnly: true);
    });
  }

  /// Compensate for [_checkEarlyStop] cutting the scan short. When a
  /// preferred machine is configured but no preferred scale is, the scan
  /// stops the instant the machine connects — a scale that advertises a
  /// beat later would never reach the scale phase. If we land here with
  /// the machine connected but no scale, arm a deferred scale-only rescan
  /// to pick it up. Fire-and-forget, mirroring the post-wake reconnect in
  /// `De1StateManager` — the machine is already `ready` and usable; the
  /// scale connects in the background if one shows up.
  ///
  /// Gated on [_earlyStopFired] — the scan was *actually* cut short on
  /// machine-connect. A full scan that ran to completion already saw
  /// every scale that advertised, so it never arms a (pointless) rescan,
  /// even when a preferred machine is set but resolved post-scan.
  void _maybeArmDeferredScaleScan() {
    if (!_earlyStopFired) return;
    if (!_machineConnected || _scaleConnected) return;
    if (_scaleReconnectBlockedByPowerMode) return;
    _log.fine(
      'Machine connected without a scale after an early stop; '
      'arming deferred scale rescan in ${deferredScaleScanDelay.inSeconds}s',
    );
    _deferredScaleScan?.cancel();
    _deferredScaleScan = Timer(deferredScaleScanDelay, () {
      _deferredScaleScan = null;
      if (_scaleConnected) return; // a scale arrived in the meantime
      if (!_machineConnected || _scaleReconnectBlockedByPowerMode) return;
      connect(scaleOnly: true); // fire-and-forget
    });
  }

  /// Route scale reacquisition to the persistent background watch when
  /// the scanner supports it (Android), else to the legacy backoff-burst
  /// loop. Every former `_maybeSchedulePreferredScaleReconnect` call
  /// site goes through here; the legacy loop also remains the fallback
  /// when the watch fails to start (see `onWatchUnavailable`).
  void _ensureScaleReacquisition() {
    if (deviceScanner.supportsBackgroundWatch) {
      // The watch's shouldWatch gate covers the full arming policy,
      // including the Bengle integrated-scale rule.
      unawaited(_scaleWatch.arm());
    } else {
      _maybeSchedulePreferredScaleReconnect();
    }
  }

  void _cancelScaleReacquisition() {
    unawaited(_scaleWatch.disarm());
    _cancelPreferredScaleReconnect();
  }

  /// Watch-driven connects bypass `_runScalePhase`, so the Bengle rule
  /// is re-applied here for sightings that land after the watch armed
  /// but once a Bengle has become the machine.
  Future<void> _connectScaleFromWatch(Scale scale) async {
    if (_disconnectSupervisor.latestMachine is BengleInterface) {
      _log.fine(
        'Ignoring watch scale sighting ${scale.deviceId}: '
        'Bengle integrated scale owns the slot',
      );
      return;
    }
    await connectScale(scale);
  }

  void _maybeSchedulePreferredScaleReconnect() {
    if (_preferredScaleReconnect != null) return;
    if (!_shouldRetryPreferredScale()) return;
    final delay = _scaleReconnectBackoff;
    _scaleReconnectFailures++;
    _log.fine(
      'Preferred scale is missing (failure #$_scaleReconnectFailures); '
      'retrying scale scan in ${delay.inSeconds}s',
    );
    _preferredScaleReconnect = Timer(delay, () {
      _preferredScaleReconnect = null;
      if (!_shouldRetryPreferredScale()) return;
      connect(scaleOnly: true); // fire-and-forget
    });
  }

  bool _shouldRetryPreferredScale() {
    return _machineConnected &&
        !_scaleConnected &&
        settingsController.preferredScaleId != null &&
        !_scaleReconnectBlockedByPowerMode;
  }

  void _cancelPreferredScaleReconnect() {
    _preferredScaleReconnect?.cancel();
    _preferredScaleReconnect = null;
    _scaleReconnectFailures = 0;
  }

  void _handleMachineConnected() {
    _stopMachineRecovery();
    _watchConnectedMachineState();
    _ensureScaleReacquisition();
  }

  void _handleMachineDisconnected() {
    // Deliberate disconnects route only through here (disconnectMachine
    // pre-nulls the supervisor view), so recovery stays off for them.
    // For unexpected drops the supervisor fires
    // [_startMachineRecovery] right after this cleanup.
    _stopMachineRecovery();
    _stopWatchingConnectedMachineState();
    _deferredScaleScan?.cancel();
    _deferredScaleScan = null;
    _cancelScaleReacquisition();
    if (_activeScaleOnlyScan) {
      deviceScanner.stopScan();
    }
  }

  /// Enter machine recovery mode after an unexpected disconnect and arm
  /// the first retry. No-op without a `preferredMachineId` — a
  /// background retry must never surface a machine-picker ambiguity.
  void _startMachineRecovery() {
    if (settingsController.preferredMachineId == null) return;
    _machineRecoveryActive = true;
    _log.info(
      'Machine disconnected unexpectedly — starting auto-reconnect scans',
    );
    _maybeScheduleMachineReconnect();
  }

  void _stopMachineRecovery() {
    _machineRecoveryActive = false;
    _machineReconnect?.cancel();
    _machineReconnect = null;
    _machineReconnectFailures = 0;
  }

  /// Whether the machine auto-reconnect recovery loop is currently armed.
  /// Test hook for asserting the staleness watchdog's strand safety-net.
  @visibleForTesting
  bool get machineRecoveryActive => _machineRecoveryActive;

  bool _shouldRetryMachine() {
    return _machineRecoveryActive &&
        !_machineConnected &&
        settingsController.preferredMachineId != null;
  }

  void _maybeScheduleMachineReconnect() {
    if (_machineReconnect != null) return;
    if (!_shouldRetryMachine()) return;
    final delay = _machineReconnectBackoff;
    _machineReconnectFailures++;
    _log.fine(
      'Machine is missing (attempt #$_machineReconnectFailures); '
      'retrying full scan in ${delay.inSeconds}s',
    );
    _machineReconnect = Timer(delay, () async {
      _machineReconnect = null;
      if (!_shouldRetryMachine()) return;
      try {
        await connect();
      } catch (e, st) {
        _log.fine('Machine reconnect attempt failed', e, st);
      }
      // Reschedule regardless of how the attempt ended — including
      // attempts silently dropped by the concurrent-connect guard.
      // No-op once the machine is back or recovery was stopped.
      _maybeScheduleMachineReconnect();
    });
  }

  void _watchConnectedMachineState() {
    _stopWatchingConnectedMachineState();
    final machine = _disconnectSupervisor.latestMachine;
    if (machine == null) return;
    final Stream<MachineSnapshot> snapshots;
    try {
      snapshots = machine.currentSnapshot;
    } catch (e, st) {
      _log.fine('Machine snapshot stream unavailable', e, st);
      return;
    }
    // Arm the initial-grace watchdog before the first frame lands —
    // covers the Android GATT-busy first-notify-loss race (sb-060/061/062):
    // if the first push is lost, the watchdog fires and forces a clean
    // reconnect that re-establishes notifications.
    _armStateWatchdog(machine.deviceId);
    _machineSnapshotSub = snapshots.listen((snapshot) {
      // Every frame — including a deduped duplicate of the current state —
      // proves the push channel is alive. Re-arm BEFORE the dedupe check
      // so a steady non-transitioning state doesn't false-trigger.
      _armStateWatchdog(machine.deviceId);
      final state = snapshot.state.state;
      if (_latestMachineState == state) return;
      _latestMachineState = state;
      if (_scaleReconnectBlockedByPowerMode) {
        _log.fine(
          'Machine is sleeping and scale power mode is disconnect; '
          'pausing preferred scale reconnect',
        );
        _pauseScaleReconnectForPowerMode();
      } else {
        _ensureScaleReacquisition();
      }
    }, onError: (Object e, StackTrace st) {
      _log.fine('Machine snapshot stream error', e, st);
    });
  }

  void _armStateWatchdog(String deviceId) {
    final gen = _watchdogGeneration;
    _stateWatchdog?.cancel();
    _stateWatchdog = Timer(snapshotStalenessTimeout, () {
      if (gen != _watchdogGeneration) return;
      if (!_machineConnected) return;
      final current = _disconnectSupervisor.latestMachine;
      if (current?.deviceId != deviceId) return;
      _log.warning(
        'Snapshot stream stale for $deviceId after '
        '${snapshotStalenessTimeout.inSeconds}s with link still '
        '"connected"; forcing a clean machine reconnect',
      );
      _forceMachineReconnect();
    });
  }

  /// Force a deliberate, immediate machine reconnect (no backoff). Bumps
  /// the generation token first so any in-flight or stale watchdog Timer
  /// bails; `disconnectMachine` also tears down the watcher (bumps gen
  /// again, cancels the Timer) and marks the disconnect expected so no
  /// error banner surfaces.
  Future<void> _forceMachineReconnect() async {
    snapshotStalenessReconnects++;
    _watchdogGeneration++;
    _stateWatchdog?.cancel();
    _stateWatchdog = null;
    try {
      await disconnectMachine();
      await connect();
    } catch (e, st) {
      _log.fine('Forced machine reconnect failed', e, st);
    } finally {
      // Safety net against stranding the machine. `disconnectMachine`
      // marked the drop expected, so the unexpected-disconnect path never
      // armed machine recovery; and the `connect()` above can be silently
      // dropped by the concurrent-connect guard (e.g. a scale-only rescan
      // already in flight) or return without finding the machine. If
      // we're still machineless, hand off to the recovery loop: it
      // retries with backoff and cancels itself the moment the machine
      // reconnects (no-op without a preferredMachineId).
      if (!_machineConnected) {
        _startMachineRecovery();
      }
    }
  }

  void _pauseScaleReconnectForPowerMode() {
    _deferredScaleScan?.cancel();
    _deferredScaleScan = null;
    _cancelScaleReacquisition();
    if (_activeScaleOnlyScan) {
      deviceScanner.stopScan();
    }
  }

  void _stopWatchingConnectedMachineState() {
    _watchdogGeneration++;
    _stateWatchdog?.cancel();
    _stateWatchdog = null;
    _machineSnapshotSub?.cancel();
    _machineSnapshotSub = null;
    _latestMachineState = null;
  }

  /// Gate the scale phase on machine type. When the connected machine
  /// is a [BengleInterface], its integrated scale (exposed as a
  /// [BengleVirtualScale]) takes the slot and external-scale discovery
  /// is skipped entirely — even if `preferredScaleId` is set. Multi-scale
  /// support is a roadmap follow-up; for now Bengle's integrated scale
  /// always wins. For DE1 (and any non-Bengle machine), the existing
  /// external-scale discovery flow runs unchanged.
  Future<void> _runScalePhase(
    De1Interface? machine,
    List<Scale> scales,
    String? preferredScaleId,
    ScanReportBuilder scanReport,
  ) async {
    if (machine is BengleInterface) {
      await _attachBengleVirtualScale(machine);
      return;
    }
    await _applyScalePolicy(scales, preferredScaleId, scanReport);
  }

  /// Wrap the machine's integrated scale in a [BengleVirtualScale] and
  /// attach it via [ScaleController]. Failures are logged but do not
  /// propagate — the machine remains connected and usable.
  Future<void> _attachBengleVirtualScale(BengleInterface machine) async {
    // TODO(multi-scale, P2): when a user has an external scale already
    // connected and Bengle reconnects, the virtual scale should take
    // over. Today this short-circuit leaves the external scale in
    // place — narrow edge case (Bengle is normally first in a
    // session); revisit when multi-scale support lands.
    if (_scaleConnected) {
      _log.fine('Scale already connected, skipping Bengle virtual scale');
      return;
    }
    final virtual = BengleVirtualScale(machine);
    try {
      await scaleController.connectToScale(virtual);
    } catch (e, st) {
      _log.warning('Failed to attach Bengle virtual scale', e, st);
    }
  }

  /// Apply the scale-phase policy, tracking attempts on [scanReport].
  Future<void> _applyScalePolicy(
    List<Scale> scales,
    String? preferredScaleId,
    ScanReportBuilder scanReport,
  ) async {
    if (_scaleReconnectBlockedByPowerMode) {
      _log.fine(
        'Skipping scale phase while machine is sleeping and scale power '
        'mode is disconnect',
      );
      return;
    }
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

  /// Returns the attempt outcome so tracked callers can report it —
  /// failures are handled here (status emit) and NOT rethrown.
  Future<ConnectionResult> connectScale(Scale scale) async {
    if (_scaleReconnectBlockedByPowerMode) {
      _log.fine(
        'connectScale: blocked while machine is sleeping and scale power '
        'mode is disconnect',
      );
      return const ConnectionResult.skipped();
    }
    if (_isConnectingScale) {
      _log.fine('connectScale: already connecting, skipping');
      return const ConnectionResult.skipped();
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
      if (_scaleReconnectBlockedByPowerMode) {
        markExpectingDisconnect(scale.deviceId);
        _publishStatus(
          currentStatus.copyWith(
            phase:
                _machineConnected ? ConnectionPhase.ready : ConnectionPhase.idle,
          ),
        );
        await scale.disconnect();
        return const ConnectionResult.succeeded();
      }
      await settingsController.setPreferredScaleId(scale.deviceId);
      // `_latestScaleState` is populated by the scaleController
      // listener; `_scaleConnected` reads from it.
      // Only emit ready if machine is also connected — scale alone isn't enough
      if (_machineConnected) {
        _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.ready));
      }
      return const ConnectionResult.succeeded();
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
      return ConnectionResult.failed(e.toString());
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

  /// Wrap [_connectScaleTracked] with the early-connect deferral gate.
  /// See [_shouldDeferEarlyScaleConnect] for the full policy.
  Future<void> _connectScaleTrackedGated(
    Scale scale,
    ScanReportBuilder scanReport,
  ) async {
    if (_scaleReconnectBlockedByPowerMode) {
      _log.fine(
        'Skipping external scale early-connect while machine is sleeping '
        'and scale power mode is disconnect',
      );
      return;
    }
    if (_shouldDeferEarlyScaleConnect()) {
      _log.fine(
        'Deferring external scale early-connect until machine resolves',
      );
      return;
    }
    return _connectScaleTracked(scale, scanReport);
  }

  /// Returns true when the external scale's early-connect path should
  /// be skipped during the scan, leaving the post-scan
  /// [_runScalePhase] to decide per resolved machine type.
  ///
  /// Two conditions trigger a defer:
  ///
  /// 1. A Bengle is already (or about to be) the connected machine —
  ///    [_isBengleAboutToBeMachine]. The integrated scale will take
  ///    the slot in the post-scan policy stage.
  ///
  /// 2. Conservative skip (added 2026-05-05): a `preferredMachineId`
  ///    is configured but no machine has resolved yet on the de1
  ///    stream. Without this, an external scale appearing in scan
  ///    results before the (preferred) Bengle would race past the
  ///    Bengle-inference check (Bengle not yet visible to scanner /
  ///    `latestMachine` still null), early-connect, and then the
  ///    post-scan virtual-attach path would short-circuit because the
  ///    scale slot is already taken.
  ///
  ///    Cost: DE1+scale users lose parallel early-connect (~1s
  ///    latency in the worst case). Acceptable trade for an
  ///    unbreakable "integrated-always-wins on Bengle" invariant.
  ///    Multi-scale support (TODO P2) will revisit.
  bool _shouldDeferEarlyScaleConnect() {
    if (_isBengleAboutToBeMachine()) return true;
    final preferredMachineId = settingsController.preferredMachineId;
    final machineResolved = _disconnectSupervisor.latestMachine != null;
    if (preferredMachineId != null && !machineResolved) return true;
    return false;
  }

  /// True if the connected machine is already a Bengle, or if the
  /// preferred-machine id matches a `BengleInterface` device currently
  /// visible to the scanner. Lets us short-circuit external-scale
  /// connects before the Bengle's `connectToDe1` finishes.
  bool _isBengleAboutToBeMachine() {
    if (_disconnectSupervisor.latestMachine is BengleInterface) {
      return true;
    }
    final preferredMachineId = settingsController.preferredMachineId;
    if (preferredMachineId == null) return false;
    for (final d in deviceScanner.devices) {
      if (d is BengleInterface && d.deviceId == preferredMachineId) {
        return true;
      }
    }
    return false;
  }

  /// Connect a scale and record the attempt outcome on the scan
  /// report builder.
  Future<void> _connectScaleTracked(
    Scale scale,
    ScanReportBuilder scanReport,
  ) async {
    scanReport.markAttempted(scale.deviceId);
    // connectScale handles its own failures (status emit) and reports the
    // outcome instead of throwing — record what actually happened rather
    // than assuming success (a swallowed failure used to log "— connected").
    final result = await connectScale(scale);
    scanReport.recordResult(scale.deviceId, result);
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
      adapterStateAtEnd: deviceScanner.currentAdapterState,
    );
    _scanReportSubject.add(report);
    _log.info(ScanReportBuilder.format(report));
  }

  Future<void> disconnectMachine() async {
    _handleMachineDisconnected();
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
    _cancelScaleReacquisition();
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

  Future<void> dispose() async {
    _stopMachineRecovery();
    _deferredScaleScan?.cancel();
    _cancelPreferredScaleReconnect();
    await _attachReconnectCoordinator?.dispose();
    // Awaited (not via _cancelScaleReacquisition) so the watch is
    // deterministically stopped before the controllers it feeds are
    // disposed.
    await _scaleWatch.dispose();
    _stopWatchingConnectedMachineState();
    await de1Controller.dispose();
    scaleController.dispose();
    _disconnectSupervisor.dispose();
    _adapterSub?.cancel();
    _disconnectExpectations.dispose();
    _statusPublisher.dispose();
    _scanReportSubject.close();
  }
}
