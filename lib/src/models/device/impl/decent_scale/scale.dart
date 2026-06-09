import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/serial/serial_service_desktop.dart';
import 'package:logging/logging.dart' as logging;
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

class DecentScale implements Scale, TransportHandoffScale {
  static final BleServiceIdentifier serviceIdentifier =
      BleServiceIdentifier.short('fff0');
  static final BleServiceIdentifier dataCharacteristic =
      BleServiceIdentifier.short('fff4');
  static final BleServiceIdentifier writeCharacteristic =
      BleServiceIdentifier.short('36f5');

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _device;

  final logging.Logger _log = logging.Logger("Decent scale");

  Timer? _heartbeatTimer;

  // Watchdog: heartbeat fires every 4s; warn after 3 missed (12s), disconnect after 5 (20s).
  // BLE is slower than USB so thresholds are more generous than HDSSerial.
  static const _watchdogWarningTicks = 3;
  static const _watchdogDisconnectTicks = 5;
  int _ticksSinceLastNotification = 0;
  bool _watchdogRetryAttempted = false;
  int _totalNotifications = 0;
  int _heartbeatTotalTicks = 0;

  DecentScale({required BLETransport transport})
    : _deviceId = transport.id,
      _device = transport;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  DeviceType get type => DeviceType.scale;

