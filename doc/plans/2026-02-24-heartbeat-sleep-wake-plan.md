# Heartbeat, Machine Sleep & Scheduled Wake — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add heartbeat/user-presence signaling, auto-sleep timeout, and recurring scheduled wake to the DE1 machine management.

**Architecture:** New `PresenceController` with constructor DI, owning heartbeat forwarding, sleep timeout timer, and wake schedule checker. Protocol layer extended with two new MMR writes and a `schedIdle` state. REST API for skins, Flutter settings sub-page for native config.

**Tech Stack:** Flutter/Dart, RxDart BehaviorSubject, Shelf HTTP handlers, SharedPreferences persistence, ShadCN UI components.

**Design doc:** `doc/plans/2026-02-24-heartbeat-sleep-wake-design.md`

---

### Task 1: WakeSchedule Model

**Files:**
- Create: `lib/src/models/wake_schedule.dart`
- Test: `test/models/wake_schedule_test.dart`

**Step 1: Write the failing test**

Create `test/models/wake_schedule_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/wake_schedule.dart';

void main() {
  group('WakeSchedule', () {
    test('toJson and fromJson round-trip', () {
      final schedule = WakeSchedule(
        id: 'test-id',
        hour: 6,
        minute: 30,
        daysOfWeek: {1, 2, 3, 4, 5},
        enabled: true,
      );

      final json = schedule.toJson();
      final restored = WakeSchedule.fromJson(json);

      expect(restored.id, 'test-id');
      expect(restored.hour, 6);
      expect(restored.minute, 30);
      expect(restored.daysOfWeek, {1, 2, 3, 4, 5});
      expect(restored.enabled, true);
    });

    test('toJson produces expected format', () {
      final schedule = WakeSchedule(
        id: 'abc',
        hour: 14,
        minute: 0,
        daysOfWeek: {},
        enabled: false,
      );

      final json = schedule.toJson();
      expect(json['id'], 'abc');
      expect(json['time'], '14:00');
      expect(json['daysOfWeek'], <int>[]);
      expect(json['enabled'], false);
    });

    test('fromJson parses time string', () {
      final schedule = WakeSchedule.fromJson({
        'id': 'x',
        'time': '09:05',
        'daysOfWeek': [6, 7],
        'enabled': true,
      });

      expect(schedule.hour, 9);
      expect(schedule.minute, 5);
      expect(schedule.daysOfWeek, {6, 7});
    });

    test('matchesNow returns true for matching day and time', () {
      // Wednesday = 3
      final schedule = WakeSchedule(
        id: 'w',
        hour: 7,
        minute: 0,
        daysOfWeek: {3},
        enabled: true,
      );

      final wednesday7am = DateTime(2026, 2, 25, 7, 0); // Wednesday
      expect(schedule.matchesTime(wednesday7am), true);

      final thursday7am = DateTime(2026, 2, 26, 7, 0); // Thursday
      expect(schedule.matchesTime(thursday7am), false);
    });

    test('empty daysOfWeek matches every day', () {
      final schedule = WakeSchedule(
        id: 'daily',
        hour: 6,
        minute: 0,
        daysOfWeek: {},
        enabled: true,
      );

      final monday = DateTime(2026, 2, 23, 6, 0);
      final sunday = DateTime(2026, 3, 1, 6, 0);
      expect(schedule.matchesTime(monday), true);
      expect(schedule.matchesTime(sunday), true);
    });

    test('disabled schedule never matches', () {
      final schedule = WakeSchedule(
        id: 'd',
        hour: 6,
        minute: 0,
        daysOfWeek: {},
        enabled: false,
      );

      final now = DateTime(2026, 2, 23, 6, 0);
      expect(schedule.matchesTime(now), false);
    });

    test('wrong minute does not match', () {
      final schedule = WakeSchedule(
        id: 'm',
        hour: 6,
        minute: 0,
        daysOfWeek: {},
        enabled: true,
      );

      final wrongMinute = DateTime(2026, 2, 23, 6, 1);
      expect(schedule.matchesTime(wrongMinute), false);
    });

    test('serializeList and deserializeList round-trip', () {
      final schedules = [
        WakeSchedule(id: 'a', hour: 6, minute: 0, daysOfWeek: {1, 2, 3, 4, 5}, enabled: true),
        WakeSchedule(id: 'b', hour: 9, minute: 30, daysOfWeek: {6, 7}, enabled: true),
      ];

      final json = WakeSchedule.serializeList(schedules);
      final restored = WakeSchedule.deserializeList(json);

      expect(restored.length, 2);
      expect(restored[0].id, 'a');
      expect(restored[1].hour, 9);
      expect(restored[1].daysOfWeek, {6, 7});
    });

    test('copyWith creates modified copy', () {
      final original = WakeSchedule(
        id: 'orig',
        hour: 6,
        minute: 0,
        daysOfWeek: {1, 2},
        enabled: true,
      );

      final modified = original.copyWith(hour: 7, enabled: false);
      expect(modified.id, 'orig');
      expect(modified.hour, 7);
      expect(modified.minute, 0);
      expect(modified.enabled, false);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/models/wake_schedule_test.dart`
