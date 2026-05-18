import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';

/// Bengle-only MMR addresses. Future Bengle peripherals (LED strip,
/// integrated scale, milk probe) declare their addresses here as the FW
/// slots are confirmed. Addresses live with the capability that owns
/// them — shared DE1 MMRs stay in `de1.models.dart#MMRItem`.
enum BengleMmr implements MmrAddress {
  /// Cup-warmer mat target temperature in °C, stored as raw IEEE-754
  /// float32 (little-endian). Range `0.0..80.0`; `0.0` = off.
  /// FW name: `MatSetPoint`. Permission RWD.
  matSetPoint(
    0x00803874,
    4,
    MmrValueKind.scaledFloat,
    'MatSetPoint',
    min: 0,
    max: 800,
    readScale: 0.1,
    writeScale: 10.0,
  ),

  /// Integrated-scale tare trigger. Address and value semantics are
  /// stubbed — FW slot TBD. Once published, fill in the real address
  /// and tighten [kind] / bounds. Capability code (`IntegratedScale-
  /// Capability.tareIntegratedScale`) currently routes through the
  /// control endpoint, not MMR — this entry exists so the FW slot has
  /// a home when the wire spec arrives.
  scaleTare(
    0x00000000, // TBD with FW
    4,
    MmrValueKind.int32, // TBD with FW
    'ScaleTare',
  );

  const BengleMmr(
    this.address,
    this.length,
    this.kind,
    this.description, {
    this.readScale = 1.0,
    this.writeScale = 1.0,
    this.min,
    this.max,
  });

  @override
  final int address;
  @override
  final int length;
  @override
  final MmrValueKind kind;
  final String description;
  @override
  final double readScale;
  @override
  final double writeScale;
  @override
  final int? min;
  @override
  final int? max;

  /// Dart enums auto-synthesize `name`, but the analyzer doesn't see it
  /// as satisfying `MmrAddress.name` through `implements` — the cast
  /// forces dispatch to the synthesized `Enum.name`. See `MMRItem` for
  /// the same pattern + history (553550d / b7b8ed7).
  @override
  String get name => (this as Enum).name;
}
