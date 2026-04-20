import 'package:flutter_test/flutter_test.dart';

/// Gap F — regression coverage for comms-harden #20 (disconnect detection
/// keyed on `device.name` instead of `deviceId`).
///
/// `DeviceController._previousDeviceNames` and `_disconnectedAt` are keyed
/// by `device.name`. Two devices sharing an advertised name (e.g. two DE1s
/// on the same bench) will have their reconnect-tracking cross-attributed.
/// A device whose firmware changes its advertised name is also never
/// cleaned up from `_disconnectedAt` (mitigated by the 24 h cleanup, but
/// the semantics are still wrong).
///
/// Phase 6 switches the key from `name` to `deviceId`. When that lands:
///   1. Remove the `skip:` argument.
///   2. Build a `DeviceController` over a stubbed `DeviceDiscoveryService`
///      that emits two devices with the same `name` but different
///      `deviceId`s. Disconnect one. Assert the other remains tracked as
///      connected, and that `_disconnectedAt` only records the one that
///      actually left.
///
/// A migration audit is required before the fix lands because persisted
/// preference keys may depend on `name` — see `comms-harden.md` landmine.
///
/// See: doc/plans/comms-harden.md #20,
///      doc/plans/comms-phase-0-1.md Gap F.
void main() {
  group('disconnect tracking keys (comms-harden #20)', () {
    test(
      'two devices with same name but different IDs do not collide',
      () async {
        fail('pending Phase 6 fix for #20');
      },
      skip:
          'pending fix for comms-harden #20 — see doc/plans/comms-phase-0-1.md',
    );
  });
}
