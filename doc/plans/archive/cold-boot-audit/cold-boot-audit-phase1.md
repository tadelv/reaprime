# Cold Boot Flow Audit — Phase 1 (safe subset)

## Context

ReaPrime TODO item `^cold-boot-audit` (P1): *"redesign startup sequence for speed and lower CPU load. Scan → connect machine → show webview → wait 1–2s → scan scale → isolate skin download/plugin loader."* Pairs with the `bb1c4163` WebView-before-webserver-ready crash variant.

**Audit finding — what actually blocks cold boot today:**

After `runApp`, the onboarding flow runs steps sequentially. The **initialization step** (`initialization_step.dart` `_initializeServices`) blocks the **scan step** from even starting until *all* of the following finish, in series:

1. `webUIStorage.initialize()` — which includes a **network download of remote skins** (`downloadRemoteSkins()`, `webui_storage.dart:203`) before scanning installed skins.
2. `webUIService.serveFolderAtPath()` — local, fast.
3. `pluginLoaderService.initialize()` — **JS/QuickJS VM init + autoload of enabled plugins** (~0.5–2s).
4. `deviceController.initialize()` — BLE adapter.

Only then does `advance()` fire and the scan step calls `connectionManager.connect()`. So BLE scanning is gated behind a network fetch and a JS VM spin-up that have nothing to do with finding the machine. The navigate-to-skin path then adds a hard `Future.delayed(500ms)` (`app.dart:250`).