Expected: FAIL — `wake_schedule.dart` does not exist.

**Step 3: Write minimal implementation**

Create `lib/src/models/wake_schedule.dart`:

```dart
import 'dart:convert';

class WakeSchedule {
  final String id;
  final int hour;
  final int minute;
  final Set<int> daysOfWeek;
  final bool enabled;

  WakeSchedule({
    required this.id,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
    required this.enabled,
  });

  bool matchesTime(DateTime dateTime) {
    if (!enabled) return false;
    if (dateTime.hour != hour || dateTime.minute != minute) return false;
    if (daysOfWeek.isEmpty) return true;
    return daysOfWeek.contains(dateTime.weekday);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      'daysOfWeek': daysOfWeek.toList()..sort(),
      'enabled': enabled,
    };
  }

  factory WakeSchedule.fromJson(Map<String, dynamic> json) {
    final timeParts = (json['time'] as String).split(':');
    return WakeSchedule(
      id: json['id'] as String,
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
      daysOfWeek: (json['daysOfWeek'] as List).map((e) => e as int).toSet(),
      enabled: json['enabled'] as bool,
    );
  }

  WakeSchedule copyWith({
    String? id,
    int? hour,
    int? minute,
    Set<int>? daysOfWeek,
    bool? enabled,
  }) {
    return WakeSchedule(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      enabled: enabled ?? this.enabled,
    );
  }

  static String serializeList(List<WakeSchedule> schedules) {
    return jsonEncode(schedules.map((s) => s.toJson()).toList());
  }

  static List<WakeSchedule> deserializeList(String json) {
    final list = jsonDecode(json) as List;
    return list.map((e) => WakeSchedule.fromJson(e as Map<String, dynamic>)).toList();
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/models/wake_schedule_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/models/wake_schedule.dart test/models/wake_schedule_test.dart
git commit -m "feat: add WakeSchedule model with JSON serialization and time matching"
```

---

### Task 2: Protocol Layer — MMR Item, De1Interface, MachineState

**Files:**
- Modify: `lib/src/models/device/impl/de1/de1.models.dart` (MMRItem enum + fromMachineState)
- Modify: `lib/src/models/device/de1_interface.dart` (new methods)
- Modify: `lib/src/models/device/machine.dart` (add `schedIdle` to MachineState)
- Modify: `lib/src/models/device/impl/de1/de1.utils.dart` (state mapping)
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` (implement methods)
- Modify: `lib/src/models/device/impl/mock_de1/mock_de1.dart` (add stubs)

**Step 1: Add `userPresent` to `MMRItem` enum**

In `lib/src/models/device/impl/de1/de1.models.dart`, after `refillKitPresent(0x0080385C, 4, "Refill Kit Present")`, add:

```dart
  userPresent(0x00803860, 4, "Is User Present");
```

Change: replace the semicolon on `refillKitPresent` line with a comma, then add the new entry with semicolon.

**Step 2: Add `schedIdle` to `MachineState` enum**

In `lib/src/models/device/machine.dart`, add `schedIdle` after `idle` in the `MachineState` enum:

```dart
enum MachineState {
  booting,
  busy,
  idle,
  schedIdle,
  sleeping,
  // ... rest unchanged
}
```

**Step 3: Update `fromMachineState` in `de1.models.dart`**

In the `fromMachineState` switch in `De1StateEnum`, add a case for `schedIdle`:

```dart
    case MachineState.schedIdle:
      return De1StateEnum.schedIdle;
```

**Step 4: Update `mapDe1ToMachineState` in `de1.utils.dart`**

Change the `schedIdle` mapping so it maps to `MachineState.schedIdle` instead of `MachineState.idle`:

```dart
    case De1StateEnum.schedIdle:
      return MachineState.schedIdle;
