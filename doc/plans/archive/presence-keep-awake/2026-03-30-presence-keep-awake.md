# Presence Keep-Awake Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional `keepAwakeFor` duration to wake schedules so the machine stays awake for a configured time after a scheduled wake.

**Architecture:** The `WakeSchedule` model gains a nullable `keepAwakeFor` field (int?, 1–720 minutes). When `PresenceController` fires a schedule with `keepAwakeFor`, it sets an in-memory `_keepAwakeUntil` timestamp. `_onSleepTimeout()` checks this timestamp and suppresses sleep while the window is active. The REST API and UI pass through the new field.

**Tech Stack:** Dart/Flutter, fakeAsync for tests, shadcn_ui for UI components.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/src/models/wake_schedule.dart` | Modify | Add `keepAwakeFor` field, serialization, validation |
| `lib/src/controllers/presence_controller.dart` | Modify | Add `_keepAwakeUntil`, suppress sleep logic, clear on manual sleep, expose status |
| `lib/src/services/webserver/presence_handler.dart` | Modify | Pass through `keepAwakeFor` in schedule CRUD, expose `keepAwakeUntil` in settings |
| `lib/src/settings/presence_settings_page.dart` | Modify | Number input for `keepAwakeFor`, active keep-awake indicator |
| `test/models/wake_schedule_test.dart` | Modify | Tests for new field |
| `test/controllers/presence_controller_test.dart` | Modify | Tests for keep-awake suppression logic |
| `assets/api/rest_v1.yml` | Modify | Document new fields |

---

### Task 1: WakeSchedule Model — Add `keepAwakeFor` Field

**Files:**
- Modify: `lib/src/models/wake_schedule.dart`
- Modify: `test/models/wake_schedule_test.dart`

- [ ] **Step 1: Write failing tests for `keepAwakeFor` serialization**

Add to `test/models/wake_schedule_test.dart`, inside the existing `group('toJson', ...)`:

```dart
test('includes keepAwakeFor when set', () {
  final schedule = WakeSchedule(
    id: 'test-id',
    hour: 10,
    minute: 0,
    daysOfWeek: {1, 3},
    enabled: true,
    keepAwakeFor: 60,
  );

  final json = schedule.toJson();
  expect(json['keepAwakeFor'], 60);
});

test('omits keepAwakeFor when null', () {
  final schedule = WakeSchedule(
    id: 'test-id',
    hour: 10,
    minute: 0,
    daysOfWeek: {},
    enabled: true,
  );

  final json = schedule.toJson();
  expect(json.containsKey('keepAwakeFor'), isFalse);
});
```

Add inside `group('fromJson', ...)`:

```dart
test('parses keepAwakeFor when present', () {
  final json = {
    'id': 'test-id',
    'time': '10:00',
    'daysOfWeek': [1, 3],
    'enabled': true,
    'keepAwakeFor': 60,
  };

  final schedule = WakeSchedule.fromJson(json);
  expect(schedule.keepAwakeFor, 60);
});

test('keepAwakeFor is null when absent from JSON', () {
  final json = {
    'id': 'test-id',
    'time': '10:00',
    'daysOfWeek': <int>[],
    'enabled': true,
  };

  final schedule = WakeSchedule.fromJson(json);
  expect(schedule.keepAwakeFor, isNull);
});

test('keepAwakeFor 0 is treated as null', () {
  final json = {
    'id': 'test-id',
    'time': '10:00',
    'daysOfWeek': <int>[],
    'enabled': true,
    'keepAwakeFor': 0,
  };

  final schedule = WakeSchedule.fromJson(json);
  expect(schedule.keepAwakeFor, isNull);
});
```

Add inside `group('toJson/fromJson round-trip', ...)`:

```dart
test('preserves keepAwakeFor through round-trip', () {
  final original = WakeSchedule(
    id: 'keep-awake-id',
    hour: 10,
    minute: 0,
    daysOfWeek: {1, 3},
    enabled: true,
    keepAwakeFor: 120,
  );

  final restored = WakeSchedule.fromJson(original.toJson());
  expect(restored.keepAwakeFor, 120);
});

