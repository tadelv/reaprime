import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

/// Minimal BLE transport stub: captures every characteristic write so the
/// FW upload prelude assertions can inspect the order of `requestedState`
/// writes vs. the `beforeFirmwareUpload` hook firing.
class _CapturingBleTransport extends BLETransport {
  final _connState =
      BehaviorSubject<ConnectionState>.seeded(ConnectionState.connected);
  final Map<String, void Function(Uint8List)> _subscribers = {};
  final Map<int, int> _intResponses = {};

  /// Ordered list of `(uuid, data)` writes seen by the transport.
  final List<({String characteristicUUID, Uint8List data})> writes = [];

  void queueMmrResponseInt(MmrAddress addr, int value) {
    _intResponses[addr.address] = value;
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
      void Function(Uint8List) callback) async {
    _subscribers[characteristicUUID] = callback;
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  @override
  Future<void> write(
      String serviceUUID, String characteristicUUID, Uint8List data,
      {bool withResponse = true, Duration? timeout}) async {
    writes.add((characteristicUUID: characteristicUUID, data: data));

    // Synthesize MMR-read responses so onConnect can complete.
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
      scheduleMicrotask(() => cb(resp));
    }
  }

  void dispose() => _connState.close();
}

class _FwHookProbe extends UnifiedDe1 {
  _FwHookProbe({required super.transport});

  bool hookCalled = false;

  /// Number of writes captured at the moment the hook fires. Lets a test
  /// assert ordering relative to `requestState(sleeping)` without driving
  /// the full FW protocol.
  int writeCountAtHook = -1;

  /// Set by tests to read the underlying transport's write log when the
  /// hook fires.
  late _CapturingBleTransport probeTransport;

  @override
  @protected
  Future<void> beforeFirmwareUpload() async {
    hookCalled = true;
    writeCountAtHook = probeTransport.writes.length;
  }
}

void main() {
  group('beforeFirmwareUpload hook', () {
    test('UnifiedDe1.beforeFirmwareUpload defaults to no-op', () async {
      final transport = _CapturingBleTransport();
      addTearDown(transport.dispose);
      final de1 = UnifiedDe1(transport: transport);
      // The default implementation must complete without side effects.
      // Tests live in the same package; @protected lint is irrelevant here.
      // ignore: invalid_use_of_protected_member
      await de1.beforeFirmwareUpload();
      // No writes should have happened from the no-op default.
      expect(transport.writes, isEmpty);
    });

    test('subclass override is invoked by the FW upload path', () async {
      final transport = _CapturingBleTransport();
      addTearDown(transport.dispose);
      transport
        ..queueMmrResponseInt(MMRItem.v13Model, 1)
        ..queueMmrResponseInt(MMRItem.ghcInfo, 0)
        ..queueMmrResponseInt(MMRItem.serialN, 12345)
        ..queueMmrResponseInt(MMRItem.cpuFirmwareBuild, 1300)
        ..queueMmrResponseInt(MMRItem.heaterV, 230)
        ..queueMmrResponseInt(MMRItem.refillKitPresent, 0);

      final de1 = _FwHookProbe(transport: transport);
      de1.probeTransport = transport;
      await de1.onConnect();

      // Snapshot the write count after onConnect so we can isolate the
      // FW prelude writes.
      final preFwWrites = transport.writes.length;

      // _updateFirmware sleeps for 10 seconds waiting on firmware erase
      // before the upload loop. We don't need to drive it to completion
      // — we just need the hook to fire (which happens immediately after
      // requestState(sleeping)).
      try {
        await de1
            .updateFirmware(Uint8List(0), onProgress: (_) {})
            .timeout(const Duration(seconds: 1));
      } on TimeoutException catch (_) {
        // Expected: erase wait blocks for 10s.
      }

      expect(de1.hookCalled, isTrue,
          reason: 'beforeFirmwareUpload hook was not invoked '
              'by the FW upload path');

      // The hook must fire AFTER requestState(sleeping) — i.e., at least
      // one write to Endpoint.requestedState must have landed on the
      // wire before hookCalled flipped.
      expect(de1.writeCountAtHook, greaterThan(preFwWrites),
          reason: 'hook fired before requestState(sleeping) wrote to wire');
      final fwPreludeWrites = transport.writes.sublist(preFwWrites);
      expect(fwPreludeWrites.first.characteristicUUID,
          Endpoint.requestedState.uuid,
          reason: 'first FW-path write must be requestState(sleeping)');
    });
  });
}
