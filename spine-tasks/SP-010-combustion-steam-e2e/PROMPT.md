# Task: SP-010 — Combustion steam stop E2E scenario

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** E2E recipe + manual sb-dev verification.
**Score:** 3/8 — Blast radius: 0, Pattern novelty: 1, Security: 0, Reversibility: 2

## Mission

Create `.agents/skills/decent-app/scenarios/combustion-probe-steam-stop.md` E2E recipe and verify via sb-dev simulate smoke (sensor list, workflow PUT, steam idle, steams/latest milkTemperature).

## Dependencies

- SP-009

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `.agents/skills/decent-app/verification.md`
- `.agents/skills/decent-app/scenarios/**`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `.agents/skills/decent-app/scenarios/combustion-probe-steam-stop.md`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `true` |
| fileScopeMustChange | `.agents/skills/decent-app/scenarios/combustion-probe-steam-stop.md` |
| fileScopeMustNotChange | `lib/src/**` |
| completionCriteria | Scenario doc complete; sb-dev smoke steps documented with expected curl/websocat output. |

## Steps

### Step 1: Author E2E scenario markdown

- [ ] Mirror Bengle milk-probe scenario structure
- [ ] Include simulate startup, sensors GET, workflow PUT, steam WS, steams/latest

### Step 2: Run sb-dev smoke

- [ ] Execute scenario against simulate mode; note results in STATUS

### Step 3: Fix any gaps found in smoke

- [ ] Only if smoke reveals bugs in scope of prior tasks — otherwise log blockers

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

- `.agents/skills/decent-app/scenarios/combustion-probe-steam-stop.md`

**Check If Affected:**

- `.agents/skills/decent-app/verification.md`

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-010): description`
- **Tests:** `test(SP-010): description`
- **Docs:** `docs(SP-010): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

