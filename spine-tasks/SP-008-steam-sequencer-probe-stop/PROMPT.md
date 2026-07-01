# Task: SP-008 — SteamSequencer preferred probe and probe-lost

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** Steam stop safety path; gateway mode gate per OD-6.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Update SteamSequencer to use resolvePreferred for steam probe, add _probeLost on disconnect mid-steam, and gate app-side stop when gatewayMode == full (OD-6).

## Dependencies

- SP-007

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/controllers/steam_sequencer.dart`
- `doc/plans/archive/shot-scale-disconnect/2026-04-06-shot-scale-disconnect.md`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/controllers/steam_sequencer.dart`
- `test/controllers/steam_sequencer_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test` |
| fileScopeMustChange | `lib/src/controllers/steam_sequencer.dart` |
| fileScopeMustNotChange | `lib/src/controllers/shot_sequencer.dart` |
| completionCriteria | Tests cover app-side stop, preferred probe, probeLost, gateway full inert. |

## Steps

### Step 1: Replace first-sensor tracking

- [ ] Use SensorController.resolvePreferred(preferredSteamProbeId)

### Step 2: Add _probeLost handling

- [ ] Listen connectionState during steam; disable stop on disconnect

### Step 3: Gateway mode gate and tests

- [ ] Skip _maybeAppSideStop when gatewayMode == full
- [ ] Extend steam_sequencer_test.dart

### Step 4: Testing & Verification

- [ ] Run `flutter test`
- [ ] Run targeted tests for files in File Scope
- [ ] Fix all failures introduced by this task

### Step 5: Completion Criteria

- [ ] All steps above complete
- [ ] Contract completionCriteria met
- [ ] Documentation requirements satisfied

## Documentation Requirements

**Must Update:**

- None

**Check If Affected:**

- None

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-008): description`
- **Tests:** `test(SP-008): description`
- **Docs:** `docs(SP-008): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

