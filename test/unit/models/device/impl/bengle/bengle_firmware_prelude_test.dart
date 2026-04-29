import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/machine.dart';

import '../../../../../helpers/fake_ble_transport.dart';

void main() {
  group('Bengle.beforeFirmwareUpload', () {
    test('requests MachineState.fwUpgrade', () async {
      final transport = FakeBleTransport();
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

    test(
        'updateFirmware drives sleeping -> fwUpgrade write sequence on the wire',
        () async {
      final transport = FakeBleTransport();
      addTearDown(transport.dispose);
      transport.queueOnConnectResponses();

      final bengle = Bengle(transport: transport);
      await bengle.onConnect();

      final preFwWrites = transport.writes.length;

      // The FW protocol blocks waiting on `fwMapRequest` notifications
      // (and a 10s erase wait). Drive it just long enough for the
      // prelude writes to land, then bail via timeout.
      try {
        await bengle
            .updateFirmware(Uint8List(0), onProgress: (_) {})
            .timeout(const Duration(seconds: 1));
      } on TimeoutException catch (_) {
        // Expected: protocol is blocked waiting on FW-path notifications.
      }

      final fwWrites = transport.writes.sublist(preFwWrites);
      // First two writes belong to the prelude:
      //   1. requestState(sleeping) — UnifiedDe1._updateFirmware
      //   2. requestState(fwUpgrade) — Bengle.beforeFirmwareUpload
      // Subsequent writes (poll for fwMapRequest, etc.) are FW-protocol
      // territory and intentionally not asserted on.
      expect(fwWrites.length, greaterThanOrEqualTo(2),
          reason: 'expected at least the sleeping + fwUpgrade writes');
      expect(fwWrites[0].characteristicUUID, Endpoint.requestedState.uuid);
      expect(fwWrites[0].data[0],
          De1StateEnum.fromMachineState(MachineState.sleeping).hexValue);
      expect(fwWrites[1].characteristicUUID, Endpoint.requestedState.uuid);
      expect(fwWrites[1].data[0], 0x22,
          reason: 'second prelude write must be fwUpgrade (0x22)');
      expect(fwWrites[1].data[0],
          De1StateEnum.fromMachineState(MachineState.fwUpgrade).hexValue);
    });
  });
}
