# Shot State WS + Stop Reason — Thread Findings

_As of 2026-06-17. Companion to the design doc
[`2026-06-16-shot-state-ws-and-stop-reason-design.md`](2026-06-16-shot-state-ws-and-stop-reason-design.md)._
_This captures what the investigation found and the decisions reached in discussion, including
refinements that post-date the design doc's last revision (flagged at the end)._

## The ask

- Maintainer's request: a "ShotState websocket", a stream of `ShotSequencer` decisions about the
  state of a shot (why a step advanced, why a shot stopped: weight, volume, machine, etc.), and get
  some of that into the logs too.
- Discussion [#343](https://github.com/tadelv/reaprime/discussions/343) broadens it to three
  objectives: (1) persist the final stop reason on `ShotRecord`, (2) a `/ws/v1/shotState` stream,
  (3) mid-shot scale-loss handling.
- Prior art: **#34** (the original block-no-scale request), **PR #230** (added the
  `ShotSequencer.decisions` stream as groundwork, explicitly "the natural home for the planned
  `/ws/v1/shotState` decision feed"; motivated by unifying the two code paths, app SAW vs
  GHC/REST-initiated shots).

## Key code findings

- `ShotSequencer` already has `ShotDecision` + a `decisions` BehaviorSubject, but the enum has only
  `noScale` and only the no-scale abort is ever emitted. Every other reason is logged inline and
  dropped (`shot_sequencer.dart`).
- `ShotSequencer` is recreated per shot and disposed (all three streams `close()`d) at shot end
  (`de1_state_manager.dart:566` / `:673`). A WS handler cannot subscribe to it directly.
- `De1StateManager` lives in the widget layer (`app.dart:226`), is built after `startWebServer`
  (`main.dart:475`), and is **not** passed to the webserver.
- `De1Controller` **is** passed to both the webserver and `De1StateManager`, and is already a
  BehaviorSubject hub (`de1_controller.dart:24-59`). This makes it the natural home for the stream.
- The firmware never reports **why** a shot ended; all reasons are app-inferred from substate
  transitions and threshold math.
- Volume-based stopping already exists when the profile has a `targetVolume` (`shot_sequencer.dart:382`;
  guard `!_bypassSAW && !_machineHasAutonomousSAW && (scale == null || _scaleLost) && targetVolume > 0`).
- `_scaleLost` is sticky (set once, never cleared; `shot_sequencer.dart:151-160`).
- Flow estimation (`getFlowEstimation`/`setFlowEstimation`, `de1_interface.dart:49-56`) is a
  **multiplier** (default 1.0) the machine applies to its own flow output; cached as
  `cachedFlowEstimation`, snapshotted onto shots as `WorkflowMachine.flowCalibration`
  (`de1_state_manager.dart:632`). It makes `_accumulatedVolume` accurate ml. It is **not** a
  grams-to-ml factor.
- Auth: LAN-trust. Only `/api/v1/account/proxy/*` is gated (`proxy_auth_middleware.dart`); all
  `/ws/v1/*` is open. `shotState` inherits the open posture, no work.
- No `ShotController` class exists (CLAUDE.md is stale on this); `De1StateManager` + `ShotSequencer`
  are the real orchestration.
- `SteamSequencer` is a long-lived fire-and-forget singleton (`main.dart:427`,
  `// ignore: unused_local_variable`), not threaded anywhere; CLAUDE.md "owned by De1StateManager" is
  stale.
- Coverage gaps: in **full gateway mode backgrounded** no sequencer is created
  (`de1_state_manager.dart:396`); on **Bengle** the FW stops the shot (autonomous SAW) so the app makes
  no decision. Both land in `machineEnded`/null.
- **Error states and mid-shot disconnect** currently leave the sequencer stuck or silent: there is no
  `error` arm, and `_handleSnapshot` routes only `espresso`/`steam` (error hits `default: break`).

## Three-agent review outcome

No architecture-breaking errors in the first design. Findings converged on:

- Host the stream on `De1Controller`, not a new object threaded through the widget tree (the
  `SteamSequencer` precedent argues against threading, it is self-wired and threaded nowhere).
- `stopReason` should be a first-class field, not a `ShotAnnotations` entry (annotations are
  user/tasting metadata).
- Terminal handling for error/disconnect is a real hole (clients would hang in `pouring`).
- `manual` is unreliable from the substate stream alone.
- `profileAdvance`/`profileSkip` detection was off by one (test the **vacated** frame against
  `skippedSteps`, not the new frame; make it delta-tolerant since `profileFrame` is a 10 Hz byte with
  no monotonicity guarantee).
