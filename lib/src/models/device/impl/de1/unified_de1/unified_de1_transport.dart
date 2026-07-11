import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/bengle_shot_sample.dart'
    show bengleShotSampleBytes;
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/device/transport/logical_endpoint.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
import 'package:rxdart/rxdart.dart';

enum TransportType { ble, serial, unknown }

class UnifiedDe1Transport {
  final DataTransport _transport;
  final TransportType transportType;
  final Logger _log;

  // Only assigned on the serial transport path (`_serialConnect`).
  // Nullable so `disconnect()` can be called safely if connect failed
  // before the subscription was wired, or on BLE transports where the
  // serial branch never runs.
  StreamSubscription<String>? _transportSubscription;

  /// period of the serial keepalive that actively drives the
  /// shared firmware link. BLE and USB share one serial view in the
  /// firmware, arbitrated by a last-writer-wins `Source` flag — any stray
  /// byte from the BLE module silently steals the notify stream from a
  /// passively-listening USB client (the firmware its BLE input path vs
  /// the BLE-UART RX path). A periodic `<+N>` re-add re-asserts
  /// Source=USB, and — because the firmware treats an add-notify as a
  /// force-update — also re-syncs any subscribed frame a silently-dropped
  /// byte corrupted (the ASCII framing has no checksum/retransmit). 5 s
  /// bounds the worst-case stolen-stream window at negligible cost (one
  /// ~8-char command up, one [N] frame + changed frames down).
  static const defaultSerialKeepaliveInterval = Duration(seconds: 5);

  /// Test seam: keepalive cadence, injectable so the timer tests can run
  /// on real (shortened) time — fakeAsync stalls on the root-zone
  /// `_nullFuture` that broadcast-subscription cancels return.
  final Duration serialKeepaliveInterval;
  Timer? _serialKeepalive;

  /// bounded wait for a single-notify serial read. The firmware
  /// answers a `<+X>` with one `[X]` frame within a notify tick, so 2 s is
  /// generous; firmware that never emits the char (e.g. a pre-parity
  /// the firmware asked for `[A]`) fails fast with a [TimeoutException] instead
  /// of hanging the raw-API caller.
  static const defaultSerialSingleReadTimeout = Duration(seconds: 2);

  /// Test seam: see [serialKeepaliveInterval].
  final Duration serialSingleReadTimeout;

  /// the firmware serial parser consumes exactly
  /// the frame length is 20 bytes per `<F>`
  /// frame (the firmware serial view counts hex pairs before accepting
  /// the newline). BLE tolerates a short final DFU chunk; serial drops the
  /// whole frame and resyncs on the next `<`. The `Len` byte (`data[0]`)
  /// carries the true payload length, so trailing zeros are inert.
  static const _writeToMmrFrameBytes = 20;

  // True while `_handleBleTimeout` is doing a deliberate disconnect→reconnect
  // to recover from a BLE timeout. The disconnect it issues must stay
  // invisible to upstream (De1Controller would otherwise null the machine on
  // `disconnected` and tear down a connection that's about to come right
  // back). Suppressing here — rather than at the transport — covers every
  // platform: the desktop/iOS `BluePlusTransport` emits `disconnected`
  // synchronously, and Android's native sub emits it async from the platform.
  bool _recovering = false;

  Stream<device.ConnectionState> get connectionState =>
      _transport.connectionState.where(
        (s) => !(_recovering && s == device.ConnectionState.disconnected),
      );

  String get id => _transport.id;

  /// The underlying [DataTransport], exposed for connect-time model-based
  /// class resolution only (see `resolveMachineForModel`): a re-resolved
  /// machine is rebuilt over this same live transport. Not for I/O — use the
  /// typed read/write/subscribe surface.
  DataTransport get dataTransport => _transport;

