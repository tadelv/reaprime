import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/wake_schedule_windows.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/sleep_timeout_safety.dart';

/// Pushes the app's sleep timeout and wake schedule into the Bengle's own
/// registers, so **the machine runs its scheduler autonomously — with the
/// tablet disconnected**.
///
/// Before this existed, the wake schedule was a purely app-side feature: a
/// 30-second `PresenceController` timer that woke the machine off Android's
/// clock. With the tablet away (or the app killed) nothing woke the machine,
/// and the three firmware registers read zero on older firmware — no clock, no
/// entries, schedule disabled.
///
/// What is written, and when:
///
/// * **Clock** (`SetLocalTimeOfWeek`) — idempotent, no side effects. Written
///   on connect and re-written every [clockResyncInterval] (RAM-only in
///   firmware: lost on every machine reboot, and a DST jump makes it an hour
///   wrong until the next tick).
/// * **Sleep timeout** (`InactivitySleepTimeout`) — persisted in firmware;
///   written whenever the user's setting differs from what we last pushed, and
///   always at least once per connect. **It is never written as `0`**: it is the
///   machine's thermal safety net for when this tablet is gone, and the app must
///   leave every machine it touches at least as safe as it found it. See
///   `sleep_timeout_safety.dart`.
/// * **Table** (`ScheduleControl` 0 → `ScheduleEntry`… → `ScheduleControl` 1)
///   — written ONLY when the desired table actually changed, or when the
///   machine has demonstrably lost it. A re-push clears the table, which drops
///   the firmware's `WasInAwakeWindow` edge — so a gratuitous re-push mid-window
///   would re-wake a machine the user had just manually put to sleep. Hence the
///   diff, and hence the periodic tick never touches the table.
///
/// **Bengle-gated.** A non-Bengle DE1 connecting is a complete no-op: not one
/// byte goes to the wire (these registers do not exist on a stock DE1).
///
/// Resilient by construction: every write path is wrapped, a failure logs and
/// retries with capped backoff, and desired state is only stamped as pushed
/// after the write lands — so a failure during the connect flow can never
/// crash it, and self-heals on the next trigger at the latest.
class BengleScheduleSync {
  BengleScheduleSync({
    required De1Controller de1Controller,
    required SettingsController settingsController,
    DateTime Function()? clock,
    this.clockResyncInterval = const Duration(minutes: 15),
    this.retryDelays = const [
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  })  : _de1 = de1Controller,
        _settings = settingsController,
        _clock = clock ?? DateTime.now;

  final De1Controller _de1;
  final SettingsController _settings;
  final DateTime Function() _clock;
  final Logger _log = Logger('BengleScheduleSync');

  /// How often the firmware clock is re-written while a Bengle is connected.
  /// A 4-byte MMR write is negligible; 15 minutes bounds DST error, crystal
  /// drift and post-reboot clock loss, and sits well inside the smallest
  /// useful wake window. The same tick carries the reboot verify-poll.
  final Duration clockResyncInterval;

  /// Backoff for a failed push; the last entry repeats as the cap.
  final List<Duration> retryDelays;

  /// The connected Bengle, or null (no machine, or a non-Bengle DE1).
  BengleInterface? _machine;

  StreamSubscription<De1Interface?>? _de1Sub;
  Timer? _clockTimer;
  Timer? _retryTimer;
  int _attempt = 0;

  /// Bumped on every connection edge and on dispose. In-flight awaits capture
  /// it and bail when it changes, so a write that was in flight across a
  /// disconnect can never stamp state for a machine that is gone.
  int _generation = 0;

  /// What the CONNECTED machine is known to hold. All three are cleared on
  /// every connection edge — the firmware keeps the clock and the table in RAM
  /// only, so a machine that went away must never be assumed to have kept
  /// anything (the same rule `WorkflowDeviceSync` follows).
  bool _clockSynced = false;
  int? _lastPushedTimeout;
  List<int>? _lastPushedTable;

  /// Single-flight guard: the drain loop and the periodic tick both talk to
  /// the machine, and interleaving them could tear the clear → entries →
  /// enable sequence apart.
  bool _busy = false;

  /// Set when a settings change lands mid-drain, so the loop re-evaluates
  /// desired state instead of finishing against a stale snapshot.
  bool _dirty = false;

  bool _disposed = false;

  /// Subscribe to the machine stream and the settings, and push to whatever
  /// Bengle is already connected.
  void initialize() {
    _de1Sub = _de1.de1.listen(_onDe1Changed);
    _settings.addListener(_onSettingsChanged);
  }

  /// Cancel every subscription and timer. Safe to call twice.
  void dispose() {
    _disposed = true;
    _generation++;
    _settings.removeListener(_onSettingsChanged);
    _de1Sub?.cancel();
    _de1Sub = null;
    _clockTimer?.cancel();
    _clockTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _machine = null;
  }

  // ---------------------------------------------------------------------------
  // Desired state
  // ---------------------------------------------------------------------------

  /// The `InactivitySleepTimeout` the machine should hold, in minutes.
  ///
  /// **NEVER 0.** `0` disables the machine's autonomous sleep *permanently and
  /// in flash* — the thermal safety net that turns the heaters off when this
  /// tablet is gone (dead battery, crashed app, blackout). A previous version
  /// of this getter pushed `0` whenever the user turned "Auto sleep & wake"
  /// off, or picked "Disabled" in the dropdown, which left the machine LESS
  /// safe than one that had never met the app (the firmware's own default is
  /// 60 min). Those settings govern whether the TABLET sleeps the machine; they
  /// are not licence to disarm the MACHINE. See `sleep_timeout_safety.dart` for
  /// the full reasoning — please read it before changing this.
  int get _desiredTimeout => machineSleepTimeoutMinutes(
        userPresenceEnabled: _settings.userPresenceEnabled,
        userTimeoutMinutes: _settings.sleepTimeoutMinutes,
      );

  /// The wake table the machine should hold, packed for `ScheduleEntry`.
  ///
  /// Gated on the master toggle — **and on nothing else**. When it is ON the
  /// table stays armed in the firmware precisely SO THAT the machine keeps
  /// waking itself with no tablet present: the FW wakes it at the window start,
  /// holds it awake for the window, and the (always non-zero, see
  /// [_desiredTimeout]) inactivity timeout sleeps it once the window closes.
  /// That autonomy is the whole point of this class. Never gate it on tablet
  /// connectivity.
  ///
  /// When the toggle is OFF the user has explicitly asked for no scheduled
  /// waking — and the UI hides the schedule section, so they believe wake is
  /// off. It must actually BE off: an empty table makes `pushWakeSchedule`
  /// write `ScheduleControl = 0` (clear + disable). That is respecting a
  /// deliberate setting, not second-guessing the tablet's presence.
  List<int> get _desiredTable => _settings.userPresenceEnabled
      ? windowsFromSettingsJson(_settings.wakeSchedules)
          .map((w) => w.packed)
          .toList(growable: false)
      : const <int>[];

  // ---------------------------------------------------------------------------
  // Triggers
  // ---------------------------------------------------------------------------

  void _onDe1Changed(De1Interface? device) {
    // Every connection edge invalidates everything we believe about the
    // machine's registers (the clock and the table are RAM-only in firmware).
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _clockTimer?.cancel();
    _clockTimer = null;
    _attempt = 0;
    _clockSynced = false;
    _lastPushedTimeout = null;
    _lastPushedTable = null;
    _dirty = false;

    if (device is! BengleInterface) {
      // Bengle-only feature. A plain DE1 (or no machine) gets NOTHING —
      // these registers do not exist there.
      _machine = null;
      return;
    }

    _machine = device;
    _log.info('Bengle connected — syncing clock, sleep timeout and schedule');
    _clockTimer = Timer.periodic(clockResyncInterval, (_) => _onTick());
    unawaited(_drain());
  }

  void _onSettingsChanged() {
    // `SettingsController.addListener` fires on ANY settings write (theme,
    // units, …) — it is not a per-key stream. The drain loop diffs desired
    // state against what was actually pushed, so an unrelated change writes
    // nothing and, crucially, never re-pushes (and re-arms) the wake table.
    if (_machine == null) return;
    _dirty = true;
    unawaited(_drain());
  }

  // ---------------------------------------------------------------------------
  // The push
  // ---------------------------------------------------------------------------

  /// Brings the connected machine in line with desired state, one write at a
  /// time. Concurrent calls collapse into the running loop.
  Future<void> _drain() async {
    if (_busy) {
      _dirty = true;
      return;
    }
    _busy = true;
    try {
      while (true) {
        final generation = _generation;
        final machine = _machine;
        if (machine == null || _disposed) return;
        _dirty = false;

        final desiredTimeout = _desiredTimeout;
        final desiredTable = _desiredTable;

        try {
          // Clock FIRST: the firmware ignores an enabled table while its
          // clock is invalid (the firmware schedule check short-circuits on
          // !ClockValid), and the enable is what arms the rising-edge wake.
          if (!_clockSynced) {
            await machine.setLocalTimeOfWeek(localSecondsOfWeek(_clock()));
            if (generation != _generation) return;
            _clockSynced = true;
          }

          if (_lastPushedTimeout != desiredTimeout) {
            await machine.setInactivitySleepTimeout(desiredTimeout);
            if (generation != _generation) return;
            _lastPushedTimeout = desiredTimeout;
            _log.info('InactivitySleepTimeout = $desiredTimeout min');
          }

          // `null` (nothing pushed on this connection yet) never equals the
          // desired table, not even an empty one: a fresh machine must always
          // be told, if only to clear a table left by a previous session.
          if (!_sameTable(_lastPushedTable, desiredTable)) {
            await machine.pushWakeSchedule(desiredTable);
            if (generation != _generation) return;
            _lastPushedTable = desiredTable;
            _log.info('Wake schedule pushed: ${desiredTable.length} window(s)');
          }

          _attempt = 0;
        } catch (e, st) {
          if (generation != _generation) return;
          // Nothing is stamped, so the retry re-attempts from the top — and a
          // half-written table (control=0 landed, entries did not) is repaired
          // by the next full sequence, which starts with control=0 again.
          _scheduleRetry(generation, e, st);
          return;
        }

        // A settings change that landed mid-write: re-evaluate rather than
        // exit against a stale snapshot.
        if (!_dirty) return;
      }
    } finally {
      _busy = false;
      // A trigger that arrived mid-write collapsed into `_dirty` (the single-
      // flight guard above). If we then abandoned the loop for a stale
      // generation — a machine that swapped while a write was in flight — the
      // clean-exit re-check at the bottom of the loop was never reached, and
      // nobody would ever pick that work up: the NEW machine would sit
      // unconfigured (no protective sleep timeout) until the 15-minute tick.
      // Hand off to a fresh drain, which re-reads `_machine` from scratch.
      if (_dirty && !_disposed && _machine != null) {
        unawaited(_drain());
      }
    }
  }

  /// The 15-minute tick: re-sync the clock, and detect a machine that rebooted
  /// while we stayed connected (possible over USB serial).
  ///
  /// **Never touches the table on a healthy machine** — re-pushing it would
  /// re-arm the firmware's rising-edge wake (§1.7 of the spec).
  Future<void> _onTick() async {
    if (_busy || _disposed) return; // a drain/retry is already talking
    final machine = _machine;
    if (machine == null) return;
    _busy = true;
    final generation = _generation;
    try {
      // The read is a WRITE ECHO, not the live firmware clock — comparing it
      // to "now" would be meaningless. Its one meaning: 0 ⇒ the machine
      // rebooted (RAM-only slot, initval 0) and the app never writes 0.
      final echo = await machine.readLocalTimeOfWeekEcho();
      if (generation != _generation) return;
      if (echo == 0) {
        _log.warning('Machine clock reads 0 — it rebooted; re-pushing '
            'clock, sleep timeout and schedule');
        _forgetDeviceState();
        return; // the drain in `finally` re-pushes everything
      }

      // Same trick for the table: we cannot read it back, but a
      // ScheduleControl echo of 0 while we expect 1 means it is gone.
      if (_lastPushedTable != null && _lastPushedTable!.isNotEmpty) {
        final control = await machine.readScheduleControl();
        if (generation != _generation) return;
        if (control == 0) {
          _log.warning('ScheduleControl reads 0 but a schedule is expected — '
              're-pushing the table');
          _forgetDeviceState();
          return;
        }
      }

      await machine.setLocalTimeOfWeek(localSecondsOfWeek(_clock()));
    } catch (e, st) {
      if (generation != _generation) return;
      // A failed tick is not worth a retry storm: the next tick re-runs the
      // whole check. Keep the desired state stamped — nothing here proves the
      // machine lost anything.
      _log.warning('Clock re-sync/verify tick failed', e, st);
    } finally {
      _busy = false;
      // Runs after the guard is released so the drain can take it. If nothing
      // was forgotten, the diff makes this a no-op.
      if (!_disposed && generation == _generation && _machine != null) {
        unawaited(_drain());
      }
    }
  }

  /// Forget everything we believe the machine holds, so the next drain pushes
  /// the lot. Used when the machine has demonstrably lost its RAM state.
  void _forgetDeviceState() {
    _clockSynced = false;
    _lastPushedTimeout = null;
    _lastPushedTable = null;
  }

  void _scheduleRetry(int generation, Object error, StackTrace st) {
    final delay = retryDelays[min(_attempt, retryDelays.length - 1)];
    _attempt++;
    _log.warning(
      'Schedule sync write failed (attempt $_attempt); retrying in '
      '${delay.inSeconds}s',
      error,
      st,
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (generation != _generation || _disposed) return;
      unawaited(_drain());
    });
  }

  static bool _sameTable(List<int>? a, List<int> b) {
    if (a == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
