import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';

import '../../helpers/fake_ble_transport.dart';

/// Regression coverage: a firmware upload must own the serial tunnel.
///
/// The upload streams the image over the `writeToMMR` endpoint (uploadFW) — the
/// SAME endpoint MMR reads/writes use. If an ordinary MMR read/write interleaves
/// into the upload's write sequence, the image lands scrambled in the machine's
/// flash and the bootloader rejects it with "Header is broken". Over a fast,
/// effectively-exclusive BLE link this rarely lined up; over the slow
/// half-duplex USB serial tunnel it was easy to hit.
///
/// The fix: `_updateFirmware` sets `_fwTunnelLock` once the erase+upload+verify
/// sequence begins, and `_mmrReadRaw`/`_mmrWriteRaw` await it. A read issued
/// mid-upload does not put its request on the wire until `updateFirmware`'s
/// finally releases the tunnel.
///
/// Remove the lock and this fails: the read's request appears on the wire,
/// interleaved with the upload chunks.
void main() {
  test('an MMR read issued during a firmware upload does not interleave',
      () async {
    final transport = FakeBleTransport();
    transport.queueOnConnectResponses(v13Model: 128); // Bengle marker
    // The concurrent read: getSteamFlow -> _readMMRScaled(targetSteamFlow).
    transport.queueMmrResponseInt(MMRItem.targetSteamFlow, 100);

    final de1 = Bengle(transport: transport);
    // Shorten the erase-settle wait so the test does not sit for ~10 s, while
    // still leaving a comfortable window to observe the lock being held.
    de1.firmwareEraseSettle = const Duration(milliseconds: 100); // 10 * 100ms
    await de1.onConnect(); // establishes the MMR notify subscription
    transport.writes.clear(); // ignore onConnect traffic; watch the upload only

    final fwImage = Uint8List.fromList(List<int>.filled(64, 0xAB));
    final upload = de1.updateFirmware(fwImage, onProgress: (_) {});

    // Past the prep (Bengle.beforeFirmwareUpload delays 500 ms then
    // requestState(fwUpgrade)) and well into the ~1 s erase settle: the upload
    // now owns the tunnel.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // Issue a read while the upload holds the tunnel.
    var readResolved = false;
    de1.getSteamFlow().then((_) => readResolved = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Gated: no read request on the wire, and it has not resolved. Without the
    // lock a readFromMMR request would already be here, interleaved with the
    // upload — the exact corruption this guards against.
    expect(
      transport.writes
          .where((w) => w.characteristicUUID == Endpoint.readFromMMR.uuid),
      isEmpty,
      reason: 'the read must wait for the upload to release the tunnel',
    );
    expect(readResolved, isFalse,
        reason: 'the read must not resolve while the upload owns the tunnel');

    // Let the upload finish; the read is released and completes.
    await upload;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(readResolved, isTrue,
        reason: 'the read completes once the tunnel is released');

    // The read's request landed AFTER the last upload chunk — never between.
    final uuids = transport.writes.map((w) => w.characteristicUUID).toList();
    final lastChunk = uuids.lastIndexOf(Endpoint.writeToMMR.uuid);
    final readReq = uuids.indexOf(Endpoint.readFromMMR.uuid);
    expect(lastChunk, greaterThanOrEqualTo(0),
        reason: 'the upload should have written chunks to writeToMMR');
    expect(readReq, greaterThan(lastChunk),
        reason: 'the read request must come after the last upload chunk');

    transport.dispose();
  });
}
