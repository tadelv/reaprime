**Current Step:** Step 5: Completion Criteria
**Status:** Complete
**Last Updated:** 2026-07-01
**Review Level:** 2
**Review Counter:** 0
**Iteration:** 0
**Size:** M

---

## Step 1: Add matchFromScanMetadata API

**Status:** Complete

- [x] Accept name, manufacturerData/ids, serviceUuids from scan + scan response
- [x] Try existing name rules first; fallback Combustion mfg ID or service UUID

## Step 2: Extend serviceUuidsFor sensor list

**Status:** Complete

- [x] Include Probe Status UUID for Android filtered-scan supplement

## Step 3: Unit tests

**Status:** Complete

- [x] Cover serial-name, empty-name+mfg, UUID in scan response, non-Combustion negative cases

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
| 2026-07-01 | Minimal `combustion_constants.dart` + `combustion_probe.dart` skeleton required for `matchFromScanMetadata` return type; SP-005 extends probe | Out-of-PROMPT-file-scope but logically required |
| 2026-07-01 | Tests live at `test/unit/services/device_matcher_test.dart` (not `test/services/` per PROMPT) | Used existing codebase path |
| 2026-07-01 | `webui_storage_bundled_test.dart` fails pre-existing (missing `assets/bundled_skins/`) | Not introduced by SP-003; 40/40 device_matcher tests pass |

## Execution Log

| Date | Event | Detail |
|------|-------|--------|
| 2026-07-01 | Step 1–2 | Added `matchFromScanMetadata`, Combustion metadata fallback, sensor UUID list |
| 2026-07-01 | Step 3 | Added 7 unit tests for scan metadata matching |
| 2026-07-01 | Step 4 | `flutter test test/unit/services/device_matcher_test.dart` — 40 passed; full suite 1847 passed, 1 pre-existing fail |

## Blockers

| Date | Blocker | Resolution |
|------|---------|------------|
| | | |

## Notes

- `matchFromScanMetadata` accepts `manufacturerCompanyIds` and `serviceUuids` (domain types, no `universal_ble` import).
