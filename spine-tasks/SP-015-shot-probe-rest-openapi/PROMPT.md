# Task: SP-015 — Shot probe REST and OpenAPI

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** API spec sync required same commit.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 0, Security: 0, Reversibility: 2

## Mission

Expose probeTemperature on shot REST endpoints; update assets/api/rest_v1.yml and doc/Api.md in same commit (FR-B6).

## Dependencies

- SP-014

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `assets/api/rest_v1.yml`
- `doc/Api.md`
- `lib/src/services/webserver/shots_handler.dart`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `assets/api/rest_v1.yml`
- `doc/Api.md`
- `lib/src/services/webserver/shots_handler.dart`
- `test/services/webserver/shots_handler_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/webserver/shots_handler_test.dart` |
| fileScopeMustChange | `assets/api/rest_v1.yml` |
| fileScopeMustNotChange | `lib/src/realtime_shot_feature/**` |
| completionCriteria | OpenAPI and handler tests include probeTemperature; spec and doc match. |

## Steps

### Step 1: Update rest_v1.yml ShotSnapshot schema

- [ ] Add nullable probeTemperature double Celsius

### Step 2: Update shots handler serialization

- [ ] Include field in GET/POST responses

### Step 3: Update doc/Api.md and handler tests

- [ ] Same commit as yml change

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

- `assets/api/rest_v1.yml`
- `doc/Api.md`

**Check If Affected:**

- None

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-015): description`
- **Tests:** `test(SP-015): description`
- **Docs:** `docs(SP-015): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

