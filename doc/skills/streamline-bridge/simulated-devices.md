# Simulated devices

Streamline Bridge ships with in-process mock implementations of its supported devices so you can develop and run tests without a real DE1 or scale on hand. Simulate mode is deterministic, CI-friendly, and enabled via `--dart-define=simulate=1` (all mocks), a comma-delimited subset like `--dart-define=simulate=machine,scale`, or the in-app Settings UI toggle (`SimulatedDevicesTypes` — machine, scale, sensor). `sb-dev start` always injects `--dart-define=simulate=1`.

## Available mocks

Registered in `lib/src/services/simulated_device_service.dart`:

| Type    | Internal id         | REST `name` field | Source |
|---------|---------------------|-------------------|--------|
| Machine | `MockDe1`           | `MockDe1`         | `lib/src/models/device/impl/mock_de1/mock_de1.dart` |
| Scale   | `MockScale`         | `Mock Scale`      | `lib/src/models/device/impl/mock_scale/mock_scale.dart` |
| Sensor  | `MockSensorBasket`  | `SensorBasket`    | `lib/src/models/device/impl/sensor/mock/mock_sensor_basket.dart` |
| Sensor  | `MockDebugPort`     | `DebugPort`       | `lib/src/models/device/impl/sensor/mock/mock_debug_port.dart` |

The internal id (left column) is what you pass to `preferredMachineId` / `preferredScaleId` dart-defines and to `sb-dev`'s `--connect-machine` / `--connect-scale` flags — case-sensitive. The REST `name` is what you match on when reading `/api/v1/devices`.

## Auto-connect fast-path

`sb-dev start --connect-machine MockDe1 --connect-scale MockScale` translates to:

```bash
flutter run \
  --dart-define=simulate=1 \
  --dart-define=preferredMachineId=MockDe1 \
  --dart-define=preferredScaleId=MockScale
```

`lib/main.dart` (~line 360) reads those defines and seeds `settingsController.setPreferredMachineId` / `setPreferredScaleId`, which `ConnectionManager` then uses to bypass the device selection screen and direct-connect on the first scan. After boot, `sb-dev`'s `connect_machine` helper polls `GET /api/v1/devices/scan?connect=true` and `GET /api/v1/devices` in a 30s loop, checking with `jq` that an entry with the requested machine `name` has `state == "connected"` before returning. For the scale, `sb-dev` just passes the dart-define and trusts the auto-connect — no post-boot verification.

## Typical TDD recipes

Unit / widget tests — no app, no simulate flag needed:

```bash
flutter test test/controllers/shot_controller_test.dart
```

Integration flow against a running app:

```bash
scripts/sb-dev.sh start --connect-machine MockDe1
curl -s http://localhost:8080/api/v1/machine/state | jq .
```

Full shot flow with machine + scale:

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
curl -sX POST http://localhost:8080/api/v1/machine/profile \
  -H 'content-type: application/json' --data @test_data/profile.json
curl -sX POST http://localhost:8080/api/v1/machine/state \
  -H 'content-type: application/json' --data '{"state":"espresso"}'
timeout 10 websocat -t ws://localhost:8080/ws/v1/machine/snapshot | jq -c .
```

## Cleaning state between runs

- **Hot restart** (`sb-dev hot-restart`) rebuilds the widget tree from `main()` but keeps the process and every on-disk file intact.
- **Cold restart** (`sb-dev stop && sb-dev start`) gives a fresh flutter process, but the Drift SQLite DB and `shared_preferences` survive.
- **Fresh slate** — stop, wipe the runtime dir, and wipe the app's documents dir:

```bash
scripts/sb-dev.sh stop
rm -rf "${SB_RUNTIME_DIR:-/tmp/streamline-bridge-$USER}"
rm -rf "$HOME/Library/Containers/net.tadel.reaprime/Data/Documents"  # macOS
```

On Linux the app documents dir is under `$HOME/.local/share/reaprime/` (or `$XDG_DATA_HOME`); see `getApplicationDocumentsDirectory()` in `lib/main.dart`.

## Known weirdness

- **First scan can be empty.** `SimulatedDeviceService.enabledDevices` is populated by a `settingsController` listener (`lib/main.dart` ~line 349). If you scan before that listener fires, `scanForDevices()` returns with no devices and the stream emits nothing. `sb-dev connect_machine` works around this with a 30s re-scan loop; a manual `curl /api/v1/devices/scan?connect=true` may need retrying.
- **`MockScale` identifier vs REST name mismatch.** The dart-define / `sb-dev --connect-scale` value is `MockScale` (no space), but the scale's `name` field returned by `/api/v1/devices` is `"Mock Scale"` (with a space). Pass `MockScale` as the flag; filter on `"Mock Scale"` when parsing the devices list. The `MockDe1` machine uses the same string (`"MockDe1"`) for both, so it has no such quirk.
