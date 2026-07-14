import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/led_strip.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/scale_calibration.dart';

/// Marker interface for Bengle-specific machine API.
///
/// **Future capability methods land here.** When a Bengle capability
/// (cup warmer, integrated scale, LED strip, etc.) needs a public
/// API method, add it to this interface and implement it on `Bengle`.
/// Capability-internal state and helpers belong in their own
/// `Capability` mixins on `UnifiedDe1` (see the protected surface in
/// `UnifiedDe1` for the contract: `readMmrInt`, `readMmrScaled`,
/// `writeMmrInt`, `writeMmrScaled`, `notificationsFor`, etc.).
abstract class BengleInterface extends De1Interface {
  /// Set the cup-warmer mat target temperature in °C. Range 0.0–80.0.
  /// `0.0` turns the mat off — there is no separate enable flag in FW.
  /// Implementations clamp out-of-range values before writing.
  Future<void> setCupWarmerTemperature(double celsius);

  /// Read the current cup-warmer mat setpoint in °C.
  Future<double> getCupWarmerTemperature();

  /// Read the LIVE cup-warmer mat temperature in °C, or `null` when there
  /// is no valid reading. Distinct from [getCupWarmerTemperature] (the
  /// setpoint): this is the measured mat temperature. `null` covers both
  /// firmware reporting raw `0` (NTC open/short — no valid reading) and
  /// older firmware without the register at all (the read is defensive).
  /// Implementations must never substitute fake data for `null`.
  Future<double?> getCupWarmerCurrentTemperature();

  // --- Scheduled cup-warmer pre-warm (contract v2) ----------------------------
  //
  // The FIRMWARE owns the timing: with `MatPreheatEnable` set it runs the mat
  // from `MatPreheatLeadMin` minutes before a scheduled wake window opens and
  // holds it until the window closes — with no tablet connected and WITHOUT
  // waking the machine (the boilers stay cold). The app implements NO pre-warm
  // timing of its own: it writes the two settings and reads the status flag.
  //
  // Both settings are persisted in firmware (unlike the RAM-only cup-warmer
  // enable), so they are NOT re-asserted on connect. The registers exist only
  // on firmware carrying firmware register-table rows 59–61 (a firmware development branch or
  // newer) — older firmware does NOT have them — so every read
  // here degrades to `null` ("unavailable"), never to fabricated data.

  /// Enable/disable the firmware's scheduled cup-warmer pre-warm and set the
  /// lead time in [leadMinutes] (`MatPreheatEnable` + `MatPreheatLeadMin`).
  ///
  /// [leadMinutes] is CLAMPED to `0..120`: the firmware clamps too, but a
  /// firmware-rejected write is a silent no-op, so the app must not rely on
  /// it. `0` = no lead (the mat starts with the window).
  ///
  /// The pre-warm additionally needs a mat setpoint (`> 0`, see
  /// [setCupWarmerTemperature]) and at least one wake window
  /// ([pushWakeSchedule]) — enabling it with an empty schedule silently does
  /// nothing. On firmware without the registers the writes land in unmapped
  /// space and are silently inert; callers confirm via [getCupWarmerPrewarm]
  /// (`null` ⇒ unsupported) and must not claim a success they cannot verify.
  Future<void> setCupWarmerPrewarm(bool enabled, int leadMinutes);

  /// Read the scheduled pre-warm settings back (`MatPreheatEnable` +
  /// `MatPreheatLeadMin`), or `null` when the firmware does not have the
  /// registers (the read is defensive — failure ⇒ absent, never fake data).
  Future<CupWarmerPrewarm?> getCupWarmerPrewarm();

  /// Read the read-only `MatPreheatActive` status: `true` when the wake
  /// SCHEDULE is driving the mat right now (as opposed to the user's manual
  /// toggle) — the answer to "why did the cup warmer come on by itself?".
  ///
  /// `null` = unknown, i.e. firmware without the register; never fabricate a
  /// `false`. Implementations never write this register.
  Future<bool?> getCupWarmerPrewarmActive();

  /// Live snapshot stream from the integrated scale.
  ///
  /// Real `Bengle` wires this to `IntegratedScaleCapability.weightSnapshot`
  /// (notify endpoint TBD with FW; lands in Task 7). `MockBengle` synthesises
  /// weight by integrating `MockDe1`'s simulated flow.
  Stream<ScaleSnapshot> get weightSnapshot;

  /// Tare the integrated scale. Subsequent snapshots have weight relative
  /// to this zero.
  Future<void> tareIntegratedScale();

