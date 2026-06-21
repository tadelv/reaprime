import 'package:reaprime/src/models/device/machine.dart';

/// Pure decision logic for stopping a hot-water dispense at a target weight.
///
/// It is deliberately free of any I/O — the [HotWaterSequencer] feeds it
/// observations and acts on the resulting [HotWaterStopDecision]. Keeping the
/// rule pure makes the stop table exhaustively unit-testable.
///
/// The model: once the machine is actually seen pouring hot water and the
/// post-tare reading has settled, project the weight a short time ahead
/// (`weight + flow * lookahead`) and request a stop the moment that projection
/// reaches the target. The lookahead compensates for the latency between
/// asking the machine to stop and the pump actually closing.

/// How long to wait for the machine to actually enter `hotWater` after arming
/// before giving up and clearing. Guards an arm that never turns into a pour.
const Duration kHotWaterArmTimeout = Duration(seconds: 10);

class HotWaterStopState {
  /// Target beverage weight in grams (the configured hot-water volume).
  final double targetWeight;

  /// Configured hot-water flow (ml/s ≈ g/s), used as the lookahead flow before
  /// the scale's own derived flow becomes trustworthy.
  final double configuredFlow;

  /// Seconds of flow to project ahead when deciding to stop.
  final double lookaheadSeconds;

  /// Whether the machine has been observed in the `hotWater` state at least
  /// once since arming.
  final bool activeSeen;

  /// Whether a stop has already been requested (latched to avoid double-stop).
  final bool stopRequested;

  const HotWaterStopState({
    required this.targetWeight,
    required this.configuredFlow,
    required this.lookaheadSeconds,
    this.activeSeen = false,
    this.stopRequested = false,
  });

  HotWaterStopState copyWith({bool? activeSeen, bool? stopRequested}) {
    return HotWaterStopState(
      targetWeight: targetWeight,
      configuredFlow: configuredFlow,
      lookaheadSeconds: lookaheadSeconds,
      activeSeen: activeSeen ?? this.activeSeen,
      stopRequested: stopRequested ?? this.stopRequested,
    );
  }
}

class HotWaterStopInput {
  /// Latest machine state, if known.
  final MachineState? machineState;

  /// Time elapsed since the controller armed (tared) for this pour.
  final Duration sinceArmed;

  /// Whether the post-tare settle window has elapsed, so the scale reading now
  /// reflects the tared zero rather than the pre-tare discontinuity.
  final bool tareSettled;

  /// Whether the scale is connected and emitting recent frames.
  final bool freshScale;

  /// Latest scale weight in grams (may be null before the first frame).
  final double? weight;

  /// Latest scale-derived flow in g/s (may be null/zero early in the pour).
  final double? weightFlow;

  const HotWaterStopInput({
    required this.machineState,
    required this.sinceArmed,
    required this.tareSettled,
    required this.freshScale,
    required this.weight,
    required this.weightFlow,
  });
}

enum HotWaterStopAction { wait, clear, stop }

class HotWaterStopDecision {
  final HotWaterStopAction action;

  /// Next controller state. Null only when [action] is [HotWaterStopAction.clear].
  final HotWaterStopState? state;

  /// Weight and projected weight at the moment of a stop decision (0 otherwise).
  final double weight;
  final double projectedWeight;

  const HotWaterStopDecision._(
    this.action,
    this.state, {
    this.weight = 0,
    this.projectedWeight = 0,
  });

  factory HotWaterStopDecision.wait(HotWaterStopState state) =>
      HotWaterStopDecision._(HotWaterStopAction.wait, state);

  factory HotWaterStopDecision.clear() =>
      const HotWaterStopDecision._(HotWaterStopAction.clear, null);

  factory HotWaterStopDecision.stop(
    HotWaterStopState state, {
    required double weight,
    required double projectedWeight,
  }) =>
      HotWaterStopDecision._(
        HotWaterStopAction.stop,
        state,
        weight: weight,
        projectedWeight: projectedWeight,
      );
}

HotWaterStopDecision nextHotWaterStop(
  HotWaterStopState state,
  HotWaterStopInput input,
) {
  var next = state;
  if (input.machineState == MachineState.hotWater) {
    next = next.copyWith(activeSeen: true);
  } else if (next.activeSeen || input.sinceArmed > kHotWaterArmTimeout) {
    // Either we left hot water after pouring, or we armed but the pour never
    // started — disarm.
    return HotWaterStopDecision.clear();
  }

  if (!next.activeSeen || next.stopRequested) {
    return HotWaterStopDecision.wait(next);
  }
  if (!input.freshScale) return HotWaterStopDecision.wait(next);
  if (!input.tareSettled) return HotWaterStopDecision.wait(next);

  final weight = _finite(input.weight) ?? 0.0;
  final flow = _positive(input.weightFlow) ?? next.configuredFlow;
  final projectedWeight = weight + flow * next.lookaheadSeconds;
  if (projectedWeight < next.targetWeight) {
    return HotWaterStopDecision.wait(next);
  }

  next = next.copyWith(stopRequested: true);
  return HotWaterStopDecision.stop(
    next,
    weight: weight,
    projectedWeight: projectedWeight,
  );
}

double? _finite(double? value) =>
    (value != null && value.isFinite) ? value : null;

double? _positive(double? value) =>
    (value != null && value.isFinite && value > 0) ? value : null;
