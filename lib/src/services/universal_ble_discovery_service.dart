import 'dart:async';
import 'dart:io' show Platform;
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/models/device/transport/ble_connect_exception.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/device/scan_filter.dart' as domain;
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';
import 'package:reaprime/src/services/ble/universal_ble_transport.dart';
import 'package:reaprime/src/services/device_factory.dart';
import 'package:reaprime/src/services/device_matcher.dart';
import 'package:reaprime/src/models/device/device_watch.dart';
import 'package:reaprime/src/models/device/watch_filter.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';
import 'package:universal_ble/universal_ble.dart';
import '../models/device/device.dart';
import '../models/device/machine.dart';
import '../models/device/impl/de1/de1.models.dart';
import 'package:logging/logging.dart' as logging;

typedef BleTransportFactory = BLETransport Function({
  required BleDevice device,
  required Future<void> Function() stopScan,
  required bool requestLargeMtuNonAndroid,
});

class UniversalBleDiscoveryService extends BleDiscoveryService
    implements DeviceWatchCapable {
    UniversalBleDiscoveryService({
    bool Function()? watchSupportGate,
    bool Function()? requestLargeMtuNonAndroid,
    BleTransportFactory? transportFactory,
  }) : _watchSupportGate =
           watchSupportGate ?? (() => Platform.isAndroid),
       requestLargeMtuNonAndroid =
           requestLargeMtuNonAndroid ?? (() => false),
       _transportFactory =
           transportFactory ?? _defaultTransportFactory;

  static BLETransport _defaultTransportFactory({
    required BleDevice device,
    required Future<void> Function() stopScan,
    required bool requestLargeMtuNonAndroid,
  }) {
    return UniversalBleTransport(
      device: device,
      stopScan: stopScan,
      requestLargeMtuNonAndroid: requestLargeMtuNonAndroid,
    );
  }

  final bool Function() _watchSupportGate;
  final BleTransportFactory _transportFactory;

  bool Function() requestLargeMtuNonAndroid;

  BLETransport _createTransport(BleDevice device) {
    return _transportFactory(
      device: device,
      stopScan: _stopScanForConnect,
      requestLargeMtuNonAndroid: requestLargeMtuNonAndroid(),
    );
  }

  @override
  bool get supportsDeviceWatch => _watchSupportGate();

  // Persistent background watch state. `_watchRequested` is the desired
  // state (a watch has been asked for and not stopped); `_watchScanActive`
  // is the actual state (an OS scan is running for it). They diverge while
  // a burst scan owns the radio (universal_ble has one global scan
  // session) and while the adapter is off.
  DeviceWatchFilter? _watchRequested;
  bool _watchScanActive = false;
  StreamSubscription<BleDevice>? _watchScanSub;
  Timer? _watchRefreshTimer;

  /// Bumped on every adapter state CHANGE (replays of the same state
  /// don't count). A watch start captures it and discards itself on
  /// completion if it changed — the transition may have killed the
  /// native scan the start opened, so claiming active would leave the
  /// watch permanently silent.
  int _watchAdapterGeneration = 0;
  AdapterState? _lastWatchAdapterState;

  /// One-shot flag set when a start discarded itself on an adapter
  /// generation change; the retry runs after the in-flight future is
  /// cleared (a retry from within the start would await itself).
  bool _watchStartNeedsRetry = false;

  /// Android silently downgrades scans running longer than 30 minutes to
  /// opportunistic mode (results only when another app scans). Restart
  /// the watch scan before that kicks in.
  static const _watchRefreshInterval = Duration(minutes: 25);

  /// Liveness probe cadence. The native scan can die without anything
  /// reaching Dart: the fork drops `onScanFailed` (logs only), and its
  /// SafeScanner throttle can swallow a start entirely (returns success,
  /// defers the real start, and a later stopScan cancels the deferral).
  /// `UniversalBle.isScanning()` is a cheap host-side check — no radio
  /// use — so probe often enough that a dead watch recovers in ~1 probe
  /// interval instead of waiting for the 25-min refresh.
  static const _watchLivenessInterval = Duration(seconds: 90);
  Timer? _watchLivenessTimer;

  final StreamController<void> _watchFailureController =
      StreamController.broadcast();

  @override
  Stream<void> get deviceWatchFailures => _watchFailureController.stream;

  /// In-flight [_startWatchScan] call. Pause/stop paths await this so
  /// watch-start and burst-start are genuinely serialized — universal_ble
  /// has one global scan session and ownership must be deterministic.
  Future<void>? _watchStartInFlight;

  @override
  Future<void> startDeviceWatch(DeviceWatchFilter filter) async {
    _watchRequested = filter;
    if (_isScanning) {
      log.fine('Burst scan in flight; watch starts when it completes');
      return;
    }
    await _startWatchScan();
  }

  @override
  Future<void> stopDeviceWatch() async {
    _watchRequested = null;
    await _awaitInFlightWatchStart();
    await _deactivateWatchScan(
      stopOsScan: _watchScanActive && !_isScanning,
      context: 'stopDeviceWatch',
    );
  }

  Future<void> _awaitInFlightWatchStart() async {
    final inflight = _watchStartInFlight;
    if (inflight == null) return;
    try {
      await inflight;
    } catch (_) {
      // The start failed — its own error handling ran; nothing to settle.
    }
  }

  /// Detach the watch's scan-stream listener. Fire-and-forget: awaiting
  /// `StreamSubscription.cancel()` can resolve through the root zone,
  /// which deadlocks fakeAsync tests, and the ordering is not
  /// load-bearing — a stray advert between cancel and stopScan just
  /// takes the normal `_deviceScanned` path.
  void _cancelWatchScanSub() {
    final sub = _watchScanSub;
    _watchScanSub = null;
    unawaited(sub?.cancel());
  }

  /// Single teardown path for the watch scan's local state (refresh
  /// timer, scan-stream listener, active flag). [stopOsScan] also stops
  /// the OS scan; pass false when something else owns or already killed
  /// the session (burst hand-over, adapter power-off).
  Future<void> _deactivateWatchScan({
    required bool stopOsScan,
    required String context,
  }) async {
    _watchRefreshTimer?.cancel();
    _watchRefreshTimer = null;
    _watchLivenessTimer?.cancel();
    _watchLivenessTimer = null;
    _cancelWatchScanSub();
    _watchScanActive = false;
    if (stopOsScan) {
      try {
        await UniversalBle.stopScan();
      } catch (e, st) {
        log.warning('$context: stopScan failed', e, st);
      }
    }
  }

  /// Restart the watch scan after it lost the OS session (refresh,
  /// post-burst resume, adapter recovery). On failure the watch is dead
  /// and cannot self-heal: clear the request and report it so ScaleWatch
  /// activates the legacy backoff fallback instead of staying silently
  /// armed.
  Future<void> _restartWatchOrReportFailure(String context) async {
    try {
      await _startWatchScan();
    } catch (e, st) {
      log.warning('$context: watch restart failed — reporting', e, st);
      _watchRequested = null;
      await _deactivateWatchScan(stopOsScan: false, context: context);
      if (!_watchFailureController.isClosed) {
        _watchFailureController.add(null);
      }
    }
  }

  Future<void> _startWatchScan() {
    // Concurrent callers (adapter replay, power-on recovery) share the
    // in-flight start instead of replacing it — replacing would leave
    // pause/stop awaiting a no-op future while the real start runs.
    final existing = _watchStartInFlight;
    if (existing != null) return existing;
    final start = _runWatchScanStart();
    _watchStartInFlight = start;
    return start.whenComplete(() {
      if (identical(_watchStartInFlight, start)) {
        _watchStartInFlight = null;
      }
      if (_watchStartNeedsRetry) {
        _watchStartNeedsRetry = false;
        unawaited(_restartWatchOrReportFailure('adapter-transition retry'));
      }
    });
  }

  Future<void> _runWatchScanStart() async {
    final filter = _watchRequested;
    if (filter == null || _watchScanActive) return;
    if (_adapterStateSubject.value != AdapterState.poweredOn) {
      log.fine('Adapter not powered on; watch pends adapter recovery');
      return;
    }
    final adapterGen = _watchAdapterGeneration;

    _watchScanSub = UniversalBle.scanStream.listen((result) async {
      if (_currentlyScanning.contains(result.deviceId)) {
        return;
      }
      await _deviceScanned(result);
    });

    final namePrefix = filter.namePrefix;
    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          withNamePrefix: namePrefix != null ? [namePrefix] : [],
          withServices: [],
        ),
        // balanced (~40% duty cycle) discovers a freshly powered-on scale
        // in 1-5s while leaving most radio time to DE1 GATT traffic —
        // the duty cycle, not filtering, is what protects the DE1 link.
        // The fork evaluates withNamePrefix plugin-side (the OS scan runs
        // unfiltered either way), so it neither hardware-filters nor
        // keeps the scan alive with the screen off.
        platformConfig: PlatformConfig(
          android: AndroidOptions(
            scanMode: AndroidScanMode.balanced,
            matchMode: AndroidScanMatchMode.aggressive,
            numOfMatches: AndroidScanNumOfMatches.max,
          ),
        ),
      );
    } catch (e) {
      _cancelWatchScanSub();
      rethrow;
    }
    // Guard the start window: state may have moved while startScan was
    // in flight. Ordered by ownership: a stop means undo the scan; a
    // burst owns the session now (its finally-block resume restarts the
    // watch); ANY adapter transition (even off-and-back-on) may have
    // killed the native scan, so the start discards itself and a fresh
    // start runs once this one settles.
    if (_watchRequested == null) {
      log.fine('Watch stopped during start; undoing scan');
      await _deactivateWatchScan(stopOsScan: true, context: 'start-undo');
      return;
    }
    if (_isScanning) {
      log.fine('Burst scan raced watch start; standing down until it ends');
      await _deactivateWatchScan(stopOsScan: false, context: 'start-burst');
      return;
    }
    if (adapterGen != _watchAdapterGeneration) {
      log.fine('Adapter transitioned during watch start; discarding start');
      await _deactivateWatchScan(
        stopOsScan: true,
        context: 'start-adapter-transition',
      );
      // Retry (via _startWatchScan's whenComplete) once this future is
      // no longer the in-flight one; its own guards re-check adapter
      // state and the request.
      _watchStartNeedsRetry = true;
      return;
    }
    _watchScanActive = true;
    _armWatchRefresh();
    _armWatchLiveness();
    log.info('Background device watch started (prefix: $namePrefix)');
  }

  void _armWatchLiveness() {
    _watchLivenessTimer?.cancel();
    _watchLivenessTimer = Timer(_watchLivenessInterval, () async {
      _watchLivenessTimer = null;
      if (!_watchScanActive || _isScanning) return;
      bool alive;
      try {
        alive = await UniversalBle.isScanning();
      } catch (e, st) {
        // A failed probe proves nothing — don't churn the scan over it.
        log.fine('Watch liveness probe failed', e, st);
        alive = true;
      }
      // Re-check: a burst/stop may have taken over during the await.
      if (!_watchScanActive || _isScanning) return;
      if (alive) {
        _armWatchLiveness();
        return;
      }
      log.warning(
        'Watch scan died silently (isScanning=false); restarting',
      );
      await _deactivateWatchScan(stopOsScan: false, context: 'liveness');
      await _restartWatchOrReportFailure('liveness restart');
    });
  }

  void _armWatchRefresh() {
    _watchRefreshTimer?.cancel();
    _watchRefreshTimer = Timer(_watchRefreshInterval, () async {
      _watchRefreshTimer = null;
      // A burst owns the radio right now; its finally-block resume will
      // start a fresh watch scan anyway.
      if (!_watchScanActive || _isScanning) return;
      log.fine('Refreshing watch scan (30-min opportunistic-downgrade guard)');
      await _deactivateWatchScan(stopOsScan: true, context: 'watch-refresh');
      await _restartWatchOrReportFailure('watch-refresh');
    });
  }

  /// Pause the watch scan so a burst scan can own the radio. Awaits any
  /// in-flight watch start first so session ownership is deterministic.
  /// The burst's finally-block calls [_resumeWatchAfterBurst].
  Future<void> _pauseWatchForBurst() async {
    await _awaitInFlightWatchStart();
    if (!_watchScanActive) return;
    log.fine('Pausing background watch for burst scan');
    await _deactivateWatchScan(stopOsScan: true, context: 'watch-pause');
  }

  Future<void> _resumeWatchAfterBurst() async {
    if (_watchRequested == null) return;
    // A resume failure must never fail the burst that triggered it —
    // _restartWatchOrReportFailure never throws.
    await _restartWatchOrReportFailure('post-burst resume');
  }

  /// Adapter transitions: the OS kills any running scan on power-off; a
  /// still-requested watch restarts on power-on (unless a burst runs).
  /// Every transition bumps the generation so an in-flight start
  /// invalidates itself (see [_runWatchScanStart]).
  void _onAdapterStateForWatch(AdapterState state) {
    if (state == _lastWatchAdapterState) return;
    _lastWatchAdapterState = state;
    _watchAdapterGeneration++;
    if (state == AdapterState.poweredOff) {
      if (!_watchScanActive) return;
      unawaited(
        _deactivateWatchScan(stopOsScan: false, context: 'adapter-off'),
      );
    } else if (state == AdapterState.poweredOn &&
        _watchRequested != null &&
        !_watchScanActive &&
        !_isScanning) {
      unawaited(_restartWatchOrReportFailure('adapter recovery'));
    }
  }

  final Map<String, Device> _devices = {};

  final log = logging.Logger("UniversalBleDeviceService");

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  final Map<String, StreamSubscription<ConnectionState>> _connections = {};

  final List<String> _currentlyScanning = [];

  bool _isScanning = false;

  // Cancellable 15s scan-duration wait. External stopScan() cancels the
  // timer and completes the completer so scanForDevices returns promptly
  // instead of being pinned for 15s with _isScanning stuck true
  // (parity with BluePlusDiscoveryService, comms-harden #11).
  Timer? _scanDurationTimer;
  Completer<void>? _scanDurationCompleter;

  final BehaviorSubject<AdapterState> _adapterStateSubject =
      BehaviorSubject.seeded(AdapterState.unknown);

  @override
  Stream<AdapterState> get adapterStateStream => _adapterStateSubject.stream;

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> initialize() async {
    // perDevice: each BLE peripheral gets its own command queue, so
    // DE1 GATT operations never block scale heartbeat writes and vice
    // versa. Mirrors flutter_blue_plus' per-connection serialization.
    UniversalBle.queueType = QueueType.perDevice;

    var initialState = await UniversalBle.getBluetoothAvailabilityState();

    // iOS with bluetooth-central background mode: universal_ble returns
    // `unknown` without creating CBCentralManager when permission is
    // .notDetermined, to avoid triggering the permission prompt during
    // background state-restoration launches. Force-create the manager
    // here so the system permission dialog appears on first foreground
    // launch and the availability stream resolves to the real state.
    if (Platform.isIOS && initialState == AvailabilityState.unknown) {
      log.info('iOS adapter state is unknown; requesting BLE permissions');
      await UniversalBle.requestPermissions();
      initialState = await UniversalBle.getBluetoothAvailabilityState();
    }

    final mappedInitialState = _mapAvailabilityState(initialState);
    _adapterStateSubject.add(mappedInitialState);
    // Seed the watch's change detector so the availability stream's
    // initial replay of this same state doesn't count as a transition.
    _lastWatchAdapterState = mappedInitialState;

    UniversalBle.availabilityStream.listen((state) {
      log.info("BLE Adapter state: ${state.name}");
      final mapped = _mapAvailabilityState(state);
      _adapterStateSubject.add(mapped);
      _onAdapterStateForWatch(mapped);
    });

    if (initialState != AvailabilityState.poweredOn) {
      log.warning(
        "Bluetooth not supported on this platform, state: ${initialState.name}",
      );
    }
  }

  static AdapterState _mapAvailabilityState(AvailabilityState state) {
    switch (state) {
      case AvailabilityState.poweredOn:
        return AdapterState.poweredOn;
      case AvailabilityState.poweredOff:
        return AdapterState.poweredOff;
      case AvailabilityState.unsupported:
        return AdapterState.unavailable;
      case AvailabilityState.unauthorized:
        return AdapterState.unauthorized;
      default:
        return AdapterState.unknown;
    }
  }

  @override
  void stopScan() {
    // stopScan means "stop the burst". When only the watch scan is
    // running, killing it would silently end scale reacquisition — the
    // watch has its own lifecycle via stopDeviceWatch().
    if (!_isScanning && _watchScanActive) {
      log.fine('stopScan ignored: only the background watch is running');
      return;
    }
    _cancelScanDurationWait();
    UniversalBle.stopScan();
  }

  /// Transport pre-connect hook: stop the native scan AND end the
  /// scan-duration wait, so a connect started mid-scan closes the scan
  /// cycle instead of leaving it dead-waiting (native scan already
  /// stopped, no results flowing) — scan reports then show the real
  /// scan window.
  Future<void> _stopScanForConnect() async {
    _cancelScanDurationWait();
    await UniversalBle.stopScan();
  }

  /// Cancel the scheduled 15s stopScan and unblock the awaiter in
  /// scanForDevices so it can proceed to cleanup / free `_isScanning`.
  void _cancelScanDurationWait() {
    _scanDurationTimer?.cancel();
    _scanDurationTimer = null;
    final c = _scanDurationCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _scanDurationCompleter = null;
  }

  /// Wait up to [duration] for the scan to finish, or return early if
  /// `stopScan()` is called. The BLE scan is stopped in either case.
  Future<void> _waitForScanDuration(Duration duration) async {
    final completer = Completer<void>();
    _scanDurationCompleter = completer;
    _scanDurationTimer = Timer(duration, () async {
      try {
        await UniversalBle.stopScan();
      } catch (e, st) {
        log.warning('Scheduled stopScan failed', e, st);
      }
      _cancelScanDurationWait();
    });
    await completer.future;
  }

  @override
  Future<void> scanForDevices({domain.ScanFilter? filter}) async {
    final state = _adapterStateSubject.value;
    if (state != AdapterState.poweredOn) {
      log.warning("Cannot scan, adapter state is $state");
      _deviceStreamController.add(_devices.values.toList());
      return;
    }
    if (_isScanning) {
      log.warning('Scan already in progress, ignoring request');
      return;
    }

    _isScanning = true;
    StreamSubscription<BleDevice>? sub;

    try {
      // universal_ble has one global scan session — a running watch scan
      // must yield to the burst and is resumed in the finally below.
      await _pauseWatchForBurst();

      log.fine("Clearing stale connections");
      _currentlyScanning.clear();

      sub = UniversalBle.scanStream.listen((result) async {
        log.finest(
          "Found: ${result.deviceId}: ${result.name}, adv: ${result.services}",
        );
        if (_currentlyScanning.contains(result.deviceId)) {
          return;
        }
        await _deviceScanned(result);
      });

      // Unfiltered scan — empty services list (sb-044: name-match is the
      // documented discovery path; service UUIDs are only a scan-filter
      // optimization, not needed on macOS/iOS).
      final scanFilter = ScanFilter(withServices: []);

      // Android: use aggressive scan settings to avoid the chip-side
      // advert de-duplication that throttles results to ~1 per 12 s.
      // matchMode: aggressive disables firmware-layer de-duplication;
      // numOfMatches: max removes the per-device match cap;
      // scanMode: lowLatency prioritises scan duty cycle over power.
      // callbackType omitted: allMatches is the Android default, and
      // matchLost causes IllegalArgumentException on some GSI images.
      final platformConfig = Platform.isAndroid
          ? PlatformConfig(
              android: AndroidOptions(
                scanMode: AndroidScanMode.lowLatency,
                matchMode: AndroidScanMatchMode.aggressive,
                numOfMatches: AndroidScanNumOfMatches.max,
              ),
            )
          : null;
      await UniversalBle.startScan(
        scanFilter: scanFilter,
        platformConfig: platformConfig,
      );

      // CoreBluetooth/BlueZ hide system-connected/bonded BLE devices from
      // scan results; query them explicitly so a DE1 paired via System
      // Settings is still discovered (#126). Optional — must never abort the
      // main scan (parity with BluePlusDiscoveryService's macOS guard), so
      // failures are swallowed.
      try {
        final systemDevices = await UniversalBle.getSystemDevices(
          withServices: [],
        );
        for (var d in systemDevices) {
          await _deviceScanned(d);
        }
      } catch (e, st) {
        log.fine('System device check failed', e, st);
      }

      // Scan for up to 15s; external stopScan() ends the wait early so the
      // scanner frees `_isScanning` without waiting out the full duration.
      await _waitForScanDuration(const Duration(seconds: 15));
    } finally {
      await sub?.cancel();
      _cancelScanDurationWait();
      _deviceStreamController.add(_devices.values.toList());
      _isScanning = false;
      await _resumeWatchAfterBurst();
    }
  }

  Future<void> _deviceScanned(BleDevice device) async {
    _currentlyScanning.add(device.deviceId);

    try {
      final name = device.name ?? '';
      if (name.isEmpty) return;

      if (_devices.containsKey(device.deviceId.toString())) return;

      final matchedDevice = await DeviceMatcher.match(
        transport: _createTransport(device),
        advertisedName: name,
      );

      if (matchedDevice != null) {
        _devices[device.deviceId.toString()] = matchedDevice;
        _deviceStreamController.add(_devices.values.toList());
        log.fine("found new device: ${device.name}");

        _connections[device.deviceId
            .toString()] = _devices[device.deviceId.toString()]!.connectionState
            .listen((connectionState) {
              if (connectionState == ConnectionState.disconnected) {
                _devices.remove(device.deviceId.toString());
                _deviceStreamController.add(_devices.values.toList());
              }
            });
      }
    } finally {
      _currentlyScanning.remove(device.deviceId);
    }
  }

  @override
  Future<Device?> tryQuickConnect(RememberedDevice remembered) async {
    final impl = remembered.implementation;
    final tt = remembered.transportType;
    if (impl == null || tt == null || tt != TransportType.ble) {
      return null;
    }

    final deviceId = remembered.id;

    BleDevice? bleDevice;
    if (Platform.isIOS || Platform.isMacOS) {
      bleDevice = await _findSystemDevice(deviceId);
      if (bleDevice == null) {
        log.info('Quick-connect: device $deviceId not in system cache');
        return null;
      }
    } else {
      bleDevice = BleDevice(deviceId: deviceId, name: remembered.name);
    }

    final transport = _createTransport(bleDevice);
    final device = DeviceFactory.createBle(impl, transport);
    if (device == null) {
      log.warning('Quick-connect: DeviceFactory returned null for $impl');
      return null;
    }

    try {
      await _connectWithRetry(device);
      if (device is Machine) {
        final model = device.machineInfo.model;
        final expectedBengle = impl == DeviceImplementation.bengle;
        final actualBengle = model == DecentMachineModel.Bengle.name;
        if (expectedBengle != actualBengle) {
          log.warning(
            'Quick-connect: identity mismatch for $deviceId '
            '(expected ${impl.name}, got model=$model)',
          );
          if (expectedBengle && !actualBengle) {
            try {
              await device.disconnect();
            } catch (_) {}
            try {
              await transport.dispose();
            } catch (_) {}
            return null;
          }
        }
      }
      _devices[deviceId] = device;
      _deviceStreamController.add(_devices.values.toList());
      _connections[deviceId] = device.connectionState.listen((state) {
        if (state == ConnectionState.disconnected) {
          _devices.remove(deviceId);
          _deviceStreamController.add(_devices.values.toList());
        }
      });
      log.info('Quick-connect succeeded for $deviceId');
      return device;
    } catch (e, st) {
      log.warning('Quick-connect failed for $deviceId', e, st);
      try {
        await device.disconnect();
      } catch (_) {}
      try {
        await transport.dispose();
      } catch (_) {}
      return null;
    }
  }

  Future<BleDevice?> _findSystemDevice(String deviceId) async {
    try {
      final systemDevices = await UniversalBle.getSystemDevices(
        withServices: [],
      );
      for (final d in systemDevices) {
        if (d.deviceId == deviceId) return d;
      }
    } catch (e, st) {
      log.fine('getSystemDevices failed during quick-connect', e, st);
    }
    return null;
  }

  Future<void> _connectWithRetry(Device device) async {
    const timeout = Duration(seconds: 10);
    try {
      await device.onConnect().timeout(timeout);
    } on BleConnectException catch (e) {
      log.info('Quick-connect GATT error ($e), retrying once after 1s');
      await Future.delayed(const Duration(seconds: 1));
      try {
        await device.disconnect();
      } catch (_) {}
      await device.onConnect().timeout(timeout);
    }
  }
}
