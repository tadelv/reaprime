# LED Strip API v2

Rethink the Bengle LED strip API to support 3 zones × 2 modes × 16-bit colour, plus commit/reset semantics.

## Changes summary

| Aspect | Current (v1) | v2 |
|--------|-------------|----|
| Zones | front strip, back strip | front strip, back strip, **front switch** |
| Channel depth | 8-bit (0–255) | **16-bit (0–65535)** |
| Modes | single | **sleeping + awake** per zone |
| Wire format | `"FF8000"` per zone | `"FFFF80000000"` per zone–mode (12 hex chars) |
| Commit/reset | none | `POST /commit` + `POST /reset` |
| Endpoints | `BengleLedEndpoint.front`, `.back` | 6 colour writes + 1 commit + 1 reset (all stubbed null) |

## Data model

### `Color16`

```dart
class Color16 {
  final int red;   // 0–65535
  final int green; // 0–65535
  final int blue;  // 0–65535

  const Color16(this.red, this.green, this.blue);
  static const off = Color16(0, 0, 0);

  String toJson() => ...;   // 12 hex chars: RRRRGGGGBBBB
  static Color16 fromJson(String hex) => ...;
}
```

### `ZoneLedState`

```dart
class ZoneLedState {
  final Color16 sleeping;
  final Color16 awake;
  const ZoneLedState({this.sleeping = Color16.off, this.awake = Color16.off});
  Map<String, dynamic> toJson() => {'sleeping': ..., 'awake': ...};
  factory ZoneLedState.fromJson(Map<String, dynamic> json) => ...;
}
```

### `LedStripState`

Replaces the current flat 6-int struct.

```dart
class LedStripState {
  final ZoneLedState frontStrip;
  final ZoneLedState backStrip;
  final ZoneLedState frontSwitch;
  // ...
}
```

Wire format:

```json
{
  "frontStrip": {
    "sleeping": "0000FFFF0000",
    "awake": "FFFF80000000"
  },
  "backStrip": {
    "sleeping": "000000000000",
    "awake": "FFFFFFFFFFFF"
  },
  "frontSwitch": {
    "sleeping": "FFFF00000000",
    "awake": "000000000000"
  }
}
```

## Endpoints (`BengleLedEndpoint`)

All stubbed with `null` UUID/representation — TBD with FW.

| Enum value | Direction | Purpose |
|------------|-----------|---------|
| `frontStripSleeping` | write | Front strip colour when machine is sleeping |
| `frontStripAwake` | write | Front strip colour when machine is awake |
| `backStripSleeping` | write | Back strip colour when sleeping |
| `backStripAwake` | write | Back strip colour when awake |
| `frontSwitchSleeping` | write | Front switch colour when sleeping |
| `frontSwitchAwake` | write | Front switch colour when awake |
| `commitConfig` | write | Persist working registers to NVM |
| `resetConfig` | write | Reload NVM into working registers |

## REST surface

All paths under `/api/v1/machine/ledStrip`. Gated on `device is BengleInterface`; 404 on plain DE1.

| Method | Path | Request body | Response | Behaviour |
|--------|------|-------------|----------|-----------|
| `GET` | `/` | — | `LedStripState` JSON | Read from in-memory cache |
| `PUT` | `/` | `LedStripState` JSON | `200 {"status":"accepted"}` | Write cache + push all 6 zone-mode colours to FW live registers |
| `POST` | `/commit` | — (or empty `{}`) | `202` | Send `commitConfig` to FW NVM |
| `POST` | `/reset` | — (or empty `{}`) | `200` with fresh `LedStripState` | Send `resetConfig` to FW, then re-read cache from FW |

**Why `PUT` on write:** idempotent — setting the same colours twice is a no-op. Keeps the API RESTful. The cup-warmer endpoint (`PUT /api/v1/machine/cupWarmer`) will be migrated from `POST` to `PUT` in the same pass for consistency.

## Behaviour when wires are stubbed

All endpoints return `null` for `uuid` and `representation`. `LedStripCapability` follows the same pattern as today:

