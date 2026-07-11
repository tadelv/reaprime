import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../helpers/fake_ble_transport.dart';

/// byte-exact shot-profile upload encoding.
///
/// A Bengle (BLE protocol v2) needs `HeaderV = 2` and **U8D1** (`byte × 0.1`)
/// flow/pressure encoding; a DE1 keeps `HeaderV = 1` and **U8P4** (`byte / 16`).
/// Encoding a v2 value with the v1 scale silently mis-commands the machine
/// (`6 ml/s` → v1 `96` → the Bengle reads `9.6`) and any value > 15.9 wraps the
/// byte. The Bengle firmware also rejects a `HeaderV != 2` header outright,
/// wiping it, so a v1 upload produces no shot at all.
///
/// These drive a real [UnifiedDe1] over [FakeBleTransport] and assert the exact
/// bytes captured on the `headerWrite` / `frameWrite` characteristics. The gate
/// is S1's `isBengle` (`v13Model >= 128` read on connect), so the Bengle group
/// connects with model 128 and the DE1 group stays on the default (model 1).
///
/// Golden bytes hand-computed and cross-checked against de1plus `binary.tcl`
/// (`convert_float_to_U8D1`, `de1_packed_shot`) and the firmware struct layout
/// in BENGLE_FIXES.md — de1plus is TCL and not callable from Dart.
void main() {
  // One profile exercising every flow/pressure field the fix touches.
  const profile = Profile(
    version: '2',
    title: 'encoder profile',
    notes: '',
    author: 'test',
    beverageType: BeverageType.espresso,
    steps: [
      // Frame 0: flow 6 ml/s, a flow-over exit at 4 ml/s, and an extension
      // frame limiter (value 8, range 2).
      ProfileStepFlow(
        name: 'preinfuse',
        transition: TransitionType.fast,
        volume: 0,
        seconds: 10,
        temperature: 92,
        sensor: TemperatureSensor.coffee,
        flow: 6.0,
        exit: StepExitCondition(
          type: ExitType.flow,
          condition: ExitCondition.over,
          value: 4.0,
        ),
        limiter: StepLimiter(value: 8.0, range: 2.0),
      ),
      // Frame 1: flow 20 ml/s — must survive without wrapping on a Bengle.
      ProfileStepFlow(
        name: 'high-flow',
        transition: TransitionType.fast,
        volume: 0,
        seconds: 20,
        temperature: 90,
        sensor: TemperatureSensor.coffee,
        flow: 20.0,
      ),
      // Frame 2: flow 30 ml/s — over the Bengle 20 ml/s ceiling; clamps.
      ProfileStepFlow(
        name: 'over-ceiling',
        transition: TransitionType.fast,
        volume: 0,
        seconds: 5,
        temperature: 88,
        sensor: TemperatureSensor.coffee,
        flow: 30.0,
      ),
      // Frame 3: pressure 9 bar, a pressure-under exit at 3 bar.
      ProfileStepPressure(
        name: 'pour',
        transition: TransitionType.smooth,
        volume: 0,
        seconds: 25,
        temperature: 93,
        sensor: TemperatureSensor.coffee,
        pressure: 9.0,
        exit: StepExitCondition(
          type: ExitType.pressure,
          condition: ExitCondition.under,
          value: 3.0,
        ),
      ),
    ],
    targetVolumeCountStart: 0,
    tankTemperature: 0,
  );

  /// Uploads [profile] once and returns the ordered writes seen on the
  /// header and frame characteristics. When [asBengle] the device connects
  /// with `v13Model = 128` so `isBengle` gates the v2 encoder.
  Future<({List<FakeBleWrite> header, List<FakeBleWrite> frames, bool bengle})>
  upload({required bool asBengle}) async {
    final transport = FakeBleTransport();
    final de1 = UnifiedDe1(transport: transport);
    if (asBengle) {
      // `queueOnConnectResponses` omits `calFlowEst` (the flow-cal warm-up
      // read at the tail of onConnect); queue it so onConnect returns
      // promptly instead of eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
      transport.queueOnConnectResponses(v13Model: 128);
      await de1.onConnect();
    }
    await de1.setProfile(profile);
    final header = transport.writes
        .where((w) => w.characteristicUUID == Endpoint.headerWrite.uuid)
        .toList();
    final frames = transport.writes
        .where((w) => w.characteristicUUID == Endpoint.frameWrite.uuid)
        .toList();
    final bengle = de1.isBengle;
    await transport.dispose();
    return (header: header, frames: frames, bengle: bengle);
  }

  group('Bengle (v13Model 128) uploads v2', () {
    late List<FakeBleWrite> header;
    late List<FakeBleWrite> frames;
    late bool gatedBengle;

    setUpAll(() async {
      final r = await upload(asBengle: true);
      header = r.header;
      frames = r.frames;
      gatedBengle = r.bengle;
    });

    test('connecting with model 128 gates the Bengle encoder', () {
      expect(gatedBengle, isTrue);
    });

    test('header carries protocol version 2', () {
      expect(header, hasLength(1));
      expect(header.single.data[0], 2);
    });

    test(
      'header MaximumFlow is U8D1(20 ml/s) = 0xC8, not the v1 12*16 byte',
      () {
        // the old hard-coded `12 * 16` (U8P4) is replaced with the
        // raised 20 ml/s ceiling, U8D1-encoded.
        expect(header.single.data[4], 0xC8);
      },
    );

    test('write sequence is 4 frames + 1 extension + tail, in order', () {
      expect(frames, hasLength(6));
      expect(frames[0].data[0], 0, reason: 'frame 0');
      expect(frames[1].data[0], 1, reason: 'frame 1');
      expect(frames[2].data[0], 2, reason: 'frame 2');
      expect(frames[3].data[0], 3, reason: 'frame 3');
      expect(frames[4].data[0], 32, reason: 'extension frame for step 0');
      expect(frames[5].data[0], 4, reason: 'tail = steps.length');
    });

    test('SetVal 6 ml/s -> 0x3C (U8D1), not 0x60 (U8P4)', () {
      expect(frames[0].data[2], 0x3C);
    });

    test('SetVal 20 ml/s -> 0xC8, survives without wrapping', () {
      expect(frames[1].data[2], 0xC8);
    });

    test('SetVal 30 ml/s clamps to the 20 ml/s ceiling -> 0xC8', () {
      expect(frames[2].data[2], 0xC8);
    });

    test('SetVal pressure 9 bar -> 0x5A (U8D1)', () {
      expect(frames[3].data[2], 0x5A);
    });

    test('TriggerVal flow-over exit 4 ml/s -> 0x28 (U8D1)', () {
      expect(frames[0].data[5], 0x28);
    });

    test('TriggerVal pressure-under exit 3 bar -> 0x1E (U8D1)', () {
      expect(frames[3].data[5], 0x1E);
    });

    test(
      'extension frame MaxFlowOrPressure 8 -> 0x50, MaxFoPRange 2 -> 0x14',
      () {
        expect(frames[4].data[1], 0x50);
        expect(frames[4].data[2], 0x14);
      },
    );
  });

  group('DE1 (default model) still uploads v1 — regression', () {
    late List<FakeBleWrite> header;
    late List<FakeBleWrite> frames;
    late bool gatedBengle;

    setUpAll(() async {
      final r = await upload(asBengle: false);
      header = r.header;
      frames = r.frames;
      gatedBengle = r.bengle;
    });

    test('a DE1 is not gated as Bengle', () {
      expect(gatedBengle, isFalse);
    });

    test('header carries protocol version 1', () {
      expect(header, hasLength(1));
      expect(header.single.data[0], 1);
    });

    test('header MaximumFlow is the unchanged v1 12*16 = 0xC0', () {
      expect(header.single.data[4], 0xC0);
    });

    test('SetVal 6 ml/s -> 0x60 (U8P4)', () {
      expect(frames[0].data[2], 0x60);
    });

    test('SetVal 20 ml/s wraps under U8P4 (320 & 0xFF = 0x40)', () {
      // Demonstrates exactly the bug this fix avoids on Bengle — kept as a
      // regression witness that the DE1 path is byte-for-byte unchanged.
      expect(frames[1].data[2], 0x40);
    });

    test('SetVal pressure 9 bar -> 0x90 (U8P4)', () {
      expect(frames[3].data[2], 0x90);
    });

    test('TriggerVal flow-over exit 4 ml/s -> 0x40 (U8P4)', () {
      expect(frames[0].data[5], 0x40);
    });

    test('extension frame limiter 8 -> 0x80, range 2 -> 0x20 (U8P4)', () {
      expect(frames[4].data[1], 0x80);
      expect(frames[4].data[2], 0x20);
    });
  });

  group('Helper.convert_float_to_U8D1 boundaries', () {
    // Direct unit coverage of the v2 encoder helper — the upload groups above
    // only exercise it through whole profiles (clamp via SetVal 30, range via
    // SetVal/TriggerVal goldens), not at the byte-range edges.
    test('negative input saturates to 0, never wraps', () {
      expect(Helper.convert_float_to_U8D1(-0.1), 0);
      expect(Helper.convert_float_to_U8D1(-100.0), 0);
    });

    test('zero encodes to 0', () {
      expect(Helper.convert_float_to_U8D1(0.0), 0);
    });

    test('upper bound 25.5 encodes to 255', () {
      expect(Helper.convert_float_to_U8D1(25.5), 255);
    });

    test('above 25.5 saturates to 255, never wraps mod-256', () {
      expect(Helper.convert_float_to_U8D1(25.6), 255);
      expect(Helper.convert_float_to_U8D1(1000.0), 255);
    });

    test(
      'rounds half-up to the nearest 0.1 step, matching the v1 +0.5 idiom',
      () {
        expect(Helper.convert_float_to_U8D1(0.05), 1); // half-up at the step
        expect(Helper.convert_float_to_U8D1(0.04), 0); // below half rounds down
        expect(Helper.convert_float_to_U8D1(9.25), 93);
        expect(Helper.convert_float_to_U8D1(19.99), 200);
      },
    );
  });
}
