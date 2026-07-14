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

/// Tablet-synced clock + weekly wake schedule (firmware firmware register-table rows
/// 54–57, logic in the firmware, consumers in
/// the firmware). Kept out of [BengleMmr] (the cup-warmer /
/// thermal group) for the same reason as [BengleSteamMmr]: addresses live
/// with the capability that owns them.
///
/// **All four are WRITE-DRIVEN. A read echoes the last value WRITTEN, not
/// live device state** (the firmware — the `F_` hooks only act on
/// `Write` and pass the value through on `Read`). There is no way to read
/// the schedule table back, and no register exposes the running firmware
/// clock, so drift cannot be measured. The only meaningful read is `== 0`
/// on [setLocalTimeOfWeek] / [scheduleControl]: the machine rebooted (both
/// slots are RAM-only with initval 0). [inactivitySleepTimeout] is the one
/// exception — it is `PERM_RWD`, persisted, and genuinely readable.
///
/// Write protocol for the table: [scheduleControl] `0` (clear + disable) →
/// one [scheduleEntry] per window → [scheduleControl] `1` (enable). The
/// clock must be valid first: a table enabled with an invalid clock does
/// nothing (the firmware schedule check returns false).
enum BengleScheduleMmr implements MmrAddress {
  /// `InactivitySleepTimeout` (0x008038BC, firmware register-table row 54, PERM_RWD —
  /// **persisted**). Minutes of inactivity before the firmware sleeps
  /// ITSELF; `0` = disabled, firmware default 60, max 240.
  ///
  /// NB the firmware skips this timer only while `TabletConnected`, which
  /// is latched exclusively from the BLE GAP connect event
  ///. **Over USB serial the firmware
  /// believes no tablet is present and the timer ACTS** — so this value
  /// governs a serial-connected tablet too. Inside an active schedule
  /// window the firmware calls its user-present hook every tick, which
  /// defers (never forces) this sleep.
  inactivitySleepTimeout(
    0x008038BC,
    4,
    MmrValueKind.int32,
    'InactivitySleepTimeout',
    min: 0,
    max: 240,
  ),

  /// `SetLocalTimeOfWeek` (0x008038C0, firmware register-table row 55, PERM_RW — RAM-only,
  /// **lost on every reboot**; there is no battery-backed RTC). LOCAL
  /// seconds since Sunday 00:00:00. Once set, the firmware ticks it from
  /// its own 1 Hz counter and wraps the week itself — no tablet needed.
  ///
  /// `max` is 604799, deliberately NARROWER than the contract's 604800:
  /// the setter rejects `secOfWeek >= SECONDS_PER_WEEK`,
  /// so writing exactly 604800 would silently leave the clock invalid. The
  /// app also never writes `0` — a read-back of `0` is the "rebooted, never
  /// synced" sentinel (see `localSecondsOfWeek`, which clamps to `>= 1`).
  setLocalTimeOfWeek(
    0x008038C0,
    4,
    MmrValueKind.int32,
    'SetLocalTimeOfWeek',
    min: 0,
    max: 604799,
  ),

  /// `ScheduleEntry` (0x008038C4, firmware register-table row 56). ONE wake window,
  /// APPENDED to the firmware table: `(dow << 22) | (startMin << 11) |
  /// endMin`.
  ///
  /// **`dow` is a day INDEX, 0 = Sunday … 6 = Saturday — NOT a bitmask.**
  /// The firmware masks it to 3 bits and compares it for EQUALITY
  ///, so a Mon–Fri schedule is FIVE entries.
  /// `startMin` is inclusive, `endMin` exclusive and `<= 1440`;
  /// `startMin >= endMin` is silently dropped, so midnight-crossing windows
  /// must be split by the app. The table holds 32 entries and the 33rd is
  /// silently dropped — the packing/merging/cap lives in
  /// `wake_schedule_windows.dart`.
  scheduleEntry(
    0x008038C4,
    4,
    MmrValueKind.int32,
    'ScheduleEntry',
    min: 0,
    max: 0x7FFFFFFF,
  ),

  /// `ScheduleControl` (0x008038C8, firmware register-table row 57). `0` = clear the table
  /// **and** disable; `1` = enable. Protocol: write `0`, then the entries,
  /// then `1`.
  ///
  /// `max` is 1, narrower than the contract's 255, on purpose: the firmware
  /// reads only bit 0 on a non-zero write, so a stray `2` would disable the
  /// schedule WITHOUT clearing it. Declaring max 1 makes that structurally
  /// impossible — `writeMmrInt` clamps to the declared range.
  scheduleControl(
    0x008038C8,
    4,
    MmrValueKind.int32,
    'ScheduleControl',
    min: 0,
    max: 1,
  );

  const BengleScheduleMmr(
    this.address,
    this.length,
    this.kind,
    this.description, {
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
  final int? min;
  @override
  final int? max;

  /// All four rows are `mult 1` in the contract — raw ints, no scaling. Fixed
  /// getters rather than constructor params so no caller can introduce a scale
  /// the firmware does not apply (the contract checker asserts
  /// `writeScale == mult` and `readScale == 1/mult`).
  @override
  double get readScale => 1.0;

  @override
  double get writeScale => 1.0;

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
