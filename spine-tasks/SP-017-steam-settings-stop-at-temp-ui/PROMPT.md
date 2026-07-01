# Task: SP-017 — Steam settings stopAtTemperature UI

**Created:** 2026-07-01
**Size:** M

## Review Level: 1

**Assessment:** Native settings UI for existing workflow field.
**Score:** 2/8 — Blast radius: 1, Pattern novelty: 0, Security: 0, Reversibility: 1

## Mission

Expose stopAtTemperature and preferred probe selection in native steam workflow settings UI (FR-U1, FR-U2).

## Dependencies

- SP-016

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `lib/src/home_feature/forms/steam_form.dart`
- `lib/src/settings/**`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/home_feature/forms/steam_form.dart`
- `lib/src/settings/**`
- `test/**/steam*`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/home_feature/` |
| fileScopeMustChange | `lib/src/home_feature/forms/steam_form.dart` |
| fileScopeMustNotChange | `lib/src/realtime_shot_feature/**` |
| completionCriteria | User can set stopAtTemperature and pick preferred probe when multiple sensors present. |

## Steps

### Step 1: Add stopAtTemperature field to steam form

- [ ] Bind to workflow steamSettings

### Step 2: Preferred probe picker

- [ ] List sensors from SensorController when count > 1

### Step 3: Widget tests

- [ ] Form renders and persists values

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

- **Implementation:** `feat(SP-017): description`
- **Tests:** `test(SP-017): description`
- **Docs:** `docs(SP-017): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

