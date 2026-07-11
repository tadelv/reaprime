part of 'unified_de1.dart';

// FIX-07 — Load-cell calibration wizard (non-blocking, ISOLATED-CELL
// AUTO-DETECT).
//
// Drives the firmware's non-blocking load-cell calibration (firmware
// its calibration engine) over MMR: write ScaleCalCmd (a trigger), poll
// ScaleCalState (a packed status word), set ScaleCalWeight (the known
// reference mass) before each latch.
//
// The procedure: platform OFF (cells mechanically isolated), precision-zero,
// then latch the SAME known mass directly on either cell — the firmware
// AUTO-DETECTS the loaded cell — move it to the other cell and latch again.
// The 2x2 solve recovers both per-cell sensitivities, so summed mass is
// position-independent. The old explicit left/right latches (ScaleCalCmd
// 4/5) are retired and return an error.
//
// Bounded polling (deadline + fast interval — better than de1plus's untimed
// 1 Hz loop), progress derived from the firmware `Remaining` field on a status
// stream, and the reference-weight write is read-back-confirmed before the
// latch is triggered.

/// Calibration MMR slots. Co-located with [ScaleCalibrationCapability] so the
/// mixin owns its wire identifiers (same pattern as [BengleScaleMmr] /
/// [BengleLedMmr]).
enum BengleCalMmr implements MmrAddress {
  /// Cal command trigger (`0x00803880`, RWT). Firmware values:
  /// `0=abort 1=zero 2=latch gain cal (platform OFF, auto-detect cell; run
  /// once per cell) 3=tare`. (`4`/`5` — the retired explicit left/right
  /// latches — return an error.) A non-zero command while the firmware is
  /// busy is ignored.
  cmd(0x00803880, 4, MmrValueKind.int32, 'ScaleCalCmd'),

  /// Packed cal status word (`0x00803884`, R):
  /// `Step[31:24] | SubState[23:16] | Remaining[15:8] | CalStatus[7:0]`,
  /// where the SubState byte carries the phase in its low nibble and the
  /// auto-detected cell in its high nibble (0 none, 1 cell A, 2 cell B).
  state(0x00803884, 4, MmrValueKind.int32, 'ScaleCalState'),

  /// Known reference weight in grams (`0x00803888`, RW, scale ×10). Written
  /// before [ScaleCalCommand.latch]. Firmware never clamps its Bengle
  /// registers, so reaprime clamps (0..10000 g).
  weight(
    0x00803888,
    4,
    MmrValueKind.scaledFloat,
    'ScaleCalWeight',
    min: 0,
    max: 100000, // 10000.0 g × 10
    readScale: 0.1,
    writeScale: 10.0,
  );