  /// Set the autonomous stop-at-weight target in grams. `0.0` disables
  /// SAW (mirrors cup-warmer `0.0 = off`). Range `0.0..10000.0`.
  /// Implementations clamp out-of-range values.
  ///
  /// When set to a positive value the Bengle FW stops the shot when
  /// the integrated scale reads >= the target — the app's own
  /// `ShotSequencer` SAW path should bypass for `BengleInterface`
  /// machines to avoid a double stop.
  Future<void> setStopAtWeightTarget(double grams);

  /// Read the current SAW target in grams.
  Future<double> getStopAtWeightTarget();

  /// Latest SAW target stream (`0.0` = SAW off). Late subscribers see
  /// the cached current value immediately.
  Stream<double> get stopAtWeightTarget;

  // --- Load-cell calibration (two-point) -----------------------------
  //
  // Procedure: [calibrateScaleZero] (empty platform) → [calibrateScaleWeightLeft]
  // (known mass on the LEFT half) → [calibrateScaleWeightRight] (same mass on
  // the RIGHT half). The firmware solves a 2x2 system on the second point and
  // persists + applies the cal. Each call is non-blocking (polls to a terminal
  // firmware step or a bounded deadline) and out-of-range masses are clamped.

  /// Precision-zero the load cells with NOTHING on the platform. Must run
  /// before the weight-cal points.
  Future<ScaleCalResult> calibrateScaleZero();

  /// Latch weight-cal point 1: the known reference [grams] mass placed anywhere
  /// on the **LEFT** half. Success means the point latched (awaiting the RIGHT
  /// point).
  Future<ScaleCalResult> calibrateScaleWeightLeft(double grams);

  /// Latch weight-cal point 2: the same reference [grams] mass placed anywhere
  /// on the **RIGHT** half. Success means both points solved and the cal was
  /// persisted + applied.
  Future<ScaleCalResult> calibrateScaleWeightRight(double grams);

  /// Abort an in-flight calibration.
  Future<void> abortScaleCalibration();

  /// Live calibration status while a run is in progress (each polled state).
  Stream<ScaleCalStatus> get scaleCalibrationProgress;

  /// Current LED strip state stream.
  Stream<LedStripState> get ledStripState;

  /// One-shot read of the current LED strip state.
  Future<LedStripState> getLedStripState();

  /// Write a full LED strip configuration (all zones, both modes) to the
  /// cache and the FW palette registers. The palette registers persist on
  /// write (`PERM_RWD`) — [commitLedStrip] is a re-assert kept for API
  /// symmetry, not a separate persist step.
  Future<void> setLedStrip(LedStripState state);

  /// Re-assert the cached LED strip configuration to the FW. The palette
  /// registers already persist on every write; there is no separate commit
  /// register — kept for API symmetry.
  Future<void> commitLedStrip();

  /// Reload the LED strip configuration from the FW palette registers,
  /// dropping local edits.
  Future<void> resetLedStrip();

  /// Preview a colour live on the strip (front + rear) immediately, regardless
  /// of awake/sleep state, without changing the stored palette — used to show
  /// e.g. the sleep colour while the machine is awake. [clearLedPreview] restores.
  Future<void> previewLedColor(Color16 front, Color16 back);

  /// Restore the strip to the cached awake palette after a [previewLedColor].
  Future<void> clearLedPreview();

  // --- Milk-probe steam stop -----------------------------------------
  //
  // The auto-stop TARGET is a real MMR write (`TargetMilkTemp`, ×10
  // decicelsius on the wire — see [[bengle_steam_mmr]]). The live probe
  // READING is separate: it rides the `0xA013` shot-sample stream into
  // `MachineSnapshot.milkTemperature` (÷100), and current firmware
  // serialises 0 there until a probe pipeline ships — so on real `Bengle`
  // `probeAttached` stays `false` and `probeTemperature` never emits
  // (graceful degradation, no fake data). The target write is NOT gated on
  // probe presence: firmware stops autonomously the moment a probe is
  // physically attached. See [[bengle_milk_probe]] for the sensor wrapper.

  /// Set the autonomous stop-at-temperature target in °C. `0.0` disables
  /// the stop. Range `0..85` (FW max 850 deci-°C). Implementations clamp
  /// out-of-range values before writing.
  Future<void> setStopAtTemperatureTarget(double celsius);

  /// Read the current stop-at-temperature target in °C. On real `Bengle`
  /// this reads the register and echoes the value onto
  /// [stopAtTemperatureTarget] so replay subscribers see post-read truth.
  Future<double> getStopAtTemperatureTarget();

