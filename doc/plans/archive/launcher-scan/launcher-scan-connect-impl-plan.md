# Launcher Scan & Connect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the launcher an in-app path to scan and connect a machine when none is connected, by reusing the onboarding scan flow behind a "Connect your machine" hero card.

**Architecture:** Extract the onboarding scan state machine from `ScanStepView` into a shared, callback-driven `ScanFlowView`. The onboarding step becomes a thin wrapper (behaviour unchanged). A new launcher hero card (shown when `de1Controller.de1` is null) pushes a new full-screen scan page that drives `ScanFlowView` with `Navigator.pop` callbacks and stops the scan on cancel.

**Tech Stack:** Flutter, shadcn_ui (`ShadButton`, `ShadCard`, `LucideIcons`), RxDart streams, `flutter_test` widget tests. Design doc: `doc/plans/launcher-scan-connect.md`.

---

## File Structure

- **Create** `lib/src/device_discovery_feature/scan_flow_view.dart` — `ScanFlowView` stateful widget owning the entire scan state machine (scanning / connecting / picker / no-devices / errors). Callback-driven, no onboarding coupling.
- **Modify** `lib/src/onboarding_feature/steps/scan_step.dart` — `ScanStepView` becomes a thin `StatelessWidget` wrapper around `ScanFlowView`; `createScanStep` unchanged.
- **Create** `lib/src/launcher/widgets/connect_device_hero_card.dart` — `ConnectDeviceHeroCard` presentational widget with an `onScan` callback.
- **Create** `lib/src/launcher/launcher_scan_page.dart` — `LauncherScanPage` (routed) wrapping `ScanFlowView`.
- **Modify** `lib/src/launcher/launcher_view.dart` — inject 4 controllers; render the hero above the skin slot when no machine.
- **Modify** `lib/src/app.dart` — pass new deps to `LauncherView`; register `LauncherScanPage` route.
- **Create** `test/helpers/mock_connection_manager.dart` — extract `MockConnectionManager` + `FakeDe1` from `scan_step_test.dart` for reuse.
- **Modify** `test/onboarding/scan_step_test.dart` — import the extracted mock instead of the local copy.
- **Create** `test/launcher/connect_hero_visibility_test.dart`, `test/launcher/connect_hero_tap_test.dart`, `test/launcher/launcher_scan_page_test.dart`.

---

## Task 1: Extract `MockConnectionManager` to a shared test helper

Pure refactor so both onboarding and launcher tests share one mock. No behaviour change — the existing 21 onboarding scan tests are the guardrail.

**Files:**
- Create: `test/helpers/mock_connection_manager.dart`
- Modify: `test/onboarding/scan_step_test.dart:27-96` (remove local `_FakeDe1` + `MockConnectionManager`, import helper)

- [ ] **Step 1: Run the onboarding scan tests to capture the green baseline**

Run: `flutter test test/onboarding/scan_step_test.dart`
Expected: PASS (21 tests). Record the count.

- [ ] **Step 2: Create the shared helper by moving the two classes verbatim**

Move `_FakeDe1` (renamed to public `FakeDe1`) and `MockConnectionManager` out of `scan_step_test.dart` into the new file. Content:

```dart
import 'dart:async';

import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/scale.dart' as device_scale;
import 'package:reaprime/src/models/scan_report.dart';
import 'package:rxdart/rxdart.dart';

/// Minimal [De1Interface] stub for testing.
class FakeDe1 implements De1Interface {
  @override
  final String deviceId;

  @override
  final String name;

  @override
  dev.DeviceType get type => dev.DeviceType.machine;

  @override
  Stream<dev.ConnectionState> get connectionState =>
      Stream.value(dev.ConnectionState.connected);

  FakeDe1({this.deviceId = 'fake-de1', String? name})
      : name = name ?? 'DE1-$deviceId';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A [ConnectionManager] subclass that gives tests direct control over the
/// status stream and records `connect()` calls, without requiring real
/// device scanning infrastructure.
class MockConnectionManager extends ConnectionManager {
  final _statusOverride = BehaviorSubject<ConnectionStatus>.seeded(
    const ConnectionStatus(phase: ConnectionPhase.scanning),
  );

  int connectCallCount = 0;
  ScanReport? _lastScanReport;

  MockConnectionManager({
    required super.deviceScanner,
    required super.de1Controller,
    required super.scaleController,
    required super.settingsController,
  });

  @override
  Stream<ConnectionStatus> get status => _statusOverride.stream;

  @override
  ConnectionStatus get currentStatus => _statusOverride.value;

  @override
  ScanReport? get lastScanReport => _lastScanReport;

  void setLastScanReport(ScanReport? report) => _lastScanReport = report;

  void emitStatus(ConnectionStatus status) => _statusOverride.add(status);

  @override
  Future<void> connect({bool scaleOnly = false}) async {
    connectCallCount++;
  }

  @override
  Future<void> connectMachine(De1Interface machine) async {}

  @override
  Future<void> connectScale(device_scale.Scale scale) async {}

  @override
  Future<void> dispose() async {
    _statusOverride.close();
    await super.dispose();
  }
}
```

