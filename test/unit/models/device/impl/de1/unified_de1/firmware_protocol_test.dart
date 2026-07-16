import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/firmware_update_state.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/errors.dart';

import '../../../../../../helpers/barrier_ble_transport.dart';
import '../../../../../../helpers/fake_ble_transport.dart';

void main() {
  late FakeBleTransport transport;
  late UnifiedDe1 de1;

  setUp(() async {
    transport = FakeBleTransport();
    addTearDown(transport.dispose);
    transport.queueOnConnectResponses(v13Model: 3);
    transport.queueMmrResponseInt(MMRItem.calFlowEst, 0);
    de1 = UnifiedDe1(
      transport: transport,
      firmwareEraseTimeout: const Duration(milliseconds: 100),
      firmwareVerificationTimeout: const Duration(milliseconds: 100),
    );
    await de1.onConnect();
  });

  test('completes only after successful verification response', () async {
    transport.queueFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);
    var completed = false;
    final update = de1
        .updateFirmware(Uint8List(16), onProgress: (_) {})
        .whenComplete(() => completed = true);

    await _waitForState(de1, FirmwareUpdateState.verifying);
    expect(completed, isFalse);

    transport.emitFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xfd]);
    await update;
    expect(de1.firmwareUpdateState, FirmwareUpdateState.idle);
  });

  test('verification failure does not complete successfully', () async {
    transport.queueFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);
    transport.queueFirmwareMapResponse([0, 0, 0, 1, 0, 0, 1]);

    await expectLater(
      de1.updateFirmware(Uint8List(16), onProgress: (_) {}),
      throwsA(isA<StateError>()),
    );
    expect(de1.firmwareUpdateState, FirmwareUpdateState.idle);
  });

  test('erase timeout prevents upload', () async {
    final writesBeforeUpdate = transport.writes.length;
    await expectLater(
      de1.updateFirmware(Uint8List(16), onProgress: (_) {}),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      transport.writes
          .skip(writesBeforeUpdate)
          .where(
            (write) => write.characteristicUUID == Endpoint.writeToMMR.uuid,
          ),
      isEmpty,
    );
  });

  test('stale successful response cannot complete erase', () async {
    transport.emitFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);
    final writesBeforeUpdate = transport.writes.length;

    await expectLater(
      de1.updateFirmware(Uint8List(16), onProgress: (_) {}),
      throwsA(isA<TimeoutException>()),
    );

    expect(
      transport.writes
          .skip(writesBeforeUpdate)
          .where(
            (write) => write.characteristicUUID == Endpoint.writeToMMR.uuid,
          ),
      isEmpty,
    );
  });

  test(
    'late erase response does not complete verification',
    () async {
      transport.queueFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);
      final update = de1.updateFirmware(Uint8List(16), onProgress: (_) {});

      await _waitForState(de1, FirmwareUpdateState.verifying);
      transport.emitFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);

      await Future<void>.delayed(Duration.zero);
      expect(de1.firmwareUpdateState, FirmwareUpdateState.verifying);
      transport.emitFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xfd]);
      await update;
      expect(de1.firmwareUpdateState, FirmwareUpdateState.idle);
    },
  );

  test('verification response must follow the verification request', () async {
    final barrierTransport = BarrierBleTransport();
    addTearDown(barrierTransport.dispose);
    barrierTransport.queueOnConnectResponses(v13Model: 3);
    barrierTransport.queueMmrResponseInt(MMRItem.calFlowEst, 0);
    final blockedDe1 = UnifiedDe1(
      transport: barrierTransport,
      firmwareEraseTimeout: const Duration(milliseconds: 100),
      firmwareVerificationTimeout: const Duration(milliseconds: 100),
    );
    await blockedDe1.onConnect();
    final uploadBarrier = Completer<void>();
    barrierTransport.pauseNextWrite(Endpoint.writeToMMR.uuid, uploadBarrier);
    barrierTransport.queueFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);
    final uploadWrite = barrierTransport.nextWrite(Endpoint.writeToMMR.uuid);
    final update = blockedDe1.updateFirmware(Uint8List(16), onProgress: (_) {});

    await uploadWrite;
    barrierTransport.emitFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xfd]);
    expect(blockedDe1.firmwareUpdateState, FirmwareUpdateState.uploading);

    uploadBarrier.complete();
    await _waitForState(blockedDe1, FirmwareUpdateState.verifying);
    barrierTransport.emitFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xfd]);
    await update;
    expect(blockedDe1.firmwareUpdateState, FirmwareUpdateState.idle);
  });

  test('cancellation while verifying is typed and returns to idle', () async {
    transport.queueFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);
    final update = de1.updateFirmware(Uint8List(16), onProgress: (_) {});
    final cancellation = expectLater(
      update,
      throwsA(isA<FirmwareUpdateCancelledException>()),
    );
    await _waitForState(de1, FirmwareUpdateState.verifying);

    await de1.cancelFirmwareUpload();
    await cancellation;
    expect(de1.firmwareUpdateState, FirmwareUpdateState.idle);
  });

  test('disconnect cancels an active update', () async {
    final update = de1.updateFirmware(Uint8List(16), onProgress: (_) {});
    final cancellation = expectLater(
      update,
      throwsA(isA<FirmwareUpdateCancelledException>()),
    );
    await de1.disconnect();

    await cancellation;
    expect(de1.firmwareUpdateState, FirmwareUpdateState.idle);
  });
}

Future<void> _waitForState(UnifiedDe1 de1, FirmwareUpdateState state) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (de1.firmwareUpdateState != state) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('State did not become ${state.name}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
