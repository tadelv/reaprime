import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
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

import 'package:usb_serial/usb_serial.dart';

class SerialServiceAndroid implements DeviceDiscoveryService {
  final _log = Logger("Android Serial service");

  List<Device> _devices = [];
  
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
    List<UsbDevice> devices = await UsbSerial.listDevices();
    _log.info("found ${devices}");

    UsbSerial.usbEventStream?.listen((data) async {
      switch (data.event) {
        case UsbEvent.ACTION_USB_DETACHED:
          _log.info("USB_DETACHED: device=${data.device?.productName ?? 'null'} "
              "raw=${data.device?.deviceId}");
          if (data.device != null) {
            // Match by stable ID, falling back to vid:pid prefix match.
            // Android detach events often have null serial, so exact stable ID
            // won't match. Use vid:pid prefix to find the orphaned device.
            final vid = data.device!.vid;
            final pid = data.device!.pid;
            final detachedStableId = computeUsbStableId(
              vid: vid,
              pid: pid,
              serial: data.device!.serial,
            );
            final vidPidPrefix = (vid != null && pid != null)
                ? 'usb-${vid.toRadixString(16)}-${pid.toRadixString(16)}-'
                : null;
            _log.info("USB_DETACHED: stableId=${detachedStableId ?? 'none'}, "
                "prefix=$vidPidPrefix");
            final match = _devices.firstWhereOrNull((d) =>
                d.deviceId == detachedStableId ||
                (vidPidPrefix != null && d.deviceId.startsWith(vidPidPrefix)) ||
                d.deviceId == "${data.device!.deviceId}");
            if (match != null) {
              _log.info("USB_DETACHED: disconnecting ${match.name}(${match.deviceId})");
              match.disconnect();
              _devices.remove(match);
            } else {
              _log.warning("USB_DETACHED: no matching device in $_devices");
            }
          } else {
            // No device info — disconnect all serial devices as a fallback
            _log.warning("USB_DETACHED: device is null, disconnecting "
                "${_devices.length} serial device(s)");
            for (final d in _devices) {
              d.disconnect();
            }
            _devices.clear();
          }
          _machineSubject.add(_devices);
          break;
        default:
          _log.info("USB event: ${data.event}, device=${data.device?.productName ?? 'null'}");
          break;
      }
    });
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
    List<Device> connected = [];
    // Create a copy to avoid concurrent modification during iteration
    final devicesCopy = List<Device>.from(_devices);
    for (var d in devicesCopy) {
      final state = await d.connectionState.first;
      if (state == ConnectionState.connected) {
        connected.add(d);
      }
    }

    final removed = _devices.where((d) => !connected.contains(d)).toList();
    if (removed.isNotEmpty) {
      _log.info("Removing ${removed.length} non-connected devices: "
          "${removed.map((d) => '${d.name}(${d.deviceId})').join(', ')}");
    }
    _devices.removeWhere((d) => connected.contains(d) == false);
    if (connected.isNotEmpty) {
      _log.fine("Keeping ${connected.length} connected: "
          "${connected.map((d) => '${d.name}(${d.deviceId})').join(', ')}");
    }

    var devices = await UsbSerial.listDevices();
    _log.info("USB enumeration: ${devices.length} ports "
        "(${devices.map((d) => '${d.productName ?? d.deviceName}[${computeUsbStableId(vid: d.vid, pid: d.pid, serial: d.serial) ?? d.deviceId}]').join(', ')})");

    // Orphan GC: force-disconnect connected devices whose port vanished from USB enumeration
    final enumeratedIds = devices.map((d) =>
        computeUsbStableId(vid: d.vid, pid: d.pid, serial: d.serial) ?? "${d.deviceId}"
    ).toSet();
    final orphans = connected.where((d) => !enumeratedIds.contains(d.deviceId)).toList();
    for (final orphan in orphans) {
      _log.warning("Orphan GC: ${orphan.name}(${orphan.deviceId}) not in USB enumeration, forcing disconnect");
      await orphan.disconnect();
      connected.remove(orphan);
      _devices.remove(orphan);
    }

