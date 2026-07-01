# Task: SP-011 — DeviceManagement Combustion documentation

**Created:** 2026-07-01
**Size:** S

## Review Level: 0

**Assessment:** Documentation only.
**Score:** 1/8 — Blast radius: 0, Pattern novelty: 0, Security: 0, Reversibility: 1

## Mission

Document Combustion discovery, advertising-only mode, and sensor precedence in doc/DeviceManagement.md.

## Dependencies

- SP-010

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/PRD.md`
- `doc/DeviceManagement.md`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `doc/DeviceManagement.md`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `true` |
| fileScopeMustChange | `doc/DeviceManagement.md` |
| fileScopeMustNotChange | `lib/src/**` |
| completionCriteria | DeviceManagement.md describes Combustion ID paths and precedence rules. |

## Steps

### Step 1: Add Combustion discovery section

- [ ] Manufacturer ID, service UUID, empty-name behavior

### Step 2: Document sensor precedence

- [ ] bridge > preferred > first registered per FR-M3

### Step 3: Review for accuracy

- [ ] Cross-check against implemented code from Phase 1 tasks

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

- `doc/DeviceManagement.md`

**Check If Affected:**

- None

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-011): description`
- **Tests:** `test(SP-011): description`
- **Docs:** `docs(SP-011): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

