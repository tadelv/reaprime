# Android Foreground Service Fix (Issues #104 + #73)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Android foreground service lifecycle — correct permission sequencing, add graceful shutdown with 5-minute grace period after machine disconnect, clean up process exit, and prevent duplicate task/activity issues on Samsung OneUI.

**Architecture:** The foreground service keeps the app process alive for BLE connections. Currently it starts before permissions are granted (race condition), never stops unless explicitly exited, and the exit path does a hard `exit(0)`. This plan fixes permission ordering, adds auto-stop on disconnect with grace period, cleans up the exit path, and ensures the notification tap always surfaces the existing activity. All changes are Android-only — iOS background BLE (`bluetooth-central` mode) is unaffected.

**Tech Stack:** Flutter, Kotlin (Android native), `flutter_foreground_task` 9.2.0, `permission_handler`

**Scope note:** The Samsung OneUI rotation/MediaQuery bug from #73 is out of scope for this plan — it will be addressed separately.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/src/services/foreground_service.dart` | Modify | Add grace-period auto-stop, machine state listener, service self-cleanup |
| `lib/main.dart` | Modify | Move foreground service start to after permissions are granted |
| `lib/src/permissions_feature/permissions_view.dart` | Modify | Start foreground service after BLE permissions confirmed |
| `lib/src/home_feature/tiles/settings_tile.dart` | Modify | Replace `exit(0)` with graceful shutdown sequence |
| `android/app/src/main/kotlin/net/tadel/reaprime/MainActivity.kt` | Modify | Add `moveTaskToBack()` on back press, add `onDestroy` cleanup |
| `test/foreground_service_test.dart` | Create | Unit tests for grace period logic and lifecycle |

---

## Task 1: Fix Permission Sequencing — Move Foreground Service Start

**Problem:** `ForegroundTaskService.start()` is called in `main.dart:355-356` *before* `PermissionsView` requests `BLUETOOTH_CONNECT` and `POST_NOTIFICATIONS`. On Android 14+, starting a `connectedDevice` foreground service without `BLUETOOTH_CONNECT` granted throws `SecurityException`.

**Files:**
- Modify: `lib/main.dart:353-356`
- Modify: `lib/src/permissions_feature/permissions_view.dart:102-118`

- [ ] **Step 1: Remove early foreground service start from main.dart**

In `lib/main.dart`, remove the foreground service start from the pre-`runApp` block. Keep only `init()`:

```dart
if (Platform.isAndroid) {
  // Initialize foreground service config (but don't start yet — needs permissions first)
  ForegroundTaskService.init();
}
```

Remove `await ForegroundTaskService.start();` from this block.

- [ ] **Step 2: Start foreground service after permissions are granted**

In `lib/src/permissions_feature/permissions_view.dart`, add foreground service start after BLE + notification permissions are confirmed, inside `_checkPermissions()`. After the notification permission request (line 118) and before battery optimization (line 122):

```dart
// Start foreground service now that BLE + notification permissions are granted
await ForegroundTaskService.start();
```

Add the import at top of file:
```dart
import 'package:reaprime/src/services/foreground_service.dart';
```

- [ ] **Step 3: Verify the change doesn't break non-Android platforms**

The `ForegroundTaskService.start()` is only called inside the `if (Platform.isAndroid)` block in `_checkPermissions()`, so iOS/desktop paths are unaffected. Verify `_checkPermissions` flow:
- Android 12+: request bluetoothScan → bluetoothConnect → notification → **start foreground service** → battery optimization → continue
- iOS: request bluetooth → continue (no foreground service)
- Desktop: wait for BLE availability → continue (no foreground service)

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings or errors.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/src/permissions_feature/permissions_view.dart
git commit -m "fix: start foreground service after permissions are granted

Moves ForegroundTaskService.start() from main.dart (pre-runApp) to
PermissionsView._checkPermissions() after BLE and notification
permissions are confirmed. Fixes SecurityException on Android 14+
when BLUETOOTH_CONNECT is not yet granted at service start time.