  @override
  String get name => "Decent Scale";

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.discovered);

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  StreamSubscription<ConnectionState>? subscription;
  @override
  Future<void> onConnect() async {
    _log.info("on connect (id=$deviceId)");
    if (await _device.connectionState.first == ConnectionState.connected) {
      return;
    }
    _connectionStateController.add(ConnectionState.connecting);

    try {
      await _device.connect();

      subscription = _device.connectionState
          .where((state) => state == ConnectionState.disconnected)
          .listen((_) {
            _log.info("Transport disconnected");
            disconnect();
          });

      final services = await _device.discoverServices();
      if (!serviceIdentifier.matchesAny(services)) {
        throw Exception(
          'Expected service ${serviceIdentifier.long} not found. '
          'Discovered services: $services',
        );
      }
      await _registerNotifications();
      _heartbeatTimer?.cancel();
      _ticksSinceLastNotification = 0;
      _watchdogRetryAttempted = false;
      _totalNotifications = 0;
      _heartbeatTotalTicks = 0;
      _heartbeatTimer = Timer.periodic(Duration(seconds: 4), (timer) async {
        if (await _connectionStateController.stream.first !=
            ConnectionState.connected) {
          timer.cancel();
          disconnect();
          return;
        }
        _heartbeatTotalTicks++;

        // Periodic heartbeat log every 5 min (75 ticks at 4s)
        if (_heartbeatTotalTicks % 75 == 0) {
          final uptimeMin = (_heartbeatTotalTicks * 4) ~/ 60;
          _log.fine("heartbeat: ${uptimeMin}m uptime, $_totalNotifications notifications");
          if (!_isSleeping) {
            await _sendOledOn();
          }
        }

        // Watchdog: only active when scale is awake (weight notifications
        // flowing). When sleeping, scale sends nothing — skip checks.
        if (!_isSleeping) {
          _ticksSinceLastNotification++;

          if (_ticksSinceLastNotification >= _watchdogDisconnectTicks) {
            _log.severe(
              "No BLE notifications for ${_watchdogDisconnectTicks * 4}s "
              "(total=$_totalNotifications, uptime=${_heartbeatTotalTicks * 4}s), disconnecting",
            );
            disconnect();
            return;
          } else if (_ticksSinceLastNotification >= _watchdogWarningTicks &&
              !_watchdogRetryAttempted) {
            _watchdogRetryAttempted = true;
            _log.warning(
              "No BLE notifications for ${_watchdogWarningTicks * 4}s "
              "(total=$_totalNotifications), re-subscribing",
            );
            _registerNotifications();
          }
        }

        await _sendHeartBeat();
      });
      await _sendHeartBeat();
      if (!_isSleeping) {
        await _sendOledOn();
      }
      _connectionStateController.add(ConnectionState.connected);
    } catch (e) {
      _log.warning('Failed to initialize scale: $e');
      subscription?.cancel();
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _connectionStateController.add(ConnectionState.disconnected);
      try {
        await _device.disconnect();
      } catch (_) {}
    }
  }

  bool _isDisconnecting = false;

  @override
  disconnect() async => _disconnect(powerOff: true);

  /// [TransportHandoffScale]: release the BLE link WITHOUT powering the
  /// physical scale off, so the controller can hand the active-scale role to
  /// another transport (USB/WiFi) of the SAME physical Half Decent Scale.
  /// Powering off here would turn the shared device off mid-switch.
  @override
  Future<void> disconnectForHandoff() => _disconnect(powerOff: false);

  Future<void> _disconnect({required bool powerOff}) async {
    if (_isDisconnecting) {
      return;
    }
    _isDisconnecting = true;
    final uptimeSec = _heartbeatTotalTicks * 4;
    _log.info("disconnecting (notifications=$_totalNotifications, "
        "uptime=${uptimeSec}s, powerOff=$powerOff)");
    subscription?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (powerOff) {
      try {
        // Best-effort: `disconnect()` often fires *on* a transport-state
        // disconnected event, in which case the write throws `device is
        // disconnected` immediately. On the happy path the scale powers
        // off after acking and severs BLE — neither outcome should block
        // or escalate. The 2 s timeout caps the wait so a flaky link
        // can't stall the rest of the disconnect sequence.
        await _sendPowerOff().timeout(const Duration(seconds: 2));
      } catch (e) {
        _log.fine('power-off write skipped (device likely already off): $e');
      }
    }
    // `BluePlusTransport.disconnect` swallows its own errors internally,
    // so no extra try/catch needed here.
    try {
      await _device.disconnect();
    } finally {
      _connectionStateController.add(ConnectionState.disconnected);
      _isDisconnecting = false;
    }
  }

  @override
  Future<void> tare() async {
    List<int> payload = [0x03, 0x0F, 0x01, 0x00, 0x00, 0x01, 0x0C];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
  }

  Future<void> _sendHeartBeat() async {
    _log.finest("send hb");
    // Heartbeat ping: tells the scale the app is still alive so it won't
    // auto-sleep or disconnect. Send even when _isSleeping — without it
    // HDS firmware times out and disconnects BLE, which wakes the display.
    // Does NOT produce a BLE notification response — watchdog
    // is fed by weight notifications (0xCE/0xCA) while scale is awake.
    List<int> payload = [0x03, 0x0A, 0x03, 0xFF, 0xFF, 0x00, 0x0A];
    try {
      await _device.write(
        serviceIdentifier.long,
        writeCharacteristic.long,
        Uint8List.fromList(payload),
      );
    } catch (e) {
      // just disconnect
      await disconnect();
    }
  }

  Future<void> _registerNotifications() async {
    await _device.subscribe(
      serviceIdentifier.long,
      dataCharacteristic.long,
      _parseNotification,
    );
  }

  void _parseNotification(List<int> data) {
    _ticksSinceLastNotification = 0;
    _watchdogRetryAttempted = false;
    _totalNotifications++;
    if (data.length < 4) return;
    _log.finest("$hashCode recv: ${data[1].toHex()}");
    switch (data[1]) {
      case 0xCE:
      case 0xCA:
        // weight
        _parseWeight(data);
      case 0x0A:
        // battery
        _parseHeartbeat(data);
    }
  }

  void _parseWeight(List<int> data) {
    var d = ByteData(2);
    d.setInt8(0, data[2]);
    d.setInt8(1, data[3]);
    var weight = d.getInt16(0) / 10;
    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: _batteryLevel.toInt(),
      ),
    );
  }

  int _batteryLevel = 100;
  void _parseHeartbeat(List<int> data) {
    final level = data[4];
    _log.fine("heartbeat: ${data.map((e) => e.toRadixString(16))}");
    _batteryLevel = min(level, 100);
  }

  Future<void> _sendOledOn() async {
    List<int> payload = [];
    payload = [0x03, 0x0A, 0x01, 0x00, 0x00, 0x01, 0x08];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
    payload = [0x03, 0x0A, 0x04, 0x00, 0x00, 0x01, 0x08];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
  }

  Future<void> _sendOledOff() async {
    List<int> payload = [];
    payload = [0x03, 0x0A, 0x04, 0x01, 0x00, 0x01, 0x09];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
    payload = [0x03, 0x0A, 0x00, 0x01, 0x00, 0x01, 0x09];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
  }

  bool _isSleeping = false;

  @override
  Future<void> sleepDisplay() async {
    _isSleeping = true;
    _log.info('Putting Decent Scale display to sleep');
    await _sendOledOff();
  }

  Future<void> _sendPowerOff() async {
    _log.info("sending power off");
    List<int> payload = [0x03, 0x0A, 0x02, 0x00, 0x00, 0x00, 0x00];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
      timeout: Duration(seconds: 10),
    );
  }

  @override
  Future<void> wakeDisplay() async {
    _isSleeping = false;
    // Reset watchdog so scale has time to resume sending weight notifications
    _ticksSinceLastNotification = 0;
    _watchdogRetryAttempted = false;
    _log.info('Waking Decent Scale display');
    await _sendOledOn();
  }

  @override
  Future<void> startTimer() async {
    List<int> payload = [0x03, 0x0B, 0x03, 0x00, 0x00, 0x00, 0x0B];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
  }

  @override
  Future<void> stopTimer() async {
    List<int> payload = [0x03, 0x0B, 0x00, 0x00, 0x00, 0x00, 0x08];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
  }

  @override
  Future<void> resetTimer() async {
    List<int> payload = [0x03, 0x0B, 0x02, 0x00, 0x00, 0x00, 0x0A];
    await _device.write(
      serviceIdentifier.long,
      writeCharacteristic.long,
      Uint8List.fromList(payload),
    );
  }
}
