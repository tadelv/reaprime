# Task: SP-005 — CombustionProbe advertising-only sensor

**Created:** 2026-07-01
**Size:** L

## Review Level: 2

**Assessment:** New Sensor implementation; adv-only pattern is novel for this codebase.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 1

## Mission

Implement `CombustionProbe implements Sensor` using advertising-only temperature reads (OD-4). Parse via CombustionProtocol; emit minimum `{temperature, timestamp}` on data stream; expose extended channels in SensorInfo. Default steam channel: virtual core (OD-1).

## Dependencies

- SP-002
- SP-004

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `lib/src/models/device/impl/combustion/combustion_protocol.dart`
- `lib/src/models/device/impl/difluid/difluid_r2_sensor.dart`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/models/device/impl/combustion/combustion_probe.dart`
- `lib/src/models/device/impl/combustion/combustion_constants.dart`
- `test/models/device/impl/combustion/combustion_probe_test.dart`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test` |
| fileScopeMustChange | `lib/src/models/device/impl/combustion/combustion_probe.dart` |
| fileScopeMustNotChange | `lib/src/services/simulated_device_service.dart` |
| completionCriteria | Unit tests show mock transport adv bytes produce data stream with temperature key. |

## Steps

### Step 1: Implement CombustionProbe skeleton

- [ ] BleServiceIdentifier, manufacturerId, Sensor interface
- [ ] onConnect registers adv listener; no GATT for MVP

### Step 2: Wire protocol to data stream

- [ ] Map virtual core to temperature key per OD-1
- [ ] Populate SensorInfo dataChannels for extended readings

### Step 3: Unit tests with mock transport

- [ ] Adv payload produces expected temperature on BehaviorSubject

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

- **Implementation:** `feat(SP-005): description`
- **Tests:** `test(SP-005): description`
- **Docs:** `docs(SP-005): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

