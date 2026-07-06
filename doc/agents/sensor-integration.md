# Sensor Integration Guide (for AI agents)

Read this before adding a BLE temperature sensor or similar third-party probe to Decent.app.

**Worked example:** [Combustion probe v2 reimplementation](../plans/combustion-probe/REIMPLEMENTATION-v2.md) — documents what went wrong when these rules were skipped (PR #404).

---

## A. Maintainer rules (authoritative)

From [tadelv PR #404 comment](https://github.com/tadelv/reaprime/pull/404#issuecomment-4896713589):

1. Implement as a `Sensor` like [`DecentTemp`](../../lib/src/models/device/impl/decent_temp/temperature.dart) — emit `temperature` on the `data` stream.
2. Register in [`device_matcher.dart`](../../lib/src/services/device_matcher.dart) only (commit [`4b00f6a`](https://github.com/tadelv/reaprime/commit/4b00f6a2f306972bee1719c6cb810bb3985e284f) pattern for DecentTemp).
3. Use existing API fields (e.g. `Workflow.SteamSettings.stopAtTemperature` on `/api/v1/workflow`) — do not add parallel settings or controllers unless the maintainer asks.
4. **Do not re-plumb sequencers** — [`SteamSequencer`](../../lib/src/controllers/steam_sequencer.dart) on `upstream/main` already consumes `sensor.data['temperature']` for stop-at-temperature.

---

## B. Existing scaffolding (read before coding)

| System | File | What it already does |
|--------|------|----------------------|
| Sensor registry | `lib/src/controllers/sensor_controller.dart` | Discovers sensors via `DeviceController`, calls `onConnect()`, merges bridge-registered adapters |
| Steam stop | `lib/src/controllers/steam_sequencer.dart` | `_trackFirstSensor()` + `_maybeAppSideStop()` when `stopAtTemperature > 0` |
| Sensor API | `lib/src/services/webserver/sensors_handler.dart` | REST `/api/v1/sensors`, WS `/ws/v1/sensors/{id}/snapshot` |
| Workflow API | `workflow_handler.dart` + `lib/src/models/data/workflow.dart` | `steamSettings.stopAtTemperature` round-trip |
| Discovery | `universal_ble_discovery_service.dart` + `device_matcher.dart` | BLE scan → device match |

On `upstream/main`, adding a sensor that emits `{temperature: <double>}` is sufficient for steam stop-at-temperature. No new controller is required.

---

## C. Reference implementations

| Pattern | File | When to copy |
|---------|------|--------------|
| Simple GATT sensor | `lib/src/models/device/impl/decent_temp/temperature.dart` | **Default template** for temperature probes |
| Rich multi-channel sensor | `lib/src/models/device/impl/difluid/difluid_r2_sensor.dart` | Multiple `data` channels + commands |
| Debug / simulate | `lib/src/models/device/impl/sensor/debug_port.dart` | `simulate=sensor` wiring |
| Advertising-only exception | Combustion v2 (after ship) | Empty-name probes + manufacturer-data forwarding only |

---

## D. Anti-patterns (from PR #404 audits)

Do **not**:

- Add `SensorController` methods for preferred-device policy without maintainer ask.
- Modify `SteamSequencer`, `ShotSequencer`, or `De1StateManager` when adding a sensor.
- Couple device-specific types into `UniversalBleTransport` (no vendor interfaces on the generic BLE layer).
- Commit pi-spine artifacts (`spine-tasks/`, `.spine/`, `.pi/`) in feature PRs.
- Expand API, OpenAPI, or UI scope beyond what the maintainer requested — verify existing endpoints first.
- Create parallel feature stacks when scaffolding already exists — **read controllers before writing new ones**.
- Branch from an over-scoped feature branch and merge wholesale — start from `upstream/main` and port only the device layer.

---

## E. Workflow checklist

1. Read this doc and [`DecentTemp`](../../lib/src/models/device/impl/decent_temp/temperature.dart).
2. Confirm whether `SteamSequencer`, `SensorController`, or workflow API already cover the feature.
3. Implement `Sensor` in `lib/src/models/device/impl/{vendor}/` — include `temperature` in `data` if used for steam stop.
4. Add matcher entry in `device_matcher.dart` (`serviceUuidsFor` + name and/or metadata rule).
5. Add minimal discovery glue only if hardware requires it (e.g. empty BLE name, advertising-only updates).
6. Wire `Mock*` + `simulate=sensor` for hardware-free tests.
7. **Do not** modify `SteamSequencer` for stop-at-temperature.
8. Verify workflow API round-trip if using workflow fields; prefer existing fields over new ones.
9. Run `flutter test` (focused + full suite) and `flutter analyze` before claiming done.
10. See [REIMPLEMENTATION-v2.md](../plans/combustion-probe/REIMPLEMENTATION-v2.md) for the full v2 task breakdown and cleanup checklist.

---

## F. Sensor precedence (main branch behavior)

`SensorController` merges discovered sensors with bridge-registered adapters (e.g. Bengle milk probe). For steam stop on `upstream/main`:

- First registered sensor in `SensorController.sensors` is used by `SteamSequencer._trackFirstSensor()`.
- If a bridge adapter and a discovered sensor share the same `deviceId`, the bridge instance wins.

Do not add `resolvePreferred()` or settings keys unless the maintainer explicitly requests multi-probe selection.
