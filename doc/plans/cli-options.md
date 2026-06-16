# CLI Options — Desktop & Cal-Station Startup

Status: plan (grilled 2026-06-16)
Author: Vid + Claude investigation
Sources:
- `lib/main.dart` — current main() flow, dart-define usage
- `lib/src/app.dart` — onboarding controller, `_navigateAfterOnboarding`
- `lib/src/onboarding_feature/steps/initialization_step.dart` — skin serve logic
- `lib/src/onboarding_feature/steps/scan_step.dart` — scan step wrapper
- `lib/src/device_discovery_feature/scan_flow_view.dart` — scan UI + connect flow
- `lib/src/controllers/connection_manager.dart` — `connectMachine()`, `connect()`
- `lib/src/controllers/scan_state_guardian.dart` — BLE adapter monitoring
- `lib/src/webui_support/webui_service.dart` — `serveFolderAtPath()`, `isServing`
- `lib/src/webui_support/webui_storage.dart` — `defaultSkin` getter, `WebUISkin`
- `lib/src/settings/settings_controller.dart` — `onboardingCompleted`, `defaultSkinId`
- Flutter issue [#32986](https://github.com/flutter/flutter/issues/32986) — RESOLVED 2020, `main(List<String> args)` works on desktop
- `pub.dev/packages/args` v2.7.0 — GNU/POSIX CLI parsing
- [[ReaPrime/TODO#^cli-options]] — original TODO
- [[Sensor Basket/Field Notes#Next steps (prioritized)]] step 7 — Keith's cal-station use case

## 1. Goal

Add CLI flags for desktop platforms (Linux, macOS, Windows) to streamline station startup — eliminating click-through onboarding, bypassing Bluetooth when on serial, pre-setting skins, and auto-connecting to first discovered devices. The primary beneficiary is Keith's Linux cal-station, but the flags are general-purpose.

Optional future: schema-based URI handling on mobile (`decent-app://<command>`). Deferred — not part of this plan.

## 2. Flags

All flags use `main(List<String> args)` with the `args` package for parsing. Implementation is surgical — parse in `main()`, apply immediately, no new types threaded through constructors (except one `bool directConnect` param — see below).

| Flag | Effect | Insertion Point |
|------|--------|-----------------|
| `--serial` | Skip BLE service creation; serial-only scan | `main()` — skip `UniversalBleDiscoveryService()` + `services.add(bleDiscoveryService)` |
| `--bypass-onboarding` | Set `onboardingCompleted=true`, `accountStepSeen=true`, `androidWarningDismissed=true`; keep `permissionsStep`, `initializationStep`, `scanStep` | `main()` — after `settingsController.loadSettings()` |
| `--direct` | Auto-connect to first discovered machine/scale; suppress picker UI | `main()` → `AppRoot` → `MyApp` → `createScanStep` → `ScanFlowView` (single bool threaded) |
| `--skin=<id>` | Set `defaultSkinId` to `<id>` from installed registry | `main()` — after `settingsController.loadSettings()` |
| `--skin-path=<path>` | Serve skin directly from filesystem path; validates readability first, falls back to registry default on failure | `main()` sets `SkinOverride` on `WebUIService`; `initialization_step.dart` reads it |

### SkinOverride enum (on `WebUIService`)

```dart
enum SkinSource { registry, path, id }

class SkinOverride {
  final SkinSource source;
  final String? value;
  const SkinOverride.registry() : source = SkinSource.registry, value = null;
  const SkinOverride.path(String p) : source = SkinSource.path, value = p;
  const SkinOverride.id(String id) : source = SkinSource.id, value = id;
}
```

CLI `--skin=<id>` uses `settingsController.setDefaultSkinId()` (persisted) — not `SkinOverride.id`. The `SkinOverride.id` variant is reserved for future session-only skin switching.

### Whitelabel lock (deferred — see TODO)

Compile-time `--dart-define=LOCK_SKIN=true` would:
- Make `SettingsController.setDefaultSkinId()` a no-op
- Hide `SkinSelectorPage` from settings

Tracked separately in [[ReaPrime/TODO]].

## 3. Architecture

Parse CLI args immediately after `WidgetsFlutterBinding.ensureInitialized()`, before any service creation:

```
main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final cliArgs = parseCliArgs(args);  // ← NEW

  // ... existing setup

  if (!cliArgs.serial) {
    bleDiscoveryService = UniversalBleDiscoveryService();
    services.add(bleDiscoveryService);
  }

  // ... service creation

  await settingsController.loadSettings();

  if (cliArgs.bypassOnboarding) {
    await settingsController.setOnboardingCompleted(true);
    // also mark accountStepSeen, androidWarningDismissed
  }
  if (cliArgs.skinId != null) {
    await settingsController.setDefaultSkinId(cliArgs.skinId!);
  }
  if (cliArgs.skinPath != null) {
    webUIService.skinOverride = SkinOverride.path(cliArgs.skinPath!);
  }

  runApp(AppRoot(
    directConnect: cliArgs.direct,  // single new param
    // ... existing params
  ));
}
```

### `--direct` threading (sole constructor-threading change)

```
main() → AppRoot(directConnect: bool)
      → MyApp(directConnect: bool)
      → _MyAppState.createScanStep(directConnect: bool)
      → ScanStepView(directConnect: bool)
      → ScanFlowView(directConnect: bool)
```

In `ScanFlowView`: when `directConnect && pendingAmbiguity && !_directAutoConnected`, call `connectionManager.connectMachine(machines.first)`. On failure, show error banner but don't show picker — remains zero-click. Same pattern for scale ambiguity.

### `--serial` + `ScanStateGuardian`

Make `ScanStateGuardian.bleService` nullable (`BleDiscoveryService?`). Guard all BLE operations with `if (bleService == null) return;`. When `--serial` is set, pass `null`.

### `--skin-path` + initialization step

`_InitializationStepView._initializeServices()` reads `webUIService.skinOverride`:

```dart
switch (widget.webUIService.skinOverride.source) {
  case SkinSource.registry:
    final skin = widget.webUIStorage.defaultSkin;
    if (skin != null) await widget.webUIService.serveFolderAtPath(skin.path);
  case SkinSource.path:
    final p = widget.webUIService.skinOverride.value!;
    if (_isReadableDirectory(p)) {
      await widget.webUIService.serveFolderAtPath(p);
    } else {
      _log.severe('--skin-path not readable: $p, falling back');
      // fall through to registry logic
    }
  case SkinSource.id:
    // reserved for future
}
```

## 4. Implementation Phases

### Phase 1 — Trivial flags (3 lines of code)

`--serial`, `--bypass-onboarding`, `--skin=<id>`. Each is a single guard or `set*()` call in `main()`. Plus `argParser` plumbing.

Changes:
- `lib/main.dart` — args parsing + three guards
- `lib/src/controllers/scan_state_guardian.dart` — nullable `bleService`
- `pubspec.yaml` — add `args: ^2.7.0`

### Phase 2 — `--skin-path` + `SkinOverride`

Changes:
- `lib/src/webui_support/webui_service.dart` — `SkinOverride` type + field
- `lib/main.dart` — set `webUIService.skinOverride`
- `lib/src/onboarding_feature/steps/initialization_step.dart` — read override

### Phase 3 — `--direct`

Changes:
- `lib/main.dart` — parse `--direct`, pass to `AppRoot`
- `lib/src/app.dart` — `MyApp(directConnect)`, thread to `createScanStep`
- `lib/src/onboarding_feature/steps/scan_step.dart` — accept `directConnect`
- `lib/src/device_discovery_feature/scan_flow_view.dart` — auto-connect logic

## 5. Testing

| Tier | What | File |
|------|------|------|
| Unit | `parseCliArgs()` — all flag combinations | `test/cli_options_test.dart` |
| Widget | `ScanFlowView` with `directConnect: true` — asserts auto-connect | existing `scan_flow_view_test.dart` |
| Manual | `sb-dev start -- --serial --direct --bypass-onboarding` on macOS with MockDe1 | N/A |

No integration tests for full-flag boots — CI can't simulate Keith's hardware layout.

## 6. Non-goals

- Schema/URI handling on mobile (`decent-app://`) — deferred
- Whitelabel `--dart-define=LOCK_SKIN` — tracked separately in TODO
- `--scale=<id>` or `--machine=<id>` runtime flags — not needed (use existing `--dart-define=preferredMachineId` if needed)
- Windows/Android/iOS-specific behavior — flags are desktop-first; mobile gets them for free if they happen to work

## 7. Playbook Deltas

To be proposed after Phase 1 implementation.