  /// Latest stop-at-temperature target stream (`0.0` = stop off).
  /// `BehaviorSubject` — late subscribers see the cached current value.
  Stream<double> get stopAtTemperatureTarget;

  /// Whether the milk probe is physically attached to the machine.
  /// `BehaviorSubject<bool>` seeded `false`. Real `Bengle` stays `false`
  /// until FW publishes a presence signal (the live reading rides `0xA013`);
  /// `MockBengle` defaults to `true` for tests.
  Stream<bool> get probeAttached;

  // --- Autonomous sleep + wake schedule ---------------------------------------
  //
  // These five exist so the machine can run its own scheduler with NO tablet
  // connected. `writeMmrInt` is `@protected` on `UnifiedDe1`, so the sync
  // service (`BengleScheduleSync`) cannot touch MMRs directly — every write
  // goes through this interface. See [[bengle_mmr]] `BengleScheduleMmr` for
  // the register semantics and `wake_schedule_windows.dart` for the packing.

  /// Set the firmware's autonomous inactivity-sleep timeout in [minutes]
  /// (`InactivitySleepTimeout`, persisted). `0` disables it; the firmware
  /// clamps/accepts 0..240. The firmware only acts on this when it believes
  /// no tablet is connected — which, over USB serial, is always.
  Future<void> setInactivitySleepTimeout(int minutes);

  /// Set the firmware's wall-clock to [secondsOfWeek] = LOCAL seconds since
  /// Sunday 00:00:00 (`SetLocalTimeOfWeek`). The clock is RAM-only and is
  /// lost on every machine reboot, so this must be re-sent on (re)connect and
  /// periodically. Implementations clamp to the firmware's writable range
  /// (1..604799 — never 0, which is the "never synced" sentinel).
  Future<void> setLocalTimeOfWeek(int secondsOfWeek);

  /// Replace the firmware's weekly wake table with [packedWindows], each
  /// packed by `packWakeWindow` (`(dow << 22) | (startMin << 11) | endMin`).
  ///
  /// Performs the whole firmware protocol: `ScheduleControl = 0` (clear the
  /// table + disable), then one `ScheduleEntry` write per window, then
  /// `ScheduleControl = 1` (enable). An empty list writes ONLY the `0` —
  /// clearing and disabling the schedule, with no enable.
  ///
  /// NB this re-arms the firmware's rising-edge wake, so callers must only
  /// push when the desired table actually changed (a mid-window re-push would
  /// re-wake a machine the user had just manually slept).
  Future<void> pushWakeSchedule(List<int> packedWindows);

  /// Read back `SetLocalTimeOfWeek`. **This is the last value WRITTEN, not
  /// the running firmware clock** — it is useless for measuring drift. Its
  /// one meaning: `0` ⇒ the machine rebooted and lost the clock (and the
  /// schedule table with it), because the app never writes 0.
  Future<int> readLocalTimeOfWeekEcho();

  /// Read back `ScheduleControl` (also a write echo). `0` while the app
  /// expects `1` ⇒ the machine rebooted, or another client cleared the table.
  Future<int> readScheduleControl();

  /// Live milk-probe temperature stream (°C). `PublishSubject<double>` —
  /// no replay, latest-only consumers should track themselves. Real
  /// `Bengle` never emits today; `MockBengle` synthesises during steam.
  Stream<double> get probeTemperature;
}

/// The firmware's persisted scheduled-pre-warm settings: `MatPreheatEnable`
/// (row 59) + `MatPreheatLeadMin` (row 60), read back as a pair.
///
/// The whole object is `null` — never a half-populated instance — when the
/// firmware does not carry the registers (see
/// [BengleInterface.getCupWarmerPrewarm]).
class CupWarmerPrewarm {
  const CupWarmerPrewarm({required this.enabled, required this.leadMinutes});

  /// `MatPreheatEnable`: the cup warmer follows the wake schedule.
  final bool enabled;

  /// `MatPreheatLeadMin`: minutes before a wake window that the mat starts.
  /// `0..120`; firmware default 30.
  final int leadMinutes;

  @override
  bool operator ==(Object other) =>
      other is CupWarmerPrewarm &&
      other.enabled == enabled &&
      other.leadMinutes == leadMinutes;

  @override
  int get hashCode => Object.hash(enabled, leadMinutes);

  @override
  String toString() =>
      'CupWarmerPrewarm(enabled: $enabled, leadMinutes: $leadMinutes)';
}
