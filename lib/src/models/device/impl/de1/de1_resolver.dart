import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

/// Model-authoritative machine class selection.
///
/// BLE discovery instantiates the machine class from the advertised name
/// (`DeviceMatcher`), before a connection exists. But the authoritative
/// identity is `v13Model` (`>= 128` ⇒ Bengle), which is only readable after
/// connecting. So the name-picked class can be wrong: a Bengle advertising a
/// DE1-style name lands as a plain [UnifiedDe1] (Bengle features dark), and a
/// DE1 mis-advertising "Bengle" lands as a [Bengle].
///
/// Call this **after** [UnifiedDe1.onConnect] (which sets [UnifiedDe1.isBengle]
/// from the read model). It returns:
///  - the same instance when the name-picked class already matches the model
///    (the common case — real Bengle hardware advertises "Bengle"), or
///  - a fresh instance of the correct class built over the **same live
///    transport**, with the connect-time identity carried over
///    ([UnifiedDe1.adoptIdentityFrom]). The caller runs `onConnect` on the
///    returned instance; because its identity is pre-populated, that call
///    skips the MMR re-reads and only (re)subscribes + runs capability init.
///
/// This mirrors the serial path, which already picks `Bengle` vs `UnifiedDe1`
/// from `v13Model >= 128` at detection time (`serial_service_*`). The BLE
/// transport's per-characteristic subscriptions are replaced (not stacked) on
/// the re-`connect`, so rebuilding over the shared transport is safe.
De1Interface resolveMachineForModel(De1Interface machine) {
  // Only DE1-family machines carry the v13Model gate; anything else is
  // returned untouched.
  if (machine is! UnifiedDe1) return machine;

  final wantsBengle = machine.isBengle;
  if (wantsBengle && machine is! Bengle) {
    return Bengle(transport: machine.dataTransport)..adoptIdentityFrom(machine);
  }
  if (!wantsBengle && machine is Bengle) {
    return UnifiedDe1(transport: machine.dataTransport)
      ..adoptIdentityFrom(machine);
  }
  return machine;
}