**This phase (agreed scope):** isolate the plugin loader + remote skin download off the critical path, start `deviceController.initialize()` ASAP (overlapped with the fast local inits), drop the 500ms nav delay, and add boot-timing instrumentation to measure the win. Firebase init stays early (it captures crashes during the very boot we're optimizing). The deeper "show webview after machine connect, defer scale ~1–2s" rework is intentionally **deferred to a follow-up** — it needs ConnectionManager phase-flow changes + real-hardware soak.

Outcome: scanning begins ~1 network-RTT + ~1 JS-VM-init sooner; remote skins and plugins load in the background while the user is already scanning/connecting.

## Why this is safe

- `serveFolderAtPath` awaits `shelf_io.serve()` (`webui_service.dart:94`) which binds the port *before* `isServing` (`:118`) flips true, and the REST server (8080) is already `await`ed in `main()` before `runApp` (`main.dart:379`). So both servers are bound before navigation — the 500ms delay is pure belt-and-braces and removable. `_navigateAfterOnboarding` already gates on `isServing` (`app.dart:223`).
- The **default skin is bundled** (`streamline.js`), extracted by `_copyBundledSkins()` + surfaced by `_scanInstalledSkins()` inside `initialize()`. Remote download is *not* needed to serve the webview — only to surface *additional* remote skins, which are only viewed later in Settings.
- Plugins hook DE1 events after load; loading them ~1–2s late only delays plugin-provided endpoints, not the machine connect or the webview.

## Changes

### 1. `lib/src/webui_support/webui_storage.dart` — split remote download out of `initialize()`

- `initialize()` (`:175`): add optional named param `{bool downloadRemote = true}`. Guard the existing block at `:200-204` with `if (downloadRemote && !_appStoreMode)`. Default `true` preserves behavior for any other caller.
- Add a public method that the background path calls (download is currently NOT followed by a rescan inside `downloadRemoteSkins()` — `initialize()` relies on the explicit `_scanInstalledSkins()` at `:207`, so we must re-scan after a deferred download):

```dart
/// Downloads remote bundled skins then rescans so newly installed skins
/// surface. Safe to call in the background after initialize(downloadRemote: false).
Future<void> downloadRemoteSkinsAndRescan() async {
  if (_appStoreMode) return;
  await downloadRemoteSkins();
  await _scanInstalledSkins();
}
```

### 2. `lib/src/onboarding_feature/steps/initialization_step.dart` — reorder critical path

Rewrite `_initializeServices()` (`:73-119`) so only the machine/webview-critical work is awaited, plugins + remote skins go to the background, and the independent BLE-adapter init overlaps the local storage init:

```dart
import 'dart:async'; // add — for unawaited

Future<void> _initializeServices() async {
  BootTiming.mark('init-step start');

  // BLE adapter init is independent of skin storage — start it now, await later.
  final deviceInit = widget.deviceController.initialize();

  // Fast, local-only: bundled-skin extraction + installed-skin scan.
  try {
    await widget.webUIStorage.initialize(downloadRemote: false);
  } catch (e) {
    _log.severe('Failed to initialize WebUI storage', e);
  }

  // Serve the bundled default skin (local, fast) — needed before the webview.
  final defaultSkin = widget.webUIStorage.defaultSkin;
  if (defaultSkin != null) {
    try {
      await widget.webUIService.serveFolderAtPath(defaultSkin.path);
    } catch (e) {
      _log.severe('Failed to start WebUI service', e);
    }
  } else {
    _log.warning('No default skin available, WebUI service not started');
  }

  await deviceInit; // BLE must be ready before scan step calls connect()
  BootTiming.mark('storage+device ready, webui serving');

  if (Platform.isAndroid) {
    await ForegroundTaskService.start();
    ForegroundTaskService.watchMachineConnection(widget.de1Controller.de1);
  }

  widget.onboardingController.advance(); // scan starts now

  // Off the critical path — user is already scanning while these run.
  final plugins = widget.pluginLoaderService;
  if (plugins != null) {
    unawaited(plugins.initialize().catchError(
      (e) => _log.warning('Background plugin init failed: $e')));
  }
  unawaited(widget.webUIStorage.downloadRemoteSkinsAndRescan().catchError(
    (e) => _log.warning('Background remote-skin download failed: $e')));
}
```

### 3. `lib/src/app.dart` — drop the artificial nav delay

In `_navigateAfterOnboarding` remove `await Future.delayed(const Duration(milliseconds: 500));` (`:249-250`). `isServing` is already checked at `:223` and the port is bound by the time `serveFolderAtPath` returns.

### 4. Boot-timing instrumentation → logs + Firebase Performance trace

**4a. `TelemetryService.recordTrace` (new interface method)** — `telemetry_service.dart`:

```dart
/// Record a one-shot performance trace carrying named integer metrics (ms).
/// No-op when telemetry/Performance is unavailable (consent off, non-Android/iOS).
Future<void> recordTrace(String name, Map<String, int> metrics);
```

- `FirebaseCrashlyticsTelemetryService`: implement with Firebase Performance (already imported). Mirror the existing Android/iOS-only guard used for `FirebasePerformance` (`:34-38`) — Perf has no macOS/Linux impl. Collection is already consent-gated via `setPerformanceCollectionEnabled`, so dropped automatically without consent.

```dart
@override
Future<void> recordTrace(String name, Map<String, int> metrics) async {
  if (kIsWeb ||
      !(defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
    return;
  }
  final trace = FirebasePerformance.instance.newTrace(name);
  await trace.start();
  metrics.forEach(trace.setMetric);
  await trace.stop();
}
```

- `NoOpTelemetryService`: no-op `recordTrace`.
- `test/controllers/device_controller_test.dart` `_RecordingTelemetry` (`:76`): add a no-op `recordTrace` override (it `implements TelemetryService`).

**4b. `lib/src/services/telemetry/boot_timing.dart` (new)** — Stopwatch + ordered marks for log lines (all platforms), plus a one-shot `complete()` that emits the collected milestone durations as a single `cold_boot` Performance trace. We can't run a *live* trace spanning boot (Firebase isn't initialized at `main()` start), so each milestone's elapsed-since-start is recorded as a trace **metric**; `total_ms` is the final elapsed.