test('preserves null keepAwakeFor through round-trip', () {
  final original = WakeSchedule(
    id: 'no-keep-awake-id',
    hour: 10,
    minute: 0,
    daysOfWeek: {},
    enabled: true,
  );

  final restored = WakeSchedule.fromJson(original.toJson());
  expect(restored.keepAwakeFor, isNull);
});
```

Add inside `group('copyWith', ...)`:

```dart
test('can set keepAwakeFor', () {
  final original = WakeSchedule(
    id: 'test-id',
    hour: 10,
    minute: 0,
    daysOfWeek: {},
    enabled: true,
  );

  final modified = original.copyWith(keepAwakeFor: 60);
  expect(modified.keepAwakeFor, 60);
});

test('can clear keepAwakeFor to null', () {
  final original = WakeSchedule(
    id: 'test-id',
    hour: 10,
    minute: 0,
    daysOfWeek: {},
    enabled: true,
    keepAwakeFor: 60,
  );

  // Use a sentinel to distinguish "not provided" from "set to null"
  final modified = original.copyWith(clearKeepAwakeFor: true);
  expect(modified.keepAwakeFor, isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/models/wake_schedule_test.dart`
Expected: Compilation errors — `keepAwakeFor` parameter doesn't exist yet.

- [ ] **Step 3: Implement `keepAwakeFor` in WakeSchedule**

In `lib/src/models/wake_schedule.dart`:

Add the field to the class (after `enabled`):

```dart
final int? keepAwakeFor; // minutes, 1–720, null = wake only
```

Update the constructor to accept `this.keepAwakeFor`:

```dart
const WakeSchedule({
  required this.id,
  required this.hour,
  required this.minute,
  required this.daysOfWeek,
  required this.enabled,
  this.keepAwakeFor,
});
```

Update `create()` factory:

```dart
factory WakeSchedule.create({
  required int hour,
  required int minute,
  Set<int> daysOfWeek = const {},
  bool enabled = true,
  int? keepAwakeFor,
}) {
  return WakeSchedule(
    id: const Uuid().v4(),
    hour: hour,
    minute: minute,
    daysOfWeek: daysOfWeek,
    enabled: enabled,
    keepAwakeFor: keepAwakeFor != null && keepAwakeFor > 0 ? keepAwakeFor : null,
  );
}
```

Update `fromJson()` — parse `keepAwakeFor`, treat 0 as null:

```dart
factory WakeSchedule.fromJson(Map<String, dynamic> json) {
  final timeParts = (json['time'] as String).split(':');
  final days = (json['daysOfWeek'] as List).cast<int>();
  final keepAwake = json['keepAwakeFor'] as int?;

  return WakeSchedule(
    id: json['id'] as String,
    hour: int.parse(timeParts[0]),
    minute: int.parse(timeParts[1]),
    daysOfWeek: days.toSet(),
    enabled: json['enabled'] as bool,
    keepAwakeFor: keepAwake != null && keepAwake > 0 ? keepAwake : null,
  );
}
```

Update `toJson()` — only include `keepAwakeFor` if non-null:

```dart
Map<String, dynamic> toJson() {
  final json = {
    'id': id,
    'time':
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
    'daysOfWeek': daysOfWeek.toList()..sort(),
    'enabled': enabled,
  };
  if (keepAwakeFor != null) {
    json['keepAwakeFor'] = keepAwakeFor;
  }
  return json;
}
```

Update `copyWith()` — use `clearKeepAwakeFor` sentinel to allow setting to null:

```dart
WakeSchedule copyWith({
  String? id,
  int? hour,
  int? minute,
  Set<int>? daysOfWeek,
  bool? enabled,
  int? keepAwakeFor,
  bool clearKeepAwakeFor = false,
}) {
  return WakeSchedule(
    id: id ?? this.id,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    enabled: enabled ?? this.enabled,
    keepAwakeFor: clearKeepAwakeFor ? null : (keepAwakeFor ?? this.keepAwakeFor),
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/models/wake_schedule_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/models/wake_schedule.dart test/models/wake_schedule_test.dart
git commit -m "feat: add keepAwakeFor field to WakeSchedule model

Adds optional keepAwakeFor (minutes, 1-720) to WakeSchedule.
Null or 0 means wake-only (current behavior). Serialized to JSON
only when non-null for backward compatibility."
```

---

### Task 2: PresenceController — Keep-Awake Suppression Logic

**Files:**
- Modify: `lib/src/controllers/presence_controller.dart`
- Modify: `test/controllers/presence_controller_test.dart`

- [ ] **Step 1: Write failing tests for keep-awake behavior**

Add to `test/controllers/presence_controller_test.dart`, new group after `'settings change'`:

```dart
group('keep-awake window', () {
  test('schedule with keepAwakeFor suppresses sleep timeout', () {
    fakeAsync((async) {
      settingsController.setSleepTimeoutMinutes(5);
      async.flushMicrotasks();

      // Schedule at 07:00 with 60 min keep-awake
      final schedule = WakeSchedule(
        id: 'keep-awake-1',
        hour: 7,
        minute: 0,
        daysOfWeek: {},
        enabled: true,
        keepAwakeFor: 60,
      );
      settingsController
          .setWakeSchedules(WakeSchedule.serializeList([schedule]));
      async.flushMicrotasks();

      final controller = PresenceController(
        de1Controller: de1Controller,
        settingsController: settingsController,
        clock: () => DateTime(2026, 1, 15, 6, 59),
      );
      controller.initialize();
      de1Controller.setDe1(testDe1);
      async.flushMicrotasks();

      // Put machine to sleep so schedule can fire
      testDe1.emitState(MachineState.sleeping);
      async.flushMicrotasks();

      // Move clock to 07:00 and fire schedule checker
      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 0);
      async.elapse(const Duration(seconds: 31));

      // Machine should have woken up
      expect(testDe1.requestedStates, contains(MachineState.schedIdle));

      // Now send a heartbeat to start the sleep timer
      controller.heartbeat();
      async.flushMicrotasks();

      // Advance past sleep timeout (5 min) but within keep-awake (60 min)
      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 6);
      async.elapse(const Duration(minutes: 5, seconds: 1));

      // Should NOT have gone to sleep — keep-awake active
      expect(
        testDe1.requestedStates.where((s) => s == MachineState.sleeping),
        isEmpty,
        reason: 'Keep-awake window should suppress sleep timeout',
      );

      controller.dispose();
    });
  });

  test('sleep timeout fires after keep-awake window expires', () {
    fakeAsync((async) {
      settingsController.setSleepTimeoutMinutes(5);
      async.flushMicrotasks();

      // Schedule at 07:00 with 10 min keep-awake
      final schedule = WakeSchedule(
        id: 'keep-awake-2',
        hour: 7,
        minute: 0,
        daysOfWeek: {},
        enabled: true,
        keepAwakeFor: 10,
      );
      settingsController
          .setWakeSchedules(WakeSchedule.serializeList([schedule]));
      async.flushMicrotasks();

      final controller = PresenceController(
        de1Controller: de1Controller,
        settingsController: settingsController,
        clock: () => DateTime(2026, 1, 15, 6, 59),
      );
      controller.initialize();
      de1Controller.setDe1(testDe1);
      async.flushMicrotasks();

      testDe1.emitState(MachineState.sleeping);
      async.flushMicrotasks();

      // Fire schedule at 07:00
      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 0);
      async.elapse(const Duration(seconds: 31));
      expect(testDe1.requestedStates, contains(MachineState.schedIdle));

      // Heartbeat to start sleep timer
      controller.heartbeat();
      async.flushMicrotasks();

      // Advance past keep-awake (10 min) and then past sleep timeout (5 more)
      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 16);
      async.elapse(const Duration(minutes: 15, seconds: 1));

      // Now sleep should have fired
      expect(testDe1.requestedStates, contains(MachineState.sleeping));

      controller.dispose();
    });
  });

  test('manual sleep during keep-awake clears the window', () {
    fakeAsync((async) {
      settingsController.setSleepTimeoutMinutes(5);
      async.flushMicrotasks();

      final schedule = WakeSchedule(
        id: 'keep-awake-3',
        hour: 7,
        minute: 0,
        daysOfWeek: {},
        enabled: true,
        keepAwakeFor: 60,
      );
      settingsController
          .setWakeSchedules(WakeSchedule.serializeList([schedule]));
      async.flushMicrotasks();

      final controller = PresenceController(
        de1Controller: de1Controller,
        settingsController: settingsController,
        clock: () => DateTime(2026, 1, 15, 6, 59),
      );
      controller.initialize();
      de1Controller.setDe1(testDe1);
      async.flushMicrotasks();

      testDe1.emitState(MachineState.sleeping);
      async.flushMicrotasks();

      // Fire schedule
      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 0);
      async.elapse(const Duration(seconds: 31));

      // Verify keep-awake is active
      expect(controller.keepAwakeUntil, isNotNull);

      // User manually puts machine to sleep
      testDe1.emitState(MachineState.sleeping);
      async.flushMicrotasks();

      // Keep-awake should be cleared
      expect(controller.keepAwakeUntil, isNull);

      controller.dispose();
    });
  });

  test('schedule without keepAwakeFor does not set keep-awake', () {
    fakeAsync((async) {
      settingsController.setSleepTimeoutMinutes(5);
      async.flushMicrotasks();

      final schedule = WakeSchedule(
        id: 'no-keep-awake',
        hour: 7,
        minute: 0,
        daysOfWeek: {},
        enabled: true,
        // no keepAwakeFor
      );
      settingsController
          .setWakeSchedules(WakeSchedule.serializeList([schedule]));
      async.flushMicrotasks();

      final controller = PresenceController(
        de1Controller: de1Controller,
        settingsController: settingsController,
        clock: () => DateTime(2026, 1, 15, 6, 59),
      );
      controller.initialize();
      de1Controller.setDe1(testDe1);
      async.flushMicrotasks();

      testDe1.emitState(MachineState.sleeping);
      async.flushMicrotasks();

      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 0);
      async.elapse(const Duration(seconds: 31));

      expect(controller.keepAwakeUntil, isNull);

      controller.dispose();
    });
  });

  test('later schedule extends keep-awake if expiry is further', () {
    fakeAsync((async) {
      settingsController.setSleepTimeoutMinutes(5);
      async.flushMicrotasks();

      // Two schedules at same time, different keepAwakeFor
      final schedules = [
        WakeSchedule(
          id: 'short',
          hour: 7,
          minute: 0,
          daysOfWeek: {},
          enabled: true,
          keepAwakeFor: 30,
        ),
        WakeSchedule(
          id: 'long',
          hour: 7,
          minute: 1,
          daysOfWeek: {},
          enabled: true,
          keepAwakeFor: 120,
        ),
      ];
      settingsController
          .setWakeSchedules(WakeSchedule.serializeList(schedules));
      async.flushMicrotasks();

      final controller = PresenceController(
        de1Controller: de1Controller,
        settingsController: settingsController,
        clock: () => DateTime(2026, 1, 15, 6, 59),
      );
      controller.initialize();
      de1Controller.setDe1(testDe1);
      async.flushMicrotasks();

      testDe1.emitState(MachineState.sleeping);
      async.flushMicrotasks();

      // Fire first schedule at 07:00
      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 0);
      async.elapse(const Duration(seconds: 31));

      final firstExpiry = controller.keepAwakeUntil;
      expect(firstExpiry, isNotNull);

      // Machine goes back to sleep (simulating), then second schedule fires at 07:01
      testDe1.emitState(MachineState.sleeping);
      async.flushMicrotasks();

      // Note: manual sleep cleared keepAwakeUntil, so second schedule fires fresh
      controller.clockOverride = () => DateTime(2026, 1, 15, 7, 1);
      async.elapse(const Duration(seconds: 31));

      final secondExpiry = controller.keepAwakeUntil;
      expect(secondExpiry, isNotNull);
      // Second expiry (07:01 + 120 min = 09:01) is after first (07:00 + 30 = 07:30)
      expect(secondExpiry!.isAfter(firstExpiry!), isTrue);

      controller.dispose();
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/controllers/presence_controller_test.dart`
Expected: Compilation errors — `keepAwakeUntil` getter doesn't exist.

- [ ] **Step 3: Implement keep-awake logic in PresenceController**

In `lib/src/controllers/presence_controller.dart`:

Add new state field after `_lastCheckedMinute` (line 49):

```dart
/// Timestamp when the current keep-awake window expires. Null = no active window.
DateTime? _keepAwakeUntil;

/// Exposes the keep-awake expiry for API/UI. Null if no window is active.
DateTime? get keepAwakeUntil => _keepAwakeUntil;
```

Update `_onSnapshot()` (line 123) to detect manual sleep and clear keep-awake:

```dart
void _onSnapshot(MachineSnapshot snapshot) {
  final newState = snapshot.state.state;
  // If machine transitions to sleeping while keep-awake is active, clear it
  if (newState == MachineState.sleeping &&
      _currentMachineState != MachineState.sleeping &&
      _keepAwakeUntil != null) {
    _log.info('Machine went to sleep during keep-awake window, clearing');
    _keepAwakeUntil = null;
  }
  _currentMachineState = newState;
}
```

Update `_onSleepTimeout()` (line 180) to check keep-awake before sleeping:

```dart
void _onSleepTimeout() {
  if (_de1 == null) return;

  // If keep-awake window is active, suppress sleep and restart timer
  if (_keepAwakeUntil != null && _clock().isBefore(_keepAwakeUntil!)) {
    _log.info('Sleep timeout suppressed by keep-awake (until $_keepAwakeUntil)');
    _resetSleepTimer();
    return;
  }

  // Clear expired keep-awake
  if (_keepAwakeUntil != null) {
    _log.info('Keep-awake window expired');
    _keepAwakeUntil = null;
  }

  // If machine is in an active state, restart the timer instead of sleeping
  if (_isActiveState(_currentMachineState)) {
    _log.info(
        'Sleep timeout fired but machine is in active state ($_currentMachineState), restarting timer');
    _resetSleepTimer();
    return;
  }

  // If machine is in idle or schedIdle, put it to sleep
  if (_currentMachineState == MachineState.idle ||
      _currentMachineState == MachineState.schedIdle) {
    _log.info('Sleep timeout fired, putting machine to sleep');
    _de1!.requestState(MachineState.sleeping).catchError((e) {
      _log.warning('Failed to request sleep: $e');
    });
  }
}
```

Update `_checkSchedules()` — after waking, set `_keepAwakeUntil` if schedule has `keepAwakeFor`. Replace the block inside the `if (schedule.matchesTime(now))` (around line 264):

```dart
if (schedule.matchesTime(now)) {
  _log.info(
      'Schedule ${schedule.id} matched at ${now.hour}:${now.minute}, waking machine');
  _firedScheduleIds.add(schedule.id);
  _de1!.requestState(MachineState.schedIdle).catchError((e) {
    _log.warning('Failed to request schedIdle: $e');
  });

  // Set keep-awake window if configured
  if (schedule.keepAwakeFor != null) {
    final newExpiry = now.add(Duration(minutes: schedule.keepAwakeFor!));
    if (_keepAwakeUntil == null || newExpiry.isAfter(_keepAwakeUntil!)) {
      _keepAwakeUntil = newExpiry;
      _log.info('Keep-awake window set until $_keepAwakeUntil');
    }
  }

  break; // One wake per check cycle
}
```

Also clean up `_keepAwakeUntil` in `_onDe1Changed()` (line 110 area) and `dispose()`:

In `_onDe1Changed`, add after `_lastPresenceSent = null;`:
```dart
_keepAwakeUntil = null;
```

In `dispose()`, add after `_scheduleTimer = null;`:
```dart
_keepAwakeUntil = null;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/controllers/presence_controller_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS (existing tests unaffected).

- [ ] **Step 6: Commit**

```bash
git add lib/src/controllers/presence_controller.dart test/controllers/presence_controller_test.dart
git commit -m "feat: implement keep-awake suppression in PresenceController

When a schedule with keepAwakeFor fires, auto-sleep is suppressed
for the configured duration. Manual sleep clears the window.
Exposes keepAwakeUntil getter for API/UI consumption."
```

---

### Task 3: Presence Handler — API Changes

**Files:**
- Modify: `lib/src/services/webserver/presence_handler.dart`

- [ ] **Step 1: Update `_getSettingsHandler` to include `keepAwakeUntil`**

In `presence_handler.dart`, update the `_getSettingsHandler` return (around line 49):

```dart
return jsonOk({
  'userPresenceEnabled': _settingsController.userPresenceEnabled,
  'sleepTimeoutMinutes': _settingsController.sleepTimeoutMinutes,
  'keepAwakeUntil': _presenceController.keepAwakeUntil?.toIso8601String(),
  'schedules': schedules,
});
```

- [ ] **Step 2: Update `_addScheduleHandler` to accept `keepAwakeFor`**

In `_addScheduleHandler` (around line 110), update the `WakeSchedule.create()` call:

```dart
final keepAwakeFor = json['keepAwakeFor'] as int?;
if (keepAwakeFor != null && (keepAwakeFor < 0 || keepAwakeFor > 720)) {
  return Response(400,
      body: jsonEncode({'error': 'keepAwakeFor must be 0-720 minutes'}),
      headers: {'content-type': 'application/json'});
}

final schedule = WakeSchedule.create(
  hour: json['hour'] as int? ??
      int.parse((json['time'] as String).split(':')[0]),
  minute: json['minute'] as int? ??
      int.parse((json['time'] as String).split(':')[1]),
  daysOfWeek: json.containsKey('daysOfWeek')
      ? (json['daysOfWeek'] as List).cast<int>().toSet()
      : {},
  enabled: json['enabled'] as bool? ?? true,
  keepAwakeFor: keepAwakeFor,
);
```

- [ ] **Step 3: Update `_updateScheduleHandler` to handle `keepAwakeFor`**

In `_updateScheduleHandler` (around line 167), after the `minute` parsing block and before the `copyWith` call, add:

```dart
int? keepAwakeFor = existing.keepAwakeFor;
bool clearKeepAwakeFor = false;
if (json.containsKey('keepAwakeFor')) {
  final val = json['keepAwakeFor'] as int?;
  if (val != null && (val < 0 || val > 720)) {
    return Response(400,
        body: jsonEncode({'error': 'keepAwakeFor must be 0-720 minutes'}),
        headers: {'content-type': 'application/json'});
  }
  if (val == null || val == 0) {
    clearKeepAwakeFor = true;
    keepAwakeFor = null;
  } else {
    keepAwakeFor = val;
  }
}
```

Then update the `copyWith` call:

```dart
final updated = existing.copyWith(
  hour: hour,
  minute: minute,
  daysOfWeek: json.containsKey('daysOfWeek')
      ? (json['daysOfWeek'] as List).cast<int>().toSet()
      : null,
  enabled: json.containsKey('enabled') ? json['enabled'] as bool : null,
  keepAwakeFor: keepAwakeFor,
  clearKeepAwakeFor: clearKeepAwakeFor,
);
```

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/services/webserver/presence_handler.dart
git commit -m "feat: expose keepAwakeFor in presence schedule REST API

Schedule create/update endpoints accept keepAwakeFor (0-720 min).
GET settings now includes keepAwakeUntil ISO 8601 timestamp when
a keep-awake window is active."
```

---

### Task 4: UI — Keep-Awake Duration Input

**Files:**
- Modify: `lib/src/settings/presence_settings_page.dart`

- [ ] **Step 1: Add keep-awake number input to schedule row**

In `lib/src/settings/presence_settings_page.dart`, in `_buildScheduleRow()`, add after the day chips `Wrap` widget and before the "Tap to select specific days" section (after line 261):

```dart
// Keep-awake duration input
Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Row(
    children: [
      Text(
        'Keep awake for',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 80,
        child: TextFormField(
          initialValue: schedule.keepAwakeFor?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '0',
            suffixText: 'min',
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: const OutlineInputBorder(),
          ),
          onFieldSubmitted: (value) {
            final minutes = int.tryParse(value);
            if (minutes != null && minutes > 720) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Maximum is 720 minutes (12 hours)')),
              );
              return;
            }
            final updated = schedules.map((s) {
              if (s.id == schedule.id) {
                if (minutes == null || minutes <= 0) {
                  return s.copyWith(clearKeepAwakeFor: true);
                }
                return s.copyWith(keepAwakeFor: minutes);
              }
              return s;
            }).toList();
            _saveSchedules(updated);
          },
        ),
      ),
    ],
  ),
),
```

- [ ] **Step 2: Add active keep-awake indicator to the wake schedules section**

In `_buildWakeSchedulesSection()`, add after the section description text and before `if (schedules.isNotEmpty)` (around line 176), add a builder that checks keep-awake status. Since `PresenceController` isn't directly available in the settings page, we need to add it.

First, update the widget constructor to optionally accept a `keepAwakeUntil`:

In the class definition, add a field:

```dart
class PresenceSettingsPage extends StatefulWidget {
  const PresenceSettingsPage({
    super.key,
    required this.controller,
    this.keepAwakeUntil,
  });

