import 'package:flutter/foundation.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/wake_schedule_windows.dart'
    show kMaxWakeWindows, kSecondsPerWeek;
import 'package:rxdart/rxdart.dart';

class Bengle extends UnifiedDe1
    with
        IntegratedScaleCapability,
        LedStripCapability,
        ScaleCalibrationCapability
    implements BengleInterface {
  Bengle({required super.transport});

  @override
  String get name => "Bengle";

  /// Last requested cup-warmer target °C (`0` = off). Remembered so the
  /// RAM-only [BengleMmr.cupWarmerMode] can be re-asserted on reconnect.
  double _cupWarmerTarget = 0.0;

  @override
  Future<void> setCupWarmerTemperature(double celsius) async {
    _cupWarmerTarget = celsius.clamp(0.0, 80.0).toDouble();
    await writeMmrScaled(BengleMmr.matSetPoint, _cupWarmerTarget);
    // CupWarmerMode is the real enable — a temperature alone does nothing.
    // `> 0 °C` ⇒ On. It is RAM-only, so it is also re-pushed on every connect.
    await writeMmrInt(BengleMmr.cupWarmerMode, _cupWarmerTarget > 0 ? 1 : 0);
  }

  @override
  Future<double> getCupWarmerTemperature() =>
      readMmrScaled(BengleMmr.matSetPoint);

  @override
  Future<double?> getCupWarmerCurrentTemperature() async {
    // Defensive read: MatCurrentTemp exists only on newer
    // firmware (firmware register-table row 58). A raw 0 means "no valid reading" (NTC
    // open/short) and older FW may not answer at all — both map to null,
    // never fake data.
    try {
      final celsius = await readMmrScaled(BengleMmr.matCurrentTemp);
      return celsius > 0 ? celsius : null;
    } on Exception catch (e) {
      log.fine('MatCurrentTemp read failed (older firmware?): $e');
      return null;
    }
  }

  // --- Scheduled cup-warmer pre-warm (contract v2, firmware register-table rows 59-61) -------
  //
  // The FIRMWARE owns the timing (it runs the mat from MatPreheatLeadMin
  // minutes before a wake window opens and holds it until the window closes,
  // with no tablet connected and without waking the machine). This is pure
  // register plumbing — the app implements NO pre-warm timing.
  //
  // Both settings are PERSISTED in firmware (PERM_RWD), unlike the RAM-only
  // CupWarmerMode, so — deliberately — nothing is re-asserted in onConnect.

  /// Latched once a pre-warm register read fails: the firmware does not have
  /// rows 59–61 (older firmware does not). Prevents a retry storm —
  /// every polled `GET /api/v1/machine/cupWarmer` would otherwise burn the full
  /// MMR read timeout ladder — and keeps the log to a single line.
  ///
  /// The latch alone is NOT enough: it can only be set once a read RESOLVES,
  /// and on firmware without the registers that takes the whole timeout ladder
  /// (the firmware ACCEPTS the read request and simply never answers it). The
  /// single-flight handles below cover that window — see [getCupWarmerPrewarm].
  bool _prewarmUnsupported = false;

  /// The in-flight pre-warm reads, shared by every concurrent caller.
  ///
  /// `null` ⇒ nothing in flight. Cleared when the read resolves (and dropped in
  /// [onConnect], so a fresh connection never piggybacks a read issued on the
  /// transport it just replaced).
  Future<CupWarmerPrewarm?>? _prewarmRead;
  Future<bool?>? _prewarmActiveRead;

  @override
  Future<void> setCupWarmerPrewarm(bool enabled, int leadMinutes) async {
    // Clamp before the write: writeMmrInt clamps to the enum's declared 0..120
    // as well, but the app must not depend on the FIRMWARE's clamp — a write
    // the firmware rejects is a silent no-op, not an error.
    final lead = leadMinutes.clamp(0, 120);
    await writeMmrInt(BengleMmr.matPreheatEnable, enabled ? 1 : 0);
    await writeMmrInt(BengleMmr.matPreheatLeadMin, lead);
  }

  @override
  Future<CupWarmerPrewarm?> getCupWarmerPrewarm() {
    // Defensive read: rows 59/60 exist only on firmware carrying the pre-warm
    // change. Absent ⇒ null ("unavailable"), never fabricated settings.
    if (_prewarmUnsupported) return Future.value(null);
    // Single-flight. On firmware without the registers this read does not fail
    // fast: the firmware accepts the request and never answers, so it fails
    // only when the MMR read timeout ladder gives up — seconds later. The REST
    // surface is polled far faster than that (the skin's cup-warmer page every
    // ~5 s, its header every 60 s), so callers arrive WHILE the first read is
    // still open, when [_prewarmUnsupported] is necessarily still false. Each
    // would open its own ladder, i.e. exactly the storm the latch exists to
    // prevent. Sharing the in-flight future means one ladder per connection,
    // full stop; the latch then absorbs every later poll.
    return _prewarmRead ??= _singleFlight(
      _readPrewarm(),
      (done) {
        if (identical(_prewarmRead, done)) _prewarmRead = null;
      },
    );
  }

  @override
  Future<bool?> getCupWarmerPrewarmActive() {
    // Read-only status (row 61). Absent ⇒ null ("unknown") — never a
    // fabricated `false`, which would claim the schedule is NOT driving the
    // mat when the truth is that we cannot tell.
    if (_prewarmUnsupported) return Future.value(null);
    // Single-flight, for the same reason as getCupWarmerPrewarm above. Two
    // concurrent GETs share one read, so they also share one instant's answer —
    // which is what a status flag sampled at the same moment means anyway.
    return _prewarmActiveRead ??= _singleFlight(
      _readPrewarmActive(),
      (done) {
        if (identical(_prewarmActiveRead, done)) _prewarmActiveRead = null;
      },
    );
  }

  /// Registers [clear] to release the handle for [read] once it resolves, and
  /// hands back the same future so every caller awaits the ONE read. The
  /// identity check in [clear] means a read left over from a previous
  /// connection cannot release a fresher one's handle.
  Future<T> _singleFlight<T>(Future<T> read, void Function(Future<T>) clear) {
    read.whenComplete(() => clear(read));
    return read;
  }

  Future<CupWarmerPrewarm?> _readPrewarm() async {
    try {
      final enabled = await readMmrInt(BengleMmr.matPreheatEnable);
      final lead = await readMmrInt(BengleMmr.matPreheatLeadMin);
      return CupWarmerPrewarm(enabled: enabled == 1, leadMinutes: lead);
    } on Exception catch (e) {
      _markPrewarmUnsupported(e);
      return null;
    }
  }

  Future<bool?> _readPrewarmActive() async {
    try {
      return await readMmrInt(BengleMmr.matPreheatActive) == 1;
    } on Exception catch (e) {
      _markPrewarmUnsupported(e);
      return null;
    }
  }

  /// Logs the degradation ONCE and latches it. Firmware without rows 59–61 is
  /// an expected configuration (the validated firmware build), not an error to shout about on
  /// every poll.
  void _markPrewarmUnsupported(Object e) {
    if (_prewarmUnsupported) return;
    _prewarmUnsupported = true;
    log.info(
      'MatPreheat registers (firmware register-table rows 59-61) unavailable on this '
      'firmware — scheduled cup-warmer pre-warm reported as unsupported '
      'for this connection: $e',
    );
  }

  /// Bengle FW requires entering state 0x22 (`MachineState.fwUpgrade`) between
  /// the `requestState(sleeping)` step and the start of `.dat` upload.
  /// DE1 doesn't need this — see [UnifiedDe1.beforeFirmwareUpload]
  /// for the hook contract.
  @override
  @protected
  Future<void> beforeFirmwareUpload() async {
    await Future.delayed(Duration(milliseconds: 500), () async {
      await requestState(MachineState.fwUpgrade);
    });
  }

  /// Bengle has hardware flow control on the serial
  /// path, so the per-batch backpressure pause that DE1 needs (UART
  /// has none) is unnecessary. Stream chunks at full bandwidth.
  @override
  @protected
  Duration get firmwareUploadBatchPause => Duration.zero;

  // --- Milk-probe steam stop ------------------------------------------------
  //
  // The auto-stop TARGET is a real MMR write ([BengleSteamMmr.stopAtTemperatureTarget]
  // = TargetMilkTemp). The live probe READING is separate — it rides the
  // `0xA013` shot-sample stream, not an MMR — so `probeAttached`/`probeTemperature`
  // are surfaced by that pipeline, not here. (FW currently serialises MilkTemp as 0.)
  final BehaviorSubject<double> _stopAtTempTarget =
      BehaviorSubject<double>.seeded(0.0);
  final BehaviorSubject<bool> _probeAttached =
      BehaviorSubject<bool>.seeded(false);
  final PublishSubject<double> _probeTemperature = PublishSubject<double>();

  @override
  Stream<double> get stopAtTemperatureTarget => _stopAtTempTarget.stream;

  @override
  Stream<bool> get probeAttached => _probeAttached.stream;

  @override
  Stream<double> get probeTemperature => _probeTemperature.stream;

  @override
  Future<void> setStopAtTemperatureTarget(double celsius) async {
    final clamped = celsius.clamp(0.0, 85.0).toDouble();
    if (!_stopAtTempTarget.isClosed) {
      _stopAtTempTarget.add(clamped);
    }
    await writeMmrScaled(BengleSteamMmr.stopAtTemperatureTarget, clamped);
  }

  @override
  Future<double> getStopAtTemperatureTarget() async {
    final value = await readMmrScaled(BengleSteamMmr.stopAtTemperatureTarget);
    if (!_stopAtTempTarget.isClosed) {
      _stopAtTempTarget.add(value);
    }
    return value;
  }

  // --- Autonomous sleep + wake schedule --------------------------------------
  //
  // Thin register plumbing only. WHAT to write and WHEN lives in
  // `BengleScheduleSync`; HOW a window is packed lives in
  // `wake_schedule_windows.dart`. See [BengleScheduleMmr] for why reads here
  // are write-echoes rather than device state.

  @override
  Future<void> setInactivitySleepTimeout(int minutes) =>
      // writeMmrInt clamps to the enum's declared 0..240.
      writeMmrInt(BengleScheduleMmr.inactivitySleepTimeout, minutes);

  @override
  Future<void> setLocalTimeOfWeek(int secondsOfWeek) => writeMmrInt(
        BengleScheduleMmr.setLocalTimeOfWeek,
        // Never 0 (the FW's "never synced" sentinel) and never >= 604800
        // (the FW setter rejects it outright, leaving the clock invalid).
        secondsOfWeek.clamp(1, kSecondsPerWeek - 1),
      );

  @override
  Future<void> pushWakeSchedule(List<int> packedWindows) async {
    // The firmware protocol, in order: 0 clears the table AND disables the
    // schedule; entries append; 1 enables. Sequential awaits on purpose —
    // the entries must land between the clear and the enable.
    await writeMmrInt(BengleScheduleMmr.scheduleControl, 0);
    if (packedWindows.isEmpty) {
      // No enabled schedules: cleared + disabled is the whole desired state.
      // Writing 1 here would enable an empty table (harmless but a lie).
      return;
    }
    // The FW silently drops the 33rd entry; expandWindows already caps at 32,
    // so this take() is belt-and-braces for a caller that packs its own list.
    for (final packed in packedWindows.take(kMaxWakeWindows)) {
      await writeMmrInt(BengleScheduleMmr.scheduleEntry, packed);
    }
    await writeMmrInt(BengleScheduleMmr.scheduleControl, 1);
  }

  @override
  Future<int> readLocalTimeOfWeekEcho() =>
      readMmrInt(BengleScheduleMmr.setLocalTimeOfWeek);

  @override
  Future<int> readScheduleControl() =>
      readMmrInt(BengleScheduleMmr.scheduleControl);

  // --- integrated scale lifecycle ---

  @override
  Future<void> onConnect() async {
    // A reconnect may be to firmware that DOES have rows 59-61 (e.g. after a
    // firmware update in the same app session), so re-probe rather than
    // carrying the "unsupported" latch across connections. The in-flight
    // handles go with it: a read still open on the transport we just replaced
    // is dead, and a caller on the NEW connection must issue its own rather
    // than await that one's corpse.
    _prewarmUnsupported = false;
    _prewarmRead = null;
    _prewarmActiveRead = null;
    await super.onConnect();
    await initIntegratedScale();
    await initScaleCalibration();
    await initLedStrip();
    // CupWarmerMode is RAM-only (FW resets it to 0 on boot) — re-assert the
    // desired state on every (re)connect so an enabled warmer survives.
    // Conditional on purpose: an app instance that never enabled the warmer
    // must write NOTHING here, or it would stomp state set by another client
    // sharing the machine.
    if (_cupWarmerTarget > 0) {
      await writeMmrScaled(BengleMmr.matSetPoint, _cupWarmerTarget);
      await writeMmrInt(BengleMmr.cupWarmerMode, 1);
    }
  }

  @override
  Future<void> onDisconnect() async {
    await disposeLedStrip();
    await disposeScaleCalibration();
    await disposeIntegratedScale();
    if (!_stopAtTempTarget.isClosed) {
      await _stopAtTempTarget.close();
    }
    if (!_probeAttached.isClosed) {
      await _probeAttached.close();
    }
    if (!_probeTemperature.isClosed) {
      await _probeTemperature.close();
    }
    await super.onDisconnect();
  }
}