```

(Remove `schedIdle` from the `idle` group.)

**Step 5: Add new methods to `De1Interface`**

In `lib/src/models/device/de1_interface.dart`, add after the USB charger section:

```dart
  //// User Presence
  Future<void> enableUserPresenceFeature();
  Future<void> sendUserPresent();
```

**Step 6: Implement in `UnifiedDe1`**

In `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart`, add:

```dart
  @override
  Future<void> enableUserPresenceFeature() async {
    await _writeMMRInt(MMRItem.appFeatureFlags, 1);
  }

  @override
  Future<void> sendUserPresent() async {
    await _writeMMRInt(MMRItem.userPresent, 1);
  }
```

Find `_writeMMRInt` — it should already exist (used by `_writeMMRScaled`). If not, it writes an integer value to an MMR register.

**Step 7: Call `enableUserPresenceFeature()` in `onConnect()`**

In `UnifiedDe1.onConnect()`, after the `_mmrWrite(MMRItem.refillKitPresent, [0x02])` line, add:

```dart
    await enableUserPresenceFeature();
```

**Step 8: Add stubs to `MockDe1`**

In `lib/src/models/device/impl/mock_de1/mock_de1.dart`, add:

```dart
  @override
  Future<void> enableUserPresenceFeature() async {}

  @override
  Future<void> sendUserPresent() async {}
```

**Step 9: Run analyzer and tests**

Run: `flutter analyze && flutter test`
Expected: No analyzer errors, all existing tests pass.

**Step 10: Commit**

```bash
git add lib/src/models/device/impl/de1/de1.models.dart \
  lib/src/models/device/de1_interface.dart \
  lib/src/models/device/machine.dart \
  lib/src/models/device/impl/de1/de1.utils.dart \
  lib/src/models/device/impl/de1/unified_de1/unified_de1.dart \
  lib/src/models/device/impl/mock_de1/mock_de1.dart
git commit -m "feat: add DE1 user presence protocol support and schedIdle state"
```

---

### Task 3: Settings Persistence

**Files:**
- Modify: `lib/src/settings/settings_service.dart` (add abstract methods)
- Modify: `lib/src/settings/settings_controller.dart` (add properties + update methods)
- Modify: `test/helpers/mock_settings_service.dart` (add mock implementations)

**Step 1: Add methods to `SettingsService` abstract class**

In `lib/src/settings/settings_service.dart`, add to the abstract class:

```dart
  Future<bool> userPresenceEnabled();
  Future<void> setUserPresenceEnabled(bool value);
  Future<int> sleepTimeoutMinutes();
  Future<void> setSleepTimeoutMinutes(int value);
  Future<String> wakeSchedules();
  Future<void> setWakeSchedules(String json);
```

**Step 2: Add to `SharedPreferencesSettingsService` implementation**

In the concrete implementation class (same file), add:

```dart
  @override
  Future<bool> userPresenceEnabled() async {
    return await prefs.getBool(SettingsKeys.userPresenceEnabled.name) ?? true;
  }

  @override
  Future<void> setUserPresenceEnabled(bool value) async {
    await prefs.setBool(SettingsKeys.userPresenceEnabled.name, value);
  }

  @override
  Future<int> sleepTimeoutMinutes() async {
    return await prefs.getInt(SettingsKeys.sleepTimeoutMinutes.name) ?? 30;
  }

  @override
  Future<void> setSleepTimeoutMinutes(int value) async {
    await prefs.setInt(SettingsKeys.sleepTimeoutMinutes.name, value);
  }

  @override
  Future<String> wakeSchedules() async {
    return await prefs.getString(SettingsKeys.wakeSchedules.name) ?? '[]';
  }

  @override
  Future<void> setWakeSchedules(String json) async {
    await prefs.setString(SettingsKeys.wakeSchedules.name, json);
  }
```

Also add to the `SettingsKeys` enum (if it exists) or the equivalent key storage.

**Step 3: Add to `SettingsController`**

In `lib/src/settings/settings_controller.dart`, add fields, getters, load, and update methods following the existing pattern:

Fields:
```dart
  late bool _userPresenceEnabled;
  late int _sleepTimeoutMinutes;
  late String _wakeSchedules;
```

Getters:
```dart
  bool get userPresenceEnabled => _userPresenceEnabled;
  int get sleepTimeoutMinutes => _sleepTimeoutMinutes;
  String get wakeSchedules => _wakeSchedules;
```

In `loadSettings()`:
```dart
    _userPresenceEnabled = await _settingsService.userPresenceEnabled();
    _sleepTimeoutMinutes = await _settingsService.sleepTimeoutMinutes();
    _wakeSchedules = await _settingsService.wakeSchedules();
