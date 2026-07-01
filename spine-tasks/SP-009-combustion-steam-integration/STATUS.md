**Current Step:** Step 5: Complete
**Status:** Complete
**Last Updated:** 2026-07-01
**Review Level:** 2
**Review Counter:** 0
**Iteration:** 0
**Size:** M

---

## Step 1: Scaffold integration test

**Status:** Complete

- [x] Wire MockCombustion, mock machine, SteamSequencer, persistence

## Step 2: Exercise stop-at-temp flow

**Status:** Complete

- [x] Assert idle requested when temp crosses target
- [x] Assert milkTemperature in steam snapshot

## Step 3: Probe disconnect scenario

**Status:** Complete

- [x] Verify no false stop after probeLost

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
| 2026-07-01 | `flutter test` reports 1 pre-existing failure in `webui_storage_bundled_test.dart` (broken `assets/bundled_skins` symlink in worktree); not introduced by SP-009 | None for this task |

## Execution Log

| Date | Event | Detail |
|------|-------|--------|
| 2026-07-01 | Implemented | `combustion_steam_stop_integration_test.dart` with FR-S1/S3 and probeLost scenarios |
| 2026-07-01 | Verified | Targeted test: 2/2 passed; full suite: 1883 passed, 1 failed (pre-existing) |

## Blockers

| Date | Blocker | Resolution |
|------|---------|------------|
| | | |

## Notes

Integration test mirrors `hot_water_sequencer_integration_test.dart` wiring: real controllers + MockDe1 + MockCombustionProbe + in-memory Drift persistence.
