# Task: SP-001 — Phase 0 BLE discovery spike

**Created:** 2026-07-01
**Size:** M

## Review Level: 2

**Assessment:** Discovery refactor affects all BLE devices; spike is research-heavy with hardware dependency.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 1

## Mission

Complete the Phase 0 spike in `SPIKE-universal-ble-discovery.md`: validate `universal_ble` scan metadata on Android (and macOS if available), capture 2–3 real Combustion advertisement hex fixtures, record go/no-go for advertising-only MVP, and commit fixtures under `test/fixtures/combustion/`.

## Dependencies

- **None**

## Context to Read First

- `spine-tasks/CONTEXT.md`
- `doc/plans/combustion-probe/PRD.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `doc/plans/combustion-probe/SPIKE-universal-ble-discovery.md`
- `lib/src/services/universal_ble_discovery_service.dart`
- `CLAUDE.md`

## Environment

- **Workspace:** reaprime (Decent.app Flutter)
- **Services required:** none (use `--dart-define=simulate=1` for app-level verification tasks)

## File Scope

- `doc/plans/combustion-probe/SPIKE-universal-ble-discovery.md`
- `test/fixtures/combustion/**`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`

## Contract

| Field | Value |
|-------|-------|
| testCommand | `true` |
| fileScopeMustChange | `test/fixtures/combustion/**` |
| fileScopeMustNotChange | `lib/src/**` |
| completionCriteria | Spike checklist complete; go/no-go recorded; hex fixtures committed if hardware available (or documented blocker with simulate-only path). |

## Steps

### Step 1: Investigate universal_ble metadata

- [ ] Fill spike checklist tables for manufacturerData, serviceUuids, and scan-response behavior
- [ ] Record package version, SDK, and hardware tested

### Step 2: Capture Combustion fixtures

- [ ] Store at least two advertisement payloads as hex under test/fixtures/combustion/
- [ ] Note firmware version and Instant Read vs normal mode if captured

### Step 3: Record go/no-go decision

- [ ] Select path A/B/C in spike doc with rationale
- [ ] Add summary paragraph to IMPLEMENTATION.md §3

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

- `doc/plans/combustion-probe/IMPLEMENTATION.md`

## Completion Criteria

- [ ] All steps complete
- [ ] `flutter test` passes (or verification pending with documented hardware blocker for SP-001 only)
- [ ] Documentation requirements satisfied

## Git Commit Convention

- **Implementation:** `feat(SP-001): description`
- **Tests:** `test(SP-001): description`
- **Docs:** `docs(SP-001): description`

## Do NOT

- Expand scope beyond this PROMPT
- Skip the Testing & Verification step
- Import `universal_ble` outside `lib/src/services/ble/`
- Modify files outside File Scope

---

## Amendments (Added During Execution)

