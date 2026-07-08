import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/weighmaster/weighmaster_scale.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

class _MockWeighMasterBleTransport extends BLETransport {
  _MockWeighMasterBleTransport({required this.serviceUUIDs});

  final List<String> serviceUUIDs;
  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  final List<List<int>> receivedWrites = [];

  void Function(Uint8List)? _notificationCallback;
  String? subscribedServiceUuid;
  String? subscribedCharUuid;

  @override
  String get id => 'AA:BB:CC:DD:EE:FF';

  @override
  String get name => 'Test WeighMaster';

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Future<ConnectionState> getConnectionState() async => _connectionState.value;

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
  Future<Uint8List> read(
    String serviceUUID,
    String characteristicUUID, {
    Duration? timeout,
  }) async => Uint8List(0);

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    subscribedServiceUuid = serviceUUID;
    subscribedCharUuid = characteristicUUID;
    _notificationCallback = callback;
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    receivedWrites.add(data.toList());
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  void simulateNotification(List<int> data) {
    _notificationCallback?.call(Uint8List.fromList(data));
  }

  @override
  Future<void> dispose() async {
    await _connectionState.close();
  }
}

void main() {
  group('WeighMasterScale', () {
    test('connects when FFF0 service is present and subscribes to FFF4', () async {
      final transport = _MockWeighMasterBleTransport(
        serviceUUIDs: [WeighMasterScale.serviceIdentifier.long],
      );
      final scale = WeighMasterScale(transport: transport);

      await scale.onConnect();

      expect(await scale.connectionState.first, ConnectionState.connected);
      expect(
        transport.subscribedServiceUuid,
        WeighMasterScale.serviceIdentifier.long,
      );
      expect(
        transport.subscribedCharUuid,
        WeighMasterScale.dataCharacteristic.long,
      );
    });

    test('parses positive and negative 0.1 g frames', () async {
      final transport = _MockWeighMasterBleTransport(
        serviceUUIDs: [WeighMasterScale.serviceIdentifier.long],
      );
      final scale = WeighMasterScale(transport: transport);
      final snapshots = <ScaleSnapshot>[];

      scale.currentSnapshot.listen(snapshots.add);
      await scale.onConnect();

      transport.simulateNotification([0x01, 0x02, 0x01, 0x00, 0x00, 0x04, 0xD2]);
      transport.simulateNotification([0x01, 0x02, 0x01, 0x01, 0x00, 0x00, 0x7B]);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(snapshots, hasLength(2));
      expect(snapshots[0].weight, closeTo(123.4, 0.01));
      expect(snapshots[1].weight, closeTo(-12.3, 0.01));
    });

    test('tare sends tare command followed by buzzer beep', () async {
      final transport = _MockWeighMasterBleTransport(
        serviceUUIDs: [WeighMasterScale.serviceIdentifier.long],
      );
      final scale = WeighMasterScale(transport: transport);

      await scale.onConnect();
      transport.receivedWrites.clear();

      await scale.tare();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(transport.receivedWrites, hasLength(2));
      expect(transport.receivedWrites[0], [0x02]);
      expect(transport.receivedWrites[1], [0x05, 0x00]);
    });

    test('rejects frames with incorrect header', () async {
      final transport = _MockWeighMasterBleTransport(
        serviceUUIDs: [WeighMasterScale.serviceIdentifier.long],
      );
      final scale = WeighMasterScale(transport: transport);
      final snapshots = <ScaleSnapshot>[];

      scale.currentSnapshot.listen(snapshots.add);
      await scale.onConnect();

      transport.simulateNotification([0x01, 0x02, 0x01, 0x00, 0x00, 0x04, 0xD2]);
      transport.simulateNotification([0x00, 0x02, 0x01, 0x00, 0x00, 0x04, 0xD2]);
      transport.simulateNotification([0x01, 0x03, 0x01, 0x00, 0x00, 0x04, 0xD2]);
      transport.simulateNotification([0x99, 0x99, 0x01, 0x00, 0x00, 0x04, 0xD2]);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(snapshots, hasLength(1));
      expect(snapshots[0].weight, closeTo(123.4, 0.01));
    });
  });
}