    // Filter out USB devices whose stable ID matches an already-known device.
    devices.removeWhere((d) {
      final usbStableId = computeUsbStableId(
        vid: d.vid,
        pid: d.pid,
        serial: d.serial,
      );
      final isDuplicate = usbStableId != null
          ? _devices.any((t) => t.deviceId == usbStableId)
          : _devices.any((t) => t.deviceId == "${d.deviceId}");
      if (isDuplicate) {
        _log.fine("Skipping ${d.productName ?? d.deviceName}: "
            "already connected as ${usbStableId ?? d.deviceId}");
      }
      return isDuplicate;
    });

    _log.info("${devices.length} new devices to detect");
    final results = await Future.wait(
      devices.map((d) async {
        try {
          final device = await _detectDevice(d);
          _log.info("Port $d -> ${device ?? 'no device'}");
          return device;
        } catch (e, st) {
          _log.warning("Error detecting device on $d", e, st);
          return null;
        }
      }),
    );
    _devices.addAll(results.whereType<Device>());
    _machineSubject.add(_devices);
  }

  Future<Device?> _detectDevice(UsbDevice device) async {
    _log.info("device name: ${device.productName}");
    if (device.productName?.contains('Serial') == false &&
        !(device.productName == 'DE1') &&
        !(device.productName == 'Half Decent Scale')) {
      return null;
    }
    UsbPort? port;
    try {
      port = await device.create(UsbSerial.CDC);
    } catch (e) {
      port = await device.create(UsbSerial.CH34x);
    }
    // final port = await device.create(UsbSerial.CDC);
    if (port == null) {
      _log.warning("failed to add $device, port is null");
      return null;
    }
    final transport = AndroidSerialPort(device: device, port: port);

    // yay, shortcuts
    if (device.productName == "DE1") {
      _log.info("short circuit to de1");
      return UnifiedDe1(transport: transport);
    }

    // Bengle shortcut (productName likely lands as "Bengle" once FW
    // exposes it; trivial future-proofing).
    if (device.productName == "Bengle") {
      _log.info("short circuit to bengle");
      return Bengle(transport: transport);
    }

    // Half Decent Scale shortcut
    if (device.productName == "Half Decent Scale") {
      _log.info("short circuit to Half Decent Scale");
      return HDSSerial(transport: transport);
    }

    // VID:PID shortcut.
    final usbModel =
        matchUsbDevice(usbDeviceTable, vid: device.vid, pid: device.pid);
    if (usbModel != null) {
      _log.info("short circuit via VID:PID -> $usbModel");
      return usbModel == UsbDeviceModel.bengle
          ? Bengle(transport: transport)
          : UnifiedDe1(transport: transport);
    }

    final List<Uint8List> rawData = [];
    final duration = const Duration(seconds: 3);

    try {
      await transport.connect().timeout(Duration(milliseconds: 300));

      // Start listening to the stream
      final subscription = transport.rawStream.listen(
        (chunk) {
          rawData.add(chunk);
        },
        onError: (err, st) => _log.warning("Serial read error", err, st),
        cancelOnError: false,
      );

      // Collect for the desired duration
      await Future.delayed(duration);
      await subscription.cancel();

      // Combine all chunks into one buffer
      final combined = rawData.expand((e) => e).toList();
      List<String> strings = [];
      try {
        strings = rawData.map(utf8.decode).toList().join().split('\n');
      } catch (_) {}
      _log.info(
        "Collected serial data: ${combined.map((e) => e.toRadixString(16).padLeft(2, '0'))}",
      );
      _log.info("parsed into strings: ${strings}");

      // Heuristic checks for device type
      if (strings.any((s) => s.startsWith('R '))) {
        return DebugPort(transport: transport);
      } else if (isDecentScale(strings, rawData)) {
        _log.info("Detected: Decent Scale");
        return HDSSerial(transport: transport);
      } else if (isSensorBasket(strings)) {
        _log.info("Detected: Sensor Basket");
        return SensorBasket(transport: transport);
      } else {
        // try and check if we get some replies when subscribing to state.
        // Also fire a v13Model MMR-read request so we can disambiguate
        // DE1 vs Bengle inline.
        final List<String> messages = [];
        final sub = transport.readStream.listen((line) {
          messages.add(line);
        });
        await transport.writeCommand('<+M>');
        await transport.writeCommand('<+E>');

        final req = buildMmrReadRequest(address: 0x0080000C, length: 0);
        final reqHex = req
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        try {
          await transport.writeCommand('<E>$reqHex');
        } catch (e) {
          _log.fine('MMR read request failed during probe', e);
        }

        await Future.delayed(duration);
        await transport.writeCommand('<-M>');
        await transport.writeCommand('<-E>');
        sub.cancel();
        final List<String> lines = messages.join().split('\n');
        if (isDE1(lines, combined)) {
          int? v13Model;
          for (final line in lines) {
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
          return isBengle
              ? Bengle(transport: transport)
              : UnifiedDe1(transport: transport);
        }
      }

      _log.warning("Unknown device on port $device");
      await transport.disconnect();
      return null;
    } catch (e, st) {
      _log.warning("Port $device is probably not a device we want", e, st);
      await transport.disconnect();
      return null;
    }
  }
}