Addresses #104"
```

---

## Task 2: Add Grace-Period Auto-Stop on Machine Disconnect

**Problem:** The foreground service runs indefinitely, even when no machine is connected. It should stop itself after a 5-minute grace period when the DE1 disconnects, and restart when a connection is re-established.

**Files:**
- Modify: `lib/src/services/foreground_service.dart`
- Test: `test/foreground_service_test.dart`

- [ ] **Step 1: Write failing test for grace period logic**

Create `test/foreground_service_test.dart`. Uses `fakeAsync` for deterministic timer testing:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/foreground_service.dart';

void main() {
  group('ForegroundServiceGraceTimer', () {
    late ForegroundServiceGraceTimer timer;
    bool stopCalled = false;
    bool startCalled = false;

    setUp(() {
      stopCalled = false;
      startCalled = false;
      timer = ForegroundServiceGraceTimer(
        gracePeriod: Duration(minutes: 5),
        onStop: () async { stopCalled = true; },
        onStart: () async { startCalled = true; },
      );
    });

    tearDown(() {
      timer.dispose();
    });

    test('does not stop immediately on disconnect', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        expect(stopCalled, isFalse);
      });
    });

    test('stops after grace period expires', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 5, seconds: 1));
        expect(stopCalled, isTrue);
      });
    });

    test('does not stop before grace period expires', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 4));
        expect(stopCalled, isFalse);
      });
    });

    test('cancels stop if machine reconnects during grace period', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 2));
        timer.onMachineConnected();
        async.elapse(Duration(minutes: 5));
        expect(stopCalled, isFalse);
      });
    });

    test('does not call onStart on connect if service was never stopped', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 2));
        timer.onMachineConnected();
        expect(startCalled, isFalse); // service was still running
      });
    });

    test('restarts service on connect if previously stopped', () {
      fakeAsync((async) {
        timer.onMachineDisconnected();
        async.elapse(Duration(minutes: 6));
        expect(stopCalled, isTrue);

        startCalled = false;
        timer.onMachineConnected();
        expect(startCalled, isTrue);
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/foreground_service_test.dart`
Expected: Compilation error — `ForegroundServiceGraceTimer` does not exist.

- [ ] **Step 3: Implement ForegroundServiceGraceTimer**

Add to `lib/src/services/foreground_service.dart`:

```dart
class ForegroundServiceGraceTimer {
  final Duration gracePeriod;
  final Future<void> Function() onStop;
  final Future<void> Function() onStart;
  final _log = Logger("ForegroundServiceGraceTimer");

  Timer? _graceTimer;
  bool _serviceStopped = false;

  ForegroundServiceGraceTimer({
    this.gracePeriod = const Duration(minutes: 5),
    required this.onStop,
    required this.onStart,
  });

  void onMachineConnected() {
    _graceTimer?.cancel();
    _graceTimer = null;

    if (_serviceStopped) {
      _log.info('Machine reconnected - restarting foreground service');
      _serviceStopped = false;
      onStart().catchError((e) =>
        _log.warning('Failed to restart foreground service: $e'));
    }
  }

  void onMachineDisconnected() {
    _graceTimer?.cancel();
    _log.info('Machine disconnected — starting ${gracePeriod.inMinutes}m grace period');
    _graceTimer = Timer(gracePeriod, () async {
      _log.info('Grace period expired — stopping foreground service');
      _serviceStopped = true;
      await onStop();
    });
  }

  void dispose() {
    _graceTimer?.cancel();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/foreground_service_test.dart`
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/foreground_service.dart test/foreground_service_test.dart
git commit -m "feat: add grace period auto-stop for foreground service

Adds ForegroundServiceGraceTimer that stops the foreground service
5 minutes after machine disconnect and restarts it on reconnect.
Saves battery when DE1 is not in use.