- [ ] **Step 3: Update `scan_step_test.dart` to use the helper**

Delete the `_FakeDe1` class (lines ~27-47) and the `MockConnectionManager` class (lines ~49-96) from `scan_step_test.dart`. Add the import near the other helper imports:

```dart
import '../helpers/mock_connection_manager.dart';
```

If any test referenced `_FakeDe1`, rename those references to `FakeDe1`.

- [ ] **Step 4: Run onboarding scan tests to verify still green**

Run: `flutter test test/onboarding/scan_step_test.dart`
Expected: PASS (same 21 tests).

- [ ] **Step 5: Commit**

```bash
git add test/helpers/mock_connection_manager.dart test/onboarding/scan_step_test.dart
git commit -m "test: extract MockConnectionManager to shared helper"
```

---

## Task 2: Extract `ScanFlowView` from `ScanStepView`

Move the entire scan state machine into a new callback-driven widget. `ScanStepView` keeps its exact public API and delegates. The onboarding tests from Task 1 guard this.

**Files:**
- Create: `lib/src/device_discovery_feature/scan_flow_view.dart`
- Modify: `lib/src/onboarding_feature/steps/scan_step.dart`

- [ ] **Step 1: Create `scan_flow_view.dart` with the moved logic**

Create `ScanFlowView` as a `StatefulWidget`. Move the **entire body** of the current `ScanStepViewState` (every method: `initState`, `dispose`, `build`, `_scanningView`, `_connectingView`, `_devicePickerView`, `_noDevicesFoundView`, `_errorView`, `_adapterErrorView`, `_onGuardianEvent`, `_startTooLongTimer`, `_cancelTooLongTimer`, `_stopScanAndShowDevices`, `_showTakingTooLongSheet`, `_exportLogs`, all fields) into `ScanFlowViewState`, plus the import block from `scan_step.dart`. Then apply exactly these semantic changes (everything else is a verbatim move):

Constructor + fields:

```dart
class ScanFlowView extends StatefulWidget {
  final ConnectionManager connectionManager;
  final DeviceController deviceController;
  final SettingsController settingsController;
  final ScanStateGuardian scanStateGuardian;

  /// Invoked once when the connection phase first reaches `ready`.
  final VoidCallback onConnected;

  /// Invoked when the user chooses to leave the scan without connecting.
  final VoidCallback onExit;

  /// Button copy for the exit affordance (e.g. 'Dashboard', 'Cancel').
  final String exitLabel;

  /// How long to wait before showing the "taking too long" button.
  @visibleForTesting
  static const scanTooLongThreshold = Duration(seconds: 16);

  const ScanFlowView({
    super.key,
    required this.connectionManager,
    required this.deviceController,
    required this.settingsController,
    required this.scanStateGuardian,
    required this.onConnected,
    required this.onExit,
    this.exitLabel = 'Dashboard',
  });

  @override
  State<ScanFlowView> createState() => ScanFlowViewState();
}
```

Replace the four onboarding-coupled call sites in the moved code:

1. In the status listener, the ready branch:
```dart
// was: widget.onboardingController.advance();
widget.onConnected();
```

2. Replace the whole `_skipToDashboard()` method body:
```dart
void _skipToDashboard() => widget.onExit();
```
(Keep the method name so its call sites in the picker/no-devices/sheet views are unchanged.)

3. In `_devicePickerView`, the secondary "Dashboard" button — both the `AccessibleButton`'s `label:` and the `ShadButton.secondary` child `Text`:
```dart
// was: label: 'Dashboard'  /  child: const Text('Dashboard')
label: widget.exitLabel,
// ...
child: Text(widget.exitLabel),
```