```

Update methods:
```dart
  Future<void> setUserPresenceEnabled(bool value) async {
    if (value == _userPresenceEnabled) return;
    _userPresenceEnabled = value;
    await _settingsService.setUserPresenceEnabled(value);
    notifyListeners();
  }

  Future<void> setSleepTimeoutMinutes(int value) async {
    if (value == _sleepTimeoutMinutes) return;
    _sleepTimeoutMinutes = value;
    await _settingsService.setSleepTimeoutMinutes(value);
    notifyListeners();
  }

  Future<void> setWakeSchedules(String json) async {
    if (json == _wakeSchedules) return;
    _wakeSchedules = json;
    await _settingsService.setWakeSchedules(json);
    notifyListeners();
  }
```

**Step 4: Add mock implementations**

In `test/helpers/mock_settings_service.dart`, add:

```dart
  bool _userPresenceEnabled = true;
  int _sleepTimeoutMinutes = 30;
  String _wakeSchedules = '[]';

  @override
  Future<bool> userPresenceEnabled() async => _userPresenceEnabled;
  @override
  Future<void> setUserPresenceEnabled(bool value) async => _userPresenceEnabled = value;
  @override
  Future<int> sleepTimeoutMinutes() async => _sleepTimeoutMinutes;
  @override
  Future<void> setSleepTimeoutMinutes(int value) async => _sleepTimeoutMinutes = value;
  @override
  Future<String> wakeSchedules() async => _wakeSchedules;
  @override
  Future<void> setWakeSchedules(String json) async => _wakeSchedules = json;
```

**Step 5: Run analyzer and tests**

Run: `flutter analyze && flutter test`
Expected: No analyzer errors, all tests pass.

**Step 6: Commit**

```bash
git add lib/src/settings/settings_service.dart \
  lib/src/settings/settings_controller.dart \
  test/helpers/mock_settings_service.dart
git commit -m "feat: add presence settings persistence (userPresence, sleepTimeout, wakeSchedules)"
```

---

### Task 4: PresenceController

**Files:**
- Create: `lib/src/controllers/presence_controller.dart`
- Create: `test/controllers/presence_controller_test.dart`

**Step 1: Write the failing tests**

Create `test/controllers/presence_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/presence_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/subjects.dart';

import '../helpers/mock_settings_service.dart';

// Minimal mock for De1Controller that exposes a controllable de1 stream
class _MockDe1Controller extends De1Controller {
  _MockDe1Controller() : super(controller: _DummyDeviceController());

  final BehaviorSubject<De1Interface?> de1Subject = BehaviorSubject.seeded(null);

  @override
  Stream<De1Interface?> get de1 => de1Subject.stream;
}

// Minimal mock for De1Interface to track calls
class _MockDe1 extends /* ... needs to implement De1Interface */ {
  int sendUserPresentCount = 0;
  final List<MachineState> requestedStates = [];

  final BehaviorSubject<MachineSnapshot> _snapshotSubject;

  _MockDe1(MachineState initialState) : _snapshotSubject = BehaviorSubject.seeded(
    MachineSnapshot(/* idle state snapshot */),
  );

  @override
  Future<void> sendUserPresent() async {
    sendUserPresentCount++;
  }

  @override
  Future<void> requestState(MachineState state) async {
    requestedStates.add(state);
  }

  // ... other required stubs
}
```

Note: The test file will need proper mock classes. The implementing engineer should use the existing `MockDe1` from `test/helpers/` or the `mock_de1.dart` device, adapting as needed. The key test cases are:

1. **Heartbeat throttling**: calling `heartbeat()` twice within 30s should only call `sendUserPresent()` once
2. **Heartbeat forwards to DE1**: calling `heartbeat()` calls `sendUserPresent()` on connected DE1
3. **Heartbeat resets sleep timeout**: calling `heartbeat()` resets the timeout timer
4. **Sleep timeout fires**: after configured timeout with no heartbeat, `requestState(sleeping)` is called
5. **Sleep timeout disabled when 0**: setting timeout to 0 means no auto-sleep
6. **Sleep timeout paused during active states**: no sleep request during espresso/steam
7. **Schedule matching**: controller sends `schedIdle` when a schedule matches current time

Use `fakeAsync` from `package:fake_async` to control time in tests.

**Step 2: Run tests to verify they fail**

Run: `flutter test test/controllers/presence_controller_test.dart`
Expected: FAIL — `presence_controller.dart` does not exist.

**Step 3: Write the implementation**

Create `lib/src/controllers/presence_controller.dart`:

```dart
import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

