# Onboarding Flow Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current permissions → device discovery flow with an extensible onboarding stepper, structured scan telemetry, troubleshooting wizard, and BLE adapter state monitoring.

**Architecture:** A new `OnboardingController` manages a linear step sequence evaluated each launch. `ScanReport` captures structured scan telemetry inside `ConnectionManager`. A `BleDiscoveryService` subclass (not on the base `DeviceDiscoveryService`) exposes adapter state. `ScanStateGuardian` monitors adapter state via `BleDiscoveryService` and app lifecycle to reconcile stale scan state. A troubleshooting wizard dialog guides users through common BLE issues.

**Key constraint:** Not all discovery services use BLE — serial/USB services exist. Adapter state belongs only on BLE services. `DeviceScanner` and `DeviceController` remain transport-blind.

**Tech Stack:** Flutter, RxDart (BehaviorSubject), existing `DeviceDiscoveryService`/`DeviceScanner`/`ConnectionManager` patterns.

**Design Doc:** `doc/plans/2026-03-31-onboarding-redesign-design.md`

---

### Task 1: AdapterState Domain Enum + BleDiscoveryService Abstract Class

**Files:**
- Create: `lib/src/models/adapter_state.dart`
- Create: `lib/src/services/ble/ble_discovery_service.dart`

**Step 1: Create AdapterState enum**

```dart
// lib/src/models/adapter_state.dart

/// Transport-agnostic adapter readiness state.
/// Used by BleDiscoveryService today; reusable for future
/// WifiDiscoveryService or other transport families.
enum AdapterState { poweredOn, poweredOff, unavailable, unknown }
```

**Step 2: Create BleDiscoveryService abstract class**

```dart
// lib/src/services/ble/ble_discovery_service.dart
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

/// BLE-transport-specific extension of DeviceDiscoveryService.
/// Adds Bluetooth adapter state monitoring.
/// Only BLE discovery services extend this — serial/simulated services do not.
abstract class BleDiscoveryService extends DeviceDiscoveryService {
  /// Stream of Bluetooth adapter state changes.
  /// Should replay current state on subscription (BehaviorSubject semantics).
  Stream<AdapterState> get adapterStateStream;
}
```

**Step 3: Run `flutter analyze`**

Expected: no issues

**Step 4: Commit**

```bash
git add lib/src/models/adapter_state.dart lib/src/services/ble/ble_discovery_service.dart
git commit -m "feat(onboarding): add AdapterState enum and BleDiscoveryService abstract class"
```

---

### Task 2: Implement adapterStateStream in BLE Discovery Services

**Files:**
- Modify: `lib/src/services/blue_plus_discovery_service.dart` — change to extend `BleDiscoveryService`
- Modify: `lib/src/services/ble/linux_ble_discovery_service.dart` — change to extend `BleDiscoveryService`
- Modify: `lib/src/services/universal_ble_discovery_service.dart` — change to extend `BleDiscoveryService`

**Step 1: BluePlusDiscoveryService**

Change `implements DeviceDiscoveryService` → `extends BleDiscoveryService`. Add:

```dart
import 'package:reaprime/src/models/adapter_state.dart';

@override
Stream<AdapterState> get adapterStateStream =>
    FlutterBluePlus.adapterState.map(_mapAdapterState);

static AdapterState _mapAdapterState(BluetoothAdapterState state) {
  switch (state) {
    case BluetoothAdapterState.on:
      return AdapterState.poweredOn;
    case BluetoothAdapterState.off:
      return AdapterState.poweredOff;
    case BluetoothAdapterState.unavailable:
      return AdapterState.unavailable;
    default:
      return AdapterState.unknown;
  }
}
```

**Step 2: LinuxBleDiscoveryService**

Change to extend `BleDiscoveryService`. The service already tracks `_adapterReady: bool` (line 44) and subscribes to adapter state (line 49). Add a `BehaviorSubject<AdapterState>` seeded with `AdapterState.unknown`, feed it from the existing `_adapterSubscription`, expose as `adapterStateStream`.

**Critical detail:** Seed with `unknown` (not `poweredOff`) — at init time the state hasn't been confirmed yet. Promote to `poweredOn`/`poweredOff` only when the adapter stream explicitly reports.

**Step 3: UniversalBleDiscoveryService**

Change to extend `BleDiscoveryService`. Map `UniversalBle.availabilityStream` to `AdapterState`.

**Critical detail:** `UniversalBle.availabilityStream` does not guarantee replay. Wrap in a `BehaviorSubject` seeded from `UniversalBle.getBluetoothAvailabilityState()` (already called in `initialize()` at line 31).

**Step 4: Run `flutter analyze`**

