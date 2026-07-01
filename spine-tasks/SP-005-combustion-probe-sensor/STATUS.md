**Current Step:** Complete
**Status:** Done
**Last Updated:** 2026-07-01
**Review Level:** 2
**Review Counter:** 0
**Iteration:** 0
**Size:** L

---

## Step 1: Implement CombustionProbe skeleton

**Status:** Complete

- [x] BleServiceIdentifier, manufacturerId, Sensor interface
- [x] onConnect registers adv listener; no GATT for MVP

## Step 2: Wire protocol to data stream

**Status:** Complete

- [x] Map virtual core to temperature key per OD-1
- [x] Populate SensorInfo dataChannels for extended readings

## Step 3: Unit tests with mock transport

**Status:** Complete

- [x] Adv payload produces expected temperature on BehaviorSubject

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
| 2026-07-01 | BLETransport has no adv stream yet; `CombustionAdvertisingTransport` interface defined in combustion_probe.dart for transport wiring | SP-006 or transport task must implement interface on UniversalBleTransport |

## Execution Log

| Date | Event | Detail |
|------|------|--------|
| 2026-07-01 | Implementation | CombustionProbe adv-only sensor + unit tests |
| 2026-07-01 | Verification | `flutter test` passed |

## Blockers

| Date | Blocker | Resolution |
|------|---------|------------|
| | | |

## Notes

- `CombustionAdvertisingTransport` is the capability hook for production adv streaming on UniversalBleTransport.