class PresenceController {
  final De1Controller _de1Controller;
  final SettingsController _settingsController;
  final Logger _log = Logger('PresenceController');

  De1Interface? _de1;
  StreamSubscription? _de1Subscription;
  StreamSubscription? _snapshotSubscription;

  Timer? _sleepTimer;
  Timer? _scheduleChecker;
  DateTime? _lastUserPresentSent;
  MachineState _currentMachineState = MachineState.sleeping;

  // Track which schedules have fired in the current minute to avoid re-triggering
  final Set<String> _firedScheduleIds = {};
  int _lastCheckedMinute = -1;

  PresenceController({
    required De1Controller de1Controller,
    required SettingsController settingsController,
  })  : _de1Controller = de1Controller,
        _settingsController = settingsController;

  void initialize() {
    _de1Subscription = _de1Controller.de1.listen(_onDe1Changed);
    _startScheduleChecker();
    _settingsController.addListener(_onSettingsChanged);
  }

  void dispose() {
    _de1Subscription?.cancel();
    _snapshotSubscription?.cancel();
    _sleepTimer?.cancel();
    _scheduleChecker?.cancel();
    _settingsController.removeListener(_onSettingsChanged);
  }

  /// Called by REST API handler and native UI NavigatorObserver.
  /// Returns seconds remaining on sleep timeout (or -1 if disabled).
  int heartbeat() {
    if (!_settingsController.userPresenceEnabled) return -1;
    if (_de1 == null) return -1;

    _sendUserPresentThrottled();
    _resetSleepTimer();

    final timeout = _settingsController.sleepTimeoutMinutes;
    if (timeout <= 0) return -1;
    return timeout * 60; // fresh timeout
  }

  void _onDe1Changed(De1Interface? de1) {
    _snapshotSubscription?.cancel();
    _de1 = de1;

    if (de1 != null) {
      _snapshotSubscription = de1.currentSnapshot.listen((snapshot) {
        _currentMachineState = snapshot.state.state;
      });
      _resetSleepTimer();
    } else {
      _sleepTimer?.cancel();
      _currentMachineState = MachineState.sleeping;
    }
  }

  void _sendUserPresentThrottled() {
    final now = DateTime.now();
    if (_lastUserPresentSent != null &&
        now.difference(_lastUserPresentSent!).inSeconds < 30) {
      _log.fine('Throttled userPresent (last sent ${now.difference(_lastUserPresentSent!).inSeconds}s ago)');
      return;
    }
    _lastUserPresentSent = now;
    _de1?.sendUserPresent();
    _log.info('Sent userPresent to DE1');
  }

  void _resetSleepTimer() {
    _sleepTimer?.cancel();
    final timeout = _settingsController.sleepTimeoutMinutes;
    if (timeout <= 0) return;

    _sleepTimer = Timer(Duration(minutes: timeout), _onSleepTimeout);
  }

  void _onSleepTimeout() {
    if (_de1 == null) return;

    // Only sleep if machine is idle (not during active operations)
    if (_currentMachineState == MachineState.idle ||
        _currentMachineState == MachineState.schedIdle) {
      _log.info('Sleep timeout fired — putting machine to sleep');
      _de1!.requestState(MachineState.sleeping);
    } else {
      _log.info('Sleep timeout fired but machine is in $_currentMachineState — restarting timer');
      _resetSleepTimer();
    }
  }