Expected: no issues. Serial services and `SimulatedDeviceService` are unaffected.

**Step 5: Commit**

```bash
git add lib/src/services/blue_plus_discovery_service.dart lib/src/services/ble/linux_ble_discovery_service.dart lib/src/services/universal_ble_discovery_service.dart
git commit -m "feat(onboarding): implement adapterStateStream in BLE discovery services"
```

---

### Task 3: MockBleDiscoveryService Test Helper

**Files:**
- Modify: `test/helpers/mock_device_discovery_service.dart` — add `MockBleDiscoveryService`

**Step 1: Add MockBleDiscoveryService**

```dart
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';

/// A controllable BleDiscoveryService for tests that need adapter state.
/// Extends MockDeviceDiscoveryService with adapter state control.
class MockBleDiscoveryService extends BleDiscoveryService {
  final _controller = BehaviorSubject<List<Device>>.seeded([]);
  final _adapterStateSubject = BehaviorSubject<AdapterState>.seeded(AdapterState.unknown);
  final List<Device> _devices = [];

  @override
  Stream<List<Device>> get devices => _controller.stream;

  @override
  Stream<AdapterState> get adapterStateStream => _adapterStateSubject.stream;

  void setAdapterState(AdapterState state) {
    _adapterStateSubject.add(state);
  }

  void addDevice(Device device) {
    _devices.add(device);
    _controller.add(List.from(_devices));
  }

  void removeDevice(String deviceId) {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    _controller.add(List.from(_devices));
  }

  void clear() {
    _devices.clear();
    _controller.add([]);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {}

  @override
  void stopScan() {}

  void dispose() {
    _controller.close();
    _adapterStateSubject.close();
  }
}
```

The existing `MockDeviceDiscoveryService` stays unchanged — tests that don't need adapter state use it.

**Step 2: Write a quick test**

```dart
// test/helpers/mock_ble_discovery_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import '../helpers/mock_device_discovery_service.dart';

void main() {
  test('MockBleDiscoveryService emits adapter state changes', () async {
    final service = MockBleDiscoveryService();
    expect(await service.adapterStateStream.first, AdapterState.unknown);
    service.setAdapterState(AdapterState.poweredOn);
    expect(await service.adapterStateStream.first, AdapterState.poweredOn);
    service.setAdapterState(AdapterState.poweredOff);
    expect(await service.adapterStateStream.first, AdapterState.poweredOff);
    service.dispose();
  });
}
```

**Step 3: Run test — expect PASS**

Run: `flutter test test/helpers/mock_ble_discovery_service_test.dart`

**Step 4: Commit**

```bash
git add test/helpers/mock_device_discovery_service.dart test/helpers/mock_ble_discovery_service_test.dart
git commit -m "feat(onboarding): add MockBleDiscoveryService test helper"
```

---

### Task 4: ScanReport and ScanTerminationReason Models

**Files:**
- Create: `lib/src/models/scan_report.dart`
- Test: `test/models/scan_report_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/scan_report.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

void main() {
  test('ScanReport stores scan telemetry', () {
    final report = ScanReport(
      totalBleDevicesSeen: 5,
      matchedDevices: [],
      scanDuration: Duration(seconds: 15),
      adapterStateAtStart: AdapterState.poweredOn,
      adapterStateAtEnd: AdapterState.poweredOn,
      scanTerminationReason: ScanTerminationReason.completed,
      preferredMachineId: 'machine-123',
      preferredScaleId: null,
    );

    expect(report.totalBleDevicesSeen, 5);
    expect(report.scanTerminationReason, ScanTerminationReason.completed);
    expect(report.preferredMachineId, 'machine-123');
    expect(report.preferredScaleId, isNull);
  });

  test('MatchedDevice tracks connection result', () {
    final matched = MatchedDevice(
      deviceName: 'DE1',
      deviceId: 'abc123',
      deviceType: DeviceType.machine,
      connectionAttempted: true,
      connectionResult: ConnectionResult.failed('timeout'),
    );

    expect(matched.connectionAttempted, isTrue);
    expect(matched.connectionResult!.success, isFalse);
    expect(matched.connectionResult!.error, 'timeout');
  });
}
```

**Step 2: Run test — expect FAIL**

**Step 3: Implement models**