Addresses #104"
```

---

## Task 3: Wire Grace Timer to Machine Connection State

**Problem:** The grace timer exists but isn't connected to the actual machine connection/disconnection events.

**Files:**
- Modify: `lib/src/services/foreground_service.dart`
- Modify: `lib/src/permissions_feature/permissions_view.dart`

- [ ] **Step 1: Identify where machine connection state is broadcast**

The `De1Controller` exposes a `de1` stream (`BehaviorSubject<De1Interface?>`) that emits the current machine interface or `null` when disconnected. The `ConnectionManager` exposes `status` stream with `ConnectionStatus` phases. Either can drive the grace timer.

Use `De1Controller.de1` — it's the most direct signal: non-null = connected, null = disconnected.

- [ ] **Step 2: Add grace timer wiring in PermissionsView**

After the foreground service is started (added in Task 1), create and wire the grace timer. The timer needs to live for the app's lifetime, so store it on `ForegroundTaskService` as a static:

In `lib/src/services/foreground_service.dart`, add a static method:

```dart
import 'dart:async';

class ForegroundTaskService {
  static final _log = Logger("ForegroundTaskService");
  static ForegroundServiceGraceTimer? _graceTimer;
  static StreamSubscription? _machineSubscription;

  // ... existing init(), start(), stop() ...

  /// Call once after start() to wire auto-stop to machine connection state.
  /// Safe to call multiple times (e.g., on hot restart) — cancels previous subscription.
  static void watchMachineConnection(Stream<dynamic> machineStream) {
    _machineSubscription?.cancel();
    _graceTimer?.dispose();
    _graceTimer = ForegroundServiceGraceTimer(
      onStop: () => stop(),
      onStart: () => start(),
    );

    _machineSubscription = machineStream.listen((machine) {
      if (machine != null) {
        _graceTimer?.onMachineConnected();
      } else {
        _graceTimer?.onMachineDisconnected();
      }
    });
  }
}
```

Also add subscription cleanup to `stop()`:
```dart
static Future<void> stop() async {
  _machineSubscription?.cancel();
  _machineSubscription = null;
  _graceTimer?.dispose();
  _graceTimer = null;
  // ... existing stop logic ...
}
```

- [ ] **Step 3: Call watchMachineConnection from PermissionsView**

In `lib/src/permissions_feature/permissions_view.dart`, inside `_checkPermissions()`, right after `await ForegroundTaskService.start();` (added in Task 1):

```dart
// Wire foreground service auto-stop to machine connection state
ForegroundTaskService.watchMachineConnection(
  widget.de1controller.de1,
);
```

Note: Although `PermissionsView` is a transient widget, `watchMachineConnection` stores the subscription as a static field on `ForegroundTaskService`, so it outlives the widget. This is acceptable because `_checkPermissions()` runs exactly once during app startup (it's a one-shot initialization gate). The static fields ensure the wiring persists for the app's lifetime, and `watchMachineConnection` is safe to call multiple times (cancels previous subscription).

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings or errors.

- [ ] **Step 5: Run all tests**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/src/services/foreground_service.dart lib/src/permissions_feature/permissions_view.dart
git commit -m "feat: wire foreground service grace timer to machine connection

Foreground service now auto-stops 5 minutes after DE1 disconnects
and restarts when DE1 reconnects. Driven by De1Controller.de1 stream.

Addresses #104"
```

---

## Task 4: Add moveTaskToBack on Android Back Press

**Problem:** On Samsung OneUI, pressing back destroys the activity and can create a new task when relaunching. Syncthing-Fork pattern: use `moveTaskToBack(true)` to keep the activity alive in the background.

**Files:**
- Modify: `android/app/src/main/kotlin/net/tadel/reaprime/MainActivity.kt`

- [ ] **Step 1: Register OnBackPressedCallback in MainActivity**

The manifest has `enableOnBackInvokedCallback="true"`, which means `onBackPressed()` is **never called** on Android 14+ (API 34+). We must use the `OnBackPressedCallback` API instead.

Add to `MainActivity.kt` in `onCreate()`, after `super.onCreate(savedInstanceState)`:

```kotlin
import androidx.activity.OnBackPressedCallback

// In onCreate(), after super.onCreate(savedInstanceState):
onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
    override fun handleOnBackPressed() {
        // Keep the activity alive in the background instead of destroying it.
        // This prevents Samsung OneUI from creating a new task on relaunch.
        moveTaskToBack(true)
    }
})
```

