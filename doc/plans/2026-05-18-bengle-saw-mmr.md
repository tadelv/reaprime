# Bengle SAW MMR — workflow-context-driven, app-wide

## Context

Bengle has an integrated scale and can stop a shot autonomously in FW when target weight is reached (SAW). Today Decent.app runs SAW in `ShotController` by polling an external scale and calling `MachineState.idle`. Once Bengle is connected, FW should own that responsibility — but the app must (a) tell FW the target weight and (b) stop its own SAW loop to avoid double-stop.

`WorkflowContext.targetYield` already captures "desired coffee output in grams" across the entire app. Rather than inventing a `POST /machine/saw` endpoint, treat targetYield as the single source of truth and have the Bengle layer reflect it into FW MMR. ShotController/Sequencer detects autonomous-SAW machines via `machine is BengleInterface` and bypasses its weight-projection branch.

FW slot for the SAW MMR is **not yet published** (same posture as `BengleScaleEndpoint.weight`/`control` UUIDs). Real Bengle wires log + no-op until FW lands; `MockBengle` implements end-to-end so the orchestration is testable today.

## Approach

### Layering (decisions confirmed via grill)

1. **`IntegratedScaleCapability` mixin** (`unified_de1/integrated_scale_capability.dart`) owns the SAW MMR write. Adds `setStopAtWeightTarget(double grams)`, `getStopAtWeightTarget()`, and `Stream<double> stopAtWeightTarget`. Co-located with the scale because FW will group them and a SAW-without-scale Bengle is hypothetical.
2. **`BengleInterface`** exposes the same three methods publicly. `Bengle` implements via the mixin's protected surface.
3. **`BengleMmr.stopAtWeightTarget`** stub entry with `MmrValueKind.scaledFloat` (scale 10, matching cup-warmer convention — grams * 10). Address `0x00000000` // TBD with FW. `0.0` = SAW off (mirrors cup-warmer `0.0 = mat off`).
4. **`BengleSawBridge`** (new, `lib/src/controllers/bengle_saw_bridge.dart`): holds `WorkflowController` + `De1Controller` refs. Two listeners:
   - WorkflowController `addListener` → debounced (~250ms, mirrors `De1Controller._shotSettingsDebounce` pattern from CLAUDE.md "Comms-layer patterns" — generation-token + cancellable timer) → if `connectedDe1() is BengleInterface` and ready, write current targetYield.
   - `De1Controller.connectedDe1Stream` (or equivalent) → on new Bengle connect, re-apply current `currentWorkflow.context?.targetYield ?? 0.0`.
5. **`ShotController` bypass** (`shot_controller.dart:199, 215, 235, 265, 293`): widen the `_bypassSAW == false` predicate to also `&& de1controller.connectedDe1() is! BengleInterface`. Capture machine-is-Bengle at construction (already injected) into a final bool to keep the inline checks short. Tare/timer logic stays — only the projected-weight stop loop bypasses.
6. **Capability discovery**: `de1handler.dart:31-39` already lists Bengle caps; add `'stopAtWeight'` so REST consumers/skins can branch.
7. **`MockBengle`**: store target in-memory, when synthesised weight (currently from flow integration) reaches target, call `requestState(MachineState.idle)`. Lets sb-dev smoke verify the full chain.

### Files to change

**New**
- `lib/src/controllers/bengle_saw_bridge.dart`
- `test/controllers/bengle_saw_bridge_test.dart`
- `test/models/device/bengle_saw_test.dart` (capability + Bengle wiring)