```dart
// lib/src/models/scan_report.dart
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

enum ScanTerminationReason { completed, timedOut, cancelledByUser, adapterStateChanged }

class ConnectionResult {
  final bool success;
  final String? error;

  const ConnectionResult.succeeded() : success = true, error = null;
  const ConnectionResult.failed(this.error) : success = false;
  const ConnectionResult.skipped() : success = false, error = null;
}

class MatchedDevice {
  final String deviceName;
  final String deviceId;
  final DeviceType deviceType;
  final bool connectionAttempted;
  final ConnectionResult? connectionResult;

  const MatchedDevice({
    required this.deviceName,
    required this.deviceId,
    required this.deviceType,
    required this.connectionAttempted,
    this.connectionResult,
  });
}

class ScanReport {
  final int totalBleDevicesSeen;
  final List<MatchedDevice> matchedDevices;
  final Duration scanDuration;
  final AdapterState adapterStateAtStart;
  final AdapterState adapterStateAtEnd;
  final ScanTerminationReason scanTerminationReason;
  final String? preferredMachineId;
  final String? preferredScaleId;

  const ScanReport({
    required this.totalBleDevicesSeen,
    required this.matchedDevices,
    required this.scanDuration,
    required this.adapterStateAtStart,
    required this.adapterStateAtEnd,
    required this.scanTerminationReason,
    this.preferredMachineId,
    this.preferredScaleId,
  });
}
```

**Step 4: Run test — expect PASS**

Run: `flutter test test/models/scan_report_test.dart`

**Step 5: Commit**

```bash
git add lib/src/models/scan_report.dart test/models/scan_report_test.dart
git commit -m "feat(onboarding): add ScanReport and related models"
```

---

### Task 5: Integrate ScanReport into ConnectionManager

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

This is the most complex task. `ConnectionManager._connectImpl()` (lines 134-281) needs to build a `ScanReport` as it runs.

**Step 1: Write failing tests**

Add to `test/controllers/connection_manager_test.dart`:

```dart
group('ScanReport', () {
  test('emits ScanReport with scan results after scan completes', () async {
    scanner.scanCompleter = Completer();
    final connectFuture = connectionManager.connect();
    await Future.delayed(Duration.zero);

    scanner.addDevice(mockMachine);
    scanner.completeScan();
    await connectFuture;

    final report = connectionManager.lastScanReport;
    expect(report, isNotNull);
    expect(report!.matchedDevices, hasLength(1));
    expect(report.matchedDevices.first.deviceId, mockMachine.deviceId);
    expect(report.scanTerminationReason, ScanTerminationReason.completed);
  });

  test('ScanReport includes preferred device IDs from settings', () async {
    settings.preferredMachineId = 'preferred-123';
    final connectFuture = connectionManager.connect();
    await connectFuture;

    final report = connectionManager.lastScanReport;
    expect(report!.preferredMachineId, 'preferred-123');
  });

  test('ScanReport tracks failed connection attempt', () async {
    // Set up a machine that fails to connect
    scanner.scanCompleter = Completer();
    final connectFuture = connectionManager.connect();
    await Future.delayed(Duration.zero);

    scanner.addDevice(failingMachine);
    scanner.completeScan();
    await connectFuture;

    final report = connectionManager.lastScanReport;
    final matched = report!.matchedDevices.first;
    expect(matched.connectionAttempted, isTrue);
    expect(matched.connectionResult!.success, isFalse);
  });
});
```

**Step 2: Run tests — expect FAIL** (no `lastScanReport` property yet)

**Step 3: Implement ScanReport building in ConnectionManager**

Key changes to `ConnectionManager`:
- Add `ScanReport? _lastScanReport` field and public getter `lastScanReport`
- Add `Stream<ScanReport> get scanReportStream` (BehaviorSubject)
- In `_connectImpl()`:
  - Record `scanStartTime` before scan
  - Track `matchedDevices` list — add entries as devices are discovered and connection attempts resolve
  - Record termination reason
  - Build and emit `ScanReport` after scan + connection attempts complete
- Wrap `connectMachine()` and `connectScale()` calls to capture `ConnectionResult`

The `totalBleDevicesSeen` count: `DeviceScanner` currently only exposes matched devices (post-`DeviceMatcher`). For the initial implementation, set this to `matchedDevices.length`. A future enhancement could add a raw advertisement counter to `DeviceScanner`, but YAGNI for now — the matched count still differentiates "zero devices seen" from "devices seen but none matched."

Adapter state for the report: `ConnectionManager` does NOT depend on `BleDiscoveryService`. The adapter state fields in `ScanReport` are populated by the caller (scan step or `ScanStateGuardian`) after the report is built, OR `ConnectionManager` accepts an optional `AdapterState` supplier function in its constructor. Keep it simple — default to `AdapterState.unknown` in the report if no supplier is provided.

**Step 4: Run tests — expect PASS**

Run: `flutter test test/controllers/connection_manager_test.dart`

**Step 5: Run full test suite**