4. In `_showTakingTooLongSheet`, the last `ListTile`:
```dart
// was: title: const Text('Continue to Dashboard')
title: Text(widget.exitLabel == 'Dashboard'
    ? 'Continue to Dashboard'
    : widget.exitLabel),
```

Every reference to `ScanStepView.scanTooLongThreshold` inside the moved code becomes `ScanFlowView.scanTooLongThreshold`. References to `widget.deviceController` / `widget.connectionManager` / `widget.settingsController` / `widget.scanStateGuardian` stay as-is (same field names now live on `ScanFlowView`).

- [ ] **Step 2: Rewrite `scan_step.dart` as a thin wrapper**

`createScanStep` stays byte-for-byte the same. Replace `ScanStepView` (and its `State`) with a `StatelessWidget` that delegates:

```dart
/// Visible for testing. Thin onboarding wrapper around [ScanFlowView].
@visibleForTesting
class ScanStepView extends StatelessWidget {
  final OnboardingController onboardingController;
  final ConnectionManager connectionManager;
  final DeviceController deviceController;
  final SettingsController settingsController;
  final ScanStateGuardian scanStateGuardian;
  final VoidCallback? onSkipToDashboard;

  /// Preserved for existing tests that pump this threshold.
  @visibleForTesting
  static const scanTooLongThreshold = ScanFlowView.scanTooLongThreshold;

  const ScanStepView({
    super.key,
    required this.onboardingController,
    required this.connectionManager,
    required this.deviceController,
    required this.settingsController,
    required this.scanStateGuardian,
    this.onSkipToDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return ScanFlowView(
      connectionManager: connectionManager,
      deviceController: deviceController,
      settingsController: settingsController,
      scanStateGuardian: scanStateGuardian,
      onConnected: onboardingController.advance,
      onExit: onSkipToDashboard ?? onboardingController.advance,
      exitLabel: 'Dashboard',
    );
  }
}
```

Trim the now-unused imports in `scan_step.dart` (e.g. `dart:async`, `file_picker`, `path_provider`, `boot_timing`, etc. — anything now only used by the moved code). Add:
```dart
import 'package:reaprime/src/device_discovery_feature/scan_flow_view.dart';
```
Keep the imports `createScanStep` still needs: `flutter/material.dart`, `connection_manager.dart`, `device_controller.dart`, `scan_state_guardian.dart`, `settings_controller.dart`, and the `onboarding_controller.dart` import.

- [ ] **Step 3: Run analyze to catch unused imports / missing refs**

Run: `flutter analyze lib/src/device_discovery_feature/scan_flow_view.dart lib/src/onboarding_feature/steps/scan_step.dart`
Expected: No issues (fix any unused-import or undefined-name warnings before proceeding).

- [ ] **Step 4: Run onboarding scan tests — they must stay green**

Run: `flutter test test/onboarding/scan_step_test.dart`
Expected: PASS (same 21 tests). This proves the extraction preserved behaviour.

- [ ] **Step 5: Commit**

```bash
git add lib/src/device_discovery_feature/scan_flow_view.dart lib/src/onboarding_feature/steps/scan_step.dart
git commit -m "refactor: extract ScanFlowView from onboarding ScanStepView"
```

---

## Task 3: `ConnectDeviceHeroCard` widget

Presentational hero card matching the existing launcher hero cards.

**Files:**
- Create: `lib/src/launcher/widgets/connect_device_hero_card.dart`
- Test: `test/launcher/connect_hero_tap_test.dart`

