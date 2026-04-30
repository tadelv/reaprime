import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale_serial.dart';
import 'package:reaprime/src/models/device/impl/sensor/debug_port.dart';
import 'package:reaprime/src/models/device/impl/sensor/sensor_basket.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
import 'mmr_codec.dart';
import 'usb_ids.dart';
import 'utils.dart';

import 'package:rxdart/subjects.dart';

import 'package:libserialport/libserialport.dart';

class SerialServiceDesktop implements DeviceDiscoveryService {
  final _log = Logger("Serial service");

  // StreamSubscription<UsbEvent>? _usbSerialSubscription;
  List<Device> _devices = [];

  // Maps port path (e.g. /dev/cu.usbmodem123) to device ID (e.g. 5B1F0919231)
  // so we can deduplicate across rescans.
  final Map<String, String> _portPathToDeviceId = {};

  // Parallel map tracking the `_DesktopSerialPort` instance bound to each
  // path. Used so scan cleanup can `dispose()` an orphaned transport (stops
  // its reader isolate, closes the libserialport handle) when the
  // underlying OS port vanishes.
  final Map<String, _DesktopSerialPort> _portPathToTransport = {};

  // Guard against concurrent scans
  bool _isScanning = false;
  Future<void>? _currentScan;

  final BehaviorSubject<List<Device>> _machineSubject = BehaviorSubject.seeded(
    <Device>[],
  );
  @override
  Stream<List<Device>> get devices => _machineSubject.stream;

  @override
  Future<void> initialize() async {
    final list = SerialPort.availablePorts;
    _log.info("Initializing");
    _log.info("found ports: $list");
  }

  @override
  void stopScan() {} // Serial enumeration is instant, nothing to stop.

  @override
  Future<void> scanForDevices() async {
    // If already scanning, wait for that scan to complete
    if (_isScanning) {
      _log.info("Scan already in progress, waiting for completion");
      await _currentScan;
      return;
    }

    _isScanning = true;
    _currentScan = _performScan();
    
    try {
      await _currentScan;
    } finally {
      _isScanning = false;
      _currentScan = null;
    }
  }

