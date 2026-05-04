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
    MmrValueKind.float32,
    'MatSetPoint',
    minDouble: 0.0,
    maxDouble: 80.0,
  );

  const BengleMmr(
    this.address,
    this.length,
    this.kind,
    this.description, {
    this.minDouble,
    this.maxDouble,
  });

  @override
  final int address;
  @override
  final int length;
  @override
  final MmrValueKind kind;
  final String description;
  @override
  final double? minDouble;
  @override
  final double? maxDouble;

  // float32 entries don't use the int-based scale/clamp fields.
  // Concrete defaults satisfy the `implements MmrAddress` contract.
  @override
  double get readScale => 1.0;
  @override
  double get writeScale => 1.0;
  @override
  int? get min => null;
  @override
  int? get max => null;

  /// Dart enums auto-synthesize `name`, but the analyzer doesn't see it
  /// as satisfying `MmrAddress.name` through `implements` — the cast
  /// forces dispatch to the synthesized `Enum.name`. See `MMRItem` for
  /// the same pattern + history (553550d / b7b8ed7).
  @override
  String get name => (this as Enum).name;
}
