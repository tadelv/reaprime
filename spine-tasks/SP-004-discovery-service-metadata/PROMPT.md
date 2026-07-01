# Task: SP-004 — Discovery service scan metadata path

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** Touches hot discovery path for all BLE devices.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Update `UniversalBleDiscoveryService` to pass full scan metadata to `DeviceMatcher.matchFromScanMetadata()` and allow Combustion match when advertised name is empty. Preserve existing name-based flow for other devices.

## Dependencies

- SP-003

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/services/universal_ble_discovery_service.dart`
- `lib/src/services/device_matcher.dart`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/services/universal_ble_discovery_service.dart`
- `test/services/universal_ble_discovery_service_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test` |
| fileScopeMustChange | `lib/src/services/universal_ble_discovery_service.dart` |
| fileScopeMustNotChange | `lib/src/models/device/impl/combustion/**` |
| completionCriteria | Empty-name Combustion metadata match works in tests; no regression for named devices. |

## Steps

### Step 1: Build scan metadata per device

- [ ] Collect name, manufacturerData, serviceUuids from BleDevice
- [ ] Remove or bypass empty-name early return when metadata matches Combustion

### Step 2: Wire matchFromScanMetadata

- [ ] Instantiate CombustionProbe candidate on match without requiring connect

### Step 3: Tests

- [ ] Mock BleDevice with empty name + mfg ID; verify discovery list includes sensor

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

- **Implementation:** `feat(SP-004): description`
- **Tests:** `test(SP-004): description`
- **Docs:** `docs(SP-004): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

