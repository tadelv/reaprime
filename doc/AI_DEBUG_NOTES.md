# AI Debug Notes

Read this when triaging Crashlytics issues, debugging BLE errors, investigating telemetry noise, or diagnosing platform-specific crashes. Skip it for feature work that doesn't touch error paths.

## Source Of Truth

- Error filter: `lib/src/services/crashlytics_error_filter.dart`.
- Telemetry: `lib/src/services/telemetry/`.
- Logging: `package:logging`, configured in `main.dart`.
- Crashlytics console: Firebase project `rea-1-556fd`.

## Crashlytics Triage Workflow

1. Open Firebase Crashlytics for the relevant app (iOS `net.tadel.reaprime` or Android `net.tadel.reaprime`).
2. Filter by version and time range (default: 7 days).
3. For each cluster: check event count, user count, last seen version, first seen version.
4. **Investigating:** `NEEDS_TRIAGE` → open the issue, read stack trace, check for known patterns below.
5. **Resolved/Muted:** mark accordingly on Crashlytics.

## SEVERE-Only Forwarder

**PR #288:** Telemetry forwarder only forwards `SEVERE` + FATAL. WARNING still buffered for crash context but not forwarded. This prevents WARNING-level noise from drowning real crashes.

## Known Error Patterns

### `LateInitializationError: _chargingMode has not been initialized`

**Pattern:** `SettingsController` `late` fields accessed before `loadSettings()`.
**Fix (PR #243):** Replaced all `late` fields with safe defaults matching `SharedPreferencesSettingsService` `??` fallbacks.
**Status:** Holding. Last seen on v0.7.1 (iOS) and v0.7.2 (Android). Monitor for reappearance on newer versions.

### `PathAccessException: Operation not permitted` (iCloud Drive)

**Pattern:** Crash `760a674b` — `_DataManagementPageState._exportShots` writing directly to iCloud Drive.
**Related:** PR #409 fixed the `saveFile` path but this is a *different* export path.
**Fix needed:** Route this path through `saveFile` too, or guard with entitlement check.

### `PlatformException(startScan, Location services required)`

**Pattern:** Android BLE scan without location permissions.
**Status:** Low volume, 1 ev / 1 user. May be addressed by troubleshooting wizard (#125/#126).

### `TimeoutException` in `universal_ble/queue.dart`

**Pattern:** Crashes `60b12216` + `38d02b06` — BLE operations timing out after 10s in the universal_ble queue.
**Related:** May relate to zombie-link (#431) or concurrent BLE write contention (#423).
**Priority:** P2. Monitor after zombie-link fixes ship.

### iOS `WebUIHandler._handleInstallFromUrl`

**Pattern:** Crash `3045294f` — aged out. 1 event v0.6.4, two weeks stale. Likely blip on Mark's machine.

### `SuperNotCalledException: Activity did not call through to super.onCreate()`

**Pattern:** Crash `bef7d3cd` — Android launch crash, FATAL, 16 ev / 4 users.
**Fix (PR #435):** `super.onCreate()` moved to top of `onCreate()` before early-return guards.
**Follow-up:** Tighten `isRunningInClonedEnvironment()` heuristic — flags legitimate multi-user/work-profile devices as clones.

## BLE Error Debugging

**GATT-133 on cold boot:** See `doc/AI_BLE_NOTES.md` footgun #1. Second scan/connect succeeds. Early-connect watcher handles it.

**Duplicate state messages:** See `doc/AI_BLE_NOTES.md` footgun #2. Listener stacking from reconnect without disconnect. Fixed in PR #246.

**Scale write exceptions:** Must be caught at `_writeCommand` / `_safeWrite`. The `isBenignFrameworkError()` filter is the safety net, not the primary defense.

## Telemetry Noise Patterns

| Pattern | Source | Status |
|---------|--------|--------|
| `android_blue_plus_transport.disconnect` WARNING | PR #246 disconnect wiring | Suppressed by SEVERE floor (PR #288) |
| `defaultWorkflow.json` PathNotFoundException | Pre-PR #288 WARNING buffer draining | Monitor — not aging out as expected |
| Decent Temp disconnect noise | Temp sensor guard missing | Multiple `disconnect()` calls per event |

## Debugging Commands

```sh
# Android log retrieval
adb shell run-as net.tadel.reaprime cat app_flutter/log.txt
adb logcat | grep -i rea

# macOS log path
~/Library/Containers/net.tadel.reaprime/Data/Documents/log.txt
```

## Keeping Notes Fresh

Add new crash patterns with: symptom, root cause (if known), fix (if shipped), tracking issue. Mark aged-out clusters as closed. Prune when upstream fixes land.
