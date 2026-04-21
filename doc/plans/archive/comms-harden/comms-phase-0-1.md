# Comms Hardening — Phase 0 + Phase 1 Implementation Plan

Execution plan for the first two phases of `doc/plans/comms-harden.md`.

- **Phase 0:** safety-net integration tests (gap-filling the existing 1114-line `connection_manager_test.dart` + adjacent tests).
- **Phase 1:** four surgical bug fixes (#1 profile guard, #2 MMR timeout, #25 typed exceptions, #26 comms-critical catch logging).

Goal: ship user-visible safety patches while establishing regression coverage for the bigger Phase 2 state-derivation refactor.

---

## Pre-work findings

Checked current code before writing this plan.

**Existing test coverage** (don't re-write):

- Happy connect path — covered (`connection_manager_test.dart:205`).
- Machine `onConnect` throws — covered (`:605`, `:699`).
- Scale `onConnect` throws → emits `scaleConnectFailed` — covered (`:805`). **Missing:** the specific #4 regression — does the *next* `connect()` re-attempt scale, or is `_scaleConnected` stuck true?
- Error surfacing on status stream — covered (`:736`, `:749`, `:764`).
- Concurrent `connect()` rejection — covered (`:513`).

**Existing helpers** (reuse where possible):

- `test/helpers/test_de1.dart`, `test_scale.dart` — both have no-op `onConnect()`. Need extension to throw on demand.
- `test/helpers/mock_device_scanner.dart` (104 lines) — may need a scan-error injection mode for #22 gap.
- `test/helpers/mock_de1_controller.dart`, `mock_scale_controller.dart`, `mock_device_discovery_service.dart` — already used; likely sufficient.

**Code sites touched in Phase 1:**

- `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart:288–303` — `setProfile` + `_currentProfile`.
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.mmr.dart:4–37` — `_mmrRead` (+ `_unpackMMRInt:120–128` bounds).
- `lib/src/controllers/de1_controller.dart:182,189,218` — three raw `String` throws of `"De1 not connected yet"`.
- `lib/src/controllers/scale_controller.dart:62` — raw `String` throw of `"No scale connected"`.
- `lib/src/models/errors.dart` — already hosts `PermissionDeniedException`; add new exception classes here.
- Comms-critical `} catch (_) {}` sites: `connection_manager.dart:548`, `linux_blue_plus_transport.dart:154`, `linux_ble_discovery_service.dart:381`, `unified_de1_transport.dart:484`.

Broader catch-swallowing (15 other sites in scale impls, serial, webserver) is **out of Phase 1 scope** — handled in later hygiene pass.

---

## Branch + delivery strategy

Four PRs, each landing independently. Each sized for unhurried review (est. sizes noted).

Recommended branch setup:

```
main
├── feature/comms-phase-0-tests            # PR 1
├── feature/comms-phase-1-profile-guard    # PR 2
├── feature/comms-phase-1-mmr-timeout      # PR 3
└── feature/comms-phase-1-catch-logging    # PR 4
```

Each branches off `main` (not stacked), so each can merge independently. PR 1 adds tests that turn green as PRs 2/3 land.

Alternative: stack on a shared integration branch if you prefer one merge. Your call when we start.

**Dependency order:**
1. PR 1 (tests) — establishes red baseline.
2. PR 2 (#1) — turns one red test green.
3. PR 3 (#2 + #25, bundled) — turns remaining red tests green.
4. PR 4 (#26) — pure observability, independent.

---

## PR 1 — Phase 0 safety-net tests

**Branch:** `feature/comms-phase-0-tests`. **Est. size:** ~400 lines (tests + helper extensions).

### Helper extensions

1. **`test/helpers/test_de1.dart`**
   - Add `Object? onConnectError` field.
   - Override `onConnect()` to `if (onConnectError != null) throw onConnectError!;`.
   - Add `Completer<void>? onConnectGate` for tests that need to hold `onConnect` pending.

2. **`test/helpers/test_scale.dart`**
   - Same treatment: `onConnectError`, `onConnectGate`.

3. **`test/helpers/mock_device_scanner.dart`**
   - Add `Object? scanStartError` — when set, `scanForDevices()` completes its internal Future with this error.
   - Purpose: exercise #22's silent-swallow path.

4. **New `test/helpers/test_mmr_de1.dart`** (optional, if cleaner than inline)
   - Minimal `UnifiedDe1`-like harness that injects a controllable `_mmr` stream.
   - Alternative: test `_mmrRead` directly via a thin integration test constructing a real `UnifiedDe1` with stub `_transport`. Pick whichever has less test plumbing.

### New tests (gap-filling)

Each test is labeled with the harden-plan item it regresses.

**Gap A — `test/controllers/connection_manager_test.dart`** (#4)

```
group('scale failure recovery', () {
  test('after scale onConnect throws, next connect() retries scale', ...);
  test('scaleOnly reconnect re-attempts after prior failure', ...);
});
```

Uses `TestScale.onConnectError` to fail first attempt, clears it, runs second `connect()`, asserts scale is connected. Red until #4 fix (Phase 2). Mark with `skip: 'covered by harden #4 — Phase 2'` or `expect(..., skip: '...')` — team preference.

**Gap C — `test/models/device/unified_de1_mmr_test.dart`** (new file, #2)

```
group('_mmrRead', () {
  test('times out when no matching response arrives', ...);
  test('throws MmrTimeoutException with item name in message', ...);
  test('_unpackMMRInt does not throw RangeError on empty buffer', ...);
});
```

Uses `fake_async` to advance beyond the 5s timeout. Red until #2 fix lands in PR 3.

**Gap D — `test/controllers/connection_manager_test.dart`** (#22)

```
group('scan error surfacing', () {
  test('scanForDevices start error surfaces on status stream', ...);
});
```

Sets `MockDeviceScanner.scanStartError = PermissionDeniedException('test')`, calls `connect()`, asserts `ConnectionError` emitted on status stream. Red until #22 fix (Phase 2).

**Gap E — `test/controllers/de1_controller_test.dart`** (new file if doesn't exist, #5)

```
group('shot-settings debounce race', () {
  test('disconnect during debounce does not throw unhandled', ...);
});
```

Uses `runZonedGuarded` to catch async errors leaking from the debounce timer. Connects, triggers shot-settings change, immediately nulls `_de1` via disconnect, verifies no uncaught error. Red until #5 fix (Phase 5).

**Gap F — `test/controllers/device_controller_test.dart`** (extend if exists, #20)

```
group('disconnect tracking keys', () {
  test('two devices with same name but different IDs do not collide', ...);
});
```

Adds two discovery-service devices sharing a `name` but with distinct `deviceId`. Disconnects one, asserts `_disconnectedAt` only records that one. Red until #20 fix (Phase 6).

### Not in Phase 0

- **#6 flag divergence from stream** — broad; Phase 2 refactor tests cover naturally.
- **#7 early-connect race** — timing race hard to reproduce deterministically; Phase 2 replaces the mechanism anyway.
- **#3 relisten throw + #12 transport sub leak** — need a "reconnect on same instance" integration test. Defer to PR accompanying Phase 5 fixes — lifecycle audit (per landmine) happens then.

### Deliverables

- 5 new test groups (Gaps A, C, D, E, F).
- Helper extensions (TestDe1, TestScale, MockDeviceScanner).
- Documentation in test files: each skipped/red test has comment referencing `comms-harden.md` item.

### Success criteria

- `flutter test` green for all currently-passing tests.
- 5 new tests present; each either skipped with explanatory comment or failing with expected error (team picks red-baseline approach — I lean skip+comment because CI stays green).

---

## PR 2 — #1 profile guard reorder

**Branch:** `feature/comms-phase-1-profile-guard`. **Est. size:** ~10 lines code + ~40 lines test.

### Change

`lib/src/models/device/impl/de1/unified_de1/unified_de1.dart:290–303`:

```dart
// Before
Future<void> setProfile(Profile profile) async {
  if (_currentProfile == profile) return;
  _currentProfile = profile;
  await _sendProfile(profile);
  await Future.delayed(const Duration(milliseconds: 500));
}

// After
Future<void> setProfile(Profile profile) async {
  if (_currentProfile == profile) return;
  await _sendProfile(profile);
  _currentProfile = profile;
  await Future.delayed(const Duration(milliseconds: 500));
}
```

Move `_currentProfile = profile` below the `await _sendProfile`. On throw, `_currentProfile` is not poisoned; retry with same profile re-attempts upload.

### Test

New test in `test/models/device/unified_de1_profile_test.dart` (or existing profile test file):

- Stub `_sendProfile` to throw on first call, succeed on second (requires either a subclass or a seam — easier with a test-local subclass that overrides).
- Call `setProfile(p)` twice with the same profile; expect second call to actually execute `_sendProfile` again.
- Third call after success: expect `_sendProfile` **not** called (guard kicks in correctly for successful profile).

**Note:** `UnifiedDe1` doesn't currently have a subclass seam for `_sendProfile`. Options:
- **Option A:** extract `_sendProfile` as a method on an injected `ProfileWriter` interface (cleaner, slightly bigger diff).
- **Option B:** test via a subclass that overrides `_sendProfile` (requires making it `@visibleForTesting` or reducing privacy — awkward because of the `part of` extension).
- **Option C:** test at integration level with a mock transport, counting `writeHeader`/`writeSteps`/`writeTail` calls.

Recommend **C** — keeps the guard at the right level, exercises real code, no refactor for testability.

### Success criteria

- Gap-A-adjacent test from PR 1 (if any) passes.
- New profile-retry test green.
- `flutter analyze` clean.

---

## PR 3 — #2 MMR timeout + #25 typed exceptions (bundled)

**Branch:** `feature/comms-phase-1-mmr-timeout`. **Est. size:** ~80 lines code + ~80 lines test.

Bundled because #25's typed exception pattern (in `errors.dart`) is the same place where #2's `MmrTimeoutException` lands — one `errors.dart` touch covers both.

### Changes

**1. `lib/src/models/errors.dart`** — add three new exception classes:

```dart
class MmrTimeoutException implements Exception {
  final String mmrItemName;
  final Duration timeout;
  const MmrTimeoutException(this.mmrItemName, this.timeout);

  @override
  String toString() =>
      'MmrTimeoutException: no response for $mmrItemName within $timeout';
}

enum DeviceKind { machine, scale }

class DeviceNotConnectedException implements Exception {
  final DeviceKind kind;
  const DeviceNotConnectedException(this.kind);
  const DeviceNotConnectedException.machine() : kind = DeviceKind.machine;
  const DeviceNotConnectedException.scale() : kind = DeviceKind.scale;

  @override
  String toString() =>
      'DeviceNotConnectedException: ${kind.name} not connected';
}
```

**2. `lib/src/models/device/impl/de1/unified_de1/unified_de1.mmr.dart:20–32`** — wrap `firstWhere` in `.timeout(...)`:

```dart
const _mmrReadTimeout = Duration(seconds: 5);

// inside _mmrRead:
var result = await _mmr
    .map((d) => d.buffer.asUint8List().toList())
    .firstWhere(
      (element) => /* same matcher */,
      orElse: () => <int>[],
    )
    .timeout(
      _mmrReadTimeout,
      onTimeout: () => throw MmrTimeoutException(item.name, _mmrReadTimeout),
    );
```

Also harden `_unpackMMRInt:120–128` — add empty-buffer guard so `MmrTimeoutException` surfaces cleanly instead of a downstream `RangeError`:

```dart
int _unpackMMRInt(List<int> buffer) {
  if (buffer.isEmpty) {
    throw StateError('MMR response buffer is empty — expected 8 bytes');
  }
  // existing impl
}
```

(Should never be reachable in Phase 1 because `_mmrRead` now throws before returning empty. Belt-and-braces.)

**3. `lib/src/controllers/de1_controller.dart:182,189,218`** — three replacements:

```dart
// Before
throw "De1 not connected yet";
// After
throw const DeviceNotConnectedException.machine();
```

**4. `lib/src/controllers/scale_controller.dart:62`** — one replacement:

```dart
// Before
throw "No scale connected";
// After
throw const DeviceNotConnectedException.scale();
```

### Caller audit

Grep for callers of `connectedDe1()` / `connectedScale()` and check whether they:
- `catch (Object)` / `catch (e)` — **safe** (typed exception still caught).
- Inspect message string via `.toString().contains('not connected')` or similar — **needs update**.
- Don't catch at all — **unchanged behavior** (uncaught before, uncaught now).

Audit action item for PR 3: run the grep and include results in PR description.

### Tests

**For #2:**
- Stub a `UnifiedDe1._mmr` stream that never emits a matching response.
- Use `fake_async` to advance past 5s.
- Expect `MmrTimeoutException`.

**For #25:**
- Call `de1Controller.connectedDe1()` when no machine connected → expect `DeviceNotConnectedException` with `DeviceKind.machine`.
- Same for scale.
- Update any existing tests that catch the old string `"De1 not connected yet"` to catch `DeviceNotConnectedException` instead (unlikely but audit during PR).

### Success criteria

- Gap C test (from PR 1) turns green.
- New DeviceNotConnectedException unit tests pass.
- `flutter analyze` clean.
- Grep audit shows no string-comparing catch sites broken.

---

## PR 4 — #26 catch logging (comms-critical scope)

**Branch:** `feature/comms-phase-1-catch-logging`. **Est. size:** ~40 lines.

Scoped to 4 comms-critical sites:

| File | Line | Context |
|------|------|---------|
| `lib/src/controllers/connection_manager.dart` | 548 | early scale connect catch |
| `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart` | 484 | transport teardown |
| `lib/src/services/ble/linux_blue_plus_transport.dart` | 154 | Linux BLE transport |
| `lib/src/services/ble/linux_ble_discovery_service.dart` | 381 | Linux discovery refresh |

Pattern:

```dart
// Before
} catch (_) {}
// After
} catch (e, st) {
  _log.warning('<specific context, e.g., "early scale connect failed">', e, st);
}
```

Each catch gets a context string describing what operation was being attempted. Verify each file has a `_log` / `Logger` already in scope; if not, add one.

### Out of scope (deferred)

The 15 other `catch (_) {}` sites in scale implementations, serial services, and webserver handlers are **not** in Phase 1. They belong to a separate observability sweep or to later phases touching those specific subsystems.

### Success criteria

- 4 catch sites now log with stack trace.
- No behavior change (logging only).
- `flutter analyze` clean.

---

## Risk summary

| PR | Functional risk | Test risk | Rollback |
|----|-----------------|-----------|----------|
| 1 | None (tests only) | Red baseline discipline — use skip+comment, not failing assertions, to keep CI green | Revert PR |
| 2 | Near-zero (one assignment moved) | Needs a `_sendProfile` seam — option C (integration with mock transport) avoids a refactor | Revert PR |
| 3 | Medium-low — real hardware may now surface MMR failures that were silently hanging. This is *desired* but may trigger bug reports | Caller-audit required; add to PR description | Revert PR |
| 4 | None (logging only) | None | Revert PR |

Net user-visible impact after all four land:

- Profile retries actually retry (#1).
- Stuck `onConnect` on dropped MMR now fails in ≤5s instead of hanging forever (#2).
- Connection errors catchable by type for callers (#25).
- Comms-layer failures visible in logs instead of silent (#26).

No user-visible regressions expected. Phase 0 tests establish the regression fence for Phase 2's state-derivation refactor.

---

## Questions to confirm before starting

1. **Branch strategy:** four independent branches off `main`, or stacked on a shared integration branch?
2. **Red-test discipline:** skip-with-comment (CI green, explicit TODO) or expected-failure pattern (CI red until fix)? I recommend skip+comment.
3. **`_sendProfile` seam for #1 test:** integration with mock transport (option C) — OK, or prefer a visible-for-testing extraction?
4. **MMR timeout value:** 5 seconds — OK, or a different default? (DE1 MMR normally responds <200ms.)
5. **PR 3 bundling:** #2 + #25 bundled, or split into two PRs?

Answer these and we can kick off PR 1.
