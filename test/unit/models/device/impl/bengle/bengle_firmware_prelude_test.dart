import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

/// Minimal BLE transport stub: captures every characteristic write so the
/// test can decode the byte written to `Endpoint.requestedState`.
class _CapturingBleTransport extends BLETransport {
  final _connState =
      BehaviorSubject<ConnectionState>.seeded(ConnectionState.connected);

  /// Ordered list of `(uuid, data)` writes seen by the transport.
  final List<({String characteristicUUID, Uint8List data})> writes = [];

  /// Last `MachineState` requested via a write to `Endpoint.requestedState`,
  /// decoded by reversing `De1StateEnum.fromMachineState(...)`.
  MachineState? get lastRequestedState {
    for (final w in writes.reversed) {
      if (w.characteristicUUID != Endpoint.requestedState.uuid) continue;
      if (w.data.isEmpty) continue;
      final stateEnum = De1StateEnum.fromHexValue(w.data[0]);
      for (final ms in MachineState.values) {
        if (De1StateEnum.fromMachineState(ms) == stateEnum) return ms;
      }
      return null;
    }
    return null;
  }

  @override
  String get id => 'capturing-ble';

  @override
  String get name => 'CapturingBle';

  @override
  Stream<ConnectionState> get connectionState => _connState.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<String>> discoverServices() async => [de1ServiceUUID];

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID,
          {Duration? timeout}) async =>
      Uint8List(20);

  @override
  Future<void> subscribe(String serviceUUID, String characteristicUUID,
      void Function(Uint8List) callback) async {}

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  @override
  Future<void> write(
      String serviceUUID, String characteristicUUID, Uint8List data,
      {bool withResponse = true, Duration? timeout}) async {
    writes.add((characteristicUUID: characteristicUUID, data: data));
  }

  void dispose() => _connState.close();
}

void main() {
  group('Bengle.beforeFirmwareUpload', () {
    test('requests MachineState.fwUpgrade', () async {
      final transport = _CapturingBleTransport();
      addTearDown(transport.dispose);
      final bengle = Bengle(transport: transport);

      // Tests live in the same package; @protected lint is irrelevant here.
      // ignore: invalid_use_of_protected_member
      await bengle.beforeFirmwareUpload();

      expect(transport.lastRequestedState, MachineState.fwUpgrade);
      // Wire byte must be 0x22.
      final stateWrites = transport.writes
          .where((w) => w.characteristicUUID == Endpoint.requestedState.uuid)
          .toList();
      expect(stateWrites, hasLength(1));
      expect(stateWrites.single.data[0], 0x22);
    });
  });
}
