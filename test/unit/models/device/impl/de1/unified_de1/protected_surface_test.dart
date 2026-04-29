import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

/// Programmable BLE transport that intercepts writes to the
/// `writeToMMR` characteristic and synthesizes a matching `readFromMMR`
/// notification with a queued integer payload. The DE1 firmware
/// normally echoes the address bytes and appends the value as a
/// little-endian int32 on the readFromMMR characteristic — this stub
/// keeps that contract so `_mmrRead` finds its matching response.
class _ProgrammableBleTransport extends BLETransport {
  final _connState =
      BehaviorSubject<ConnectionState>.seeded(ConnectionState.connected);
  final Map<String, void Function(Uint8List)> _subscribers = {};

  /// Map address (full 32-bit) -> integer to emit on the next matching
  /// MMR read request.
  final Map<int, int> _intResponses = {};

  void queueMmrResponseInt(MmrAddress addr, int value) {
    _intResponses[addr.address] = value;
  }

  @override
  String get id => 'programmable-ble';

  @override
  String get name => 'ProgrammableBle';

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
      void Function(Uint8List) callback) async {
    _subscribers[characteristicUUID] = callback;
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  @override
  Future<void> write(
      String serviceUUID, String characteristicUUID, Uint8List data,
      {bool withResponse = true, Duration? timeout}) async {
    // Only react to MMR write-read requests on the writeToMMR
    // characteristic (`Endpoint.readFromMMR.uuid` is what `_mmrRead`
    // actually writes to — the firmware overloads the read endpoint
    // with a write to request a payload, then notifies the same UUID).
    // Looking at `_mmrRead`, it writes to `Endpoint.readFromMMR`.
    if (characteristicUUID != Endpoint.readFromMMR.uuid) return;
    if (data.length < 4) return;
    final addrMid1 = data[1];
    final addrMid2 = data[2];
    final addrLow = data[3];
    int? matchedAddr;
    for (final addr in _intResponses.keys) {
      final bytes = ByteData(4)..setInt32(0, addr, Endian.big);
      if (bytes.getUint8(1) == addrMid1 &&
          bytes.getUint8(2) == addrMid2 &&
          bytes.getUint8(3) == addrLow) {
        matchedAddr = addr;
        break;
      }
    }
    if (matchedAddr == null) return;
    final value = _intResponses.remove(matchedAddr)!;
    final resp = Uint8List(20);
    final view = ByteData.sublistView(resp);
    view.setUint8(0, data[0]);
    view.setUint8(1, addrMid1);
    view.setUint8(2, addrMid2);
    view.setUint8(3, addrLow);
    view.setInt32(4, value, Endian.little);
    final cb = _subscribers[Endpoint.readFromMMR.uuid];
    if (cb != null) {
      // Emit asynchronously so `_mmrRead`'s firstWhere subscription is
      // set up before the value lands.
      scheduleMicrotask(() => cb(resp));
    }
  }

  void dispose() => _connState.close();
}

// Capability-style mixin that exercises the protected surface.
mixin _TestCapability on UnifiedDe1 {
  Future<int> readFan() => readMmrInt(MMRItem.fanThreshold);
  Future<int> readFanViaWrongHelper() => readMmrInt(MMRItem.targetSteamFlow);
  Future<double> readScaledViaWrongHelper() =>
      readMmrScaled(MMRItem.fanThreshold, readScale: 0.1);
}

class _TestDe1 extends UnifiedDe1 with _TestCapability {
  _TestDe1({required super.transport});
}

void main() {
  group('UnifiedDe1 protected surface', () {
    late _ProgrammableBleTransport transport;
    late _TestDe1 de1;

    setUp(() async {
      transport = _ProgrammableBleTransport();
      de1 = _TestDe1(transport: transport);
      // Subscribe wiring needs the BLE connect path to run; queue the
      // MMR reads `onConnect` performs so it can complete.
      transport
        ..queueMmrResponseInt(MMRItem.v13Model, 1)
        ..queueMmrResponseInt(MMRItem.ghcInfo, 0)
        ..queueMmrResponseInt(MMRItem.serialN, 12345)
        ..queueMmrResponseInt(MMRItem.cpuFirmwareBuild, 1300)
        ..queueMmrResponseInt(MMRItem.heaterV, 230)
        ..queueMmrResponseInt(MMRItem.refillKitPresent, 0);
      await de1.onConnect();
    });

    tearDown(() {
      transport.dispose();
    });

    test('mixin can read int MMR via readMmrInt', () async {
      transport.queueMmrResponseInt(MMRItem.fanThreshold, 42);
      expect(await de1.readFan(), 42);
    });

    test('readMmrInt throws on scaledFloat address', () async {
      // targetSteamFlow.kind == scaledFloat — wrong helper.
      await expectLater(
        de1.readFanViaWrongHelper(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('readMmrInt'), contains('kind')),
        )),
      );
    });

    test('readMmrScaled throws on int32 address', () async {
      // fanThreshold.kind == int32 — wrong helper.
      await expectLater(
        de1.readScaledViaWrongHelper(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('readMmrScaled'), contains('kind')),
        )),
      );
    });
  });
}
