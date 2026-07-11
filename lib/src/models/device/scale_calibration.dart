// Public domain types for Bengle integrated-scale load-cell calibration
// (FIX-07). Kept out of the `unified_de1` impl library so `BengleInterface`,
// `MockBengle`, and the webserver handler can import them without depending on
// the transport implementation (same layering as `scale.dart` /
// `led_strip.dart`). The wire encoding + the state machine live in
// `impl/de1/unified_de1/scale_calibration_capability.dart`.
//
// The firmware cal is a **two-point** load-cell calibration (redesigned
// firmware calibration redesign): precision-zero on an empty platform,
// then latch a known reference mass directly on EITHER bare cell (platform
// OFF — the firmware AUTO-DETECTS the loaded cell), move it to the other
// cell and latch again; the 2x2 solve recovers both per-cell sensitivities
// so summed mass is position-independent. The detected cell is reported in
// the SubState byte's high nibble (0 = none, 1 = cell A/left, 2 = cell
// B/right) so a wizard can prompt the move.

/// Decoded `Step` field of a `ScaleCalState` word (firmware `E_ScaleCalStep`).
/// Poll until [complete] or [error].
enum ScaleCalStep {
  idle(0),
  zeroing(1),
  calLatch(2), // isolated-cell gain latch (auto-detect) in progress
  taring(4),
  complete(5),
  error(6),
  unknown(-1);

  const ScaleCalStep(this.wire);
  final int wire;

  static ScaleCalStep fromWire(int w) =>
      values.firstWhere((s) => s.wire == w, orElse: () => ScaleCalStep.unknown);
}

/// Decoded `SubState` field (firmware `C_LoadCellCal::getState()`):
/// settling → averaging → done/error.
enum ScaleCalSubState {
  settling(0),
  averaging(1),
  done(2),
  error(3),
  unknown(-1);

  const ScaleCalSubState(this.wire);
  final int wire;

  static ScaleCalSubState fromWire(int w) => values
      .firstWhere((s) => s.wire == w, orElse: () => ScaleCalSubState.unknown);
}

/// The `CalStatus` low byte of `ScaleCalState` — firmware `E_CalStatus`, the
/// result of the last cal latch attempt. Only meaningful during/after a
/// gain latch ([ScaleCalStep.calLatch]); the firmware reports [none]
/// (`0xFF`) for zero/tare.
///
/// [ok] = both points solved (firmware persisted + applied the cal).
/// [incomplete] = this point latched fine; place the mass on the other half
/// and latch the sibling point. The rest are rejections.
enum ScaleCalPointStatus {
  ok(0),
  incomplete(1),
  noZero(2), // load cells never zeroed — run zero first
  notSettled(3), // counts drifted through the average window; re-run
  badWeight(4), // reference weight implausible
  badDelta(5), // non-positive / implausible per-cell delta
  illConditioned(6), // solve backstop: placements indistinguishable
  outOfRange(7), // solved cals outside +/-50% of nominal
  notIsolated(8), // no dominant cell: platform still fitted / mass bridging
  none(0xFF), // not a cal point (zero/tare) / in progress
  unknown(-1);

  const ScaleCalPointStatus(this.wire);
  final int wire;

  static ScaleCalPointStatus fromWire(int w) => values
      .firstWhere((c) => c.wire == w, orElse: () => ScaleCalPointStatus.unknown);
}

/// Decoded `ScaleCalState` packed word
/// (`Step[31:24] | SubState[23:16] | Remaining[15:8] | CalStatus[7:0]`).
class ScaleCalStatus {
  const ScaleCalStatus({
    required this.step,
    required this.subState,
    required this.remainingSeconds,
    required this.pointStatus,
    required this.raw,
    this.detectedCell,
  });

  final ScaleCalStep step;
  final ScaleCalSubState subState;

  /// Cell auto-detected by the last successful latch, from the SubState
  /// byte's high nibble: 0 = cell A (left), 1 = cell B (right), null = none.
  final int? detectedCell;

  /// Whole seconds the firmware reports remaining in the current phase.
  final int remainingSeconds;

  /// Last cal-point latch result ([ScaleCalPointStatus.none] outside a
  /// weight-cal point).
  final ScaleCalPointStatus pointStatus;

  /// The raw packed word (low 32 bits), for logging / forward-compat.
  final int raw;

  // Terminal detection keys off SubState, NOT Step.  The SubState field (`done=2`/`error=3`) is set
  // atomically with Step and is stable across both firmware variants.
  bool get isComplete => subState == ScaleCalSubState.done;
  bool get isError => subState == ScaleCalSubState.error;
  bool get isTerminal => isComplete || isError;

  factory ScaleCalStatus.fromRaw(int rawSigned) {
    final u = rawSigned & 0xFFFFFFFF; // treat as unsigned 32-bit
    // SubState byte: phase in the low nibble; auto-detected cell in the
    // high nibble (0 = none, 1 = cell A, 2 = cell B).
    final cellNibble = (u >> 20) & 0x0F;
    return ScaleCalStatus(
      step: ScaleCalStep.fromWire((u >> 24) & 0xFF),
      subState: ScaleCalSubState.fromWire((u >> 16) & 0x0F),
      remainingSeconds: (u >> 8) & 0xFF,
      pointStatus: ScaleCalPointStatus.fromWire(u & 0xFF),
      raw: u,
      detectedCell: cellNibble == 0 ? null : cellNibble - 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'step': step.name,
        'subState': subState.name,
        'remainingSeconds': remainingSeconds,
        'pointStatus': pointStatus.name,
        if (detectedCell != null) 'detectedCell': detectedCell,
      };

  @override
  String toString() =>
      'ScaleCalStatus(step: ${step.name}, subState: ${subState.name}, '
      'remaining: ${remainingSeconds}s, pointStatus: ${pointStatus.name})';
}

/// Outcome of a bounded calibration step (zero, or one weight-cal point).
class ScaleCalResult {
  const ScaleCalResult({
    required this.success,
    required this.finalStep,
    required this.pointStatus,
    this.message,
  });

  final bool success;
  final ScaleCalStep finalStep;

  /// The firmware `CalStatus` at the terminal step. For a successful point-1
  /// latch this is [ScaleCalPointStatus.incomplete] (latched, awaiting the
  /// sibling); for a successful point-2 latch it is [ScaleCalPointStatus.ok]
  /// (solved + persisted). [ScaleCalPointStatus.none] for zero/tare.
  final ScaleCalPointStatus pointStatus;

  /// Human-readable reason on failure (`timed out`, `firmware error`,
  /// `aborted`, `already in progress`, or the rejecting CalStatus), null on
  /// success.
  final String? message;

  Map<String, dynamic> toJson() => {
        'success': success,
        'finalStep': finalStep.name,
        'pointStatus': pointStatus.name,
        if (message != null) 'message': message,
      };

  @override
  String toString() => 'ScaleCalResult(success: $success, '
      'finalStep: ${finalStep.name}, pointStatus: ${pointStatus.name}'
      '${message != null ? ', message: $message' : ''})';
}