- One unified event type over two frame kinds; single-source logging; re-slice the phases; expose the
  reason as an open string (not a closed enum); mint `shotId` once so it equals `ShotRecord.id`.

## Decisions as they stand now

- **Host:** `De1Controller.shotState` (seeded BehaviorSubject) + `publishShotEvent`. `De1StateManager`
  forwards from its existing per-shot `.state`/`.decisions` taps; the WS handler just listens. No new
  widget-tree wiring.
- **Wire format:** one `ShotStateEvent` = `{ event: state|decision|terminal, timestamp, shotId,
  state, machineState, machineSubstate, profileFrame, scaleConnected, scaleLost,
  machineHasAutonomousSAW, decision?: { kind, reason, details, data } }`. Seeded stream replays the
  current state to late joiners.
- **Persist:** first-class `ShotRecord.stopReason`, exposed as an **open string** in `rest_v1.yml`
  (not a closed enum), null for old shots; schema version bumped 3 to 4 with a real migration branch.
- **Granularity:** stream everything on the WS (advance/skip/stop/terminal); persist only the final
  reason.
- **Vocabulary:** `targetWeight`, `targetVolume`, `apiStop`, `appStop`, `machineEnded`, `noScaleBlock`
  (canonical name TBD), plus terminal `error` and `disconnected`. Step changes: `profileAdvance`
  (firmware-natural) vs `profileSkip` (app-issued weight skip).
- **`manual` (attribute by source, not deferred):** stamp the REST stop (`de1handler`) and the in-app
  Stop button (`realtime_shot_feature.dart:218`); with app-side SAW that covers everything
  software-initiated. The remaining bare-signal case is GHC or natural completion, distinguishable
  only by heuristic (ended before the last frame likely means GHC). Note REST means external client,
  not necessarily a human, hence `apiStop` rather than `manual`.
- **Terminal handling:** add an `error` arm to the sequencer and emit an explicit terminal event on
  error and on mid-shot disconnect (owned by `De1StateManager`, published before teardown), so clients
  never hang in `pouring`.
- **Scale-loss ladder:** (1) fire `scaleLost` immediately so the skin/UI warns the user; (2) bounded,
  platform-aware reconnect (reuse `ConnectionManager.connect(scaleOnly: true)`), resume SAW if the
  scale kept its zero (no re-tare, that would zero the espresso already in the cup); (3) flood guard,
  cap the shot at `targetYield * 1.1` ml against the flow-calibrated `_accumulatedVolume` (authored
  `targetVolume` wins if the profile has one). Do **not** convert weight to volume to hit the yield.
  `_scaleLost` changes from sticky to recoverable.
- **Logging:** single source. Human string goes in `ShotDecision.details`; the forwarder logs each
  event once via `Logger('ShotState')` at INFO (FINE for finalize), which auto-flows to `log.txt` and
  `/ws/v1/logs`. Delete the now-redundant inline `_log.info` lines. Never WARNING+ for normal
  decisions (auto-forwards to telemetry).
- **Auth:** no work; inherits LAN-trust.
- **Plan order:** A) reasons + emission + terminal arms, B) persist on `ShotRecord`, C) `De1Controller`
  stream + WS topic + logging, D) scale-loss (event + reconnect + overfill cap), E) reconnect tuning
  and fail policy.

## Still the maintainer's call

- Canonical name for `noScale` / `block_no_scale` / `noScaleBlock`.
- `profileAdvance` vs `profileSkip` granularity (emit both or collapse to "step changed").
- Reconnect aggressiveness / platform tuning and the fail-to-reconnect behavior.
- Whether to also dispatch decisions as a JS plugin event (extra sink), or WS-only.
- Topic path: `/ws/v1/machine/shotState` vs `/ws/v1/shotState`.
- Whether persisting `stopReason` earns the schema bump given how often it will be `null` (full
  gateway) or the ambiguous bucket (GHC/Bengle).
- Steam (`/ws/v1/machine/steamState`) deferred; reuse this event/terminal contract when it lands.

## Artifacts

- Design doc:
  [`2026-06-16-shot-state-ws-and-stop-reason-design.md`](2026-06-16-shot-state-ws-and-stop-reason-design.md).
- A reply for discussion #343 was drafted (not posted).

### Design-doc sync needed

Two spots in the design doc predate the final refinements in this thread and should be reconciled:

1. Open decision #1 in the doc recommends **deferring `manual`**; the thread landed on
   **attribute-by-source** (`apiStop`/`appStop` + heuristic for GHC vs completion).
2. The doc's scale-loss tier 3 says "authored `targetVolume`, else let it run"; the thread added the
   **`targetYield * 1.1` ml overfill cap** as the flood guard.

No code has been written; everything so far is investigation plus these design docs.