  void _startScheduleChecker() {
    _scheduleChecker = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkSchedules();
    });
  }

  void _checkSchedules() {
    if (_de1 == null) return;
    if (_currentMachineState != MachineState.sleeping) return;

    final now = DateTime.now();
    final currentMinute = now.hour * 60 + now.minute;

    // Reset fired set when minute changes
    if (currentMinute != _lastCheckedMinute) {
      _firedScheduleIds.clear();
      _lastCheckedMinute = currentMinute;
    }

    final schedulesJson = _settingsController.wakeSchedules;
    List<WakeSchedule> schedules;
    try {
      schedules = WakeSchedule.deserializeList(schedulesJson);
    } catch (e) {
      _log.warning('Failed to parse wake schedules: $e');
      return;
    }

    for (final schedule in schedules) {
      if (_firedScheduleIds.contains(schedule.id)) continue;
      if (schedule.matchesTime(now)) {
        _log.info('Wake schedule "${schedule.id}" fired at ${schedule.hour}:${schedule.minute}');
        _firedScheduleIds.add(schedule.id);
        _de1!.requestState(MachineState.schedIdle);
        return; // Only fire one schedule per check
      }
    }
  }

  void _onSettingsChanged() {
    // Reset sleep timer if timeout changed
    if (_de1 != null) {
      _resetSleepTimer();
    }
  }
}
```

**Step 4: Write proper tests using fakeAsync**

The test file needs to exercise:
- `heartbeat()` throttling (two calls within 30s → 1 MMR write)
- `heartbeat()` after 30s → second MMR write
- Sleep timeout fires after configured duration
- Sleep timeout disabled when set to 0
- Sleep timeout restarts if machine is in active state
- Schedule checker wakes sleeping machine at matching time
- Schedule checker does not wake non-sleeping machine
- Disconnected DE1 → no crashes, graceful no-ops

**Step 5: Run tests to verify they pass**

Run: `flutter test test/controllers/presence_controller_test.dart`
Expected: All tests PASS.

**Step 6: Run full test suite**

Run: `flutter analyze && flutter test`
Expected: No errors.

**Step 7: Commit**

```bash
git add lib/src/controllers/presence_controller.dart \
  test/controllers/presence_controller_test.dart
git commit -m "feat: add PresenceController with heartbeat, sleep timeout, and scheduled wake"
```

---

### Task 5: REST API Handler

**Files:**
- Create: `lib/src/services/webserver/presence_handler.dart`
- Modify: `lib/src/services/webserver_service.dart` (register handler)

**Step 1: Create the handler**

Create `lib/src/services/webserver/presence_handler.dart`:

```dart
part of '../webserver_service.dart';

class PresenceHandler {
  final PresenceController _presenceController;
  final SettingsController _settingsController;
  final log = Logger('PresenceHandler');

  PresenceHandler({
    required PresenceController presenceController,
    required SettingsController settingsController,
  })  : _presenceController = presenceController,
        _settingsController = settingsController;

  void addRoutes(RouterPlus app) {
    app.post('/api/v1/machine/heartbeat', _heartbeatHandler);
    app.get('/api/v1/presence/settings', _getSettingsHandler);
    app.post('/api/v1/presence/settings', _updateSettingsHandler);
    app.get('/api/v1/presence/schedules', _getSchedulesHandler);
    app.post('/api/v1/presence/schedules', _addScheduleHandler);
    app.put('/api/v1/presence/schedules/<id>', _updateScheduleHandler);
    app.delete('/api/v1/presence/schedules/<id>', _deleteScheduleHandler);
  }

  Future<Response> _heartbeatHandler(Request request) async {
    final secondsRemaining = _presenceController.heartbeat();
    return Response.ok(jsonEncode({'timeout': secondsRemaining}));
  }

  Future<Response> _getSettingsHandler(Request request) async {
    final schedules = WakeSchedule.deserializeList(
      _settingsController.wakeSchedules,
    );
    return Response.ok(jsonEncode({
      'userPresenceEnabled': _settingsController.userPresenceEnabled,
      'sleepTimeoutMinutes': _settingsController.sleepTimeoutMinutes,
      'schedules': schedules.map((s) => s.toJson()).toList(),
    }));
  }

  Future<Response> _updateSettingsHandler(Request request) async {
    final body = jsonDecode(await request.readAsString());
    if (body['userPresenceEnabled'] != null) {
      await _settingsController.setUserPresenceEnabled(body['userPresenceEnabled'] as bool);
    }
    if (body['sleepTimeoutMinutes'] != null) {
      await _settingsController.setSleepTimeoutMinutes(body['sleepTimeoutMinutes'] as int);
    }
    return Response(202);
  }

  Future<Response> _getSchedulesHandler(Request request) async {
    final schedules = WakeSchedule.deserializeList(
      _settingsController.wakeSchedules,
    );
    return Response.ok(jsonEncode(schedules.map((s) => s.toJson()).toList()));
  }

  Future<Response> _addScheduleHandler(Request request) async {
    final body = jsonDecode(await request.readAsString());
    final newSchedule = WakeSchedule.fromJson(body as Map<String, dynamic>);
    final schedules = WakeSchedule.deserializeList(
      _settingsController.wakeSchedules,
    );
    schedules.add(newSchedule);
    await _settingsController.setWakeSchedules(WakeSchedule.serializeList(schedules));
    return Response(201, body: jsonEncode(newSchedule.toJson()));
  }