Run: `flutter test`
Expected: All pass (existing tests should not break)

**Step 6: Commit**

```bash
git add lib/src/controllers/connection_manager.dart test/controllers/connection_manager_test.dart
git commit -m "feat(onboarding): build ScanReport in ConnectionManager during scan"
```

---

### Task 6: ScanStateGuardian

**Files:**
- Create: `lib/src/controllers/scan_state_guardian.dart`
- Test: `test/controllers/scan_state_guardian_test.dart`

**Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/scan_state_guardian.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import '../helpers/mock_device_discovery_service.dart';

void main() {
  late MockBleDiscoveryService bleService;
  late ScanStateGuardian guardian;

  setUp(() {
    bleService = MockBleDiscoveryService();
    guardian = ScanStateGuardian(bleService: bleService);
  });

  tearDown(() {
    guardian.dispose();
    bleService.dispose();
  });

  test('emits adapterTurnedOff when adapter state changes to poweredOff', () async {
    bleService.setAdapterState(AdapterState.poweredOn);
    await Future.delayed(Duration.zero);

    expectLater(
      guardian.events,
      emits(ScanStateEvent.adapterTurnedOff),
    );
    bleService.setAdapterState(AdapterState.poweredOff);
  });

  test('emits adapterTurnedOn when adapter state changes to poweredOn', () async {
    bleService.setAdapterState(AdapterState.poweredOff);
    await Future.delayed(Duration.zero);

    expectLater(
      guardian.events,
      emits(ScanStateEvent.adapterTurnedOn),
    );
    bleService.setAdapterState(AdapterState.poweredOn);
  });

  test('emits scanStateStale on app resume', () async {
    guardian.onAppResumed();

    expectLater(
      guardian.events,
      emits(ScanStateEvent.scanStateStale),
    );
  });

}
```

**Step 2: Run — expect FAIL**

**Step 3: Implement ScanStateGuardian**

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';
import 'package:rxdart/rxdart.dart';
import 'package:logging/logging.dart';

enum ScanStateEvent {
  adapterTurnedOff,
  adapterTurnedOn,
  scanStateStale,
}

class ScanStateGuardian with WidgetsBindingObserver {
  final BleDiscoveryService bleService;
  final _log = Logger('ScanStateGuardian');
  final _eventSubject = PublishSubject<ScanStateEvent>();
  late final StreamSubscription _adapterSub;
  AdapterState _lastAdapterState = AdapterState.unknown;

  Stream<ScanStateEvent> get events => _eventSubject.stream;

  /// Current adapter state as last reported by the BLE service.
  AdapterState get currentAdapterState => _lastAdapterState;

  ScanStateGuardian({required this.bleService}) {
    _adapterSub = bleService.adapterStateStream.listen(_onAdapterStateChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onAdapterStateChanged(AdapterState state) {
    final previous = _lastAdapterState;
    _lastAdapterState = state;

    if (previous == AdapterState.poweredOn && state == AdapterState.poweredOff) {
      _log.warning('BLE adapter turned off');
      _eventSubject.add(ScanStateEvent.adapterTurnedOff);
    } else if (previous == AdapterState.poweredOff && state == AdapterState.poweredOn) {
      _log.info('BLE adapter turned on');
      _eventSubject.add(ScanStateEvent.adapterTurnedOn);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onAppResumed();
    }
  }

  /// Public for testability — called by WidgetsBindingObserver on resume.
  void onAppResumed() {
    _log.fine('App resumed, checking scan state');
    _eventSubject.add(ScanStateEvent.scanStateStale);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adapterSub.cancel();
    _eventSubject.close();
  }
}
```

**Step 4: Run tests — expect PASS**

Run: `flutter test test/controllers/scan_state_guardian_test.dart`

**Step 5: Commit**

```bash
git add lib/src/controllers/scan_state_guardian.dart test/controllers/scan_state_guardian_test.dart
git commit -m "feat(onboarding): add ScanStateGuardian with BleDiscoveryService adapter monitoring"
```

---

### Task 7: OnboardingStep Abstraction and OnboardingController

**Files:**
- Create: `lib/src/onboarding_feature/onboarding_controller.dart`
- Test: `test/onboarding/onboarding_controller_test.dart`

**Step 1: Write failing tests**

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';