  Future<void> _performScan() async {
    final ports = await SerialPort.availablePorts;
    _log.info("Found ports: $ports");

    // Classify each currently-known device by liveness. Anything not yet
    // `disconnected` is still owning its port — we must NOT re-detect it in
    // this scan (that would create a duplicate `_DesktopSerialPort` with a
    // second reader isolate on the same tty; previously observed as two
    // `SensorBasket` instances after wake-from-sleep and two HDS instances
    // on macOS after scale-picker pending).
    final devicesCopy = List<Device>.from(_devices);
    final live = <Device>[];
    for (var d in devicesCopy) {
      final state = await d.connectionState.first;
      if (state != ConnectionState.disconnected) {
        live.add(d);
      }
    }

    // Reconcile dedup + transport maps with reality. A tracked path is
    // stale if EITHER:
    //   (a) the OS port no longer exists (physical unplug / OS rename), OR
    //   (b) the device bound to that path has self-disconnected (watchdog,
    //       serial error, explicit disconnect) even if the tty is still
    //       present. Freeing the slot lets the next scan re-detect the
    //       port with a fresh transport.
    // In either case we dispose the transport (stops the reader isolate
    // and frees the libserialport handle) and drop the entry.
    final availablePorts = ports.toSet();
    final liveDeviceIds = live.map((d) => d.deviceId).toSet();
    final stalePaths = _portPathToDeviceId.entries
        .where((e) =>
            !availablePorts.contains(e.key) ||
            !liveDeviceIds.contains(e.value))
        .map((e) => e.key)
        .toList();
    for (final path in stalePaths) {
      final deviceId = _portPathToDeviceId.remove(path);
      final transport = _portPathToTransport.remove(path);
      final reason = !availablePorts.contains(path)
          ? "port vanished"
          : "device disconnected";
      _log.warning("Reaping transport for $path (deviceId=$deviceId, "
          "reason=$reason) — disposing");
      if (transport != null) {
        try {
          await transport.dispose();
        } catch (e, st) {
          _log.warning("dispose failed for $path", e, st);
        }
      }
      if (deviceId != null) {
        live.removeWhere((d) => d.deviceId == deviceId);
      }
    }

    // Collect stable IDs of live devices for the cross-path dedup below.
    // (Recomputed after the stale-reap above in case it dropped anything.)
    final liveStableIds = live.map((d) => d.deviceId).toSet();

    // Pre-filter ports: skip already-connected, Bluetooth, and non-USB ports
    final scanPorts = ports.where((p) {
      if (_portPathToDeviceId.containsKey(p)) return false;
      final port = SerialPort(p);
      final meta = _readPortMetadata(p, port);
      port.dispose();
      if (meta.stableId != null &&
          liveStableIds.contains(meta.stableId)) {
        return false;
      }
      if (meta.transport == "Bluetooth") return false;
      // Known device productNames — always scan regardless of port name
      if (meta.productName == 'DE1' ||
          meta.productName == 'Half Decent Scale') {
        return true;
      }
      // Unix-style USB serial port names
      if (meta.name.contains('serial') ||
          meta.name.contains('usbmodem') ||
          meta.name.contains('ttyACM') ||
          meta.name.contains('ttyUSB')) {
        return true;
      }
      // Windows COM ports with USB transport
      if (meta.transport == "USB" && meta.name.startsWith('COM')) {
        return true;
      }
      return false;
    }).toList();

    _log.info("Scanning ${scanPorts.length} USB serial ports: $scanPorts");

    // Scan ports in parallel instead of sequentially
    final rawResults = await Future.wait(
      scanPorts.map((portId) async {
        try {
          return await _detectDevice(portId);
        } catch (e, st) {
          _log.warning("Error detecting device on $portId", e, st);
          return null;
        }
      }),
    );
    // Merge the still-live devices (any state except disconnected) with
    // newly-detected ones. Previously the merge used only `connected`,
    // which dropped devices sitting in `discovered` or `connecting` — the
    // next scan would then re-detect them from scratch and spawn a second
    // `_DesktopSerialPort` on the same tty.
    final results = <Device?>[...rawResults, ...live];

    _devices = results.whereType<Device>().toList();
    _machineSubject.add(_devices);
    _log.info("Added devices: $_devices");
  }

  _PortMetadata _readPortMetadata(String path, SerialPort port) {
    // libserialport reads USB descriptors from sysfs on Linux; some drivers
    // (or missing udev rules / permissions) cause getters to throw
    // `SerialPortError: No such file or directory, errno = 2`. Any throw here
    // must not abort the whole scan — fall back to name-based matching.
    String name = path;
    String transport = 'Unknown';
    String? productName;
    int? vid;
    int? pid;
    String? serial;
    try { name = port.name ?? path; } catch (_) {}
    try { transport = port.transport.toTransport(); } catch (_) {}
    try { productName = port.productName; } catch (_) {}
    try { vid = port.vendorId; } catch (_) {}
    try { pid = port.productId; } catch (_) {}
    try { serial = port.serialNumber; } catch (_) {}
    final stableId = computeUsbStableId(vid: vid, pid: pid, serial: serial);
    return _PortMetadata(
      name: name,
      transport: transport,
      productName: productName,
      stableId: stableId,
    );
  }

