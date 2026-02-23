import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

/// Varia AKU scale implementation.
///
/// BLE Protocol (FFF0 service, shared with Decent/Eureka/SmartChef):
/// - Notifications: header, command, length, payload, xor
/// - Weight notification: command=0x01, length=0x03, w1 w2 w3
///   - Sign in highest nibble of w1 (0x10 = negative)
///   - Weight = ((w1 & 0x0F) << 16) | (w2 << 8) | w3, in hundredths of gram
/// - Battery notification: command=0x85, length=0x01, battery%
/// - Tare: 0xFA 0x82 0x01 0x01 0x82
class VariaAkuScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier =
      BleServiceIdentifier.short('fff0');
  static final BleServiceIdentifier dataCharacteristic =
      BleServiceIdentifier.short('fff1');
  static final BleServiceIdentifier commandCharacteristic =
      BleServiceIdentifier.short('fff2');

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  int _batteryLevel = 0;

  VariaAkuScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Varia AKU";

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.connecting);

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  Future<void> onConnect() async {
    if (await _transport.connectionState.first == true) {
      return;
    }
    _connectionStateController.add(ConnectionState.connecting);

    StreamSubscription<bool>? disconnectSub;

    try {
      await _transport.connect();

      disconnectSub = _transport.connectionState
          .where((state) => !state)
          .listen((_) {
        _connectionStateController.add(ConnectionState.disconnected);
        disconnectSub?.cancel();
      });

      final services = await _transport.discoverServices();
      if (!serviceIdentifier.matchesAny(services)) {
        throw Exception(
          'Expected service ${serviceIdentifier.long} not found. '
          'Discovered services: $services',
        );
      }
      _registerNotifications();
      _connectionStateController.add(ConnectionState.connected);
    } catch (e) {
      disconnectSub?.cancel();
      _connectionStateController.add(ConnectionState.disconnected);
      try {
        await _transport.disconnect();
      } catch (_) {}
    }
  }

  @override
  disconnect() async {
    await _transport.disconnect();
  }

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Future<void> tare() async {
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0xFA, 0x82, 0x01, 0x01, 0x82]),
      withResponse: false,
    );
  }

  @override
  Future<void> sleepDisplay() async {
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // Varia AKU doesn't support display wake via BLE
  }

  void _registerNotifications() async {
    await _transport.subscribe(serviceIdentifier.long, dataCharacteristic.long, _parseNotification);
  }

  void _parseNotification(List<int> data) {
    if (data.length < 4) return;

    int command = data[1];
    int length = data[2];

    // Weight notification: command=0x01, length=0x03
    if (command == 0x01 && length == 0x03 && data.length >= 7) {
      int w1 = data[3];
      int w2 = data[4];
      int w3 = data[5];

      // Sign is in highest nibble of w1 (0x10 means negative)
      bool isNegative = (w1 & 0x10) != 0;

      // Weight is 3 bytes big-endian in hundredths of gram
      // Strip sign nibble from w1
      int weightRaw = ((w1 & 0x0F) << 16) | (w2 << 8) | w3;
      double weight = weightRaw / 100.0;

      if (isNegative) {
        weight = -weight;
      }

      _streamController.add(
        ScaleSnapshot(
          timestamp: DateTime.now(),
          weight: weight,
          batteryLevel: _batteryLevel,
        ),
      );
    }
    // Battery notification: command=0x85, length=0x01
    else if (command == 0x85 && length == 0x01 && data.length >= 5) {
      _batteryLevel = data[3];
    }
  }

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}
}