void main() {
  test('evaluates shouldShow and skips steps that return false', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'always-skip',
        shouldShow: () async => false,
        builder: (_) => const SizedBox(),
      ),
      OnboardingStep(
        id: 'always-show',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();
    expect(controller.currentStep.id, 'always-show');
    expect(controller.activeSteps, hasLength(1));
  });

  test('advance() moves to next step', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'step-1',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
      OnboardingStep(
        id: 'step-2',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();
    expect(controller.currentStep.id, 'step-1');

    controller.advance();
    expect(controller.currentStep.id, 'step-2');
  });

  test('advance() on last step emits completed', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'only-step',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();

    expectLater(controller.completedStream, emits(true));
    controller.advance();
  });

  test('currentStepStream emits on advance', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'step-1',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
      OnboardingStep(
        id: 'step-2',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();

    expectLater(
      controller.currentStepStream.map((s) => s.id),
      emitsInOrder(['step-1', 'step-2']),
    );

    controller.advance();
  });
}
```

**Step 2: Run — expect FAIL**

**Step 3: Implement**

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

typedef StepWidgetBuilder = Widget Function(OnboardingController controller);

class OnboardingStep {
  final String id;
  final Future<bool> Function() shouldShow;
  final StepWidgetBuilder builder;

  const OnboardingStep({
    required this.id,
    required this.shouldShow,
    required this.builder,
  });
}

class OnboardingController {
  final List<OnboardingStep> _allSteps;
  List<OnboardingStep> _activeSteps = [];
  int _currentIndex = 0;

  final _currentStepSubject = BehaviorSubject<OnboardingStep>();
  final _completedSubject = PublishSubject<bool>();

  Stream<OnboardingStep> get currentStepStream => _currentStepSubject.stream;
  Stream<bool> get completedStream => _completedSubject.stream;
  OnboardingStep get currentStep => _activeSteps[_currentIndex];
  List<OnboardingStep> get activeSteps => List.unmodifiable(_activeSteps);

  OnboardingController({required List<OnboardingStep> steps}) : _allSteps = steps;

  Future<void> initialize() async {
    _activeSteps = [];
    for (final step in _allSteps) {
      if (await step.shouldShow()) {
        _activeSteps.add(step);
      }
    }
    _currentIndex = 0;
    if (_activeSteps.isNotEmpty) {
      _currentStepSubject.add(_activeSteps[_currentIndex]);
    }
  }

  void advance() {
    if (_currentIndex >= _activeSteps.length - 1) {
      _completedSubject.add(true);
      return;
    }
    _currentIndex++;
    _currentStepSubject.add(_activeSteps[_currentIndex]);
  }

  void dispose() {
    _currentStepSubject.close();
    _completedSubject.close();
  }
}
```

**Step 4: Run tests — expect PASS**

Run: `flutter test test/onboarding/onboarding_controller_test.dart`

**Step 5: Commit**

```bash
git add lib/src/onboarding_feature/onboarding_controller.dart test/onboarding/onboarding_controller_test.dart
git commit -m "feat(onboarding): add OnboardingController with step evaluation and navigation"
```

---

### Task 8: OnboardingView Widget with PopScope

**Files:**
- Create: `lib/src/onboarding_feature/onboarding_view.dart`
- Test: `test/onboarding/onboarding_view_test.dart`

**Step 1: Write failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('renders current step widget', (tester) async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'test-step',
        shouldShow: () async => true,
        builder: (_) => const Text('Step Content'),
      ),
    ]);
    await controller.initialize();

    await tester.pumpWidget(
      ShadApp(home: Scaffold(body: OnboardingView(controller: controller))),
    );
    await tester.pump();

    expect(find.text('Step Content'), findsOneWidget);
  });

  testWidgets('blocks system back navigation via PopScope', (tester) async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'test-step',
        shouldShow: () async => true,
        builder: (_) => const Text('Step Content'),
      ),
    ]);
    await controller.initialize();

    await tester.pumpWidget(
      ShadApp(home: Scaffold(body: OnboardingView(controller: controller))),
    );
    await tester.pump();

    // Verify PopScope is in the tree with canPop: false
    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);
  });
}
```

**Step 2: Run — expect FAIL**

**Step 3: Implement OnboardingView**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'onboarding_controller.dart';

class OnboardingView extends StatefulWidget {
  final OnboardingController controller;
  final VoidCallback? onComplete;

  const OnboardingView({
    super.key,
    required this.controller,
    this.onComplete,
  });

  static const routeName = '/onboarding';

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  late StreamSubscription _stepSub;
  late StreamSubscription _completeSub;

  @override
  void initState() {
    super.initState();
    _stepSub = widget.controller.currentStepStream.listen((_) {
      if (mounted) setState(() {});
    });
    _completeSub = widget.controller.completedStream.listen((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _stepSub.cancel();
    _completeSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: widget.controller.currentStep.builder(widget.controller),
    );
  }
}
```

**Step 4: Run tests — expect PASS**