  Future<Device?> _detectDevice(String id) async {
    final port = SerialPort(id);
    _log.info("detecting: ${port.name} ; ${port.productName} ; ${port.transport.toTransport()}");
    if (port.transport.toTransport() == "Bluetooth") {
      port.dispose();
      return null;
    }

    final transport = _DesktopSerialPort(port: port);
    // Track the transport up-front so any cleanup path (including an
    // exception partway through detection) can find + dispose it.
    _portPathToTransport[id] = transport;
    // De1 shortcut
    if (port.productName == "DE1") {
      final device = UnifiedDe1(transport: transport);
      _portPathToDeviceId[id] = device.deviceId;
      return device;
    }

    // Bengle shortcut (productName likely lands as "Bengle" once FW
    // exposes it; trivial future-proofing).
    if (port.productName == "Bengle") {
      final device = Bengle(transport: transport);
      _portPathToDeviceId[id] = device.deviceId;
      return device;
    }

    // Half Decent Scale shortcut
    if (port.productName == "Half Decent Scale") {
      final device = HDSSerial(transport: transport);
      _portPathToDeviceId[id] = device.deviceId;
      return device;
    }

    // VID:PID shortcut.
    int? vid;
    int? pid;
    try { vid = port.vendorId; } catch (_) {}
    try { pid = port.productId; } catch (_) {}
    final usbModel = matchUsbDevice(usbDeviceTable, vid: vid, pid: pid);
    if (usbModel != null) {
      final device = usbModel == UsbDeviceModel.bengle
          ? Bengle(transport: transport)
          : UnifiedDe1(transport: transport);
      _portPathToDeviceId[id] = device.deviceId;
      return device;
    }

    final rawData = <Uint8List>[];
    const readDuration = Duration(milliseconds: 1800);
    _log.fine("Inspecting: ${port.name}, ${port.productName}");

    try {
      await transport.connect().timeout(Duration(milliseconds: 300));

      // Collect data with a timeout rather than a fixed delay
      final subscription = transport.rawStream.listen(rawData.add);

      // Wait for data or timeout
      await subscription.asFuture<void>().timeout(
        readDuration,
        onTimeout: () async {
          await subscription.cancel();
        },
      );

      final combined = rawData.expand((e) => e).toList();
      List<String> strings = [];
      try {
        strings = rawData
            .map((e) => utf8.decode(e, allowMalformed: true))
            .toList()
            .join()
            .split('\n');
      } catch (e) {
        _log.warning("failed to decode:", e);
      }
      _log.info("Collected serial data: ${combined.map((e) => e.toRadixString(16).padLeft(2,'0'))}");
      _log.info("parsed into strings: ${strings}");
      if (combined.isEmpty && strings.isEmpty) {
        throw ('no data collected');
      }
      if (strings.any((s) => s.startsWith('R '))) {
        final device = DebugPort(transport: transport);
        _portPathToDeviceId[id] = device.deviceId;
        return device;
      } else if (isDecentScale(strings, rawData)) {
        _log.info("Detected: Decent Scale");
        final device = HDSSerial(transport: transport);
        _portPathToDeviceId[id] = device.deviceId;
        return device;
      } else if (isSensorBasket(strings)) {
        _log.info("Detected: Sensor Basket");
        final device = SensorBasket(transport: transport);
        _portPathToDeviceId[id] = device.deviceId;
        return device;
      } else {
        // Detect DE1-family by sending state + MMR-notify enables, then
        // waiting for `[M]` (DE1 protocol baseline) and `[E]` (v13Model
        // MMR response) to come back. v13Model >= 128 → Bengle.
        final messages = <String>[];
        final stateSubscription = transport.readStream.listen(messages.add);

        await transport.writeCommand('<+M>');
        await transport.writeCommand('<+E>');

        // Fire the v13Model MMR-read request. Address layout for
        // 0x0080000C: byte[0]=length, byte[1..3]=addr triplet.
        final req = buildMmrReadRequest(address: 0x0080000C, length: 4);
        final reqHex = req
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        try {
          await transport.writeCommand('<F>$reqHex');
        } catch (e) {
          _log.fine('MMR read request failed during probe', e);
        }

        try {
          await stateSubscription.asFuture<void>().timeout(
            readDuration,
            onTimeout: () async {
              await stateSubscription.cancel();
            },
          );
        } finally {
          await transport.writeCommand('<-M>');
          await transport.writeCommand('<-E>');
        }

        if (isDE1(messages.join().split('\n'), combined)) {
          // DE1-family confirmed. Scan the same message buffer for the
          // v13Model MMR response to disambiguate DE1 vs Bengle.
          int? v13Model;
          for (final line in messages.join().split('\n')) {
            final v = decodeMmrInt32Response(
              line.trim(),
              expectedAddr: (0x80, 0x00, 0x0C),
            );
            if (v != null) {
              v13Model = v;
              break;
            }
          }

          final isBengle = v13Model != null && v13Model >= 128;
          _log.info(
              "Detected: ${isBengle ? 'Bengle' : 'DE1'} (v13Model=$v13Model)");
          final device = isBengle
              ? Bengle(transport: transport)
              : UnifiedDe1(transport: transport);
          _portPathToDeviceId[id] = device.deviceId;
          return device;
        }
      }

      _log.warning("Unknown device on port $id");
      _portPathToTransport.remove(id);
      await transport.dispose();
      return null;
    } catch (e, st) {
      _log.warning("Port $id is probably not a device we want", e, st);
      _portPathToTransport.remove(id);
      await transport.dispose();
      return null;
    }
  }
}