  final BehaviorSubject<ByteData> _stateSubject = BehaviorSubject.seeded(
    ByteData(4),
  );
  final BehaviorSubject<ByteData> _shotSampleSubject = BehaviorSubject.seeded(
    ByteData(19),
  );
  // TODO: change this to expose a different subject if needed
  final BehaviorSubject<ByteData> shotSettingsSubject = BehaviorSubject.seeded(
    ByteData(9),
  );
  final BehaviorSubject<ByteData> _waterLevelsSubject = BehaviorSubject.seeded(
    ByteData(4),
  );
  final BehaviorSubject<ByteData> _mmrSubject = BehaviorSubject.seeded(
    ByteData(20),
  );
  final BehaviorSubject<ByteData> _fwMapRequestSubject = BehaviorSubject.seeded(
    ByteData(7),
  );
  // Bengle 0xA013 BengleShotSample (28 bytes). Only fed on a Bengle — the
  // subscription is gated (BLE via [subscribeBengleShotSample], serial via the
  // `<+S>` in `_serialConnect`). Seeded 28 zero bytes so late subscribers get a
  // valid-length frame.
  final BehaviorSubject<ByteData> _bengleShotSampleSubject =
      BehaviorSubject.seeded(ByteData(bengleShotSampleBytes));

  // single-notify serial read channels ([A] Versions,
  // [J] Temperatures, [R] Calibration). Plain broadcast controllers, NOT
  // BehaviorSubjects: a read must resolve with the fresh frame provoked by
  // its own `<+X>`, never a cached one.
  final StreamController<ByteData> _versionsController =
      StreamController.broadcast();
  final StreamController<ByteData> _temperaturesController =
      StreamController.broadcast();
  final StreamController<ByteData> _calibrationController =
      StreamController.broadcast();

  Stream<ByteData> get state => _stateSubject.asBroadcastStream();
  Stream<ByteData> get shotSample => _shotSampleSubject.asBroadcastStream();
  Stream<ByteData> get shotSettings => shotSettingsSubject.asBroadcastStream();
  Stream<ByteData> get waterLevels => _waterLevelsSubject.asBroadcastStream();
  Stream<ByteData> get mmr => _mmrSubject.asBroadcastStream();
  Stream<ByteData> get fwMapRequest => _fwMapRequestSubject.asBroadcastStream();
  Stream<ByteData> get bengleShotSample =>
      _bengleShotSampleSubject.asBroadcastStream();

  // Serial only
  String _currentBuffer = "";

  UnifiedDe1Transport({
    required DataTransport transport,
    this.serialKeepaliveInterval = defaultSerialKeepaliveInterval,
    this.serialSingleReadTimeout = defaultSerialSingleReadTimeout,
  })
    : _transport = transport,
      transportType =
          transport is BLETransport
              ? TransportType.ble
              : transport is SerialTransport
              ? TransportType.serial
              : TransportType.unknown,
      _log = Logger("UnifiedDe1Transport-${transport.id}");
  Future<void> connect() async {
    // A connect() while the transport already reports `connected` is a
    // no-op reconnect: the underlying GATT link never came down (e.g. the
    // app-level disconnect on machine sleep nulled De1Controller._de1 but
    // the native BLE transport lingered connected — a zombie link). The
    // prior fix (PR #246 / sb-030) made `_bleConnect()`'s per-characteristic
    // `subscribe()` cancel-before-replace so it no longer STACKED duplicate
    // listeners. But re-subscribing against the zombie link had an inverse
    // failure mode seen in the field: a pure-push characteristic
    // (stateInfo/A00E) silently stopped delivering while solicited
    // reads/writes kept succeeding — invisible to the zombie watchdog,
    // which only counts GATT op timeouts and own-advert probes.
    //
    // The load-bearing fix is to tear down the stale native link BEFORE
    // re-connecting, so `_bleConnect()` runs against a freshly-established
    // GATT and every CCCD is written cleanly. The transient `disconnected`
    // the native link emits during teardown is absorbed without surfacing
    // to upstream: De1Controller.connectToDe1 has already cancelled its
    // `connectionState` listener (via _onDisconnect) before `onConnect()`
    // runs this method, and only re-subscribes after `onConnect()` returns.
    final wasConnected = transportType == TransportType.ble &&
        await _transport.connectionState.first ==
            device.ConnectionState.connected;

    if (wasConnected) {
      _log.info(
        'Transport already connected; tearing down stale link before '
        'reconnect to avoid no-op-reconnect push death',
      );
      await _transport.disconnect();
    }

    await _transport.connect();

    switch (transportType) {
      case TransportType.ble:
        await _bleConnect();
        break;
      case TransportType.serial:
        await _serialConnect();
        break;
      default:
        throw StateError('Unknown transport type: $transportType');
    }
  }