This works on all API levels (the AndroidX `OnBackPressedDispatcher` handles compatibility). It intercepts all back gestures/presses and moves the task to background instead of finishing the activity.

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings or errors (Kotlin change, not Dart).

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/net/tadel/reaprime/MainActivity.kt
git commit -m "fix: use moveTaskToBack instead of finish on Android back press

Keeps the activity alive in the background when user presses back,
preventing Samsung OneUI from creating duplicate tasks on relaunch.
Pattern borrowed from Syncthing-Fork.

Addresses #73"
```

---

## Task 5: Clean Up Exit Path — Replace exit(0)

**Problem:** `settings_tile.dart` calls `exit(0)` which is a hard process kill. The foreground service (with `stopWithTask=false`) can survive this, leaving an orphaned service. Need a graceful shutdown: disconnect machine, stop foreground service, then exit.

**Files:**
- Modify: `lib/src/home_feature/tiles/settings_tile.dart`
- Modify: `lib/src/services/foreground_service.dart`

- [ ] **Step 1: Read current exit code in settings_tile.dart**

Current code (lines 48-54):
```dart
ShadButton.secondary(
  onPressed: () async {
    await (await widget.controller.de1.first)?.disconnect();
    await ForegroundTaskService.stop();
    exit(0);
  },
  child: Text("Exit Streamline-Bridge"),
),
```

This already stops the foreground service before exit — good. But `exit(0)` is still abrupt. On Android, `SystemNavigator.pop()` is the recommended way to "exit" — it finishes the activity and lets the system clean up properly.

- [ ] **Step 2: Replace exit(0) with graceful shutdown**

`SystemNavigator.pop()` finishes the activity but leaves the process alive briefly (Android reclaims it). Since we stop the foreground service first, there's no orphaned service. The process will be reclaimed by Android shortly after. This is the recommended Android pattern — `exit(0)` bypasses cleanup and can leave native resources dangling.

```dart
import 'package:flutter/services.dart'; // for SystemNavigator

// In the onPressed callback:
onPressed: () async {
  // Disconnect machine
  await (await widget.controller.de1.first)?.disconnect();
  // Cancel grace timer, subscription, and stop foreground service
  await ForegroundTaskService.stop();
  // Finish the activity — Android reclaims the process shortly after
  SystemNavigator.pop();
},
```

- [ ] **Step 3: Add grace timer cleanup to ForegroundTaskService.stop()**

In `lib/src/services/foreground_service.dart`, ensure `stop()` also disposes the grace timer:

```dart
static Future<void> stop() async {
  _graceTimer?.dispose();
  _graceTimer = null;
  try {
    // ... existing stop logic ...
  }
}
```

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings or errors.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_feature/tiles/settings_tile.dart lib/src/services/foreground_service.dart
git commit -m "fix: replace exit(0) with graceful shutdown sequence

Uses SystemNavigator.pop() instead of exit(0) for clean Android
activity teardown. Ensures grace timer is disposed and foreground
service is stopped before exit.

Addresses #104"
```

---

## Task 6: Remove Notification Update from onRepeatEvent + Add onNotificationPressed

**Problem:** Two things: (1) `onRepeatEvent` in the service isolate updates the notification every 60s, which will race with `ForegroundServiceGraceTimer` notification updates from the main isolate (Task 7). Only one source should own notification text. (2) Need `onNotificationPressed` handler for observability.

**Files:**
- Modify: `lib/src/services/foreground_service.dart`

- [ ] **Step 1: Remove notification text update from onRepeatEvent**

In `FirstTaskHandler.onRepeatEvent`, remove the `FlutterForegroundTask.updateService()` call. Keep the heartbeat logging. The grace timer (main isolate) will own all notification text updates.

```dart
@override
void onRepeatEvent(DateTime timestamp) {
  _eventCount++;

  // Log periodically to confirm service is running
  if (_eventCount % 5 == 0) {
    _log.fine('Foreground service heartbeat: $_eventCount events, uptime: ${_formatUptime()}');
  }
}
```