Run: `flutter test test/onboarding/onboarding_view_test.dart`

**Step 5: Commit**

```bash
git add lib/src/onboarding_feature/onboarding_view.dart test/onboarding/onboarding_view_test.dart
git commit -m "feat(onboarding): add OnboardingView with PopScope back-navigation blocking"
```

---

### Task 9: Wrap Existing PermissionsView as an OnboardingStep

**Files:**
- Create: `lib/src/onboarding_feature/steps/permissions_step.dart`

**Step 1: Create the step factory**

This wraps the existing `PermissionsView` logic into an `OnboardingStep`. The `shouldShow` predicate queries actual platform permissions (extracted from the current `_checkPermissions` logic in `permissions_view.dart`).

```dart
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../onboarding_controller.dart';

OnboardingStep createPermissionsStep({
  required DeviceController deviceController,
  // ... other required params matching current PermissionsView constructor
}) {
  return OnboardingStep(
    id: 'permissions',
    shouldShow: () => _checkPermissionsNeeded(),
    builder: (controller) => PermissionsStepView(
      onboardingController: controller,
      deviceController: deviceController,
      // ... pass through dependencies
    ),
  );
}

Future<bool> _checkPermissionsNeeded() async {
  if (Platform.isAndroid) {
    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt >= 31) {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      return !scan.isGranted || !connect.isGranted;
    } else {
      final bt = await Permission.bluetooth.status;
      final loc = await Permission.locationWhenInUse.status;
      return !bt.isGranted || !loc.isGranted;
    }
  } else if (Platform.isIOS) {
    final bt = await Permission.bluetooth.status;
    return !bt.isGranted;
  }
  // Desktop: no permissions needed
  return false;
}
```

The `PermissionsStepView` is a thin wrapper around the existing permissions UI that calls `controller.advance()` on completion instead of navigating to `DeviceDiscoveryView`.

**Step 2: Run `flutter analyze`**

**Step 3: Commit**

```bash
git add lib/src/onboarding_feature/steps/permissions_step.dart
git commit -m "feat(onboarding): wrap PermissionsView as OnboardingStep with runtime permission check"
```

---

### Task 10: Scan Step with "Taking Too Long" Timer

**Files:**
- Create: `lib/src/onboarding_feature/steps/scan_step.dart`
- Test: `test/onboarding/scan_step_test.dart`

**Step 1: Write failing tests**

```dart
testWidgets('shows coffee message initially, no action buttons', (tester) async {
  // Build scan step with mock ConnectionManager in scanning phase
  // Verify: progress indicator visible, no "taking too long" button
});

testWidgets('shows "taking too long" button after 8 seconds', (tester) async {
  // Build scan step, advance fake timer by 8 seconds
  // Verify: button appears with fade animation
});

testWidgets('taking too long button opens bottom sheet with 3 options', (tester) async {
  // Tap the button
  // Verify: bottom sheet with "Re-start scan", "Export logs", "Continue to Dashboard"
});

testWidgets('shows scan results summary when scan completes with no devices', (tester) async {
  // Complete scan with empty results
  // Verify: ScanReport summary is displayed
});
```

**Step 2: Run — expect FAIL**

**Step 3: Implement scan step**

Key implementation points:
- Subscribes to `connectionManager.status` stream
- Starts an 8-second `Timer` when scan begins (`const scanTooLongThreshold = Duration(seconds: 8)`)
- Timer triggers `_showTakingTooLong` state → fade-in animation on the button
- Bottom sheet with three actions: restart (calls `connectionManager.connect()`), export logs, continue to dashboard
- When scan completes with no devices: reads `connectionManager.lastScanReport` and renders scan results summary
- When scan completes with devices: existing picker/auto-connect flow → `onboardingController.advance()`
- Integrates `ScanStateGuardian.events` to handle adapter off / stale scan
- Gets adapter state for `ScanReport` from `ScanStateGuardian.currentAdapterState`

**Step 4: Run tests — expect PASS**

**Step 5: Commit**

```bash
git add lib/src/onboarding_feature/steps/scan_step.dart test/onboarding/scan_step_test.dart
git commit -m "feat(onboarding): add scan step with 8-second 'taking too long' timer"
```

---

### Task 11: Scan Results Summary View

**Files:**
- Create: `lib/src/onboarding_feature/widgets/scan_results_summary.dart`
- Test: `test/onboarding/scan_results_summary_test.dart`

**Step 1: Write failing tests**

