import 'dart:typed_data';

/// Wire length of the Bengle `0xA013` BengleShotSample characteristic, in
/// bytes. Firmware struct `T_BengleShotSample` is size-locked with
/// `static_assert(sizeof(T_BengleShotSample) == 28)`; the authoritative field
/// table lives in `assets/api/bengle_hw_v1.yml` (`packet_0xA013`).
const int bengleShotSampleBytes = 28;

/// Decoded Bengle `0xA013` BengleShotSample frame.
///
/// This is a *reorganised superset* of the DE1 `0xA00D` ShotSample — the field
/// order, widths and scaling differ, so it needs its own decoder (do NOT reuse
/// the `0xA00D` fixed-point parser). Unlike the little-endian MMR registers,
/// the shot-sample payload is **big-endian**.
///
/// Two firmware caveats (see the contract file's `packet_0xA013` rows):
///  * [milkTemp] — `0` means no probe / no fresh reading; older firmware
/// hardcoded the field to `0` outright. Parse it, expose it,
///    never fake a reading.
///  * [flags] — on newer firmware bit0 is `LastTARE != 0` (a value proxy, not
///    a tare event); older firmware wrote `0` unconditionally. Never gate any
///    behaviour on it — the real tare signal is that [weight] already arrives
///    net of `LastTARE` (firmware subtracts it before serialising).
class BengleShotSample {
  /// Half-cycles since shot start (offset 0, `u16`).
  final int sampleTime;

  /// Group pressure, bar (offset 2, `u16 / 100`).
  final double groupPressure;

  /// Target group pressure, bar (offset 4, `u16 / 100`).
  final double setGroupPressure;

  /// Group flow, ml/s (offset 6, `u16 / 100`).
  final double groupFlow;

  /// Target group flow, ml/s (offset 8, `u16 / 100`).
  final double setGroupFlow;

  /// Gravimetric flow from the integrated scale, g/s (offset 10, `u16 / 100`).
  final double gFlow;

  /// Mix temperature, °C (offset 12, `u16 / 100`).
  final double mixTemp;

  /// Head (group) temperature, °C (offset 14, `u16 / 100`).
  final double headTemp;

  /// Target mix temperature, °C (offset 16, `u16 / 100`).
  final double setMixTemp;

  /// Target head temperature, °C (offset 18, `u16 / 100`).
  final double setHeadTemp;

  /// Integrated-scale weight, g (offset 20, `u16 / 32`, U16P5 — max 2048 g,
  /// step 0.03125 g). **Already net of tare** — firmware subtracts `LastTARE`
  /// before serialising, so trust it directly. A negative net weight clamps
  /// to 0 on the wire (U16P5 has no sign bit).
  final double weight;

  /// Profile frame number (offset 22, `u8`).
  final int frameNumber;

  /// Steam temperature, °C (offset 23, `u16 / 100` — unaligned offset, the
  /// firmware struct is packed).
  final double steamTemp;

  /// Milk-probe temperature, °C (offset 25, `u16 / 100`). `0` = no probe /
  /// no fresh reading (older firmware hardcodes `0`).
  final double milkTemp;

  /// Status flags (offset 27, `u8`). Never gate on this — see the class doc.
  final int flags;

  const BengleShotSample({
    required this.sampleTime,
    required this.groupPressure,
    required this.setGroupPressure,
    required this.groupFlow,
    required this.setGroupFlow,
    required this.gFlow,
    required this.mixTemp,
    required this.headTemp,
    required this.setMixTemp,
    required this.setHeadTemp,
    required this.weight,
    required this.frameNumber,
    required this.steamTemp,
    required this.milkTemp,
    required this.flags,
  });
}

/// Decode a big-endian `0xA013` BengleShotSample frame.
///
/// Returns `null` when the frame is shorter than [bengleShotSampleBytes] — a
/// truncated notification (e.g. a stale/undersized ATT MTU) is dropped rather
/// than throwing a `RangeError`. Extra trailing bytes are ignored.
BengleShotSample? parseBengleShotSample(ByteData d) {
  if (d.lengthInBytes < bengleShotSampleBytes) return null;
  return BengleShotSample(
    sampleTime: d.getUint16(0, Endian.big),
    groupPressure: d.getUint16(2, Endian.big) / 100.0,
    setGroupPressure: d.getUint16(4, Endian.big) / 100.0,
    groupFlow: d.getUint16(6, Endian.big) / 100.0,
    setGroupFlow: d.getUint16(8, Endian.big) / 100.0,
    gFlow: d.getUint16(10, Endian.big) / 100.0,
    mixTemp: d.getUint16(12, Endian.big) / 100.0,
    headTemp: d.getUint16(14, Endian.big) / 100.0,
    setMixTemp: d.getUint16(16, Endian.big) / 100.0,
    setHeadTemp: d.getUint16(18, Endian.big) / 100.0,
    weight: d.getUint16(20, Endian.big) / 32.0,
    frameNumber: d.getUint8(22),
    steamTemp: d.getUint16(23, Endian.big) / 100.0,
    milkTemp: d.getUint16(25, Endian.big) / 100.0,
    flags: d.getUint8(27),
  );
}