  const BengleCalMmr(
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

/// A `ScaleCalCmd` value (`BengleCalMmr.cmd`). Tare (cmd 3) exists in firmware
/// too, but reaprime tares through the dedicated `ScaleTare` register (FIX-06),
/// so it is not part of the cal command set here.
enum ScaleCalCommand {
  abort(0),
  zero(1),
  latch(2); // latch the loaded cell (auto-detected; platform OFF)

  const ScaleCalCommand(this.wire);
  final int wire;
}

// Public status/result types (ScaleCalStep/SubState/PointStatus/Status/Result)
// live in `lib/src/models/device/scale_calibration.dart` so the interface +
// handler can import them without depending on this impl library.

/// Non-blocking two-point load-cell calibration for Bengle's integrated scale
/// (FIX-07).
///
/// Lifecycle mirrors [IntegratedScaleCapability]: [initScaleCalibration] from
/// `onConnect`, [disposeScaleCalibration] from `onDisconnect`; re-init-safe.
///
/// Procedure (platform OFF): [calibrateScaleZero] → [calibrateScaleWeightLeft]
/// (known mass directly on either cell; auto-detected) →
/// [calibrateScaleWeightRight] (same mass on the OTHER cell). The second
/// latch solving both cells persists + applies the cal. Both weight methods
/// trigger the same auto-detect latch — the left/right names survive for the
/// wizard's step ordering only.
mixin ScaleCalibrationCapability on UnifiedDe1 {
  /// Poll cadence while a calibration phase runs.
  Duration _calPollInterval = const Duration(milliseconds: 500);

  /// Hard ceiling on a single command. The firmware settle+average is ~15 s;
  /// 30 s leaves headroom. de1plus has no timeout at all.
  Duration _calPollDeadline = const Duration(seconds: 30);

  /// Test seam: shorten polling so a timeout path is exercisable without a
  /// 30 s wall-clock wait.
  @visibleForTesting
  void configureScaleCalibrationTiming({
    Duration? pollInterval,
    Duration? deadline,
  }) {
    if (pollInterval != null) _calPollInterval = pollInterval;
    if (deadline != null) _calPollDeadline = deadline;
  }

  BehaviorSubject<ScaleCalStatus> _calProgress =
      BehaviorSubject<ScaleCalStatus>();
  bool _calInProgress = false;

  /// Monotonic run token. [_runCalStep] captures it at start and bails as soon
  /// as it changes; [abortScaleCalibration] / [disposeScaleCalibration] bump it
  /// to unwind an in-flight poll. A counter (not a bool) so a stale poll
  /// surviving a disconnect→reconnect still sees the change — a reset-on-init
  /// flag could be cleared before the stale poll observed it. Firmware abort →
  /// Step Idle is non-terminal, so without this the poll would spin to the
  /// deadline; and a dispose must tear down in-flight work (mirrors
  /// `disposeIntegratedScale` cancelling its subscription).
  int _calGeneration = 0;

  /// Live calibration status stream. Emits each polled [ScaleCalStatus].
  Stream<ScaleCalStatus> get scaleCalibrationProgress => _calProgress.stream;

  /// Whether a calibration run is currently in flight (single-flight guard).
  bool get scaleCalibrationInProgress => _calInProgress;

  Future<void> initScaleCalibration() async {
    // Deliberately does NOT touch _calGeneration — it only ever increases, so
    // a stale poll from a prior connection still detects the dispose bump.
    if (_calProgress.isClosed) {
      _calProgress = BehaviorSubject<ScaleCalStatus>();
    }
  }

  Future<void> disposeScaleCalibration() async {
    // Bump the run token first so a poll running across a disconnect unwinds
    // instead of injecting stale status into a post-reconnect subject or
    // firing _safeAbort on a fresh calibration.
    _calGeneration++;
    _calInProgress = false;
    if (!_calProgress.isClosed) {
      await _calProgress.close();
    }
  }

  /// Precision-zero the load cells. Place NOTHING on the platform. Must run
  /// before the weight-cal points (the firmware rejects a latch with `NoZero`
  /// otherwise).
  Future<ScaleCalResult> calibrateScaleZero() async {
    if (_calInProgress) return _busyResult();
    _calInProgress = true;
    try {
      return await _runCalStep(ScaleCalCommand.zero, (s) => s.isComplete);
    } finally {
      _calInProgress = false;
    }
  }

  /// First latch: place the known [grams] reference mass directly on EITHER
  /// bare cell (platform off); the firmware auto-detects which. Success means
  /// the cell latched — the firmware reports
  /// [ScaleCalPointStatus.incomplete] (awaiting the other cell). Run
  /// [calibrateScaleZero] first.
  Future<ScaleCalResult> calibrateScaleWeightLeft(double grams) =>
      _weightCalPoint(
        ScaleCalCommand.latch,
        grams,
        (s) =>
            s.isComplete &&
            (s.pointStatus == ScaleCalPointStatus.incomplete ||
                s.pointStatus == ScaleCalPointStatus.ok),
      );

  /// Second latch: the same known [grams] reference mass moved to the OTHER
  /// cell. Success means both cells solved ([ScaleCalPointStatus.ok]) — the
  /// firmware persisted + applied the cal. Re-latching the same cell reports
  /// incomplete (a refresh), which this step surfaces as "not accepted".
  Future<ScaleCalResult> calibrateScaleWeightRight(double grams) =>
      _weightCalPoint(
        ScaleCalCommand.latch,
        grams,
        (s) => s.isComplete && s.pointStatus == ScaleCalPointStatus.ok,
      );

  Future<ScaleCalResult> _weightCalPoint(
    ScaleCalCommand cmd,
    double grams,
    bool Function(ScaleCalStatus) isSuccess,
  ) async {
    if (_calInProgress) return _busyResult();
    _calInProgress = true;
    try {
      final clamped = grams.clamp(0.0, 10000.0).toDouble();
      // Set the reference mass and confirm it landed before triggering the
      // latch — a dropped write would calibrate to the wrong mass.
      await writeMmrScaled(BengleCalMmr.weight, clamped);
      final readBack = await readMmrScaled(BengleCalMmr.weight);
      if ((readBack - clamped).abs() > 0.1) {
        return ScaleCalResult(
          success: false,
          finalStep: ScaleCalStep.idle,
          pointStatus: ScaleCalPointStatus.none,
          message: 'reference weight write not confirmed '
              '(wrote $clamped g, read $readBack g)',
        );
      }
      return await _runCalStep(cmd, isSuccess);
    } finally {
      _calInProgress = false;
    }
  }

  /// Abort an in-flight calibration: unwind the poll loop (by bumping
  /// [_calGeneration]) AND tell the firmware to abort (ScaleCalCmd = 0). Both
  /// are needed — the firmware returns to Step Idle (non-terminal), which the
  /// poll would otherwise keep polling until the deadline.
  Future<void> abortScaleCalibration() async {
    _calGeneration++;
    await writeMmrInt(BengleCalMmr.cmd, ScaleCalCommand.abort.wire);
  }

  /// Trigger [cmd], then poll [BengleCalMmr.state] to a terminal Step
  /// (Complete/Error), a cancel (run-token bump), or the deadline. [isSuccess]
  /// decides whether a *Complete* step counts as success for this command
  /// (e.g. a point-1 latch is Complete with `pointStatus == incomplete`). The
  /// caller owns [_calInProgress].
  Future<ScaleCalResult> _runCalStep(
    ScaleCalCommand cmd,
    bool Function(ScaleCalStatus) isSuccess,
  ) async {
    final gen = _calGeneration;
    // Bind this run's progress subject so a dispose+reconnect that swaps
    // `_calProgress` can't route a late status into the new session's stream.
    final progress = _calProgress;
    await writeMmrInt(BengleCalMmr.cmd, cmd.wire);
    final deadline = DateTime.now().add(_calPollDeadline);
    var last = ScaleCalStatus.fromRaw(0); // Idle until the first read
    while (true) {
      if (gen != _calGeneration) return _abortedResult(last);
      last = ScaleCalStatus.fromRaw(await readMmrInt(BengleCalMmr.state));
      if (!progress.isClosed) progress.add(last);

      if (last.isTerminal) {
        final ok = isSuccess(last);
        return ScaleCalResult(
          success: ok,
          finalStep: last.step,
          pointStatus: last.pointStatus,
          message: ok ? null : _terminalFailMessage(last),
        );
      }
      if (gen != _calGeneration) return _abortedResult(last);
      if (DateTime.now().isAfter(deadline)) {
        await _safeAbort();
        return ScaleCalResult(
          success: false,
          finalStep: last.step,
          pointStatus: last.pointStatus,
          message: 'timed out after ${_calPollDeadline.inSeconds}s',
        );
      }
      await Future<void>.delayed(_calPollInterval);
    }
  }

  String _terminalFailMessage(ScaleCalStatus s) {
    final st = s.pointStatus;
    final hasReason = st != ScaleCalPointStatus.none &&
        st != ScaleCalPointStatus.unknown &&
        st != ScaleCalPointStatus.ok;
    if (s.isError) {
      // Upfront rejects (BadWeight / NoZero) surface as an Error step; carry
      // the CalStatus reason when the firmware set one.
      return hasReason
          ? 'firmware error (status: ${st.name})'
          : 'firmware reported error';
    }
    // Completed step but the point status is a rejection (NotSettled,
    // BadDelta, IllConditioned, OutOfRange) or unexpected.
    return 'calibration not accepted (status: ${st.name})';
  }

  ScaleCalResult _abortedResult(ScaleCalStatus last) => ScaleCalResult(
        success: false,
        finalStep: last.step,
        pointStatus: last.pointStatus,
        message: 'aborted',
      );

  Future<void> _safeAbort() async {
    try {
      await writeMmrInt(BengleCalMmr.cmd, ScaleCalCommand.abort.wire);
    } catch (_) {
      // Best-effort — the caller already has a timeout result.
    }
  }

  ScaleCalResult _busyResult() => const ScaleCalResult(
        success: false,
        finalStep: ScaleCalStep.unknown,
        pointStatus: ScaleCalPointStatus.unknown,
        message: 'calibration already in progress',
      );
}
