import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/services/ble/ble_exception_mapper.dart';
import 'package:rxdart/subjects.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBleTransport implements BLETransport {
  final BleDevice _device;

  late Logger _log;

  final BehaviorSubject<device.ConnectionState> _connectionStateSubject = BehaviorSubject.seeded(
    device.ConnectionState.discovered,
  );

  StreamSubscription? _connectionStateSubscription;

  // --- Zombie-link detection (see doc/plans/machine-connection-recovery.md).
  // A dead link doesn't always deliver a disconnect event (observed on
  // Android after a DE1 power outage: writes time out forever while the
  // app believes it is connected). Two independent detectors feed
  // [_declareLinkDead]:
  //  1. GATT operation timeouts trigger an OS-level connection-state probe;
  //     [_maxConsecutiveOpTimeouts] in a row force a teardown even when the
  //     OS still claims connected.
  //  2. Advertisements for our own deviceId while we believe we are
  //     connected trigger the same probe (throttled) — probe-confirmed
  //     only, because some peripherals legitimately advertise while
  //     connected (this transport is shared by scales and sensors).
  int _consecutiveOpTimeouts = 0;
  bool _linkDeadDeclared = false;
  DateTime? _lastAdvertProbe;
  StreamSubscription<BleDevice>? _advertSub;

  static const int _maxConsecutiveOpTimeouts = 3;
  static const Duration _linkProbeTimeout = Duration(seconds: 2);

  /// Minimum spacing between advert-triggered OS probes. A disconnected
  /// peripheral advertises ~1/s during a scan; one probe per window is
  /// plenty.
  static const Duration _advertProbeThrottle = Duration(seconds: 5);

  // BlueZ-specific timings (Linux only). universal_ble's Linux backend is the
  // pure-Dart `bluez` client, which needs the same handling the former
  // LinuxBluePlusTransport applied: connecting while (or right after) a scan
  // triggers `le-connection-abort-by-local`, so we stop scanning and let the
  // adapter settle before connecting; GATT service resolution also needs
  // retries because BlueZ resolves services asynchronously after connect.
  static const Duration _bluezPostConnectDelay = Duration(milliseconds: 500);
  static const Duration _bluezScanSettleDelay = Duration(seconds: 2);
  static const Duration _bluezCacheRefreshScan = Duration(seconds: 4);
  static const int _bluezDiscoveryRetries = 3;
  static const Duration _bluezDiscoveryRetryDelay = Duration(seconds: 1);

  bool get _isLinux => Platform.isLinux;

  UniversalBleTransport({
    required BleDevice device,
    Future<void> Function()? stopScan,
  })  : _device = device,
        _stopScan = stopScan {
    _log = Logger("BLETransport-${device.deviceId}");
  }

  /// Scan-stop hook injected by the discovery service. Routing the
  /// pre-connect stop through the service ends its scan-duration wait too,
  /// so the scan cycle (and its report) reflects the actual scan window
  /// instead of dead-waiting out the full duration after the native scan
  /// is already stopped. Falls back to a direct platform stop for
  /// transports constructed without a service.
  final Future<void> Function()? _stopScan;

  Future<void> _stopScanViaOwner() =>
      _stopScan?.call() ?? UniversalBle.stopScan();

  // Android post-connect settle duration. The Android BLE stack needs
  // a brief period after connectGatt reports success before service
  // discovery works reliably (particularly on older tablet SoCs).
  static const Duration _androidPostConnectDelay =
      Duration(milliseconds: 200);

  // Brief pause between stopScan and connectGatt so the scanner actually
  // releases the radio before the connection attempt starts.
  static const Duration _androidPreConnectSettleDelay =
      Duration(milliseconds: 300);

  @override
  Future<void> connect() async {
    _linkDeadDeclared = false;
    _consecutiveOpTimeouts = 0;
    _lastAdvertProbe = null;
    // Use connectionUpdateStream (from our universal_ble fork) to get
    // native disconnect reason codes (GATT error, HCI status) — the
    // standard connectionStream only emits bool.
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = UniversalBle.connectionUpdateStream(
      _device.deviceId,
    ).listen((update) {
      if (update.isConnected) {
        _connectionStateSubject.add(device.ConnectionState.connected);
      } else {
        final reason = update.error ?? 'unknown';
        _log.warning('Transport disconnected: $reason');
        _connectionStateSubject.add(device.ConnectionState.disconnected);
      }
    });
    if (_isLinux) {
      await _connectBlueZ();
      _startAdvertWatch();
      return;
    }
    // Android: stop any active scan before connecting — connectGatt gets
    // starved by a lowLatency scan's radio duty cycle (same problem class
    // as the BlueZ le-connection-abort-by-local mitigation above; observed
    // 2026-07-15 as repeated 10s connect timeouts to an advertising scale
    // mid-scan). The ConnectionManager retry loop restarts scanning.
    if (Platform.isAndroid) {
      try {
        _log.fine("stopping scan before connect");
        await _stopScanViaOwner();
      } catch (e) {
        _log.fine("stopScan before connect failed (ignored): $e");
      }
      await Future.delayed(_androidPreConnectSettleDelay);
    }
    try {
      // 20s: connectGatt on a busy radio (live DE1 link, recent scan) can
      // legitimately need more than 10s — fbp defaults to 35s. Must stay
      // comfortably under ConnectionManager's 30s end-to-end guard so the
      // richer transport-level error wins over the generic outer timeout.
      await UniversalBle.connect(
        _device.deviceId,
        timeout: Duration(seconds: 20),
      );
    } on UniversalBleException catch (e) {
      throw mapUniversalConnectError(e);
    }
    _startAdvertWatch();

    // Android: post-connect settle + MTU bump.
    // The 200ms settle avoids service-discovery races on tablet SoCs
    // where the BLE stack finalises GATT setup asynchronously after
    // connect. MTU 517 reduces GATT round-trips for reads/writes.
    if (!_isLinux && Platform.isAndroid) {
      await Future.delayed(_androidPostConnectDelay);
      try {
        await UniversalBle.requestMtu(
          _device.deviceId,
          517,
          timeout: const Duration(seconds: 5),
        );
        _log.fine('MTU negotiation successful');
      } catch (e) {
        _log.fine('MTU negotiation failed (using default): $e');
      }
    }
  }

  /// BlueZ connect with the same mitigations the Linux BLE path needs.
  /// First attempt stops any scan and lets BlueZ settle, then connects. On
  /// failure, run a brief refresh scan (BlueZ can drop the device from its
  /// cache after a disconnect) and retry once.
  Future<void> _connectBlueZ() async {
    try {
      await _doConnectBlueZ();
    } on UniversalBleException catch (e) {
      _log.warning(
        "BlueZ connect failed ($e); refreshing device cache and retrying",
      );
      await _refreshDeviceCache();
      try {
        await _doConnectBlueZ();
      } on UniversalBleException catch (e2) {
        throw mapUniversalConnectError(e2);
      }
    }
  }

  Future<void> _doConnectBlueZ() async {
    // Stop scanning and let the adapter settle — connecting while a scan is
    // active (or immediately after) causes le-connection-abort-by-local.
    await _stopScanAndSettle();
    await UniversalBle.connect(
      _device.deviceId,
      timeout: Duration(seconds: 15),
    );
    // BlueZ finalizes GATT client setup slightly after connect reports success.
    await Future.delayed(_bluezPostConnectDelay);
  }

  Future<void> _stopScanAndSettle() async {
    try {
      await _stopScanViaOwner();
    } catch (e) {
      _log.fine("stopScan before BlueZ connect failed (ignored): $e");
    }
    _log.fine(
      "Waiting ${_bluezScanSettleDelay.inSeconds}s for BlueZ to settle "
      "before connect",
    );
    await Future.delayed(_bluezScanSettleDelay);
  }

  /// Brief scan to repopulate BlueZ's device cache (the device can drop out of
  /// the adapter's object tree after a disconnect), then settle before retry.
  Future<void> _refreshDeviceCache() async {
    try {
      await UniversalBle.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      await UniversalBle.startScan(scanFilter: ScanFilter(withServices: []));
      await Future.delayed(_bluezCacheRefreshScan);
      await UniversalBle.stopScan();
      await Future.delayed(_bluezScanSettleDelay);
    } catch (e) {
      _log.warning("BlueZ cache-refresh scan failed: $e");
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    }
  }

  /// Error codes that indicate the device is effectively gone — no sense
  /// retrying, and definitely not worth a crash. Emit disconnected and throw
  /// [DeviceNotConnectedException] so upper layers handle it gracefully.
  static const _goneDeviceCodes = {
    UniversalBleErrorCode.characteristicNotFound,
    UniversalBleErrorCode.deviceNotFound,
    UniversalBleErrorCode.serviceNotFound,
    UniversalBleErrorCode.connectionTerminated,
    UniversalBleErrorCode.deviceDisconnected,
  };

  Never _handleGattError(UniversalBleException e, String operation, String path) {
    if (_goneDeviceCodes.contains(e.code)) {
      _log.warning('GATT $operation($path) failed — device gone: ${e.code}');
      _connectionStateSubject.add(device.ConnectionState.disconnected);
      // Drain pending writes — the device is gone, queued writes will
      // only fail with deviceNotFound and flood logs.
      UniversalBle.clearQueue(_device.deviceId);
      throw const DeviceNotConnectedException.unknown();
    }
    // GATT-133 (gattError): transient Android BLE stack error. Often
    // retryable — clear the queue and throw BleTimeoutException so the
    // caller (UnifiedDe1Transport) can retry via _handleBleTimeout.
    // Do NOT declare the link dead or emit disconnected.
    if (e.code == UniversalBleErrorCode.gattError) {
      _log.warning('GATT $operation($path) failed — GATT error 133 (transient): $e');
      UniversalBle.clearQueue(_device.deviceId);
      throw BleTimeoutException('GATT $operation($path)', e);
    }
    // Also treat unknownError as likely device-gone on Bluetooth-off / macOS
    // adapter restarts — same symptom, different error code.
    if (e.code == UniversalBleErrorCode.unknownError) {
      _log.warning(
        'GATT $operation($path) failed — unknown error (likely BT off): $e',
      );
      _connectionStateSubject.add(device.ConnectionState.disconnected);
      UniversalBle.clearQueue(_device.deviceId);
      throw const DeviceNotConnectedException.unknown();
    }
    // All other codes: throw as-is (caller's problem).
    throw e;
  }

  @override
  Future<device.ConnectionState> getConnectionState() async {
    final state = await UniversalBle.getConnectionState(
      _device.deviceId,
      timeout: const Duration(seconds: 2),
    );
    return switch (state) {
      BleConnectionState.connected => device.ConnectionState.connected,
      BleConnectionState.connecting => device.ConnectionState.connecting,
      BleConnectionState.disconnecting ||
      BleConnectionState.disconnected =>
        device.ConnectionState.disconnected,
    };
  }

  @override
  Stream<device.ConnectionState> get connectionState =>
      _connectionStateSubject.asBroadcastStream();

  @override
  Future<void> disconnect() async {
    _advertSub?.cancel();
    _advertSub = null;
    try {
      _log.fine("disconnect");
      for (var sub in _subscriptions.keys) {
        final split = sub.split('--');
        UniversalBle.unsubscribe(_device.deviceId, split[0], split[1]);
        _subscriptions[sub]?.cancel();
      }
      await UniversalBle.disconnect(
        _device.deviceId,
        timeout: Duration(seconds: 5),
      );
    } catch (e) {
      _log.warning("failed to disconnect", e);
      _connectionStateSubject.add(device.ConnectionState.disconnected);
    }
    _connectionStateSubscription?.cancel();
  }

  @override
  Future<List<String>> discoverServices() async {
    if (!_isLinux) {
      final services = await UniversalBle.discoverServices(
        _device.deviceId,
        timeout: Duration(seconds: 10),
      );
      _log.fine(
        "discovered services: ${services.map((e) => e.toString()).toList().join('\n')}",
      );
      return services.map((s) => s.uuid).toList();
    }

    // BlueZ resolves GATT services asynchronously after connect; a query too
    // soon can throw "Failed to resolve services" or return empty. Retry a
    // few times (ported from LinuxBluePlusTransport).
    for (int attempt = 1; attempt <= _bluezDiscoveryRetries; attempt++) {
      try {
        final services = await UniversalBle.discoverServices(
          _device.deviceId,
          timeout: Duration(seconds: 15),
        );
        if (services.isEmpty && attempt < _bluezDiscoveryRetries) {
          _log.warning(
            "discoverServices returned empty "
            "(attempt $attempt/$_bluezDiscoveryRetries), retrying",
          );
          await Future.delayed(_bluezDiscoveryRetryDelay);
          continue;
        }
        _log.fine("discovered ${services.length} services");
        return services.map((s) => s.uuid).toList();
      } on UniversalBleException catch (e) {
        _log.warning(
          "discoverServices attempt $attempt/$_bluezDiscoveryRetries "
          "failed: $e",
        );
        if (attempt < _bluezDiscoveryRetries) {
          await Future.delayed(_bluezDiscoveryRetryDelay);
        } else {
          rethrow;
        }
      }
    }
    return [];
  }

  @override
  String get id => _device.deviceId;

  @override
  String get name => _device.name ?? "Unknown";

  @override
  TransportType get transportType => TransportType.ble;

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID, {Duration? timeout}) async {
    try {
      final value = await UniversalBle.read(
        _device.deviceId,
        serviceUUID,
        characteristicUUID,
        timeout: timeout
      );
      _noteOperationSuccess();
      return value;
    } on TimeoutException {
      // Fail fast (see write() — a read-timeout reconnect mid profile-upload
      // would wedge the firmware the same way). Clear the stuck queue entry and
      // let the plain timeout propagate.
      _onOperationTimeout('read', '$serviceUUID/$characteristicUUID');
      rethrow;
    } on UniversalBleException catch (e) {
      _handleGattError(e, 'read', '$serviceUUID/$characteristicUUID');
    } catch (e) {
      // Same clearQueue rationale as write() — see write() catch block.
      if (e.toString().contains('Queue Cancelled')) {
        _log.fine('read($serviceUUID/$characteristicUUID) cancelled by clearQueue');
        _connectionStateSubject.add(device.ConnectionState.disconnected);
        throw const DeviceNotConnectedException.unknown();
      }
      rethrow;
    }
  }

  /// universal_ble's internal operation queue throws a bare [TimeoutException]
  /// (not a [UniversalBleException]) when a GATT op never completes — e.g. the
  /// DE1 stops servicing ops on a flaky link. Clear the stuck queue entry so it
  /// doesn't block (and time out) every following operation, then let the plain
  /// timeout propagate. Do NOT convert it to a [BleTimeoutException]: that would
  /// trigger a disconnect/reconnect+single-write retry, which corrupts an
  /// in-flight profile upload (a stateful multi-write sequence).
  ///
  /// A timeout is also a zombie-link symptom: verify the link async (never
  /// blocking the caller). A single timeout with a healthy OS link changes
  /// nothing; an OS-confirmed drop — or [_maxConsecutiveOpTimeouts] in a
  /// row — declares the link dead so recovery can start instead of the app
  /// staying "connected" to a corpse forever.
  void _onOperationTimeout(String operation, String path) {
    _log.warning('GATT $operation($path) timed out — clearing BLE queue');
    UniversalBle.clearQueue(_device.deviceId);
    _consecutiveOpTimeouts++;
    if (_consecutiveOpTimeouts >= _maxConsecutiveOpTimeouts) {
      _declareLinkDead(
        '$_consecutiveOpTimeouts consecutive GATT timeouts',
        forceOsDisconnect: true,
      );
    } else {
      unawaited(_probeAndDeclareIfDead('GATT $operation timeout'));
    }
  }

  void _noteOperationSuccess() {
    _consecutiveOpTimeouts = 0;
  }

  /// Listen for advertisements carrying our own deviceId while we believe
  /// the link is up. Adverts only flow while some scan runs (the scale
  /// reconnect loop, UI scans) — this starts none itself.
  void _startAdvertWatch() {
    _advertSub?.cancel();
    _advertSub = UniversalBle.scanStream
        .where((d) => d.deviceId == _device.deviceId)
        .listen(_onOwnAdvertisement);
  }

  void _onOwnAdvertisement(BleDevice _) {
    if (_connectionStateSubject.valueOrNull !=
        device.ConnectionState.connected) {
      return;
    }
    final now = DateTime.now();
    final last = _lastAdvertProbe;
    if (last != null && now.difference(last) < _advertProbeThrottle) return;
    _lastAdvertProbe = now;
    _log.warning(
      'Received advertisement while believed connected — probing OS link state',
    );
    unawaited(_probeAndDeclareIfDead('advertising while believed connected'));
  }

  /// Ask the OS for the actual connection state. Declares the link dead
  /// only on an explicit disconnected/disconnecting answer — a probe
  /// error is inconclusive and must not tear down a possibly-live link.
  Future<void> _probeAndDeclareIfDead(String context) async {
    final BleConnectionState state;
    try {
      state = await UniversalBle.getConnectionState(
        _device.deviceId,
        timeout: _linkProbeTimeout,
      );
    } catch (e) {
      _log.fine('Link probe inconclusive ($context): $e');
      return;
    }
    if (state == BleConnectionState.connected ||
        state == BleConnectionState.connecting) {
      return;
    }
    _declareLinkDead('$context; OS reports ${state.name}');
  }

  /// Emit `disconnected` so the normal recovery cascade runs (device impl →
  /// controller reset → DisconnectSupervisor → machine auto-reconnect).
  /// Idempotent per connection. [forceOsDisconnect] additionally releases
  /// the OS-level GATT handle (best-effort) so it can't block the next
  /// connect — used when the OS still claims the dead link is connected.
  void _declareLinkDead(String reason, {bool forceOsDisconnect = false}) {
    if (_linkDeadDeclared) return;
    _linkDeadDeclared = true;
    _log.warning('Declaring BLE link dead: $reason');
    _advertSub?.cancel();
    _advertSub = null;
    UniversalBle.clearQueue(_device.deviceId);
    _connectionStateSubject.add(device.ConnectionState.disconnected);
    if (forceOsDisconnect) {
      unawaited(
        UniversalBle.disconnect(
          _device.deviceId,
          timeout: const Duration(seconds: 5),
        ).catchError((Object e) {
          _log.fine('Best-effort OS disconnect failed: $e');
        }),
      );
    }
  }

  final Map<String, StreamSubscription<Uint8List>> _subscriptions = {};

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    _log.fine("subscribe to: $serviceUUID, $characteristicUUID");
    final key = "$serviceUUID--$characteristicUUID";
    // Cancel any prior listener for this characteristic before replacing it.
    // A re-subscribe without an intervening disconnect (no-op reconnect)
    // would otherwise stack listeners and deliver every notification twice.
    await _subscriptions.remove(key)?.cancel();
    final sub = UniversalBle.characteristicValueStream(
      _device.deviceId,
      characteristicUUID,
    ).listen(callback);
    _subscriptions[key] = sub;

    try {
      await UniversalBle.subscribeNotifications(
        _device.deviceId,
        serviceUUID,
        characteristicUUID,
      );
    } on UniversalBleException catch (e) {
      _handleGattError(e, 'subscribe', '$serviceUUID/$characteristicUUID');
    }
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    try {
      await UniversalBle.write(
        _device.deviceId,
        BleUuidParser.string(serviceUUID),
        BleUuidParser.string(characteristicUUID),
        data,
        withoutResponse: !withResponse,
        timeout: timeout
      );
      _noteOperationSuccess();
    } on TimeoutException {
      // Fail fast — do NOT map this to a BleTimeoutException. Doing so routes it
      // into the DE1 transport's reconnect-and-retry-this-one-write recovery,
      // which is catastrophic mid profile-upload: a profile is a stateful
      // multi-write sequence (header declares N frames, then each indexed
      // frame, then a tail), and a disconnect/reconnect resets the firmware's
      // receive state machine — leaving the DE1 stuck "receiving" (GHC purple)
      // until reaprime restarts. Surfacing it as a plain timeout fails the whole
      // upload, which WorkflowDeviceSync then re-drives cleanly from the header.
      _onOperationTimeout('write', '$serviceUUID/$characteristicUUID');
      rethrow;
    } on UniversalBleException catch (e) {
      _handleGattError(e, 'write', '$serviceUUID/$characteristicUUID');
    } catch (e) {
      // universal_ble's Queue.dispose() (called from clearQueue in
      // _handleGattError or _onOperationTimeout) cancels pending items
      // with Exception('Queue Cancelled') — a plain Exception, not
      // UniversalBleException, so the on UniversalBleException catch
      // above misses it. Treat it as a gone-device: the queue was
      // cleared because the device is gone, so emit disconnected and
      // throw the domain exception.
      if (e.toString().contains('Queue Cancelled')) {
        _log.fine(
            'write($serviceUUID/$characteristicUUID) cancelled by clearQueue',
        );
        _connectionStateSubject.add(device.ConnectionState.disconnected);
        throw const DeviceNotConnectedException.unknown();
      }
      rethrow;
    }
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {
    // Android-only in universal_ble 2.x; throws `notSupported` elsewhere.
    if (!BleCapabilities.supportsConnectionPriorityApi) return;
    try {
      await UniversalBle.requestConnectionPriority(
        _device.deviceId,
        prioritized
            ? BleConnectionPriority.highPerformance
            : BleConnectionPriority.balanced,
      );
    } on UniversalBleException catch (e) {
      // Best-effort hint; never fail a connection over it.
      _log.fine("requestConnectionPriority not applied: ${e.code}");
    }
  }

  @override
  Future<void> dispose() async {
    _advertSub?.cancel();
    _advertSub = null;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    if (!_connectionStateSubject.isClosed) {
      _connectionStateSubject.close();
    }
  }
}