class _DesktopSerialPort implements SerialTransport {
  final SerialPort _port;
  late Logger _log;
  final BehaviorSubject<ConnectionState> _open = BehaviorSubject.seeded(ConnectionState.discovered);

  @override
  Stream<ConnectionState> get connectionState => _open.asBroadcastStream();

  _DesktopSerialPort({required SerialPort port}) : _port = port {
    _log = Logger("SerialPort:${port.name}");
  }

  @override
  Future<void> disconnect() async {
    _portSubscription?.cancel();
    _port.close();
    _open.add(ConnectionState.disconnected);
  }

  /// End-of-life cleanup. Calls `disconnect()` to stop the reader isolate +
  /// close the tty, then frees the libserialport `sp_port` FFI handle and
  /// closes the exposed stream controllers. Safe to call more than once.
  Future<void> dispose() async {
    try {
      await disconnect();
    } catch (e) {
      _log.warning("dispose: disconnect failed", e);
    }
    try {
      _port.dispose();
    } catch (e) {
      _log.warning("dispose: _port.dispose failed", e);
    }
    if (!_rawStreamController.isClosed) {
      await _rawStreamController.close();
    }
    if (!_readController.isClosed) {
      await _readController.close();
    }
    if (!_open.isClosed) {
      await _open.close();
    }
  }

  @override
  String get id {
    // USB descriptor getters can throw on Linux when sysfs attrs are missing
    // (some drivers / permission issues). Fall back to port address.
    int? vid;
    int? pid;
    String? serial;
    try { vid = _port.vendorId; } catch (_) {}
    try { pid = _port.productId; } catch (_) {}
    try { serial = _port.serialNumber; } catch (_) {}
    final stable = computeUsbStableId(vid: vid, pid: pid, serial: serial);
    return stable ?? "${_port.address}";
  }

  @override
  String get name => _port.name ?? "Unknown port";

  StreamSubscription<Uint8List>? _portSubscription;

  final StreamController<Uint8List> _rawStreamController =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get rawStream => _rawStreamController.stream;

