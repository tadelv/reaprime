import 'package:clock/clock.dart';
import 'package:reaprime/src/models/device/machine.dart';

/// Shot lifecycle phases as tracked by `ShotSequencer`.
enum ShotState { idle, preheating, pouring, stopping, finished }

/// What a [ShotDecision] did to the shot.
///
/// * [advance] — moved the profile to the next step (app-issued skip or
///   firmware-natural frame exit).
/// * [stop] — ended the pour (target reached, machine reported done, or a
///   client/user commanded it).
/// * [abort] — the shot never ran (e.g. blocked because no scale connected).
/// * [terminal] — the shot ended abnormally (machine error, disconnect).
/// * [finalize] — closed the post-stop settling window; not why the shot
///   stopped, so it never overrides the persisted stop reason.
enum ShotDecisionKind { advance, stop, abort, terminal, finalize }

/// Why the sequencer made a decision.
///
/// Serialized by `.name` onto the wire (`/ws/v1/machine/shotState`) and into
/// the persisted `ShotRecord.stopReason`. The wire vocabulary is an OPEN set —
/// consumers must tolerate unknown values from newer builds.
///
/// [noScale] corresponds to the REST `block_no_scale` error type; keep the two
/// vocabularies aligned.
enum ShotDecisionReason {
  /// Shot blocked/aborted: blockOnNoScale enabled and no scale connected.
  noScale,

  /// App-side stop-at-weight hit the target yield.
  targetWeight,

  /// App-side stop-at-volume hit the profile's target volume.
  targetVolume,

  /// Stop commanded by an external client via the REST API.
  apiStop,

  /// Stop commanded from the in-app UI (Stop Shot button).
  appStop,

  /// The machine reported the shot end with no app/client command on record —
  /// GHC stop or natural profile completion (indistinguishable from the
  /// substate stream alone).
  machineEnded,

  /// Firmware advanced to the next profile frame on its own.
  profileAdvance,

  /// The app skipped the current frame (per-step weight exit).
  profileSkip,

  /// The machine entered an error state mid-shot.
  error,

  /// The machine disconnected mid-shot (sequencer torn down).
  disconnected,

  /// The 4s post-stop safety backstop closed the settling window.
  stoppingBackstop,
}

/// A single sequencer decision: what happened ([kind]), why ([reason]),
/// a human-readable [details] string, and optional numeric context ([data]).
class ShotDecision {
  final ShotDecisionKind kind;
  final ShotDecisionReason reason;
  final String? details;
  final Map<String, dynamic>? data;

  const ShotDecision({
    required this.kind,
    required this.reason,
    this.details,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'reason': reason.name,
    'details': details,
    'data': data,
  };
}

/// One frame on the `/ws/v1/machine/shotState` topic.
///
/// A single event type multiplexes shot-state transitions and decisions,
/// discriminated by [event] (`state` | `decision` | `terminal`). Every frame
/// carries the current shot phase and machine context so late joiners get a
/// coherent view from any single frame; [decision] is non-null only for
/// `decision`/`terminal` frames.
class ShotStateEvent {
  final String event;

  /// When the event happened: the timestamp of the machine snapshot that
  /// drove it, so clients can align frames with `/ws/v1/machine/snapshot`
  /// telemetry. Falls back to wall clock only when no snapshot context
  /// exists (e.g. the between-shots idle re-seed after a disconnect).
  final DateTime timestamp;

  /// Stable id for the shot, equal to the persisted `ShotRecord.id` when the
  /// shot is saved. Null between shots.
  final String? shotId;
  final ShotState state;
  final MachineState? machineState;
  final MachineSubstate? machineSubstate;
  final int? profileFrame;
  final bool scaleConnected;

  /// Sticky for the remainder of the shot once the scale drops mid-pour —
  /// stop-at-weight stays disabled even if [scaleConnected] flips back.
  final bool scaleLost;
  final bool machineHasAutonomousSAW;
  final ShotDecision? decision;

  ShotStateEvent({
    required this.event,
    required this.timestamp,
    required this.state,
    this.shotId,
    this.machineState,
    this.machineSubstate,
    this.profileFrame,
    this.scaleConnected = false,
    this.scaleLost = false,
    this.machineHasAutonomousSAW = false,
    this.decision,
  });

  /// The between-shots resting frame — seeds the topic so late joiners never
  /// replay a stale mid-shot frame from a previous shot.
  factory ShotStateEvent.idle() => ShotStateEvent(
    event: 'state',
    timestamp: clock.now(),
    state: ShotState.idle,
  );

  Map<String, dynamic> toJson() => {
    'event': event,
    'timestamp': timestamp.toIso8601String(),
    'shotId': shotId,
    'state': state.name,
    'machineState': machineState?.name,
    'machineSubstate': machineSubstate?.name,
    'profileFrame': profileFrame,
    'scaleConnected': scaleConnected,
    'scaleLost': scaleLost,
    'machineHasAutonomousSAW': machineHasAutonomousSAW,
    'decision': decision?.toJson(),
  };
}