```dart
testWidgets('shows "no BLE devices detected" when totalBleDevicesSeen is 0', (tester) async {
  final report = ScanReport(totalBleDevicesSeen: 0, matchedDevices: [], ...);
  // Build widget, verify message
});

testWidgets('shows "devices found but none matched" when seen > 0 but no matches', (tester) async {
  final report = ScanReport(totalBleDevicesSeen: 5, matchedDevices: [], ...);
  // Verify message
});

testWidgets('shows preferred machine not found message', (tester) async {
  final report = ScanReport(preferredMachineId: 'abc', matchedDevices: [], ...);
  // Verify: "Your preferred machine wasn't found"
});

testWidgets('shows connection failure details', (tester) async {
  final report = ScanReport(matchedDevices: [
    MatchedDevice(deviceName: 'DE1', connectionAttempted: true,
      connectionResult: ConnectionResult.failed('timeout'), ...),
  ], ...);
  // Verify: shows device name and failure reason
});

testWidgets('has Scan Again, Troubleshoot, Export Logs, Continue buttons', (tester) async {
  // Verify all four action buttons present
});
```

**Step 2: Run — expect FAIL**

**Step 3: Implement**

A stateless widget that takes a `ScanReport` and renders:
- An icon and heading based on the report contents
- Human-readable summary message derived from the report
- Four action buttons: "Scan Again", "Troubleshoot", "Export Logs", "Continue to Dashboard"

Message derivation logic (priority order):
1. `totalBleDevicesSeen == 0` → "No Bluetooth devices were detected at all"
2. `matchedDevices.isEmpty` → "X BLE devices found, but none matched a Decent machine"
3. Has matched device with failed connection → "Found [name] but connection failed: [error]"
4. `preferredMachineId != null` and not in matched → "Your preferred machine wasn't found during the scan"

**Step 4: Run tests — expect PASS**

**Step 5: Commit**

```bash
git add lib/src/onboarding_feature/widgets/scan_results_summary.dart test/onboarding/scan_results_summary_test.dart
git commit -m "feat(onboarding): add ScanResultsSummary view with human-readable report"
```

---

### Task 12: Troubleshooting Wizard Dialog

**Files:**
- Create: `lib/src/onboarding_feature/widgets/troubleshooting_wizard.dart`
- Test: `test/onboarding/troubleshooting_wizard_test.dart`

**Step 1: Write failing tests**

```dart
testWidgets('shows "machine powered on?" as first step', (tester) async {
  // Open wizard dialog
  // Verify first step content and button
});

testWidgets('advances to "other apps" step after confirming machine is on', (tester) async {
  // Tap "Yes, it's on"
  // Verify next step shows
});

testWidgets('shows Bluetooth step on iOS when adapter is off', (tester) async {
  // Mock platform as iOS, adapter state poweredOff
  // Verify Bluetooth step appears
});

testWidgets('skips Bluetooth step on Android', (tester) async {
  // Mock platform as Android
  // Verify goes straight from step 1 to "other apps" step
});

testWidgets('dismisses dialog on final step confirmation', (tester) async {
  // Complete all steps
  // Verify dialog is dismissed
});
```

**Step 2: Run — expect FAIL**

**Step 3: Implement**

A `StatefulWidget` shown via `showDialog()`. Internal step index, forward-only. Steps defined as a list, each with:
- `title`, `description`, `buttonText`
- `shouldShow` predicate (e.g., Bluetooth step checks `Platform.isIOS && adapterState != poweredOn`)

The Bluetooth step uses `BleDiscoveryService.adapterStateStream` (via `ScanStateGuardian`) to show live adapter status and a platform-specific "Open Settings" button.

On dismiss (completing all steps or tapping outside): returns to caller, no side effects.

**Step 4: Run tests — expect PASS**

**Step 5: Commit**

```bash
git add lib/src/onboarding_feature/widgets/troubleshooting_wizard.dart test/onboarding/troubleshooting_wizard_test.dart
git commit -m "feat(onboarding): add troubleshooting wizard dialog"
```

---

### Task 13: Device Picker Preferred-Device Messaging

**Files:**
- Modify: `lib/src/onboarding_feature/steps/scan_step.dart`
- Modify: `lib/src/home_feature/widgets/device_selection_widget.dart`

**Step 1: Write failing test**

```dart
testWidgets('shows preferred device not found message when picker shown as fallback', (tester) async {
  // ScanReport has preferredMachineId set, machine not in matchedDevices
  // But other machines exist
  // Verify header: "Your preferred machine wasn't found, but we discovered these:"
});
```

**Step 2: Run — expect FAIL**

**Step 3: Implement**

In the scan step's device picker state: check `ScanReport.preferredMachineId` against found machines. If preferred is set but not found, pass a custom `headerText` to `DeviceSelectionWidget`:

```dart
headerText: "Your preferred machine wasn't found, but we discovered these:"
```

