import 'package:flutter_test/flutter_test.dart';

/// Gap E — regression coverage for comms-harden #5 (shot-settings debounce
/// races disconnect).
///
/// `De1Controller._shotSettingsUpdate` schedules a 100 ms debounce timer
/// that calls `_processShotSettingsUpdate`. Once the timer fires, its async
/// body awaits a chain of `connectedDe1().getSteamFlow()` / `getFlushFlow()`
/// / etc. If the DE1 disconnects mid-chain, `_de1` is nulled by
/// `_onDisconnect()` and subsequent `connectedDe1()` calls throw the raw
/// string `"De1 not connected yet"` — unhandled, leaking as an async error
/// from the timer.
///
/// Phase 1 PR 3 replaces the raw string with `DeviceNotConnectedException`.
/// Phase 5 (#5 proper) adds generation-token guards so the running debounce
/// body bails out cleanly on disconnect.
///
/// When the fix lands:
///   1. Remove the `skip:` arguments.
///   2. Implement the test body using `runZonedGuarded` (or a test binding
///      error hook) to catch async errors from the timer body.
///   3. Fire `_shotSettingsUpdate`, immediately disconnect, advance time
///      past the 100 ms debounce, and assert no unhandled exception was
///      emitted.
///
/// See: doc/plans/comms-harden.md #5,
///      doc/plans/comms-phase-0-1.md Gap E.
void main() {
  group('shot-settings debounce race (comms-harden #5)', () {
    test(
      'disconnect during debounce does not leak an unhandled async error',
      () async {
        fail('pending Phase 5 fix for #5');
      },
      skip: 'pending fix for comms-harden #5 — see doc/plans/comms-phase-0-1.md',
    );
  });
}
