# AI Build Notes

Read this when building, running, flashing, or touching platform configuration. Skip it for pure Dart/logic changes that don't touch native code or build tooling.

## Common Commands

```bash
# Run (with git commit version injection)
./flutter_with_commit.sh run

# Run with simulated devices
flutter run --dart-define=simulate=1           # All simulated
flutter run --dart-define=simulate=machine,scale  # Specific types
flutter run --dart-define=simulate=bengle      # Bengle only

# Test & Lint
flutter test                                   # All tests
flutter test test/path/to_test.dart            # Specific file
flutter test --name "test pattern"             # Specific test
flutter analyze                                # Static analysis
flutter format lib/ test/                      # Format

# Build (Linux via Docker/Colima)
make build-arm                                 # ARM64 binary
make build-amd                                 # x86_64 binary
make dual-build                                # Both architectures
```

## Simulate Modes

Simulated devices avoid hardware requirements for smoke testing. Available types:

| Flag value | Devices |
|------------|---------|
| `1` | All: `MockDe1`, `MockScale`, `MockBengle`, `MockSensor` |
| `machine` | `MockDe1` only |
| `scale` | `MockScale` only |
| `bengle` | `MockBengle` only |
| `machine,scale` | `MockDe1` + `MockScale` |
| `sensor` | `MockSensor` only |

Also toggleable from the settings UI after launch.

## Platform Config

**Supported platforms:** Android (primary), macOS, Linux, Windows, iOS.

- `flutter_with_commit.sh` injects the git commit hash as a compile-time constant via `--dart-define`.
- CI uses pinned Flutter version. Linux build smoke runs via Docker.
- Android uses `ForegroundTaskService` for background BLE. Auto-stops 5min after disconnect; auto-restarts on reconnect.
- `Makefile` targets: `build-arm`, `build-amd`, `dual-build` (Linux only, requires Docker/Colima).

## Footgun #1: Xcode 26.4 / flutter_inappwebview

**Symptom:** `flutter build macos` fails with `Swift 6.3 error: protocol 'ASWebAuthenticationPresentationContextProviding' requires 'presentationAnchor(for:)' to be available in macOS 10.14 and newer`.

**Root cause:** Upstream `flutter_inappwebview_macos` plugin bug — `presentationAnchor(for:)` annotated `@available(macOS 10.15, *)`, narrower than the protocol requirement (10.14). Swift 6.3 promotes this from warning to hard error. Xcode 26.3 still builds fine.

**Fix:** `dependency_override` in `pubspec.yaml` pointing to fork `wangqiang1588/flutter_inappwebview` (commit `fc33a449`). Upstream PR #2809 is open but unreviewed (3+ months).

**Impact:** Blocks local macOS smoke-testing only. CI (Linux) and Android builds unaffected.

**Track:** Remove override once upstream #2809 merges + plugin release ships.

## Footgun #2: Serial Probe Write Hang

**Symptom:** Windows startup freezes when a non-Decent USB-serial device sits on a COM port.

**Root cause (fixed PR #241):** Serial discovery probes every port with MMR writes; `write(timeout:0)` blocked forever + unbounded `drain()` froze the main isolate in native FFI. Dart `.timeout()` couldn't fire.

**Fix:** Finite 500ms per-chunk write timeout + bail on zero-progress, `drainWithTimeout` polling `bytesToWrite`.

## Footgun #3: USB Charger Mode Spam

**Symptom:** ~2665 `setUsbChargerMode` writes per 2 days on m50mini.

**Fix (PR #246):** `shouldWriteChargerMode()` in `charging_logic.dart` — write-on-change, re-assert "off" every 5min while discharging, skip otherwise. Reset on disconnect.

## Dev-Loop Skill

Driving a running app through its lifecycle: `.agents/skills/decent-app/SKILL.md`. Managed by `scripts/sb-dev.sh`:

```bash
scripts/sb-dev.sh start      # Launch in simulate mode
scripts/sb-dev.sh reload     # Hot reload (preserves state)
scripts/sb-dev.sh hot-restart  # Full restart (resets state)
scripts/sb-dev.sh stop       # Kill the app
scripts/sb-dev.sh logs       # Tail logs
scripts/sb-dev.sh status     # Is it running?
```

Prefer `reload` over `hot-restart` — state is preserved.

## Logging

- Dart-side: `package:logging`, configured in `main.dart`.
- File log: `getApplicationDocumentsDirectory()/log.txt` (plus rotated `log.txt.1..3`).
- Android retrieval: `adb shell run-as net.tadel.reaprime cat app_flutter/log.txt` or `adb logcat`.

## Focused Checks

```sh
flutter analyze          # Minimum before any commit
flutter test             # Full suite before commit/PR
flutter format lib/ test/  # Format check
```

## Keeping Notes Fresh

Add build footguns, platform-specific quirks, and toolchain issues that would save debugging time. Prune when upstream fixes ship. Prefer fewer, sharper notes over long background.
