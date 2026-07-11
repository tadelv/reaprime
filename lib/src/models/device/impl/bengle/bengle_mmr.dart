import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';

/// Bengle-only MMR addresses. Future Bengle peripherals (LED strip,
/// integrated scale) declare their addresses here as the FW slots are
/// confirmed. Addresses live with the capability that owns them —
/// shared DE1 MMRs stay in `de1.models.dart#MMRItem`. The milk-probe
/// stop-at-temperature target lives in [BengleSteamMmr].
enum BengleMmr implements MmrAddress {
  /// Cup-warmer mat target temperature in whole °C. Firmware `MatSetPoint`
  /// uses `mult = 1`, packed as a little-endian int32 (NOT an IEEE-754
  /// float, NOT deci-°C). Matches de1plus `set_cupwarmer_temperature`
  /// (unscaled). Range `0..80 °C`; `0` = off. Permission RWD. Enabling the
  /// warmer is a separate register — [cupWarmerMode] (0x008038AC, 0/1);
  ///
  /// history: the register has been mis-encoded twice — first as
  /// float32 (early FW notes), then as ×10 deci-°C (every set landed 10×
  /// too hot, every read 10× too cold). FW firmware register-table row 36 is `mult 1`
  /// and the FW write path consumes the raw value as °C; hardware won.
  matSetPoint(
    0x00803874,
    4,
    MmrValueKind.scaledFloat,
    'MatSetPoint',
    min: 0,
    max: 80,
    readScale: 1.0,
    writeScale: 1.0,
  ),

  /// Cup-warmer enable: `0` = Off, `1` = On. Firmware `CupWarmerMode`
  /// (`0x008038AC`, firmware register-table row 50), plain int32 0/1, **not persisted** —
  /// deliberately `PERM_RW` (not RWD) so the machine can never boot with
  /// the mat silently heating; the firmware resets it to 0 every boot and
  /// the app must re-send it on every connect. Enabling the warmer needs
  /// this in addition to [matSetPoint] (setting the temperature alone does
  /// nothing)
  cupWarmerMode(
    0x008038AC,
    4,
    MmrValueKind.boolean,
    'CupWarmerMode',
    min: 0,
    max: 1,
  ),

  /// Live cup-warmer mat temperature. Firmware `MatCurrentTemp`
  /// (`0x008038CC`, firmware register-table row 58), **read-only**, ×10 deci-°C on the
  /// wire, max 1600 (= 160.0 °C). Raw `0` = no valid reading (NTC
  /// open/short) — callers map it to `null` and NEVER fake data. Older
  /// firmware lacks the register entirely, so reads are defensive
  /// (failure → `null`); see [Bengle.getCupWarmerCurrentTemperature].
  /// `writeScale` mirrors the contract `mult` for the drift checker —
  /// the app never writes this register.
  matCurrentTemp(
    0x008038CC,
    4,
    MmrValueKind.scaledFloat,
    'MatCurrentTemp',
    min: 0,
    max: 1600,
    readScale: 0.1,
    writeScale: 10.0,
  );
  // Integrated-scale tare (`ScaleTare`) lives with the scale capability
  // that owns it: [BengleScaleMmr.scaleTare]. Milk-probe stop
  // lives in [BengleSteamMmr].

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

/// MMR addresses for the milk-probe steam stop. Currently the
/// stop-at-temperature target only — probe discovery / temperature
/// transport is separate (the live reading rides the `0xA013`
/// shot-sample stream, not an MMR).
///
/// `stopAtTemperatureTarget` is a **set/get target** endpoint, not a
/// presence/detection mechanism. Backed by firmware `TargetMilkTemp`
/// (`0x008038A8`, firmware register-table row 49), decicelsius on the wire
/// (`mult = 10`), `0` = disabled. NB the asymmetric milk scaling
///: this target is ×10 while the live `0xA013` `MilkTemp`
/// reading is ÷100 — confusing them puts the auto-stop 10× off.
enum BengleSteamMmr implements MmrAddress {
  /// Stop-at-temperature target in °C. `0.0` disables autonomous stop.
  /// Encoded as `scaledFloat` with scale factor 10 — decicelsius on
  /// the wire, unsigned. Range `0..85 °C` (FW max 850).
  stopAtTemperatureTarget(
    0x008038A8, // TargetMilkTemp
    4,
    MmrValueKind.scaledFloat,
    'StopAtTemperatureTarget',
    min: 0,
    max: 850, // 85.0 °C
    readScale: 0.1,
    writeScale: 10.0,
  );

  const BengleSteamMmr(
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

  @override
  String get name => (this as Enum).name;
}
