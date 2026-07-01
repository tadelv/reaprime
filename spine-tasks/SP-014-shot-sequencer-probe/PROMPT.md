# Task: SP-014 — ShotSequencer probe subscription

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** Shot recording path; disconnect safety required.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Wire ShotSequencer to preferred shot probe via resolvePreferred; subscribe during recording; populate probeTemperature on ShotSnapshot; _probeLost on disconnect (FR-B3a).

## Dependencies

- SP-013

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/controllers/shot_sequencer.dart`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/controllers/shot_sequencer.dart`
- `test/controllers/shot_sequencer_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/controllers/shot_sequencer_test.dart` |
| fileScopeMustChange | `lib/src/controllers/shot_sequencer.dart` |
| fileScopeMustNotChange | `assets/api/rest_v1.yml` |
| completionCriteria | Tests show probe temp on snapshots; disconnect mid-shot uses last-known temp. |

## Steps

### Step 1: Resolve and subscribe to preferred probe

- [ ] Use preferredShotProbeId from settings

### Step 2: Populate ShotSnapshot.probeTemperature

- [ ] Track latest reading each frame

### Step 3: _probeLost and tests

- [ ] Continue recording with last-known on disconnect
- [ ] Extend shot_sequencer_test.dart

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

- **Implementation:** `feat(SP-014): description`
- **Tests:** `test(SP-014): description`
- **Docs:** `docs(SP-014): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

