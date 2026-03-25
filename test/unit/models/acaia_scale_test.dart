import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

class MockAcaiaBleTransport extends BLETransport {
  final List<String> serviceUUIDs;
  final List<List<int>> receivedWrites = [];
  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  void Function(Uint8List)? _notificationCallback;
  String? subscribedServiceUuid;
  String? subscribedCharUuid;

  MockAcaiaBleTransport({required this.serviceUUIDs});

  @override
  String get id => 'AA:BB:CC:DD:EE:FF';

  @override
  String get name => 'Test Acaia';

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Future<void> connect() async {
    _connectionState.add(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  Future<List<String>> discoverServices() async => serviceUUIDs;

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID,
          {Duration? timeout}) async =>
      Uint8List(0);

  @override
  Future<void> subscribe(String serviceUUID, String characteristicUUID,
      void Function(Uint8List) callback) async {
    subscribedServiceUuid = serviceUUID;
    subscribedCharUuid = characteristicUUID;
    _notificationCallback = callback;
  }

  @override
  Future<void> write(
      String serviceUUID, String characteristicUUID, Uint8List data,
      {bool withResponse = true, Duration? timeout}) async {
    receivedWrites.add(data.toList());
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  void simulateNotification(List<int> data) {
    _notificationCallback?.call(Uint8List.fromList(data));
  }
}

void main() {
  group('AcaiaScale protocol auto-detection', () {
    test('detects IPS protocol when service 1820 is present', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final state = await scale.connectionState.first;
      expect(state, ConnectionState.connected);

      // IPS subscribes on the 2a80 characteristic
      expect(transport.subscribedCharUuid, contains('2a80'));
    });

    test('detects Pyxis protocol when service 49535343 is present', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['49535343-fe7d-4ae5-8fa9-9fafd205e455'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final state = await scale.connectionState.first;
      expect(state, ConnectionState.connected);

      // Pyxis subscribes on the status characteristic
      expect(transport.subscribedCharUuid,
          '49535343-1e4d-4bd9-ba61-23c647249616');
    });

    test('fails when neither service is present', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['0000fff0-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final state = await scale.connectionState.first;
      expect(state, ConnectionState.disconnected);
    });
  });

  group('AcaiaScale weight parsing', () {
    test('decodes weight from event type 5 notification', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final snapshots = <ScaleSnapshot>[];
      scale.currentSnapshot.listen(snapshots.add);

      // Weight: value=1850 (0x3A,0x07,0x00), unit=1, sign=0
      // Expected: 1850 / 10^1 = 185.0g
      transport.simulateNotification([
        0xEF, 0xDD, 12, 10, 5,
        0x3A, 0x07, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);

      await Future.delayed(Duration(milliseconds: 50));
      expect(snapshots, hasLength(1));
      expect(snapshots.first.weight, closeTo(185.0, 0.01));
    });

    test('decodes negative weight', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final snapshots = <ScaleSnapshot>[];
      scale.currentSnapshot.listen(snapshots.add);

      // Same weight but sign byte > 1 -> negative
      transport.simulateNotification([
        0xEF, 0xDD, 12, 10, 5,
        0x3A, 0x07, 0x00, 0x00, 0x01, 0x02,
        0x00, 0x00, 0x00, 0x00,
      ]);

      await Future.delayed(Duration(milliseconds: 50));
      expect(snapshots, hasLength(1));
      expect(snapshots.first.weight, closeTo(-185.0, 0.01));
    });
  });

  group('AcaiaScale tare', () {
    test('sends tare command 3 times for reliability', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      transport.receivedWrites.clear();

      await scale.tare();

      // Count tare commands (msgType 0x04 at byte index 2)
      final tareWrites = transport.receivedWrites.where((w) =>
          w.length >= 3 && w[0] == 0xEF && w[1] == 0xDD && w[2] == 0x04);
      expect(tareWrites.length, 3);
    });
  });
}
