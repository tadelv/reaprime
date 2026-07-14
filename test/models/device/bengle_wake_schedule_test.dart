import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';

import '../../helpers/fake_ble_transport.dart';

/// The autonomous wake schedule + sleep timeout, at the WIRE.
///
/// The firmware protocol is order-sensitive and unforgiving: `ScheduleControl`
/// = 0 clears the table AND disables it, entries append one at a time, and
/// `ScheduleControl` = 1 enables. Get the order wrong and the entries land in
/// a table that is then cleared; pack the day as a bitmask and the firmware
/// silently schedules the wrong day. These tests assert the exact bytes and
/// the exact sequence.
void main() {
  late FakeBleTransport transport;
  late Bengle bengle;

  setUp(() async {
    transport = FakeBleTransport();
    bengle = Bengle(transport: transport);
    transport.queueOnConnectResponses(v13Model: 128); // Bengle marker
    await bengle.onConnect();
    transport.writes.clear();
  });

  tearDown(() {
    transport.dispose();
  });

  /// Every MMR write, in order, as (address, little-endian int32 value).
  List<({int address, int value})> mmrWrites() {
    final out = <({int address, int value})>[];
    for (final w in transport.writes) {
      if (w.characteristicUUID != Endpoint.writeToMMR.uuid) continue;
      final d = w.data;
      // Frame: [len, addrHi, addrMid, addrLo, payload LE...]
      final address = 0x00800000 | (d[2] << 8) | d[3];
      final value =
          d[4] | (d[5] << 8) | (d[6] << 16) | (d[7] << 24);
      out.add((address: address, value: value));
    }
    return out;
  }

  group('BengleScheduleMmr register declarations', () {
    test('addresses, kinds and (deliberately narrowed) bounds', () {
      expect(BengleScheduleMmr.inactivitySleepTimeout.address, 0x008038BC);
      expect(BengleScheduleMmr.inactivitySleepTimeout.max, 240);
      expect(BengleScheduleMmr.setLocalTimeOfWeek.address, 0x008038C0);
      // Narrower than the contract's 604800 on purpose: the FW setter rejects
      // `>= SECONDS_PER_WEEK`, so 604800 would silently leave the clock invalid.
      expect(BengleScheduleMmr.setLocalTimeOfWeek.max, 604799);
      expect(BengleScheduleMmr.scheduleEntry.address, 0x008038C4);
      expect(BengleScheduleMmr.scheduleControl.address, 0x008038C8);
      // Narrower than the contract's 255: the FW reads only bit 0 on a
      // non-zero write, so a stray 2 would disable WITHOUT clearing.
      expect(BengleScheduleMmr.scheduleControl.max, 1);

      for (final r in BengleScheduleMmr.values) {
        expect(r.kind, MmrValueKind.int32);
        expect(r.length, 4);
        expect(r.readScale, 1.0);
        expect(r.writeScale, 1.0);
      }
    });
  });

  group('setInactivitySleepTimeout', () {
    test('writes the minutes as an LE int32 to 0x008038BC', () async {
      await bengle.setInactivitySleepTimeout(30);
      final w = transport.writes
          .lastWhere((w) => w.characteristicUUID == Endpoint.writeToMMR.uuid);
      expect(w.data[0], 4);
      expect(w.data.sublist(1, 4), [0x80, 0x38, 0xBC]);
      expect(w.data.sublist(4, 8), [0x1E, 0x00, 0x00, 0x00]); // 30
    });

    test('0 disables the firmware timer', () async {
      await bengle.setInactivitySleepTimeout(0);
      expect(mmrWrites().single, (address: 0x008038BC, value: 0));
    });

    test('clamps above the firmware max of 240 minutes', () async {
      await bengle.setInactivitySleepTimeout(9999);
      expect(mmrWrites().single.value, 240);
    });
  });

  group('setLocalTimeOfWeek', () {
    test('writes LOCAL seconds-of-week as an LE int32 to 0x008038C0', () async {
      // Spec §5.1: Tuesday 07:20:00 = 199200 = 0x00030A20.
      await bengle.setLocalTimeOfWeek(199200);
      final w = transport.writes.single;
      expect(w.data.sublist(1, 4), [0x80, 0x38, 0xC0]);
      expect(w.data.sublist(4, 8), [0x20, 0x0A, 0x03, 0x00]);
    });

    test('never writes 0 — 0 is the "rebooted, never synced" sentinel',
        () async {
      await bengle.setLocalTimeOfWeek(0);
      expect(mmrWrites().single.value, 1);
    });

    test('never writes 604800 — the firmware setter rejects it outright',
        () async {
      await bengle.setLocalTimeOfWeek(604800);
      expect(mmrWrites().single.value, 604799);
    });
  });

  group('pushWakeSchedule — the firmware write protocol', () {
    test('control(0) -> entries -> control(1), in that exact order', () async {
      // Spec §5.1: Mon-Fri 05:30 for 90 minutes.
      await bengle.pushWakeSchedule([
        0x004A51A4,
        0x008A51A4,
        0x00CA51A4,
        0x010A51A4,
        0x014A51A4,
      ]);

      expect(mmrWrites(), [
        (address: 0x008038C8, value: 0), // clear the table + disable
        (address: 0x008038C4, value: 0x004A51A4), // Mon
        (address: 0x008038C4, value: 0x008A51A4), // Tue
        (address: 0x008038C4, value: 0x00CA51A4), // Wed
        (address: 0x008038C4, value: 0x010A51A4), // Thu
        (address: 0x008038C4, value: 0x014A51A4), // Fri
        (address: 0x008038C8, value: 1), // enable
      ]);
    });

    test('the entry bytes are the little-endian packed int32', () async {
      await bengle.pushWakeSchedule([0x004A51A4]);
      final entry = transport.writes
          .where((w) => w.characteristicUUID == Endpoint.writeToMMR.uuid)
          .elementAt(1); // [0] is control=0
      expect(entry.data.sublist(1, 4), [0x80, 0x38, 0xC4]);
      expect(entry.data.sublist(4, 8), [0xA4, 0x51, 0x4A, 0x00]);
    });

    test('an empty table writes ONLY control(0) — clear + disable, no enable',
        () async {
      await bengle.pushWakeSchedule(const []);
      expect(
        mmrWrites(),
        [(address: 0x008038C8, value: 0)],
        reason: 'enabling an empty table would be a lie, and writing entries '
            'after a clear with no enable would be dead state',
      );
    });

    test('caps at the 32-entry firmware table (the 33rd is dropped silently)',
        () async {
      await bengle.pushWakeSchedule(List<int>.generate(40, (i) => i + 1));
      final entries = mmrWrites().where((w) => w.address == 0x008038C4);
      expect(entries, hasLength(32));
      expect(entries.last.value, 32);
    });
  });

  group('read-backs (write echoes, not device state)', () {
    test('readLocalTimeOfWeekEcho reads 0x008038C0', () async {
      transport.queueMmrResponseInt(BengleScheduleMmr.setLocalTimeOfWeek, 0);
      expect(await bengle.readLocalTimeOfWeekEcho(), 0);
    });

    test('readScheduleControl reads 0x008038C8', () async {
      transport.queueMmrResponseInt(BengleScheduleMmr.scheduleControl, 1);
      expect(await bengle.readScheduleControl(), 1);
    });
  });
}
