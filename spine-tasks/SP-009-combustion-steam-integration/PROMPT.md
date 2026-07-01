# Task: SP-009 — Combustion steam session integration test

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** Multi-component integration; validates Phase 1 steam path.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Add integration test: MockCombustion + SteamSequencer + PersistenceController full steam session with stopAtTemperature and milkTemperature in steam records.

## Dependencies

- SP-008

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `test/integration/**`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `test/integration/combustion_steam_stop_integration_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/integration/combustion_steam_stop_integration_test.dart` |
| fileScopeMustChange | `test/integration/combustion_steam_stop_integration_test.dart` |
| fileScopeMustNotChange | `lib/src/**` |
| completionCriteria | Integration test passes; documents FR-S1/S3 behavior. |

## Steps

### Step 1: Scaffold integration test

- [ ] Wire MockCombustion, mock machine, SteamSequencer, persistence

### Step 2: Exercise stop-at-temp flow

- [ ] Assert idle requested when temp crosses target
- [ ] Assert milkTemperature in steam snapshot

### Step 3: Probe disconnect scenario

- [ ] Verify no false stop after probeLost

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

- **Implementation:** `feat(SP-009): description`
- **Tests:** `test(SP-009): description`
- **Docs:** `docs(SP-009): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

