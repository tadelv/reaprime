**Current Step:** Step 1: Not started
**Status:** Ready
**Last Updated:** 2026-07-01
**Review Level:** 2
**Review Counter:** 0
**Iteration:** 0
**Size:** M

---

## Step 1: Add constants and reading model

**Status:** Not Started

- [ ] Create combustion_constants.dart with UUIDs, manufacturer ID 0x09C7, channel IDs
- [ ] Define CombustionReading with timestamp and thermistor fields

## Step 2: Implement decode logic

**Status:** Not Started

- [ ] Parse 13-byte thermistor field; celsius = (raw * 0.05) - 20
- [ ] Handle edge temps and corrupt/short packets without throwing on hot path

## Step 3: Unit tests with fixtures

**Status:** Not Started

- [ ] Test all committed hex fixtures plus synthetic edge cases

## Step 4: Testing & Verification

**Status:** Not Started

- [ ] Run flutter test
- [ ] Fix failures

## Step 5: Completion Criteria

**Status:** Not Started

- [ ] All steps complete
- [ ] Documentation satisfied

---

## Reviews

| Date | Step | Type | Outcome |
|------|------|------|---------|
| | | | |

## Discoveries

| Date | Finding | Impact |
|------|---------|--------|
| | | |

## Execution Log

| Date | Event | Detail |
|------|-------|--------|
| | | |

## Blockers

| Date | Blocker | Resolution |
|------|---------|------------|
| | | |

## Notes

