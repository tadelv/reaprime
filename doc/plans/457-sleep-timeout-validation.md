# PR #457 — Sleep Timeout Validation

## Original failure modes

`POST /api/v1/presence/settings` treated the JSON body as trusted:

- `json['sleepTimeoutMinutes'] as int` — non-integer values threw `TypeError`, surfaced as 500
- Out-of-range integers were written unchecked (e.g., 99999)
- `userPresenceEnabled as bool` had the same unchecked cast
- Settings import (`SettingsExportSection._importSetting`) had the identical hard cast
- The native settings page used a dropdown with only 0, 15, 30, 45, 60, 90, 120, 180 options

## Selected preference contract

- `sleepTimeoutMinutes` range: **0–240** (0 = disabled)
- Integer values outside this range are **normalized** (clamped), not rejected
- Non-integer values (string, double, null) are **rejected** with 400
- `userPresenceEnabled` accepts `bool` only — everything else is 400
- Both fields remain optional (partial updates valid)

## Architecture boundary

**App-side preference** (this PR):
- Owned by `SleepTimeoutPreference` (`sleep_timeout_preference.dart`)
- Controls how the app asks the machine to sleep
- Validated and normalized at every entry point

**Machine-side safety** (separate, not in this PR):
- Bengle's machine-register sleep timeout (hardware register)
- Separate safety boundary with its own range
- This PR intentionally preserves the separation

## REST atomicity

The handler follows a validate-all-then-persist pattern:

1. Decode JSON body (reject malformed/non-object)
2. Extract `userPresenceEnabled` and `sleepTimeoutMinutes` into locals, validating types
3. Normalize `sleepTimeoutMinutes` integer to `0..240`
4. Persist both fields
5. Return normalized values

Mixed valid/invalid requests change nothing — the 400 response preserves the prior state.

## Persisted-value repair

`SettingsController.loadSettings()` now runs the normalization on the value read from SharedPreferences. This repairs hand-edited or legacy persisted values, bringing them in-range on first load.

## UI lifecycle

The `PresenceSettingsPage` timeout field uses:

- State-owned `TextEditingController` and `FocusNode` (initialized in `initState`, disposed in `dispose`)
- External change sync via `SettingsController.addListener` → `_handleSettingsChanged`
- Focus guard: field text is only synced from model when the field does not have focus
- Async `_commitSleepTimeout` that normalizes and reads back the stored value
- `keyboardType: numberWithOptions(signed: true, decimal: false)` to accept negative input

## Test matrix

| Category | Count | What |
|---|---|---|
| Preference unit | 3 | normalization bounds |
| Controller | 7 | normalize-on-write, repair-on-load, no-op guard |
| REST handler | 15 | atomic validation, normalization, rejection, partial updates |
| Import | 8 | int OK, string/null rejected, negative normalized to 0, field index tracking |
| Widget | 9 | commit, clamp, validation, rebuild survival, external sync, focus protection |

**Total: 42 tests**

## Manual verification

- `scripts/sb-dev.sh start` + curl
- `{"sleepTimeoutMinutes":37}` → 200, stores 37
- `{"sleepTimeoutMinutes":999}` → 200, stores 240
- `{"sleepTimeoutMinutes":-10}` → 200, stores 0
- `{"userPresenceEnabled":false,"sleepTimeoutMinutes":"30"}` → 400, neither setting changed
- Malformed JSON → 400
- Array root → 400
