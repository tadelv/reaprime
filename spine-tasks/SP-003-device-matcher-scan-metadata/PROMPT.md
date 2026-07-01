# Task: SP-003 — DeviceMatcher scan metadata matching

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** Discovery matching affects all device types; new API surface.
**Score:** 3/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 0

## Mission

Add `DeviceMatcher.matchFromScanMetadata()` for Combustion identification by manufacturer ID 0x09C7 and/or Probe Status service UUID, including empty-name and scan-response UUID paths. Add Combustion UUID to `serviceUuidsFor(DeviceType.sensor)`.

## Dependencies

- SP-001

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/services/device_matcher.dart`
- `doc/plans/archive/ble-scan-refactor/2026-02-23-ble-scan-refactor-design.md`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/services/device_matcher.dart`
- `test/services/device_matcher_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test` |
| fileScopeMustChange | `lib/src/services/device_matcher.dart` |
| fileScopeMustNotChange | `lib/src/services/universal_ble_discovery_service.dart` |
| completionCriteria | Tests cover name, mfg ID, service UUID in scan response, empty name + mfg; existing matchers unchanged. |

## Steps

### Step 1: Add matchFromScanMetadata API

- [ ] Accept name, manufacturerData/ids, serviceUuids from scan + scan response
- [ ] Try existing name rules first; fallback Combustion mfg ID or service UUID

### Step 2: Extend serviceUuidsFor sensor list

- [ ] Include Probe Status UUID for Android filtered-scan supplement

### Step 3: Unit tests

- [ ] Cover serial-name, empty-name+mfg, UUID in scan response, non-Combustion negative cases

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

- **Implementation:** `feat(SP-003): description`
- **Tests:** `test(SP-003): description`
- **Docs:** `docs(SP-003): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