class AndroidSerialPort implements SerialTransport {
  final UsbDevice _device;
  final UsbPort _port;
  late Logger _log;
  final BehaviorSubject<ConnectionState> _open = BehaviorSubject.seeded(ConnectionState.discovered);

  @override
  Stream<ConnectionState> get connectionState => _open.asBroadcastStream();

  AndroidSerialPort({required UsbDevice device, required UsbPort port})
    : _device = device,
      _port = port {
    _log = Logger("Serial:${_device.deviceName}");
  }
  @override
  Future<void> disconnect() async {
    _log.info("disconnecting (id=$id, path=${_device.deviceName})");
    _open.add(ConnectionState.disconnected);
    _portSubscription?.cancel();
    await _port.close();
  }

  @override
  String get id {
    final stable = computeUsbStableId(
      vid: _device.vid,
      pid: _device.pid,
      serial: _device.serial,
    );
    return stable ?? "${_device.deviceId}";
  }

  @override
  String get name => _device.deviceName;

  StreamSubscription<Uint8List>? _portSubscription;
  @override
  Future<void> connect() async {
    if (await _open.first == ConnectionState.connected) {
      _log.warning('port already open');
      return;
    }
    if (await _port.open() == false) {
      throw "Failed to open port";
    }

    await _port.setDTR(false);
    await _port.setRTS(false);

    _port.setPortParameters(
      115200,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    final inputStream = _port.inputStream;
    if (inputStream == null) {
      _log.warning("inputStream is null after port.open() — no data will flow");
    }
    _portSubscription = inputStream?.listen(
      (Uint8List event) {
        _rawController.add(event);
        try {
          final input = utf8.decode(event);
          _log.finest("received serial input: $input");
          _outputController.add(input);
        } catch (e) {
          _log.fine("unable to parse to string", e);
        }
      },
      onError: (error) {
        _log.severe("port read failed", error);
        disconnect();
      },
      onDone: () {
        _log.warning("inputStream closed (onDone) — USB pipe may be dead");
        disconnect();
      },
    );
    _log.info("port connected (id=$id, path=${_device.deviceName})");
    _open.add(ConnectionState.connected);
  }

  final StreamController<Uint8List> _rawController =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get rawStream => _rawController.stream;

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get readStream => _outputController.stream;

  @override
  Future<void> writeCommand(String command) async {
    final toSend = "$command\n";
    await writeHexCommand(utf8.encode(toSend));
    _log.fine("wrote string: $command");
  }

  @override
  Future<void> writeHexCommand(Uint8List command) async {
    await _port.write(command);
    _log.fine("wrote request: ${command.map((e) => e.toRadixString(16))}");
  }
}