  Future<void> _bleConnect() async {
    if (_transport is! BLETransport) {
      throw "wrong transport type";
    }
    final services = await _transport.discoverServices();
    final de1Service = BleServiceIdentifier.parse(de1ServiceUUID);
    if (!de1Service.matchesAny(services)) {
      throw Exception(
        'Expected DE1 service ${de1Service.long} not found. '
        'Discovered services: $services',
      );
    }

    _stateNotification(
      ByteData.sublistView(
        await _transport.read(de1ServiceUUID, Endpoint.stateInfo.uuid),
      ),
    );

    _shotSettingsNotification(
      ByteData.sublistView(
        await _transport.read(de1ServiceUUID, Endpoint.shotSettings.uuid),
      ),
    );

    await _transport.subscribe(de1ServiceUUID, Endpoint.stateInfo.uuid, (d) {
      _stateNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.shotSample.uuid, (d) {
      _shotSampleNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.waterLevels.uuid, (d) {
      _waterLevelsNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.shotSettings.uuid, (d) {
      _shotSettingsNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.readFromMMR.uuid, (d) {
      _mmrNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.fwMapRequest.uuid, (d) {
      _fwMapNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
  }

  /// Subscribe to the Bengle 0xA013 BengleShotSample characteristic over BLE.
  ///
  /// Called by `UnifiedDe1.onConnect` **after** the Bengle identity is
  /// confirmed (`v13Model >= 128`), never blind-enabled: enabling a
  /// characteristic a plain DE1 lacks throws and permanently stalls the BLE
  /// command queue (de1plus `de1_comms.tcl:777-785`). Idempotent: [subscribe]
  /// replaces (not stacks) a prior listener for the same characteristic.
  ///
  /// On serial the `<+S>` enable already happened in `_serialConnect`;
  /// instead this post-detection hook drops the now-redundant base stream
  ///: on a Bengle, 0xA013 is the sole snapshot source, so `[M]`
  /// (0xA00D) is pure wasted bandwidth — and the dual 15 Hz stream overruns
  /// the firmware's ~1920 B/s serial downlink ceiling (hw-confirmed
  /// 2026-07-09: truncated/odd-length frames, weight flicker).
  /// `_serialConnect` must keep subscribing `<+M>` unconditionally because
  /// it runs before the identity is known and `[M]` is how the serial probe
  /// recognises a DE1-family device at all. BLE has the headroom and keeps
  /// 0xA00D subscribed (parse-and-drop).
  Future<void> subscribeBengleShotSample() async {
    final t = _transport;
    if (transportType == TransportType.serial && t is SerialTransport) {
      await t.writeCommand("<-${Endpoint.shotSample.representation}>");
      return;
    }
    if (transportType != TransportType.ble) return;
    if (_transport is! BLETransport) return;
    await _transport.subscribe(de1ServiceUUID, Endpoint.bengleShotSample.uuid, (
      d,
    ) {
      _bengleShotSampleNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
  }

  Future<void> _serialConnect() async {
    if (_transport is! SerialTransport) {
      throw "Wrong transport type";
    }
    // Start notifications - regular setup
    // await _transport.writeCommand("<-N>");
    // await _transport.writeCommand("<-M>");
    // await _transport.writeCommand("<-Q>");
    // await _transport.writeCommand("<-K>");
    // await _transport.writeCommand("<-E>");

    _transportSubscription = _transport.readStream.listen(_processSerialInput);

    await _transport.writeCommand("<+${Endpoint.stateInfo.representation}>");
    await _transport.writeCommand("<+${Endpoint.shotSample.representation}>");
    await _transport.writeCommand("<+${Endpoint.waterLevels.representation}>");
    await _transport.writeCommand("<+${Endpoint.shotSettings.representation}>");
    await _transport.writeCommand("<+${Endpoint.readFromMMR.representation}>");
    await _transport.writeCommand("<+${Endpoint.fwMapRequest.representation}>");
    // Bengle 0xA013. Unconditional on serial (unlike the gated BLE subscribe):
    // the serial parser has no CCCD-on-missing-characteristic stall hazard,
    // and a plain DE1 simply never emits `[S]` frames.
    await _transport.writeCommand(
      "<+${Endpoint.bengleShotSample.representation}>",
    );

    // needed to know which state we're at - request idle state
    await _transport.writeCommand("<B>02");

    // actively drive the shared BLE/USB link — see
    // [serialKeepaliveInterval] for why a passive USB client loses its
    // notify stream. Fire-and-forget: a failed keepalive write means the
    // port is dying, which the read-side onError/onDone paths already
    // handle; it must not become an unhandled async error.
    _serialKeepalive?.cancel();
    _serialKeepalive = Timer.periodic(serialKeepaliveInterval, (_) {
      _transport
          .writeCommand("<+${Endpoint.stateInfo.representation}>")
          .catchError(
            (Object e) => _log.fine('serial keepalive write failed', e),
          );
    });
  }

  /// End-of-life cleanup. Closes all subjects, cancels the serial
  /// subscription, and disposes the underlying transport. Safe to call
  /// more than once. Re-use after dispose is not supported.
  Future<void> dispose() async {
    // Cancel serial subscription if active
    await _transportSubscription?.cancel();
    _transportSubscription = null;
    _serialKeepalive?.cancel();
    _serialKeepalive = null;

    // Close all BehaviorSubjects so downstream listeners see onDone
    if (!_stateSubject.isClosed) _stateSubject.close();
    if (!_shotSampleSubject.isClosed) _shotSampleSubject.close();
    if (!shotSettingsSubject.isClosed) shotSettingsSubject.close();
    if (!_waterLevelsSubject.isClosed) _waterLevelsSubject.close();
    if (!_mmrSubject.isClosed) _mmrSubject.close();
    if (!_fwMapRequestSubject.isClosed) _fwMapRequestSubject.close();
    if (!_bengleShotSampleSubject.isClosed) _bengleShotSampleSubject.close();
    if (!_versionsController.isClosed) _versionsController.close();
    if (!_temperaturesController.isClosed) _temperaturesController.close();
    if (!_calibrationController.isClosed) _calibrationController.close();

    await _transport.dispose();
  }

  /// Releases this wrapper's own resources (serial read subscription + local
  /// subjects) WITHOUT disposing the underlying [dataTransport]. Used when a
  /// machine is re-resolved to a different class over the same live transport
  /// (`resolveMachineForModel`): the discarded interim wrapper must stop
  /// listening — else a serial `readStream` listener lingers and
  /// double-parses every line — but must NOT tear down the shared transport,
  /// which the replacement wrapper now owns. Not for normal teardown; use
  /// [dispose] for that.
  Future<void> detach() async {
    await _transportSubscription?.cancel();
    _transportSubscription = null;
    _serialKeepalive?.cancel();
    _serialKeepalive = null;
    if (!_stateSubject.isClosed) _stateSubject.close();
    if (!_shotSampleSubject.isClosed) _shotSampleSubject.close();
    if (!shotSettingsSubject.isClosed) shotSettingsSubject.close();
    if (!_waterLevelsSubject.isClosed) _waterLevelsSubject.close();
    if (!_mmrSubject.isClosed) _mmrSubject.close();
    if (!_fwMapRequestSubject.isClosed) _fwMapRequestSubject.close();
    if (!_bengleShotSampleSubject.isClosed) _bengleShotSampleSubject.close();
    if (!_versionsController.isClosed) _versionsController.close();
    if (!_temperaturesController.isClosed) _temperaturesController.close();
    if (!_calibrationController.isClosed) _calibrationController.close();
  }

  Future<void> disconnect() async {
    _log.warning(
      'disconnect() called by app code',
      null,
      StackTrace.current,
    );
    switch (transportType) {
      case TransportType.serial:
        if (_transport is! SerialTransport) {
          throw "Wrong transport type";
        }
        await _transportSubscription?.cancel();
        _transportSubscription = null;
        _serialKeepalive?.cancel();
        _serialKeepalive = null;
        // Start notifications - regular setup
        await _transport.writeCommand(
          "<-${Endpoint.stateInfo.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.shotSample.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.waterLevels.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.shotSettings.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.readFromMMR.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.fwMapRequest.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.bengleShotSample.representation}>",
        );
        break;
      case TransportType.ble:
        // BLE doesn't need special disconnect handling
        break;
      case TransportType.unknown:
        throw StateError('Unknown transport type: $transportType');
    }

    await _transport.disconnect();
  }

  // Matches a complete message: [X] prefix + hex payload, terminated by
  // another '[' (next message) or newline.
  // Group 1 = the message content (e.g., "[M]0A0B0C").
  static final _messagePattern =
      RegExp(r'(\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n)');

  // Render the first `max` characters of a buffer for a log line. Replaces
  // non-printable and whitespace chars with their escape form so the sample
  // stays on a single line and reveals whether the content is e.g. sensor
  // basket text, binary noise, or something else.
  static String _sampleForLog(String s, int max) {
    final head = s.length <= max ? s : '${s.substring(0, max)}…';
    final escaped = head
        .replaceAll('\\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t')
        .replaceAllMapped(
          RegExp(r'[^\x20-\x7e]'),
          (m) => '\\x${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}',
        );
    return '"$escaped"';
  }

  void _processSerialInput(String input) {
    _currentBuffer += input;

    // Discard any leading junk before the first '['
    final firstBracket = _currentBuffer.indexOf('[');
    if (firstBracket < 0) {
      // No message start in buffer at all
      _currentBuffer = '';
      return;
    }
    if (firstBracket > 0) {
      _log.finest(
          "Discarding non-message data: '${_currentBuffer.substring(0, firstBracket)}'");
      _currentBuffer = _currentBuffer.substring(firstBracket);
    }

    // Extract all complete messages. A message is "complete" when followed by
    // another '[' (next message start) or a newline. Incomplete messages at
    // the end of the buffer won't match the lookahead and stay buffered.
    final matches = _messagePattern.allMatches(_currentBuffer).toList();

    if (matches.isEmpty) {
      // Guard against unbounded buffer growth from corrupted serial streams
      if (_currentBuffer.length > 4096) {
        _log.warning(
            'Serial buffer overflow (${_currentBuffer.length} bytes), discarding. '
            'Head sample: ${_sampleForLog(_currentBuffer, 200)}');
        _currentBuffer = '';
      }
      return;
    }

    final completeCount = matches.length;

    for (int i = 0; i < completeCount; i++) {
      final message = matches[i].group(1)!.trim();
      if (message.isNotEmpty) {
        _log.finest("received complete response: $message");
        _processDe1Response(message);
      }
    }

    // Keep unprocessed portion in the buffer
    if (completeCount > 0) {
      _currentBuffer = _currentBuffer.substring(matches[completeCount - 1].end);
      // Strip consumed newlines
      _currentBuffer = _currentBuffer.replaceAll(RegExp(r'^\n+'), '');
    }
  }

  void _processDe1Response(String input) {
    _log.finest("processing input: $input");
    try {
      final Uint8List payload = hexToBytes(input.substring(3));
      final ByteData data = ByteData.sublistView(payload);
      switch (input.substring(0, 3)) {
        case "[M]":
          _shotSampleNotification(data);
        case "[N]":
          _stateNotification(data);
        case "[Q]":
          _waterLevelsNotification(data);
        case "[K]":
          _shotSettingsNotification(data);
        case "[E]":
          _mmrNotification(data);
        case "[I]":
          _fwMapNotification(data);
        case "[S]":
          _bengleShotSampleNotification(data);
        // single-notify read replies. Only ever solicited by
        // _serialSingleNotifyRead's own `<+X>`, so no length guard here —
        // the awaiting reader owns interpretation.
        case "[A]":
          _versionsController.add(data);
        case "[J]":
          _temperaturesController.add(data);
        case "[R]":
          _calibrationController.add(data);
        default:
          _log.warning("unhandled de1 message: $input");
          break;
      }
    } on FormatException catch (e) {
      _log.warning("malformed serial message, skipping: '$input' ($e)");
    }
  }

  Uint8List hexToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), ''); // strip whitespace
    if (hex.length.isOdd) {
      throw FormatException('Invalid input length, must be even', hex);
    }
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      final byteStr = hex.substring(i, i + 2);
      result[i ~/ 2] = int.parse(byteStr, radix: 16);
    }
    return result;
  }

  // Minimum lengths required by `_parseStateAndShotSample` in
  // `unified_de1.parsing.dart`. Shorter frames (observed in the wild on
  // Galaxy Tab A9+ 0.5.13) cause a `RangeError` deep in rxdart and land
  // in Crashlytics as fatal. Drop them here with a warning instead.
  static const _minShotSampleBytes = 19;
  static const _minStateBytes = 2;

  void _shotSampleNotification(ByteData d) {
    if (d.lengthInBytes < _minShotSampleBytes) {
      _log.warning(
        'Dropping short shotSample frame '
        '(${d.lengthInBytes} < $_minShotSampleBytes bytes)',
      );
      return;
    }
    _shotSampleSubject.add(d);
  }

  // a truncated 0xA013 frame (e.g. a stale/undersized ATT MTU) is
  // dropped rather than forwarded, so the downstream decoder never hits a
  // RangeError. Applies to both transports — serial `[S]` frames route here
  // too.
  void _bengleShotSampleNotification(ByteData d) {
    if (d.lengthInBytes < bengleShotSampleBytes) {
      _log.warning(
        'Dropping short bengleShotSample frame '
        '(${d.lengthInBytes} < $bengleShotSampleBytes bytes)',
      );
      return;
    }
    _bengleShotSampleSubject.add(d);
  }

  void _stateNotification(ByteData d) {
    if (d.lengthInBytes < _minStateBytes) {
      _log.warning(
        'Dropping short state frame '
        '(${d.lengthInBytes} < $_minStateBytes bytes)',
      );
      return;
    }
    _stateSubject.add(d);
  }

  void _waterLevelsNotification(ByteData d) {
    _waterLevelsSubject.add(d);
  }

  void _shotSettingsNotification(ByteData d) {
    shotSettingsSubject.add(d);
  }

  void _fwMapNotification(ByteData d) {
    _fwMapRequestSubject.add(d);
  }

  void _mmrNotification(ByteData d) {
    _mmrSubject.add(d);
  }

  Future<ByteData> read(LogicalEndpoint endpoint, {Duration? timeout}) async {
    if (await _transport.connectionState.first != device.ConnectionState.connected) {
      throw const DeviceNotConnectedException.machine();
    }

    try {
      switch (transportType) {
        case TransportType.ble:
          if (endpoint.uuid == null) {
            throw StateError(
                'UnifiedDe1Transport.read: endpoint ${endpoint.name} has no BLE wire support');
          }
          return await _bleRead(endpoint, timeout: timeout);
        case TransportType.serial:
          // _serialRead has a closed switch on Endpoint values to map to RX subjects;
          // non-Endpoint LogicalEndpoints can't be dispatched here.
          if (endpoint is! Endpoint) {
            throw StateError(
                'UnifiedDe1Transport.read: endpoint ${endpoint.name} is not a DE1 Endpoint, serial read not supported');
          }
          // Defense-in-depth: `Endpoint.representation` is currently
          // declared non-null, but if a future variant relaxes that we
          // want a clear error rather than passing null downstream.
          // ignore: unnecessary_null_comparison, dead_code
          if (endpoint.representation == null) {
            // ignore: dead_code
            throw StateError(
                'UnifiedDe1Transport.read: endpoint ${endpoint.name} has no serial wire support');
          }
          return await _serialRead(endpoint);
        default:
          throw ("Unknown transport type: $transportType");
      }
    } catch (e, st) {
      if (_isBleTimeout(e)) {
        if (await _handleBleTimeout(e, st)) {
          _log.info('Retrying read of ${endpoint.name} after reconnect');
          return read(endpoint, timeout: timeout);
        }
      }
      _log.severe("failed to read", e, st);
      rethrow;
    }
  }

  Future<ByteData> _bleRead(LogicalEndpoint e, {Duration? timeout}) async {
    if (_transport is! BLETransport) {
      throw "Invalid transport type, expected BLE";
    }
    var data =
        await _transport.read(de1ServiceUUID, e.uuid!, timeout: timeout);
    ByteData response = ByteData.sublistView(Uint8List.fromList(data));
    return response;
  }

  /// Serial reads come in three shapes:
  ///
  /// 1. **Continuously-subscribed streams** (`<+X>` sent in
  ///    `_serialConnect`) — the BehaviorSubject's current value *is* the
  ///    latest frame; return it.
  /// 2. **Single-notify round trips** — the DE1 serial view has no read
  ///    verb; an add-notify (`<+X>`) makes the firmware emit one `[X]`
  ///    frame immediately, so a read is `<+X>` → await fresh frame →
  ///    `<-X>` ([_serialSingleNotifyRead]).
  /// 3. **No read path** — the firmware never emits the char (its
  ///    the firmware notify loop serves only N/M/S/Q/I/E/R — plus J/K with the
  ///    serial-parity firmware; the firmware has no version-frame support,
  ///    so a `versions` read times out cleanly on every firmware today —
  ///    and F/G/H are write-only commands). A descriptive
  ///    [UnsupportedError] beats `UnimplementedError`: the raw WS API
  ///    surfaces it to the client instead of crashing the read.
  Future<ByteData> _serialRead(Endpoint e) async {
    if (transportType != TransportType.serial) {
      throw "Invalid transport type, expected Serial";
    }

    switch (e) {
      // -- continuously subscribed: current value is the latest frame.
      case Endpoint.requestedState:
      case Endpoint.stateInfo:
        return _stateSubject.first;
      case Endpoint.readFromMMR:
        return _mmrSubject.first;
      case Endpoint.fwMapRequest:
        return _fwMapRequestSubject.first;
      case Endpoint.shotSettings:
        // Note: the the Bengle firmware accepts <K> writes but does not emit
        // [K] frames (no the firmware notify loop block), so on serial this stays the
        // seeded zero frame until the firmware gains [K] support.
        return shotSettingsSubject.first;
      case Endpoint.shotSample:
        return _shotSampleSubject.first;
      case Endpoint.waterLevels:
        return _waterLevelsSubject.first;
      case Endpoint.bengleShotSample:
        return _bengleShotSampleSubject.first;

      // -- single-notify round trips.
      case Endpoint.versions:
        return _serialSingleNotifyRead(e, _versionsController.stream);
      case Endpoint.temperatures:
        return _serialSingleNotifyRead(e, _temperaturesController.stream);
      case Endpoint.calibration:
        return _serialSingleNotifyRead(e, _calibrationController.stream);

      // -- no serial read path.
      case Endpoint.setTime:
      case Endpoint.shotDirectory:
      case Endpoint.writeToMMR:
      case Endpoint.shotMapRequest:
      case Endpoint.deleteShotRange:
      case Endpoint.deprecatedShotDesc:
      case Endpoint.headerWrite:
      case Endpoint.frameWrite:
        throw UnsupportedError(
          'Endpoint ${e.name} has no serial read path: the DE1 serial view '
          'never emits [${e.representation}] frames',
        );
    }
  }

  /// One-shot serial read of a characteristic that is not continuously
  /// subscribed: arm a listener, provoke a single notify with
  /// `<+X>`, await the fresh frame, then `<-X>` so the read leaves no
  /// stream subscription behind. Bounded by [serialSingleReadTimeout] so
  /// firmware that never emits the char yields a clean [TimeoutException]
  /// instead of a hang.
  Future<ByteData> _serialSingleNotifyRead(
    Endpoint e,
    Stream<ByteData> frames,
  ) async {
    final t = _transport;
    if (t is! SerialTransport) {
      throw StateError(
        '_serialSingleNotifyRead(${e.name}) requires a serial transport',
      );
    }
    // Arm BEFORE requesting so the reply can't slip between the write
    // completing and the listener attaching (same race `_mmrReadRaw`
    // guards against).
    final response = frames.first.timeout(serialSingleReadTimeout);
    // If the request write throws, nothing awaits `response` and its later
    // timeout would surface as an unhandled async error — mark it handled.
    response.ignore();
    try {
      await t.writeCommand('<+${e.representation}>');
      return await response;
    } finally {
      await t.writeCommand('<-${e.representation}>');
    }
  }

  Future<void> write(LogicalEndpoint endpoint, Uint8List data) async {
    if (await _transport.connectionState.first != device.ConnectionState.connected) {
      throw const DeviceNotConnectedException.machine();
    }
    try {
      _log.fine('about to write to ${endpoint.name}');
      _log.fine(
        'payload: ${data.map((el) => el.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      switch (transportType) {
        case TransportType.ble:
          if (endpoint.uuid == null) {
            throw StateError(
                'UnifiedDe1Transport.write: endpoint ${endpoint.name} has no BLE wire support');
          }
          await _bleWrite(endpoint, data, false);
          break;
        case TransportType.serial:
          if (endpoint.representation == null) {
            throw StateError(
                'UnifiedDe1Transport.write: endpoint ${endpoint.name} has no serial wire support');
          }
          await _serialWrite(endpoint, data);
          break;
        default:
          throw ("Unknown transport type: $transportType");
      }
    } catch (e, st) {
      if (_isBleTimeout(e)) {
        if (await _handleBleTimeout(e, st)) {
          _log.info('Retrying write to ${endpoint.name} after reconnect');
          return write(endpoint, data);
        }
      }
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  Future<void> writeWithResponse(LogicalEndpoint endpoint, Uint8List data) async {
    if (await _transport.connectionState.first != device.ConnectionState.connected) {
      throw const DeviceNotConnectedException.machine();
    }
    try {
      _log.fine('about to write to ${endpoint.name}');
      _log.fine(
        'payload: ${data.map((el) => el.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      switch (transportType) {
        case TransportType.ble:
          if (endpoint.uuid == null) {
            throw StateError(
                'UnifiedDe1Transport.writeWithResponse: endpoint ${endpoint.name} has no BLE wire support');
          }
          await _bleWrite(endpoint, data, true);
          break;
        case TransportType.serial:
          if (endpoint.representation == null) {
            throw StateError(
                'UnifiedDe1Transport.writeWithResponse: endpoint ${endpoint.name} has no serial wire support');
          }
          await _serialWrite(endpoint, data);
          break;
        default:
          throw ("Unknown transport type: $transportType");
      }
    } catch (e, st) {
      if (_isBleTimeout(e)) {
        if (await _handleBleTimeout(e, st)) {
          _log.info('Retrying write to ${endpoint.name} after reconnect');
          return writeWithResponse(endpoint, data);
        }
      }
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  bool _isBleTimeout(Object error) {
    return transportType == TransportType.ble &&
        error is BleTimeoutException;
  }

  /// Attempts to recover from a BLE timeout by reconnecting.
  /// Returns true if reconnect succeeded, false if it failed.
  Future<bool> _handleBleTimeout(Object error, StackTrace st) async {
    _log.warning('BLE write timed out, attempting reconnect');
    _recovering = true;
    try {
      await _transport.disconnect();
      await _transport.connect();
      await _bleConnect();
      _log.info('BLE reconnect successful after timeout');
      return true;
    } catch (reconnectError) {
      _log.severe(
        'BLE reconnect failed, disconnecting',
        reconnectError,
      );
      // Recovery failed — this is a genuine disconnect. Clear the guard
      // before tearing down so the `disconnected` reaches upstream.
      _recovering = false;
      try {
        // Don't await — BLE stack may be unresponsive
        _transport.disconnect();
      } catch (e, st) {
        _log.fine('transport.disconnect() during BLE recovery failed', e, st);
      }
      return false;
    } finally {
      _recovering = false;
    }
  }

  Future<void> _serialWrite(LogicalEndpoint e, Uint8List data) async {
    if (_transport is! SerialTransport) {
      throw "Invalid transport type, expected Serial";
    }
    var frame = data;
    // length-exact framing. Only writeToMMR has a short-frame
    // producer (the DFU uploader's final image chunk); every other caller
    // already emits struct-sized frames (`_mmrWriteRaw` pads to 20,
    // Header/Frame writes are 5 B / 8 B by construction). See
    // [_writeToMmrFrameBytes] for why the firmware requires this.
    if (e == Endpoint.writeToMMR && data.length < _writeToMmrFrameBytes) {
      frame = Uint8List(_writeToMmrFrameBytes)..setRange(0, data.length, data);
    }
    final payload = frame
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join('');
    await _transport.writeCommand('<${e.representation!}>$payload');
  }

  Future<void> _bleWrite(LogicalEndpoint e, Uint8List data, bool withResponse) async {
    if (_transport is! BLETransport) {
      throw "Invalid transport type, expected BLE";
    }

    await _transport.write(
      de1ServiceUUID,
      e.uuid!,
      data,
      withResponse: withResponse,
    );
  }
}
