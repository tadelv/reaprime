# Task: SP-006 — MockCombustion simulate wiring

**Created:** 2026-07-01
**Size:** S

## Review Level: 1

**Assessment:** Follows existing MockScale/MockDe1 simulate patterns.
**Score:** 2/8 — Blast radius: 1, Pattern novelty: 0, Security: 0, Reversibility: 1

## Mission

Add `MockCombustionProbe` and wire into `SimulatedDeviceService` and simulate startup so `--dart-define=simulate=1` includes a Combustion sensor (FR-X1).

## Dependencies

- SP-005

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/services/simulated_device_service.dart`
- `lib/main.dart`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/models/device/impl/combustion/mock_combustion_probe.dart`
- `lib/src/services/simulated_device_service.dart`
- `lib/main.dart`
- `test/services/simulated_device_service_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/services/simulated_device_service_test.dart` |
| fileScopeMustChange | `lib/src/models/device/impl/combustion/mock_combustion_probe.dart` |
| fileScopeMustNotChange | `lib/src/controllers/steam_sequencer.dart` |
| completionCriteria | Simulate mode exposes Combustion in sensor list; tests pass. |

## Steps

### Step 1: Implement MockCombustionProbe

- [ ] Emit controllable temperature stream for tests and simulate mode

### Step 2: Wire SimulatedDeviceService and main.dart

- [ ] Include combustion in simulate device types

### Step 3: Tests

- [ ] Verify mock appears when simulate sensor type enabled

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

- **Implementation:** `feat(SP-006): description`
- **Tests:** `test(SP-006): description`
- **Docs:** `docs(SP-006): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