  Future<Response> _updateScheduleHandler(Request request, String id) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final schedules = WakeSchedule.deserializeList(
      _settingsController.wakeSchedules,
    );
    final index = schedules.indexWhere((s) => s.id == id);
    if (index == -1) {
      return Response.notFound(jsonEncode({'error': 'Schedule not found'}));
    }
    body['id'] = id; // Ensure ID stays the same
    schedules[index] = WakeSchedule.fromJson(body);
    await _settingsController.setWakeSchedules(WakeSchedule.serializeList(schedules));
    return Response.ok(jsonEncode(schedules[index].toJson()));
  }

  Future<Response> _deleteScheduleHandler(Request request, String id) async {
    final schedules = WakeSchedule.deserializeList(
      _settingsController.wakeSchedules,
    );
    final removed = schedules.removeWhere((s) => s.id == id);
    await _settingsController.setWakeSchedules(WakeSchedule.serializeList(schedules));
    return Response.ok('');
  }
}
```

**Step 2: Register in `webserver_service.dart`**

Add to the part directives:
```dart
part 'webserver/presence_handler.dart';
```

Add import for `PresenceController` and `WakeSchedule` at top of file.

Add `PresenceController` parameter to `startWebServer()`:
```dart
Future<void> startWebServer(
  // ... existing params ...
  PresenceController? presenceController,
) async {
```

Add handler instantiation and registration inside `_init()`:
```dart
  if (presenceController != null) {
    final presenceHandler = PresenceHandler(
      presenceController: presenceController,
      settingsController: settingsController,
    );
    presenceHandler.addRoutes(app);
  }
```

**Step 3: Run analyzer**

Run: `flutter analyze`
Expected: No errors. (Will have a call-site error in `main.dart` — addressed in Task 6.)

**Step 4: Commit**

```bash
git add lib/src/services/webserver/presence_handler.dart \
  lib/src/services/webserver_service.dart
git commit -m "feat: add presence REST API handler (heartbeat, settings, schedules)"
```

---

### Task 6: Wire Up in main.dart

**Files:**
- Modify: `lib/main.dart`

**Step 1: Create and initialize PresenceController**

After the `De1Controller` creation and before `startWebServer()`:

```dart
final presenceController = PresenceController(
  de1Controller: de1Controller,
  settingsController: settingsController,
);
presenceController.initialize();
```

**Step 2: Pass to startWebServer**

Add `presenceController` to the `startWebServer()` call.

**Step 3: Run analyzer and tests**

Run: `flutter analyze && flutter test`
Expected: No errors, all tests pass.

**Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: wire up PresenceController in main.dart"
```

---

### Task 7: Presence Settings Page (Flutter UI)

**Files:**
- Create: `lib/src/settings/presence_settings_page.dart`
- Modify: `lib/src/settings/settings_view.dart` (add navigation)

**Step 1: Create the settings page**

Create `lib/src/settings/presence_settings_page.dart` following the `BatteryChargingSettingsPage` pattern. It should have:

1. **User Presence** ShadCard with `ShadSwitch` to enable/disable
2. **Sleep Timeout** ShadCard with `DropdownButton<int>` offering: Disabled (0), 15, 30, 45, 60 minutes
3. **Wake Schedules** ShadCard with:
   - List of existing schedules (time, days, enabled switch, delete button)
   - "Add schedule" button that shows a dialog with time picker and day-of-week toggles
   - Each schedule row: `ListTile` with time display, day chips, `ShadSwitch` for enable, `IconButton` for delete

Use `SettingsController` + `WakeSchedule.deserializeList/serializeList` for data.

Generate UUIDs for new schedules using `DateTime.now().millisecondsSinceEpoch.toRadixString(36)` or similar simple approach (no external package needed).

**Step 2: Add navigation in `settings_view.dart`**

Add a `_buildPresenceSection()` method following the `_buildBatterySection()` pattern:
- Icon: `Icons.schedule_outlined` or `Icons.access_time`
- Title: "Presence & Sleep"
- Subtitle: current status summary
- "Configure" button → `Navigator.push` to `PresenceSettingsPage`

Add the section call in the settings view's column of cards.

**Step 3: Run analyzer**

Run: `flutter analyze`
Expected: No errors.

**Step 4: Commit**

```bash
git add lib/src/settings/presence_settings_page.dart \
  lib/src/settings/settings_view.dart
git commit -m "feat: add Presence & Sleep settings page with schedule management UI"
```

---

### Task 8: Native UI Heartbeat via NavigatorObserver

**Files:**
- Create: `lib/src/controllers/presence_navigator_observer.dart`
- Modify: `lib/main.dart` (register observer)

**Step 1: Create the observer**

Create `lib/src/controllers/presence_navigator_observer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/presence_controller.dart';

class PresenceNavigatorObserver extends NavigatorObserver {
  final PresenceController _presenceController;

  PresenceNavigatorObserver({required PresenceController presenceController})
      : _presenceController = presenceController;

  @override
  void didPush(Route route, Route? previousRoute) {
    _presenceController.heartbeat();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _presenceController.heartbeat();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _presenceController.heartbeat();
  }
}
```

**Step 2: Register in the MaterialApp**

In `lib/main.dart`, find where `MaterialApp` (or `ShadApp`) is constructed. Add the observer to its `navigatorObservers` list:

```dart
navigatorObservers: [
  PresenceNavigatorObserver(presenceController: presenceController),
  // ... any existing observers
],
```

This requires `presenceController` to be accessible where the app widget is built. It may need to be passed down or stored in a way the widget tree can access. Follow the existing pattern for how other controllers are passed to widgets (likely via constructor or a provider pattern).

**Step 3: Run analyzer and tests**

Run: `flutter analyze && flutter test`
Expected: No errors.

**Step 4: Commit**

```bash
git add lib/src/controllers/presence_navigator_observer.dart lib/main.dart
git commit -m "feat: add NavigatorObserver for native UI heartbeat on route changes"
```

---

### Task 9: Settings Plugin Update

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`
- Modify: `assets/plugins/settings.reaplugin/manifest.json`

**Step 1: Add fetch function in `plugin.js`**

Add a new fetch function following the existing pattern (like `fetchReaSettings`):

```javascript
async function fetchPresenceSettings() {
  try {
    const res = await fetch("http://localhost:8080/api/v1/presence/settings");
    if (!res.ok) {
      log(`Failed to fetch presence settings: ${res.status}`);
      return null;
    }
    return await res.json();
  } catch (e) {
    log(`Error fetching presence settings: ${e.message}`);
    return null;
  }
}
```

**Step 2: Add HTML rendering section**

In the `buildSettingsHtml` function (or equivalent), add a new section that renders:
- User presence enabled/disabled
- Sleep timeout (minutes or "Disabled")
- Wake schedules table: time, days, enabled

Follow the existing HTML table/card pattern used for other settings.

**Step 3: Call the fetch in the refresh cycle**

Add `fetchPresenceSettings()` to the data-fetching section alongside the existing fetches.

**Step 4: Bump manifest version**

In `assets/plugins/settings.reaplugin/manifest.json`, change:
```json
"version": "0.0.13"
```

**Step 5: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js \
  assets/plugins/settings.reaplugin/manifest.json
git commit -m "feat: add presence & schedule section to settings plugin (v0.0.13)"
```

---

### Task 10: API Documentation

**Files:**
- Modify: `assets/api/rest_v1.yml`

**Step 1: Document new endpoints**

Add OpenAPI spec entries for all new endpoints:
- `POST /api/v1/machine/heartbeat`
- `GET /api/v1/presence/settings`
- `POST /api/v1/presence/settings`
- `GET /api/v1/presence/schedules`
- `POST /api/v1/presence/schedules`
- `PUT /api/v1/presence/schedules/{id}`
- `DELETE /api/v1/presence/schedules/{id}`

Follow the existing YAML formatting pattern in the file.

**Step 2: Commit**

```bash
git add assets/api/rest_v1.yml
git commit -m "docs: add presence API endpoints to OpenAPI spec"
```

---

### Task 11: Final Verification

**Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests PASS.

**Step 2: Run analyzer**

Run: `flutter analyze`
Expected: No issues.

**Step 3: Run app with simulated devices**

Run: `flutter run --dart-define=simulate=1`
Verify:
- App starts without errors
- Settings page shows "Presence & Sleep" section
- Navigating to presence settings page works
- Adding/removing wake schedules persists
- Sleep timeout dropdown works

**Step 4: Test heartbeat API**

With app running:
```bash
curl -X POST http://localhost:8080/api/v1/machine/heartbeat
# Expected: {"timeout": 1800} (or -1 if disabled)

curl http://localhost:8080/api/v1/presence/settings
# Expected: {"userPresenceEnabled":true,"sleepTimeoutMinutes":30,"schedules":[]}

curl -X POST http://localhost:8080/api/v1/presence/schedules \
  -H 'Content-Type: application/json' \
  -d '{"id":"test1","time":"07:00","daysOfWeek":[1,2,3,4,5],"enabled":true}'
# Expected: 201 with schedule JSON
```

**Step 5: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: address issues found during final verification"
```