**Modify**
- `lib/src/models/device/bengle_interface.dart` — add `setStopAtWeightTarget` / `getStopAtWeightTarget` / `stopAtWeightTarget` stream.
- `lib/src/models/device/impl/de1/unified_de1/integrated_scale_capability.dart` — add SAW state (`BehaviorSubject<double> _sawTarget`), `setStopAtWeightTarget` via `writeMmrScaled(BengleMmr.stopAtWeightTarget, …)`, `getStopAtWeightTarget` via `readMmrScaled`, init-on-connect hydration in `initIntegratedScale`, close in `disposeIntegratedScale`.
- `lib/src/models/device/impl/bengle/bengle.dart` — thin overrides forwarding to mixin members.
- `lib/src/models/device/impl/bengle/bengle_mmr.dart` — add `stopAtWeightTarget` enum entry (stub addr, `scaledFloat`, `min: 0`, `max: 2000` = 200g).
- `lib/src/models/device/impl/bengle/mock_bengle.dart` — store target, halt synth-flow at target via `requestState(MachineState.idle)`.
- `lib/src/controllers/shot_controller.dart` — capture `final bool _machineHasAutonomousSAW = de1controller.connectedDe1() is BengleInterface;` in ctor; widen the four SAW guards.
- `lib/src/services/webserver/de1handler.dart:31-39` — add `'stopAtWeight'` to caps list.
- `lib/main.dart` — instantiate `BengleSawBridge(workflowController, de1Controller)` after both exist; cancel on dispose.
- `assets/api/rest_v1.yml` — update `/api/v1/machine/capabilities` enum to include `stopAtWeight`.
- `doc/Api.md` — note new capability string.

### Reuse refs

- `writeMmrScaled` / `readMmrScaled` already on `UnifiedDe1` protected surface (see `bengle.dart:17` cup-warmer pattern).
- `BehaviorSubject` + `disposeXyz` lifecycle pattern from `IntegratedScaleCapability` (mirror existing weight subject).
- Capability discovery sniff pattern from `de1handler.dart:34-36`.
- Debounce-across-disconnect idiom from CLAUDE.md "Comms-layer patterns" (generation token + cancellable Timer) — apply inside `BengleSawBridge`.
- `connection_manager.dart:458` `machine is BengleInterface` sniff for the connect-side re-apply.

### Out of scope (separate commits / future work)

- **Commit 2**: rename `ShotController` → `ShotSequencer` (mechanical, separate commit on the same branch). Touches all references.
- Refactor to dedicated `StopAtWeightCapability` mixin — defer until a non-Bengle SAW machine appears.
- Real FW MMR address — fill in `BengleMmr.stopAtWeightTarget.address` when FW publishes; no-op stays until then for real Bengle.
- App-side "SAW armed" UI indicator — current realtime shot view shows `targetYield`; no extra surface needed yet.

## Verification

End-to-end on MockBengle (no FW dependency):

1. `flutter analyze` — clean.
2. `flutter test` — full suite + new tests.
3. `./scripts/sb-dev.sh start --simulate=machine` (verify MockBengle is selected; otherwise drive via app UI in simulate mode).
4. `curl http://localhost:8080/api/v1/machine/capabilities` → expect `"capabilities": ["cupWarmer","integratedScale","ledStrip","stopAtWeight"]`.
5. Set targetYield via WorkflowController (UI or REST) to 30g; confirm `BengleSawBridge` debounces + writes (log line on MockBengle).
6. Start shot via REST; MockBengle synthesises flow, weight integrates, MockBengle calls `requestState(idle)` when weight ≥ 30g.
7. Verify `ShotController` did **not** issue its own stop (log: bypass branch taken).
8. Disconnect + reconnect Bengle; verify bridge re-applies current target.
9. Set targetYield to `0.0`; verify MMR write of `0.0` → MockBengle reports SAW disabled.

Regression scenarios:
- DE1 connected (not Bengle) → no MMR write, ShotController SAW path runs as before.
- Bengle connected + `gatewayMode == full` → both bypass conditions short-circuit; ShotController stays out of SAW (no double-bypass bug).
- WorkflowController updates rapidly (slider drag) → debounce coalesces, no MMR write storm.

## Branching

- **New branch**: `feat/bengle-saw-mmr` off `main`.
- **Commits**:
  1. `feat: Bengle SAW MMR via WorkflowContext.targetYield` (the work above).
  2. `refactor: rename ShotController → ShotSequencer` (mechanical).
- **Completion**: PR to `main` when both commits land + tests green; do not push until user instructs.
- Move this plan to `doc/plans/` on the feature branch before opening the PR (per CLAUDE.md workflow), archive to `doc/plans/archive/bengle-saw-mmr/` post-merge.
