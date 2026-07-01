# Task: SP-012 — API docs for sensor WS during shots

**Created:** 2026-07-01
**Size:** S

## Review Level: 0

**Assessment:** Documentation only for Phase 2.
**Score:** 0/8 — Blast radius: 0, Pattern novelty: 0, Security: 0, Reversibility: 0

## Mission

Document skin developer use of `/ws/v1/sensors/{id}/snapshot` during espresso shots in doc/Api.md (OD-5: API for skins).

## Dependencies

- SP-011

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `doc/Api.md`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `doc/Api.md`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `true` |
| fileScopeMustChange | `doc/Api.md` |
| fileScopeMustNotChange | `lib/src/**` |
| completionCriteria | Api.md section explains live probe temp during shots for skin devs. |

## Steps

### Step 1: Add brew-time sensor WS section

- [ ] Document subscription during active shot
- [ ] Note preferredShotProbeId setting

### Step 2: Cross-link DeviceManagement

- [ ] Link sensor precedence docs

### Step 3: Review

- [ ] Ensure no stale endpoint paths

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

- `doc/Api.md`

**Check If Affected:**

- None

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-012): description`
- **Tests:** `test(SP-012): description`
- **Docs:** `docs(SP-012): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

