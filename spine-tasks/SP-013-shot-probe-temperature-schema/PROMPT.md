# Task: SP-013 — ShotSnapshot probeTemperature schema

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** DB migration and domain model change.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Add nullable `probeTemperature` to ShotSnapshot, Drift shot tables, DAO, and mapper with migration. Default brew channel uses T1 per OD-2. Unit-test round-trip.

## Dependencies

- SP-012

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/models/data/shot_snapshot.dart`
- `lib/src/services/storage/**`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/models/data/shot_snapshot.dart`
- `lib/src/services/storage/**`
- `test/**/shot*`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/database/shot_dao_test.dart test/models/shot_annotations_test.dart` |
| fileScopeMustChange | `lib/src/models/data/shot_snapshot.dart` |
| fileScopeMustNotChange | `lib/src/controllers/shot_sequencer.dart` |
| completionCriteria | Migration applies; DAO tests pass; probeTemperature persists nullable double. |

## Steps

### Step 1: Extend domain ShotSnapshot

- [ ] Add probeTemperature nullable double with JSON serialization

### Step 2: Drift migration and DAO

- [ ] Add column; update mapper; migration test

### Step 3: DAO round-trip tests

- [ ] Save/load shot with and without probeTemperature

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

- `assets/api/rest_v1.yml`

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-013): description`
- **Tests:** `test(SP-013): description`
- **Docs:** `docs(SP-013): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