- `PUT /ledStrip` → updates cache, writes are no-ops (info log on first write of the session), returns 200.
- `POST /commit` → info log, returns 202.
- `POST /reset` → info log, returns cache unchanged (all-off or last cached value).
- `GET /ledStrip` → returns cache (works regardless of FW wire state).

The capability is fully functional as an in-memory config store. When FW publishes wires, fill in `BengleLedEndpoint` values and the cache ↔ FW sync lights up unchanged.

## MockBengle

- Stores `LedStripState` in memory.
- `commit` saves the current cache to an internal `_committed` field (starts as all-off).
- `reset` copies `_committed` back into the cache.
- All `currentSnapshot` / flow / scale integration unchanged.

## Test plan

### Unit — `LedStripCapability`

1. Initial state: all zones, both modes → `Color16.off`.
2. `PUT` with full `LedStripState` → cache updated.
3. `GET` → returns cache.
4. Stubbed-wire info log fires once on first write.
5. Connect → disconnect → reconnect lifecycle: subject re-created, cache resets to all-off.
6. `commit` → info log, no crash.
7. `reset` → info log, no crash.

### Unit — `Color16` / `ZoneLedState` / `LedStripState`

1. `Color16.off` → hex `"000000000000"`.
2. `Color16(0xFFFF, 0x8000, 0x0000)` → hex `"FFFF80000000"`.
3. Hex parse symmetry: `fromJson(toJson())` round-trip.
4. Equality and hashCode.
5. `ZoneLedState` and `LedStripState` JSON round-trip.

### Unit — `MockBengle`

1. Initial state all-off.
2. Write → read returns same.
3. `commit` → `reset` cycles: after commit, reset brings back committed state.
4. Uncommitted changes dropped on reset.

### Integration — `de1handler`

1. `GET /api/v1/machine/ledStrip` → 200 + full state on Bengle.
2. `GET` → 404 on plain DE1.
3. `PUT` with valid body → 200.
4. `PUT` with invalid body → 400.
5. `PUT` → 404 on plain DE1.
6. `POST /commit` → 202 on Bengle, 404 on DE1.
7. `POST /reset` → 200 + state on Bengle, 404 on DE1.

### API spec

`assets/api/rest_v1.yml` updated:
- `LedStripState` schema replaced (was flat `front`/`back` hex strings, now nested with `ZoneLedState` → `Color16`).
- New `commit` and `reset` endpoints.
- `Color16` and `ZoneLedState` as reusable components.
- Capabilities list updated (still `ledStrip` — no change needed there).

## Implementation order

1. `Color16` class — new file `lib/src/models/device/led_strip.dart` (replaces existing content, no backwards compat needed).
2. `ZoneLedState` class — same file.
3. `LedStripState` class — replaces the current flat struct. `toJson`/`fromJson` changed.
4. `BengleLedEndpoint` enum — 8 entries, all null.
5. `LedStripCapability` mixin — updated `setLedStrip`/`getLedStripState`, new `commitLedStrip`/`resetLedStrip`. Cache-only when wires null.
6. `BengleInterface` — add `commitLedStrip()` and `resetLedStrip()` methods.
7. `Bengle` — wire `commitLedStrip`/`resetLedStrip` through mixin, delegate `ledStripState`/`getLedStripState`/`setLedStrip` (same pattern as today).
8. `MockBengle` — in-memory commit/reset.
9. REST handler — new routes for commit/reset. `PUT` replaces current `POST` (or keep `POST` — see open question above).
10. API spec + tests.

## Open questions

- **Commit/reset endpoint request body.** Empty JSON object `{}`.

## Adjacent change — cup warmer PUT migration

The cup-warmer endpoint currently uses `POST /api/v1/machine/cupWarmer`. Migrate to `PUT` for idempotency consistency with the LED strip API. Update:
- REST handler route
- `assets/api/rest_v1.yml`
- Test expectations
- Scenario files referencing the POST

This is a single-commit change (no functionality change, just verb swap + 200 response instead of 202).
