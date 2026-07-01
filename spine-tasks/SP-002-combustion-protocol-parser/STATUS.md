**Current Step:** Step 5: Completion Criteria
**Status:** Complete
**Last Updated:** 2026-07-01
**Review Level:** 2
**Review Counter:** 0
**Iteration:** 0
**Size:** M

---

## Step 1: Add constants and reading model

**Status:** Complete

- [x] Create combustion_constants.dart with UUIDs, manufacturer ID 0x09C7, channel IDs
- [x] Define CombustionReading with timestamp and thermistor fields

## Step 2: Implement decode logic

**Status:** Complete

- [x] Parse 13-byte thermistor field; celsius = (raw * 0.05) - 20
- [x] Handle edge temps and corrupt/short packets without throwing on hot path

## Step 3: Unit tests with fixtures

**Status:** Complete

- [x] Test all committed hex fixtures plus synthetic edge cases

## Step 4: Testing & Verification

**Status:** Complete

- [x] Run flutter test
- [x] Fix failures

## Step 5: Completion Criteria

**Status:** Complete

- [x] All steps complete
- [x] Documentation satisfied

---

## Reviews

| Date | Step | Type | Outcome |
|------|------|------|---------|
| | | | |

## Discoveries

| Date | Finding | Impact |
|------|---------|--------|
| 2026-07-01 | Raw value 0 decodes to -20°C (range minimum), not null | Tests use 0x1FFF for missing sensors per iOS reference |

## Execution Log

| Date | Event | Detail |
|------|-------|--------|
| 2026-07-01 | Implemented | combustion_constants, combustion_protocol, unit tests |

## Blockers

| Date | Blocker | Resolution |
|------|---------|------------|
| | | |

## Notes

- Parser returns null (no throw) for corrupt/short packets on hot path.
- Virtual core/surface/ambient resolved from battery/virtual byte per spec.
