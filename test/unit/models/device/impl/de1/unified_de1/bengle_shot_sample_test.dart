import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/bengle_shot_sample.dart';

/// Hand-computed golden `0xA013` frame (28 bytes, big-endian), cross-checked
/// against firmware `T_BengleShotSample`, the de1plus decoder
/// (`de1_de1.tcl:912-941`) and the contract table in
/// `assets/api/bengle_hw_v1.yml` (`packet_0xA013`).
///
/// | off | field            | raw (BE) | decoded          |
/// |-----|------------------|----------|------------------|
/// |  0  | SampleTime       | 0x03E8   | 1000             |
/// |  2  | GroupPressure    | 0x0384   | 900/100 = 9.00   |
/// |  4  | SetGroupPressure | 0x0258   | 600/100 = 6.00   |
/// |  6  | GroupFlow        | 0x00FA   | 250/100 = 2.50   |
/// |  8  | SetGroupFlow     | 0x00C8   | 200/100 = 2.00   |
/// | 10  | GFlow            | 0x00B4   | 180/100 = 1.80   |
/// | 12  | MixTemp          | 0x2422   | 9250/100 = 92.50 |
/// | 14  | HeadTemp         | 0x2260   | 8800/100 = 88.00 |
/// | 16  | SetMixTemp       | 0x2454   | 9300/100 = 93.00 |
/// | 18  | SetHeadTemp      | 0x2328   | 9000/100 = 90.00 |
/// | 20  | Weight (U16P5)   | 0x0490   | 1168/32  = 36.5  |
/// | 22  | FrameNumber      | 0x07     | 7                |
/// | 23  | SteamTemp        | 0x34BC   | 13500/100 = 135  |
/// | 25  | MilkTemp         | 0x0000   | 0.0              |
/// | 27  | Flags            | 0x00     | 0                |
final List<int> _goldenBytes = [
  0x03, 0xE8, // SampleTime
  0x03, 0x84, // GroupPressure
  0x02, 0x58, // SetGroupPressure
  0x00, 0xFA, // GroupFlow
  0x00, 0xC8, // SetGroupFlow
  0x00, 0xB4, // GFlow
  0x24, 0x22, // MixTemp
  0x22, 0x60, // HeadTemp
  0x24, 0x54, // SetMixTemp
  0x23, 0x28, // SetHeadTemp
  0x04, 0x90, // Weight
  0x07, //       FrameNumber
  0x34, 0xBC, // SteamTemp
  0x00, 0x00, // MilkTemp
  0x00, //       Flags
];

ByteData _bytes(List<int> b) => ByteData.sublistView(Uint8List.fromList(b));

void main() {
  group('parseBengleShotSample', () {
    test('golden frame decodes byte-exact (big-endian, correct scaling)', () {
      expect(_goldenBytes, hasLength(bengleShotSampleBytes));
      final s = parseBengleShotSample(_bytes(_goldenBytes))!;

      expect(s.sampleTime, 1000);
      expect(s.groupPressure, closeTo(9.00, 1e-9));
      expect(s.setGroupPressure, closeTo(6.00, 1e-9));
      expect(s.groupFlow, closeTo(2.50, 1e-9));
      expect(s.setGroupFlow, closeTo(2.00, 1e-9));
      expect(s.gFlow, closeTo(1.80, 1e-9));
      expect(s.mixTemp, closeTo(92.50, 1e-9));
      expect(s.headTemp, closeTo(88.00, 1e-9));
      expect(s.setMixTemp, closeTo(93.00, 1e-9));
      expect(s.setHeadTemp, closeTo(90.00, 1e-9));
      // Weight is U16P5 (÷32), NOT ÷100 — 1168/100 would give 11.68.
      expect(s.weight, closeTo(36.5, 1e-9));
      expect(s.frameNumber, 7);
      expect(s.steamTemp, closeTo(135.00, 1e-9));
      // 0 = no probe / no fresh reading (older firmware hardcodes 0).
      expect(s.milkTemp, closeTo(0.0, 1e-9));
      // Flags must never be gated on (bit0 is a LastTARE value proxy at best).
      expect(s.flags, 0);
    });

    test('a non-zero MilkTemp decodes from offset 25 (u16 ÷ 100)', () {
      // Bytes 25-26 = 0x18,0x36 -> 6198/100 = 61.98 °C. Locks both the
      // unaligned offset (25, not 24/26) and the ÷100 scaling for the day the
      // firmware starts serialising real probe readings.
      final b = List<int>.from(_goldenBytes);
      b[25] = 0x18;
      b[26] = 0x36;
      final s = parseBengleShotSample(_bytes(b))!;
      expect(s.milkTemp, closeTo(61.98, 1e-9));
      // The neighbouring fields must be untouched by the milk bytes.
      expect(s.steamTemp, closeTo(135.00, 1e-9));
      expect(s.flags, 0);
    });

    test('weight uses ÷32 (U16P5), not ÷100 — a diverging case', () {
      // raw 0x0100 = 256 -> 256/32 = 8.0 g (÷100 would give 2.56).
      final b = List<int>.from(_goldenBytes);
      b[20] = 0x01;
      b[21] = 0x00;
      final s = parseBengleShotSample(_bytes(b))!;
      expect(s.weight, closeTo(8.0, 1e-9));
    });

    test('multi-byte fields are big-endian (byte order matters)', () {
      // SampleTime bytes 0x12,0x34 -> big-endian 0x1234 = 4660
      // (little-endian would be 0x3412 = 13330).
      final b = List<int>.from(_goldenBytes);
      b[0] = 0x12;
      b[1] = 0x34;
      final s = parseBengleShotSample(_bytes(b))!;
      expect(s.sampleTime, 0x1234);
    });

    test('frames shorter than 28 bytes are dropped (null, no RangeError)', () {
      expect(
        parseBengleShotSample(_bytes(_goldenBytes.sublist(0, 27))),
        isNull,
      );
      expect(
        parseBengleShotSample(_bytes(_goldenBytes.sublist(0, 19))),
        isNull,
      );
      expect(parseBengleShotSample(_bytes(const [])), isNull);
    });

    test('trailing bytes beyond 28 are ignored', () {
      final s = parseBengleShotSample(_bytes([..._goldenBytes, 0xFF, 0xFF]))!;
      expect(s.weight, closeTo(36.5, 1e-9));
      expect(s.flags, 0);
    });
  });
}
