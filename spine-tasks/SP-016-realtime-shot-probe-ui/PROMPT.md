# Task: SP-016 — Realtime shot UI probe display

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** UI change in realtime shot feature (OD-5 overlay).
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Display live and recorded probe temperature in realtime shot UI when sensor connected (FR-B5, OD-5).

## Dependencies

- SP-015

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/PRD.md`
- `lib/src/realtime_shot_feature/**`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/realtime_shot_feature/**`
- `test/**/realtime_shot*`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/realtime_shot_feature/` |
| fileScopeMustChange | `lib/src/realtime_shot_feature/**` |
| fileScopeMustNotChange | `lib/src/home_feature/forms/steam_form.dart` |
| completionCriteria | Widget test or manual verify path; probe temp visible during shot when sensor present. |

## Steps

### Step 1: Subscribe to preferred probe in UI layer

- [ ] Use existing sensor streams; avoid duplicating ShotSequencer logic in UI

### Step 2: Display live probe temp overlay

- [ ] Show Celsius when data available; hide when absent

### Step 3: Widget test

- [ ] Mock sensor stream shows temperature label

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

- `doc/Api.md`

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-016): description`
- **Tests:** `test(SP-016): description`
- **Docs:** `docs(SP-016): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

