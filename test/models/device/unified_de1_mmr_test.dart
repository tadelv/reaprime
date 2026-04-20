import 'package:flutter_test/flutter_test.dart';

/// Gap C — regression coverage for comms-harden #2 (MMR read timeout).
///
/// `_mmrRead` in `unified_de1.mmr.dart` currently wraps
/// `_mmr.firstWhere(...)` without a timeout. A single dropped MMR notify
/// from the DE1 (firmware glitch, BLE drop between write and notify) during
/// `onConnect()` leaves the Future pending forever, permanently wedging
/// `ConnectionManager._isConnecting`.
///
/// Phase 1 PR 3 introduces `MmrTimeoutException` in `lib/src/models/errors.dart`
/// and wraps the `firstWhere` with `.timeout(const Duration(seconds: 2), ...)`.
///
/// When PR 3 lands:
///   1. Remove the `skip:` arguments below.
///   2. Implement the test bodies using a fake `DataTransport` that feeds
///      `UnifiedDe1Transport._mmrSubject` without ever matching the request.
///   3. Drive the timeout via `package:fake_async`.
///
/// See: doc/plans/comms-harden.md #2,
///      doc/plans/comms-phase-0-1.md PR 3 / Gap C.
void main() {
  group('_mmrRead timeout (comms-harden #2)', () {
    test(
      'throws MmrTimeoutException when no matching response arrives',
      () async {
        fail('pending Phase 1 PR 3 — MmrTimeoutException not yet defined');
      },
      skip: 'pending fix for comms-harden #2 — see doc/plans/comms-phase-0-1.md',
    );

    test(
      '_unpackMMRInt throws a bounded error (not RangeError) on empty buffer',
      () async {
        fail('pending Phase 1 PR 3 — empty-buffer guard not yet added');
      },
      skip: 'pending fix for comms-harden #2 — see doc/plans/comms-phase-0-1.md',
    );
  });
}
