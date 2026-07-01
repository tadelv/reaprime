# Task: SP-018 — Hardware validation protocol

**Created:** 2026-07-01
**Size:** S

## Review Level: 1

**Assessment:** Docs + checklist for DE1 tablet hardware sign-off.
**Score:** 2/8 — Blast radius: 0, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Document hardware test protocol: DE1/Bengle + scale + Combustion probe concurrent; wake-from-sleep discovery; stop-at-temp accuracy. Add checklist to IMPLEMENTATION or doc/plans/combustion-probe/.

## Dependencies

- SP-017

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `doc/plans/combustion-probe/PRD.md`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `doc/plans/combustion-probe/HARDWARE-VALIDATION.md`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter analyze && flutter test` |
| fileScopeMustChange | `doc/plans/combustion-probe/HARDWARE-VALIDATION.md` |
| fileScopeMustNotChange | `lib/src/**` |
| completionCriteria | Hardware validation checklist ready for manual sign-off on Android DE1 tablet. |

## Steps

### Step 1: Author HARDWARE-VALIDATION.md

- [ ] Concurrent connection scenarios, wake-from-sleep, stop latency

### Step 2: Link from IMPLEMENTATION acceptance criteria

- [ ] Cross-reference §14 Phase 3 hardware item

### Step 3: Note firmware pin and fixture provenance

- [ ] Reference test/fixtures/combustion and spec DRAFT status

### Step 4: Testing & Verification

- [ ] Run `flutter analyze && flutter test`
- [ ] Run targeted tests for files in File Scope
- [ ] Fix all failures introduced by this task

### Step 5: Completion Criteria

- [ ] All steps above complete
- [ ] Contract completionCriteria met
- [ ] Documentation requirements satisfied

## Documentation Requirements

**Must Update:**

- `doc/plans/combustion-probe/HARDWARE-VALIDATION.md`

**Check If Affected:**

- `doc/plans/combustion-probe/IMPLEMENTATION.md`

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter analyze && flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-018): description`
- **Tests:** `test(SP-018): description`
- **Docs:** `docs(SP-018): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

