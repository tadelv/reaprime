# Task: SP-002 — CombustionProtocol pure parser

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** New pure-Dart protocol module; isolated but correctness-critical.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Mission

Implement `CombustionProtocol` as pure Dart parse/decode for Combustion advertising and Probe Status payloads. Unit-test with fixtures from Phase 0. Emit `CombustionReading` with raw T1–T8 and optional virtual core/surface/ambient per spec.

## Dependencies

- SP-001

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `test/fixtures/combustion/**`
- `lib/src/models/device/impl/decent_temp/temperature.dart`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `lib/src/models/device/impl/combustion/combustion_constants.dart`
- `lib/src/models/device/impl/combustion/combustion_protocol.dart`
- `test/models/device/impl/combustion/combustion_protocol_test.dart`
- `test/fixtures/combustion/**`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `flutter test test/models/device/impl/combustion/combustion_protocol_test.dart` |
| fileScopeMustChange | `lib/src/models/device/impl/combustion/combustion_protocol.dart` |
| fileScopeMustNotChange | `lib/src/services/**` |
| completionCriteria | Parser tests pass; corrupt packets handled safely; temperature formula matches spec. |

## Steps

### Step 1: Add constants and reading model

- [ ] Create combustion_constants.dart with UUIDs, manufacturer ID 0x09C7, channel IDs
- [ ] Define CombustionReading with timestamp and thermistor fields

### Step 2: Implement decode logic

- [ ] Parse 13-byte thermistor field; celsius = (raw * 0.05) - 20
- [ ] Handle edge temps and corrupt/short packets without throwing on hot path

### Step 3: Unit tests with fixtures

- [ ] Test all committed hex fixtures plus synthetic edge cases

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

- **Implementation:** `feat(SP-002): description`
- **Tests:** `test(SP-002): description`
- **Docs:** `docs(SP-002): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