```dart
import 'dart:async';
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';

class BootTiming {
  static final Stopwatch _sw = Stopwatch();
  static final Logger _log = Logger('BootTiming');
  static final Map<String, int> _marks = {};
  static int _lastMs = 0;
  static bool _completed = false;
  static TelemetryService? telemetry;

  static void start() {
    _sw..reset()..start();
    _lastMs = 0;
    _marks.clear();
    _completed = false;
  }

  static void mark(String label) {
    if (!_sw.isRunning) return;
    final now = _sw.elapsedMilliseconds;
    _log.info('[BOOT] $label: ${now}ms (Δ${now - _lastMs}ms)');
    _marks[_metricKey(label)] = now;
    _lastMs = now;
  }

  static void complete() {
    if (_completed || !_sw.isRunning) return;
    _completed = true;
    final total = _sw.elapsedMilliseconds;
    _sw.stop();
    _log.info('[BOOT] complete: total ${total}ms');
    final metrics = Map<String, int>.from(_marks)..['total_ms'] = total;
    final t = telemetry;
    if (t != null) {
      unawaited(t.recordTrace('cold_boot', metrics)
          .catchError((e) => _log.warning('boot trace failed: $e')));
    }
  }

  // Firebase Performance metric name: <=32 chars, alnum + underscore.
  static String _metricKey(String label) {
    var k = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    k = k.replaceAll(RegExp(r'^_+|_+$'), '');
    if (!k.endsWith('_ms')) k = '${k}_ms';
    if (k.length > 32) k = k.substring(0, 32);
    return k;
  }
}
```

Marks use **short labels** (metric names must be ≤32 chars):
- `main.dart`: `BootTiming.start()` right after the "==== Decent starting ====" log (`:156`); after creating `telemetryService` (`:181`) set `BootTiming.telemetry = telemetryService;`; `mark('firebase_done')` after the Firebase block; `mark('webserver_up')` after `startWebServer` (`:402`); `mark('runapp')` just before `runApp` (`:454`).
- `initialization_step.dart`: `mark('init_start')`, `mark('init_ready')` (after storage+device+webui), `mark('scan_start')` right before `advance()`.
- `scan_step.dart`: in the `status.listen` handler (`:137`) `mark('connect_<phase>')` on phase change; the `ready` branch (`:140`) `mark('scan_ready')`.
- `skin_view.dart`: `mark('webview')` then `BootTiming.complete()` where the URL is loaded.

## Out of scope (follow-up item)

Showing the webview right after **machine** connect with the **scale** connecting in the background (the "show webview → wait 1–2s → scan scale" half). That requires either advancing onboarding on `connectingScale` instead of `ready`, or a two-phase connect reusing `connect(scaleOnly: true)` / the already-discovered scales. Park as a new TODO sub-item under `^cold-boot-audit`.

## Verification

1. `flutter analyze` — zero issues.
2. `flutter test` — full suite green (currently ~1347). Add/adjust a widget test for the initialization step: inject a `WebUIStorage` whose `downloadRemoteSkinsAndRescan()` and a `PluginLoaderService` whose `initialize()` never complete (or complete slowly), and assert `onboardingController.advance()` still fires — i.e. the critical path does not await them.
3. End-to-end (`scripts/sb-dev.sh` + `--dart-define=simulate=1`): boot, confirm `[BOOT]` timing lines appear, webview shows the default skin, and the machine connects. Compare timing lines before/after.
4. **Real-hardware smoke on m50mini** (connectivity-adjacent — `deviceController.initialize()` timing + scan start changed): flash branch, read `http://m50mini.home:8080/api/v1/logs` (use `/usr/bin/grep`), confirm at the nearest `==== Decent starting ====` block: scan starts sooner, machine + scale both connect, no skin/plugin regressions, and that remote skins still appear in Settings after the background download completes.

## Risks

- A skin needing a plugin-provided endpoint on first paint sees it ~1–2s late (acceptable per scope).
- Background remote-skin download races nothing BLE-related (network vs BLE are independent); new skins surface in Settings a moment later via the rescan.
