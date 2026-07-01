# Task: SP-007 — Preferred probe settings and resolution

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** Settings + SensorController policy affects steam and shot paths.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Add settings keys `preferredSteamProbeId`, `preferredShotProbeId`, `combustionDefaultChannel` (OD-3). Implement `SensorController.resolvePreferred()` with precedence: bridge-registered > explicit preferred > first registered.

## Dependencies

- SP-006

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/controllers/sensor_controller.dart`
- `lib/src/services/settings_service.dart`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/controllers/sensor_controller.dart`
- `lib/src/services/settings_service.dart`
- `test/controllers/sensor_controller_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/controllers/sensor_controller_test.dart` |
| fileScopeMustChange | `lib/src/controllers/sensor_controller.dart` |
| fileScopeMustNotChange | `lib/src/controllers/steam_sequencer.dart` |
| completionCriteria | Tests verify precedence with bridge, preferred, and fallback sensors. |

## Steps

### Step 1: Add settings keys

- [ ] Persist preferredSteamProbeId, preferredShotProbeId, combustionDefaultChannel

### Step 2: Implement resolvePreferred

- [ ] Bridge collision wins; then explicit ID; then first registered

### Step 3: Unit tests

- [ ] Multi-sensor scenarios per FR-M1/M2/M3

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

- `doc/DeviceManagement.md`

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-007): description`
- **Tests:** `test(SP-007): description`
- **Docs:** `docs(SP-007): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