  @override
  Future<void> connect() async {
    // Log name↔id mapping on every connect attempt so later log lines tagged
    // either by path (`SerialPort:/dev/tty…`) or stable id
    // (`UnifiedDe1Transport-usb-…`) can be correlated.
    final instanceTag = "instance=${identityHashCode(this).toRadixString(16)}";
    String? description;
    String? manufacturer;
    try { description = _port.description; } catch (_) {}
    try { manufacturer = _port.manufacturer; } catch (_) {}
    _log.info(
      "connect() name=${_port.name} id=$id $instanceTag "
      "description=$description manufacturer=$manufacturer isOpen=${_port.isOpen}",
    );

    if (_port.isOpen) {
      _log.warning("already open (id=$id $instanceTag) — bailing out of connect()");
      return;
    }
    await Future.microtask(() async {
      if (await _port.open(mode: 3) == false) {
        _log.warning("could not open port");
        throw "failed to open port: ${SerialPort.lastError}";
      }
      final SerialPortConfig cfg = SerialPortConfig();
      cfg.baudRate = 115200;
      cfg.bits = 8;
      cfg.parity = 0;
      cfg.stopBits = 1;
      cfg.rts = 0;
      cfg.cts = 0;
      cfg.dtr = 0;
      cfg.dsr = 0;
      cfg.xonXoff = 0;
      cfg.setFlowControl(0);
      await _port.setConfig(cfg);
      // _port.config = cfg;
      _log.finest("current config: ${_port.config.bits}");
      _log.finest("current config: ${_port.config.parity}");
      _log.finest("current config: ${_port.config.stopBits}");
      _log.finest("current config: ${_port.config.baudRate}");

      _log.fine("port opened");
      final reader = SerialPortReader(_port);
      final readerTag = "reader=${identityHashCode(reader).toRadixString(16)}";
      _log.info("subscribing reader (id=$id $instanceTag $readerTag)");
      _portSubscription = reader.stream.listen(
        (data) {
          _rawStreamController.add(data);
          try {
            final input = utf8.decode(data);
            _log.finest("received serial input: $input");
            _readController.add(input);
          } catch (e) {
            _log.finest("unable to parse serial input to string", e);
          }
        },
        onError: (error) {
          _log.severe(
            "port error (id=$id $instanceTag $readerTag): $error",
          );
          _readController.addError(error);
          disconnect();
        },
        onDone: () {
          // Also fires when the libserialport reader isolate dies on an
          // uncaught `throw bytes` from `_SerialPortReaderImpl._waitRead`
          // (package:libserialport/src/reader.dart:151). When that happens
          // the Dart VM logs `[ERROR:…] Unhandled exception: <negative int>`
          // with no port identity — correlate by $readerTag / time proximity.
          _log.warning(
            "serial stream closed (onDone) — cable unplug or reader isolate "
            "death. id=$id $instanceTag $readerTag",
          );
          disconnect();
        },
      );
      _log.fine("port subscribed: ${_portSubscription} ($readerTag)");
    });
    _open.add(ConnectionState.connected);
  }

  final StreamController<String> _readController =
      StreamController<String>.broadcast();
  @override
  Stream<String> get readStream => _readController.stream;

  @override
  Future<void> writeCommand(String command) async {
    await _write(utf8.encode("$command\n"));
    _log.fine("wrote: $command");
  }

  @override
  Future<void> writeHexCommand(Uint8List command) async {
    await _write(command);
  }

  Future<void> _write(Uint8List command) async {
    try {
      // Write all bytes, handling short writes by looping.
      // timeout: 0 = blocking write (waits until bytes are accepted by OS).
      int offset = 0;
      while (offset < command.length) {
        final chunk =
            offset == 0 ? command : Uint8List.sublistView(command, offset);
        final written = await _port.write(chunk, timeout: 0);
        if (written < 0) {
          throw StateError('Serial write failed: ${SerialPort.lastError}');
        }
        offset += written;
      }
      _port.drain();
      _log.fine("wrote: ${command.map((e) => e.toRadixString(16))}");
      if (Platform.isLinux || Platform.isMacOS) {
        await Future.delayed(Duration(milliseconds: 20), () {
          _log.finest("delaying next write");
        });
      }
    } catch (e) {
      _log.warning("Serial write error, disconnecting", e);
      await disconnect();
      rethrow;
    }
  }
}

class _PortMetadata {
  final String name;
  final String transport;
  final String? productName;
  final String? stableId;
  _PortMetadata({
    required this.name,
    required this.transport,
    required this.productName,
    required this.stableId,
  });
}

extension IntToString on int {
  String toHex() => '0x${toRadixString(16)}';
  String toPadded([int width = 3]) => toString().padLeft(width, '0');
  String toTransport() {
    switch (this) {
      case SerialPortTransport.usb:
        return 'USB';
      case SerialPortTransport.bluetooth:
        return 'Bluetooth';
      case SerialPortTransport.native:
        return 'Native';
      default:
        return 'Unknown';
    }
  }
}