Same pattern for scales.

When user taps a non-preferred device and connects, show a confirmation: "Set [device name] as your preferred machine?"

**Step 4: Run tests — expect PASS**

**Step 5: Commit**

```bash
git add lib/src/onboarding_feature/steps/scan_step.dart lib/src/home_feature/widgets/device_selection_widget.dart test/onboarding/scan_step_test.dart
git commit -m "feat(onboarding): add preferred-device-aware messaging to device picker"
```

---

### Task 14: Wire Onboarding into App Routing

**Files:**
- Modify: `lib/src/app.dart` — replace default route with `OnboardingView`
- Modify: `lib/main.dart` — create `ScanStateGuardian`, wire onboarding

**Step 1: Update `main.dart`**

Type the BLE discovery service explicitly and pass it to `ScanStateGuardian`:

```dart
// Around line 196 — the BLE service is already created per-platform.
// Type it as BleDiscoveryService before adding to the services list.
// Around line 196 — the BLE service is already created per-platform.
// Type it as BleDiscoveryService before adding to the services list.
// Every platform always has exactly one BLE service.
final BleDiscoveryService bleDiscoveryService;

if (Platform.isLinux) {
  bleDiscoveryService = LinuxBleDiscoveryService(...);
} else if (Platform.isWindows) {
  bleDiscoveryService = UniversalBleDiscoveryService(...);
} else {
  bleDiscoveryService = BluePlusDiscoveryService(...);
}

services.add(bleDiscoveryService);
// ... serial + simulated services added as before

final scanStateGuardian = ScanStateGuardian(
  bleService: bleDiscoveryService,
);
```

Pass `scanStateGuardian` through to `MyApp` / `AppRoot`.

**Step 2: Update `app.dart` default route**

Replace the `PermissionsView` default route with `OnboardingView`:

```dart
// Default route — onboarding flow
return MaterialPageRoute(
  builder: (_) => OnboardingView(
    controller: _onboardingController,
    onComplete: () => Navigator.of(context).pushReplacementNamed(HomeScreen.routeName),
  ),
);
```

Create the `OnboardingController` in `MyApp.initState()` with:
- `createPermissionsStep(...)` (from Task 9)
- `createScanStep(...)` (from Task 10)

Call `controller.initialize()` and render `OnboardingView` once ready.

**Step 3: Run `flutter analyze`**

**Step 4: Run full test suite**

Run: `flutter test`
Expected: All pass. Existing `device_discovery_view_test.dart` may need updates if it assumed direct navigation to `DeviceDiscoveryView`.

**Step 5: Smoke test with simulator**

Run: `flutter run --dart-define=simulate=1`
Verify: App launches → permissions step (if needed) → scan step → devices found → dashboard

**Step 6: Commit**

```bash
git add lib/src/app.dart lib/main.dart
git commit -m "feat(onboarding): wire OnboardingView as app entry point"
```

---

### Task 15: Final Integration Test and Cleanup

**Step 1: Run full test suite**

Run: `flutter test`
Fix any regressions.

**Step 2: Run `flutter analyze`**

Fix any warnings.

**Step 3: MCP smoke test (if app running)**

Use MCP tools to verify scan flow with `simulate=machine,scale`.

**Step 4: Clean up unused code**

- If `PermissionsView` is no longer directly routed to, check if it can be simplified or if only the step wrapper is needed.
- Remove any dead navigation paths from `app.dart`.

**Step 5: Commit**

```bash
git commit -m "chore(onboarding): integration test fixes and cleanup"
```

---

## Task Dependency Graph

```
Task 1 (AdapterState + BleDiscoveryService)
  ├─> Task 2 (implement in BLE services)
  └─> Task 3 (MockBleDiscoveryService)
        └─> Task 6 (ScanStateGuardian)
              └─> Task 14 (wire into app)

Task 4 (ScanReport model)
  └─> Task 5 (integrate into ConnectionManager)
        └─> Task 10 (scan step)
              ├─> Task 11 (scan results summary)
              │     └─> Task 12 (troubleshooting wizard)
              └─> Task 13 (device picker messaging)

Task 7 (OnboardingController)
  └─> Task 8 (OnboardingView)
        └─> Task 9 (permissions step)
              └─> Task 14 (wire into app)
                    └─> Task 15 (final integration)
```

Parallelizable tracks:
- **Track A:** Tasks 1→2→3→6 (BLE adapter state pipeline)
- **Track B:** Tasks 4→5 (ScanReport pipeline)
- **Track C:** Tasks 7→8→9 (onboarding framework)

Tracks A, B, C are independent until Task 10 where they converge.