  final SettingsController controller;
  final DateTime? keepAwakeUntil;
```

Then in `_buildWakeSchedulesSection()`, after the description text (around line 176):

```dart
if (widget.keepAwakeUntil != null &&
    widget.keepAwakeUntil!.isAfter(DateTime.now())) ...[
  const SizedBox(height: 12),
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(Icons.coffee, color: Theme.of(context).colorScheme.onPrimaryContainer),
        const SizedBox(width: 8),
        Text(
          'Keeping awake until ${TimeOfDay.fromDateTime(widget.keepAwakeUntil!).format(context)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
        ),
      ],
    ),
  ),
],
```

- [ ] **Step 3: Update callers of `PresenceSettingsPage` to pass `keepAwakeUntil`**

Search for usages of `PresenceSettingsPage(` and add the `keepAwakeUntil` parameter. Since it's optional, existing callers still compile. If the caller has access to `PresenceController`, pass `presenceController.keepAwakeUntil`. If not, leave it as null (the indicator simply won't show).

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 5: Run app in simulate mode and verify UI**

Run: `flutter run --dart-define=simulate=1`
Verify:
- Schedule rows show the "Keep awake for ___ min" input
- Entering a value saves it (check via MCP or restart)
- Values > 720 show validation snackbar
- Empty/0 clears the field

- [ ] **Step 6: Commit**

```bash
git add lib/src/settings/presence_settings_page.dart
git commit -m "feat: add keep-awake duration input to presence settings UI

Number input with validation (max 720 min / 12 hours).
Shows active keep-awake indicator when a window is running."
```

---

### Task 5: API Documentation

**Files:**
- Modify: `assets/api/rest_v1.yml`

- [ ] **Step 1: Update WakeSchedule schema**

In `assets/api/rest_v1.yml`, find the `WakeSchedule` schema definition (around line 3945) and add `keepAwakeFor`:

```yaml
keepAwakeFor:
  type: integer
  nullable: true
  minimum: 1
  maximum: 720
  description: >
    Optional duration in minutes (1-720) to keep the machine awake after
    this schedule fires. During this window, the auto-sleep timeout is
    suppressed. Null or absent means wake-only (no keep-awake window).
```

- [ ] **Step 2: Update presence settings response schema**

Find the presence settings response schema and add `keepAwakeUntil`:

```yaml
keepAwakeUntil:
  type: string
  format: date-time
  nullable: true
  description: >
    ISO 8601 timestamp when the current keep-awake window expires.
    Null if no keep-awake window is active.
```

- [ ] **Step 3: Update schedule create/update request docs**

Add `keepAwakeFor` to the request body examples for POST and PUT schedule endpoints.

- [ ] **Step 4: Commit**

```bash
git add assets/api/rest_v1.yml
git commit -m "docs: document keepAwakeFor and keepAwakeUntil in API spec"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests PASS.

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Archive plan documents**

Move plan and spec:
```bash
mkdir -p doc/plans/archive/presence-keep-awake
mv docs/superpowers/specs/2026-03-30-presence-keep-awake-design.md doc/plans/archive/presence-keep-awake/
mv docs/superpowers/plans/2026-03-30-presence-keep-awake.md doc/plans/archive/presence-keep-awake/
```

- [ ] **Step 4: Commit archive move**

```bash
git add doc/plans/archive/presence-keep-awake/ docs/superpowers/
git commit -m "chore: archive presence keep-awake plan and spec"
```