- [ ] **Step 2: Add onNotificationPressed handler**

In `FirstTaskHandler`:
```dart
@override
void onNotificationPressed() {
  _log.info('Notification tapped - bringing app to foreground');
  // flutter_foreground_task handles launching the activity automatically
  // singleTask launch mode ensures existing activity is surfaced
}
```

- [ ] **Step 3: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings or errors.

- [ ] **Step 4: Commit**

```bash
git add lib/src/services/foreground_service.dart
git commit -m "fix: single source of truth for notification text

Removes notification update from onRepeatEvent (service isolate)
so that ForegroundServiceGraceTimer (main isolate) is the sole
owner of notification content. Prevents race conditions.
Adds onNotificationPressed handler for observability.

Addresses #104"
```

---

## Task 7: Update Notification Text for Service States

**Problem:** The notification always shows "Streamline Active" even during grace period or when disconnected. Should reflect actual state.

**Files:**
- Modify: `lib/src/services/foreground_service.dart`

- [ ] **Step 1: Add state-aware notification updates**

The `ForegroundServiceGraceTimer` should update the notification text when entering/leaving grace period. Add notification update calls:

Add a helper method to `ForegroundServiceGraceTimer` and call it from `onMachineConnected` / `onMachineDisconnected`:

```dart
Future<void> _updateNotification(String title, String text) async {
  try {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  } catch (e) {
    _log.warning('Failed to update notification: $e');
  }
}
```

In `onMachineDisconnected()`, after starting the grace timer:
```dart
_updateNotification(
  'Streamline: Disconnected',
  'Will stop in ${gracePeriod.inMinutes} minutes if no reconnection',
);
```

In `onMachineConnected()`, after cancelling the timer:
```dart
_updateNotification(
  'Streamline Active',
  'Connected to DE1',
);
```

Note: Task 6 removes the competing `updateService` call from `onRepeatEvent`, so the grace timer is the sole owner of notification content.

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings or errors.

- [ ] **Step 3: Commit**

```bash
git add lib/src/services/foreground_service.dart
git commit -m "feat: show connection state in foreground service notification

Notification now shows 'Connected to DE1' when connected and
'Will stop in 5 minutes' during grace period after disconnect.

Addresses #104"
```

---

## Task 8: Final Integration Test

**Files:**
- All modified files

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No warnings or errors.

- [ ] **Step 3: Manual test checklist (with simulate=1)**

Run: `flutter run --dart-define=simulate=1`

Verify:
- [ ] App starts, permissions are requested, foreground service starts AFTER permissions granted
- [ ] Notification appears: "Streamline Active — Connected to DE1" (simulated)
- [ ] Pressing Android back button: app goes to background, notification persists
- [ ] Tapping notification: existing activity surfaces (no duplicate)
- [ ] Disconnecting simulated machine: notification updates to grace period message
- [ ] After 5 minutes: notification disappears (service stopped)
- [ ] Reconnecting: service restarts, notification reappears
- [ ] Exit button: clean shutdown, no orphaned notification

- [ ] **Step 4: Commit any final fixes**

```bash
git commit -m "fix: integration fixes from manual testing

Addresses #104"
```

---

## Summary of Changes by Issue

### Issue #104 (Foreground service correct implementation)
- **Permission sequencing:** Service starts after BLE + notification permissions granted (Task 1)
- **Grace period auto-stop:** Service stops 5 min after machine disconnect (Tasks 2-3)
- **Process cleanup:** Graceful shutdown replaces `exit(0)` (Task 5)
- **Service self-cleanup:** Notification tap and destroy handling (Task 6)
- **State-aware notifications:** Shows connection state (Task 7)

### Issue #73 (Samsung OneUI — partial fix)
- **Duplicate task prevention:** `moveTaskToBack()` on back press (Task 4)
- **Rotation bug:** Deferred to separate fix (out of scope)

### iOS Impact
- **None.** All changes are inside `Platform.isAndroid` guards or in Android-native code. iOS continues to use `bluetooth-central` background mode unaffected.