- [ ] **Step 1: Write the failing tap test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/launcher/widgets/connect_device_hero_card.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('ConnectDeviceHeroCard fires onScan when tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: ConnectDeviceHeroCard(onScan: () => tapped++),
        ),
      ),
    );

    expect(find.text('Connect your machine'), findsOneWidget);

    await tester.tap(find.text('Scan for devices'));
    await tester.pump();

    expect(tapped, 1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/launcher/connect_hero_tap_test.dart`
Expected: FAIL — `connect_device_hero_card.dart` / `ConnectDeviceHeroCard` not found.

- [ ] **Step 3: Implement the widget**

```dart
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Launcher hero card shown when no machine is connected. Tapping the
/// action drives the launcher scan flow. Sits above the skin slot.
class ConnectDeviceHeroCard extends StatelessWidget {
  const ConnectDeviceHeroCard({super.key, required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.bluetoothSearching,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Connect your machine', style: theme.textTheme.h4),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No machine connected. Scan to find and connect your '
            'Decent machine.',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 16),
          ShadButton(
            size: ShadButtonSize.lg,
            leading: const Icon(LucideIcons.search, size: 18),
            onPressed: onScan,
            child: const Text('Scan for devices'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/launcher/connect_hero_tap_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/launcher/widgets/connect_device_hero_card.dart test/launcher/connect_hero_tap_test.dart
git commit -m "feat: add ConnectDeviceHeroCard launcher widget"
```

---

## Task 4: `LauncherScanPage` (routed scan page)

Full-screen page wrapping `ScanFlowView`, popping on connect/exit and stopping the scan on cancel.

**Files:**
- Create: `lib/src/launcher/launcher_scan_page.dart`
- Test: `test/launcher/launcher_scan_page_test.dart`

- [ ] **Step 1: Write the failing tests (ready→pop, cancel→stopScan+pop)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/launcher/launcher_scan_page.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_connection_manager.dart';
import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';

/// DeviceController that records stopScan calls.
class _SpyDeviceController extends DeviceController {
  int stopScanCalls = 0;
  _SpyDeviceController() : super([]);
  @override
  void stopScan() {
    stopScanCalls++;
    super.stopScan();
  }
}

void main() {
  late MockConnectionManager connectionManager;
  late _SpyDeviceController deviceController;
  late ScanStateGuardian guardian;
  late MockBleDiscoveryService bleService;
  late SettingsController settingsController;

  setUp(() async {
    settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();
    connectionManager = MockConnectionManager(
      deviceScanner: MockDeviceScanner(),
      de1Controller: MockDe1Controller(controller: DeviceController([])),
      scaleController: MockScaleController(),
      settingsController: settingsController,
    );
    deviceController = _SpyDeviceController();
    bleService = MockBleDiscoveryService();
    guardian = ScanStateGuardian(bleService: bleService);
  });

  tearDown(() {
    connectionManager.dispose();
    guardian.dispose();
    bleService.dispose();
  });

  Widget host() => ShadApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LauncherScanPage(
                      connectionManager: connectionManager,
                      deviceController: deviceController,
                      settingsController: settingsController,
                      scanStateGuardian: guardian,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('pops back to launcher when phase reaches ready',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LauncherScanPage), findsOneWidget);

    connectionManager.emitStatus(
        const ConnectionStatus(phase: ConnectionPhase.ready));
    await tester.pumpAndSettle();

    expect(find.byType(LauncherScanPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('cancel stops the scan and pops', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();

    // Drive to the device-picker state, which exposes the exit ('Cancel')
    // affordance, then tap it.
    connectionManager.emitStatus(const ConnectionStatus(
      phase: ConnectionPhase.idle,
      foundMachines: [],
      pendingAmbiguity: AmbiguityReason.machinePicker,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deviceController.stopScanCalls, greaterThanOrEqualTo(1));
    expect(find.byType(LauncherScanPage), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/launcher/launcher_scan_page_test.dart`
Expected: FAIL — `launcher_scan_page.dart` / `LauncherScanPage` not found.

- [ ] **Step 3: Implement the page**

```dart
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/device_discovery_feature/scan_flow_view.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

/// Full-screen scan page launched from the launcher's connect-hero. Reuses
/// the shared [ScanFlowView]; pops back to the launcher on connect or cancel.
class LauncherScanPage extends StatelessWidget {
  static const routeName = '/launcher-scan';

  const LauncherScanPage({
    super.key,
    required this.connectionManager,
    required this.deviceController,
    required this.settingsController,
    required this.scanStateGuardian,
  });

  final ConnectionManager connectionManager;
  final DeviceController deviceController;
  final SettingsController settingsController;
  final ScanStateGuardian scanStateGuardian;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ScanFlowView(
          connectionManager: connectionManager,
          deviceController: deviceController,
          settingsController: settingsController,
          scanStateGuardian: scanStateGuardian,
          onConnected: () => Navigator.of(context).pop(),
          onExit: () {
            deviceController.stopScan();
            Navigator.of(context).pop();
          },
          exitLabel: 'Cancel',
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/launcher/launcher_scan_page_test.dart`
Expected: PASS (2 tests). If the picker state needs `runAsync`/extra pumps to settle stream microtasks, add `await tester.runAsync(() async {...})` around the emit+pump as `scan_step_test.dart` does for the picker views.

- [ ] **Step 5: Commit**

```bash
git add lib/src/launcher/launcher_scan_page.dart test/launcher/launcher_scan_page_test.dart
git commit -m "feat: add LauncherScanPage reusing ScanFlowView"
```

---

## Task 5: Show the hero in `LauncherView` and wire `app.dart`

Inject the controllers, render the hero above the skin slot when no machine, and register the route.

**Files:**
- Modify: `lib/src/launcher/launcher_view.dart`
- Modify: `lib/src/app.dart:449-458` (LauncherView construction) and the route switch
- Test: `test/launcher/connect_hero_visibility_test.dart`

- [ ] **Step 1: Write the failing visibility test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/launcher/launcher_view.dart';
import 'package:reaprime/src/launcher/widgets/connect_device_hero_card.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_connection_manager.dart';
import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';

void main() {
  late MockDe1Controller de1Controller;
  late MockScaleController scaleController;
  late MockConnectionManager connectionManager;
  late ScanStateGuardian guardian;
  late MockBleDiscoveryService bleService;
  late SettingsController settingsController;

  setUp(() async {
    settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();
    de1Controller = MockDe1Controller(controller: DeviceController([]));
    scaleController = MockScaleController();
    connectionManager = MockConnectionManager(
      deviceScanner: MockDeviceScanner(),
      de1Controller: de1Controller,
      scaleController: scaleController,
      settingsController: settingsController,
    );
    bleService = MockBleDiscoveryService();
    guardian = ScanStateGuardian(bleService: bleService);
  });

  tearDown(() {
    connectionManager.dispose();
    guardian.dispose();
    bleService.dispose();
  });

  // NOTE: WebUIService is required by LauncherView. Reuse the existing
  // launcher test's construction pattern if one exists; otherwise pass the
  // real WebUIService instance the app uses. See existing launcher tests.
  Widget buildLauncher() => ShadApp(
        home: LauncherView(
          de1Controller: de1Controller,
          scaleController: scaleController,
          webUIService: testWebUIService(), // helper — see Step 3 note
          pluginLoaderService: testPluginLoaderService(),
          connectionManager: connectionManager,
          deviceController: DeviceController([]),
          settingsController: settingsController,
          scanStateGuardian: guardian,
        ),
      );

  testWidgets('hero shows when no machine connected', (tester) async {
    de1Controller.de1Subject.add(null);
    await tester.pump();
    await tester.pumpWidget(buildLauncher());
    await tester.pump();

    expect(find.byType(ConnectDeviceHeroCard), findsOneWidget);
  });

  testWidgets('hero hidden when a machine is connected', (tester) async {
    de1Controller.de1Subject.add(FakeDe1());
    await tester.pump();
    await tester.pumpWidget(buildLauncher());
    await tester.pump();

    expect(find.byType(ConnectDeviceHeroCard), findsNothing);
  });
}
```

> Implementation note for Step 1: `LauncherView` needs `WebUIService` and `PluginLoaderService`. Before writing this test, open the repo for an existing launcher widget test or a `WebUIService` test fixture and mirror how it constructs those. If none exists, construct the real `WebUIService` the way `app.dart` does and a `PluginLoaderService` with an empty plugin set. Replace the `testWebUIService()` / `testPluginLoaderService()` placeholders with the concrete construction you find. Do NOT invent helpers that don't exist — wire the real services.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/launcher/connect_hero_visibility_test.dart`
Expected: FAIL — `LauncherView` has no `connectionManager` (etc.) parameter / `ConnectDeviceHeroCard` not rendered.

- [ ] **Step 3: Add the deps and hero to `LauncherView`**

Add imports:
```dart
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/launcher/launcher_scan_page.dart';
import 'package:reaprime/src/launcher/widgets/connect_device_hero_card.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
```

Add fields + constructor params (alongside the existing ones):
```dart
final ConnectionManager connectionManager;
final DeviceController deviceController;
final SettingsController settingsController;
final ScanStateGuardian scanStateGuardian;
```
```dart
required this.connectionManager,
required this.deviceController,
required this.settingsController,
required this.scanStateGuardian,
```

In `build`, replace the inner `Column` children (the one with `spacing: 24` containing the skin slot + grid) so the hero renders above the skin slot when no machine. Wrap the skin slot + hero in a `StreamBuilder`:
```dart
children: [
  StreamBuilder<De1Interface?>(
    stream: de1Controller.de1,
    builder: (context, snapshot) {
      final hasMachine = snapshot.data != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 24,
        children: [
          if (!hasMachine)
            ConnectDeviceHeroCard(
              onScan: () => Navigator.of(context).pushNamed(
                LauncherScanPage.routeName,
              ),
            ),
          _buildSkinSlot(context, slot),
        ],
      );
    },
  ),
  _buildGrid(context),
],
```
(The `slot` value computed at the top of `build` stays as-is.)

- [ ] **Step 4: Wire `app.dart` — pass deps + register route**

In the `LauncherView.routeName` case (around line 450), add the new args:
```dart
case LauncherView.routeName:
  return LauncherView(
    de1Controller: widget.de1Controller,
    scaleController: widget.scaleController,
    webUIService: widget.webUIService,
    pluginLoaderService: widget.pluginLoaderService,
    batteryController: widget.batteryController,
    decentAccountService: widget.decentAccountService,
    isDegradedAndroid: _degradedAndroid,
    connectionManager: widget.connectionManager,
    deviceController: widget.deviceController,
    settingsController: widget.settingsController,
    scanStateGuardian: widget.scanStateGuardian,
  );
```

Add a new case for the scan page (mirror the import style at the top of `app.dart`, importing `LauncherScanPage`):
```dart
case LauncherScanPage.routeName:
  return LauncherScanPage(
    connectionManager: widget.connectionManager,
    deviceController: widget.deviceController,
    settingsController: widget.settingsController,
    scanStateGuardian: widget.scanStateGuardian,
  );
```

- [ ] **Step 5: Run analyze + the visibility test + the full suite**

Run: `flutter analyze`
Expected: No new issues.

Run: `flutter test test/launcher/`
Expected: PASS (visibility, tap, scan-page tests).

Run: `flutter test`
Expected: PASS (whole suite, including the 21 onboarding scan tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/launcher/launcher_view.dart lib/src/app.dart test/launcher/connect_hero_visibility_test.dart
git commit -m "feat: show connect-hero in launcher and route to scan page"
```

---

## Task 6: End-to-end verification + docs

**Files:**
- Possibly modify: `doc/DeviceManagement.md` (note the launcher reconnect entry point)

- [ ] **Step 1: Run the app in simulate mode and verify the flow**

Per `.agents/skills/decent-app/` dev loop: `scripts/sb-dev.sh start` with simulated devices, or `flutter run --dart-define=simulate=1`. Confirm: with no machine, the launcher shows the connect-hero above the skin slot; tapping it opens the scan page; on connect it pops back and the hero disappears; Cancel pops back and the status bar still reads "No machine".

> Visual/behaviour change — the verification tier here is "Run app" (GUI change), per CLAUDE.md. Capture the before/after for the user.

- [ ] **Step 2: Final full test + analyze**

Run: `flutter test && flutter analyze`
Expected: All pass, no issues. Show the output.

- [ ] **Step 3: Update docs if device flows are documented**

Check `doc/DeviceManagement.md` for a launcher/reconnect section; if device discovery entry points are documented there, add a line for the launcher connect-hero → scan page. If nothing relevant exists, skip (note that you checked).

- [ ] **Step 4: Commit any doc change**

```bash
git add doc/DeviceManagement.md
git commit -m "docs: note launcher connect-hero reconnect path"
```

---

## Self-Review Notes

- **Spec coverage:** hero card (Task 3), machine-only visibility via `de1` null (Task 5), stacked above skin slot (Task 5 Step 3), push full-screen page reusing onboarding flow (Tasks 2+4), ready→pop + cancel→stopScan+pop (Task 4), extraction with onboarding tests as guard (Tasks 1-2). All spec sections map to a task.
- **Deferred items NOT built:** tappable chips, scale-only hero — correctly excluded per spec scope.
- **Type consistency:** `ScanFlowView` field/callback names (`onConnected`, `onExit`, `exitLabel`, `scanTooLongThreshold`) are identical across Tasks 2, 4, 5. `LauncherScanPage.routeName` consistent across Tasks 4-5. `MockConnectionManager.emitStatus` / `FakeDe1` consistent across Tasks 1, 4, 5.
- **Known soft spot:** Task 5 Step 1 leaves `WebUIService`/`PluginLoaderService` construction to be matched against the existing launcher test fixtures (explicitly flagged, not a silent placeholder). The implementer wires the real services.
