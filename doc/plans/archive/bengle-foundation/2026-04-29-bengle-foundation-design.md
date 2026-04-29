# Bengle Foundation — Design

## Problem

Bengle is a DE1-derived espresso machine adding integrated scale, optional milk-temp probe, cup warmer, and a color LED strip. Streamline-Bridge needs to support it (internal beta end of May 2026). Most of the work is SB-side, not firmware.

The current state in `lib/`:

- `Bengle extends UnifiedDe1 implements BengleInterface` (`models/device/impl/bengle/bengle.dart`) — stub that overrides `name` only.
- `BengleInterface extends De1Interface` — empty.
- `DecentMachineModel.Bengle` enum value present (`models/device/impl/de1/de1.models.dart:274`).
- `device_matcher.dart` routes advertised name `Bengle*` to the `Bengle` instance.
- `UnifiedDe1.onConnect` already detects Bengle hardware via the `v13Model` MMR (`unified_de1.dart:185`) and warns.

Nothing else exists. Cup warmer, integrated scale, LED, milk probe, and the FW-update prelude are all unimplemented. Each of these will need new endpoints / MMR addresses, some new state, and some new public methods on Bengle.

This doc is the **foundation step**. It locks the abstraction so the per-feature work in later steps plugs in without base-class churn.

## Goal

Land an extension shape on `UnifiedDe1` that:

1. Lets Bengle add new capabilities (with their own state, endpoints, and MMRs) without modifying `UnifiedDe1` or the shared `Endpoint` / `MMRItem` enums beyond a one-time interface lift.
2. Keeps the BLE/serial transport split working for Bengle the same way it works for DE1 today.
3. Lets Bengle modify inherited DE1 behavior (specifically the FW upload prelude) cleanly via subclass override.
4. Keeps existing DE1 behavior unchanged — no functional regression.

No feature implementation lands in this step. After this step, `Bengle` is still functionally identical to `UnifiedDe1`.

## Architecture decision

### Shape: `UnifiedDe1` baseline + capability mixins + per-capability registries

```dart
mixin CupWarmerCapability on UnifiedDe1 { ... }
mixin IntegratedScaleCapability on UnifiedDe1 { ... }
mixin LedStripCapability on UnifiedDe1 { ... }
mixin MilkProbeCapability on UnifiedDe1 { ... }

class Bengle extends UnifiedDe1
    with CupWarmerCapability,
         IntegratedScaleCapability,
         LedStripCapability,
         MilkProbeCapability
    implements BengleInterface { ... }
```

Considered and rejected:

- **Subclass + per-feature helpers inside `Bengle`.** Cheap, but `Bengle` becomes a god class and inheritance is sticky.
- **Pure composition (`Bengle` holds a `UnifiedDe1`).** Maximum flexibility but ~50 boilerplate forwarders, easy to drift on unimplemented surface.

Chosen because:

- **Future-proof for Bengle 2.0 / GHC replacement / 3rd-party peripherals.** Other devices mix and match capabilities. Aftermarket LED add-on = some other device implementing `LedStripCapability`.
- **Capability discovery falls out for free.** Skins / handlers query `device is LedStripCapability` at the boundary. The dynamic API surface (which endpoints to mount) follows from this without per-device branching.
- **Per-capability registries.** Each capability owns its own MMR addresses and `LogicalEndpoint`s in its own file. Shared DE1 endpoints/MMRs stay in their existing enums untouched.

### When to use what

| Bengle addition shape | Mechanism | Example |
|---|---|---|
| Single MMR write, no state | Extension on `Bengle` in own file | Cup warmer (likely) |
| Stateful (stream subs, BehaviorSubjects) | Mixin on `UnifiedDe1` in own file | Integrated scale, LED state, milk probe |
| Modifies inherited DE1 behavior | `@protected` template-method hook on `UnifiedDe1`, override on `Bengle` (not a mixin) | FW update `0x22` prelude |

### Transport access for capabilities

`UnifiedDe1` runs on top of two very different `DataTransport` shapes:

- `BLETransport` — addressable by `(serviceUUID, characteristicUUID)`; supports per-characteristic subscribe/read/write.
- `SerialTransport` — line/hex command stream, no addressing; single read stream parsed by the consumer; writes go through `writeCommand("<+X>")` framing.

The codebase already abstracts this divide: `Endpoint` (in `de1.models.dart`) carries **both** wire encodings — `uuid` for BLE and a single-char `representation` for serial. `UnifiedDe1Transport._bleConnect` subscribes via `uuid`; `_serialConnect` subscribes via `<+${representation}>`.

The capability layer must target *logical endpoints*, never wire identifiers — otherwise serial breaks.

`@protected` is annotation-only in Dart but the linter honors it. Mixins declared `on UnifiedDe1` see methods marked `@protected` in `UnifiedDe1`.

MMR helpers live one level above the endpoint primitives. They wrap the existing MMR protocol (address packing, read/response correlation, timeout) implemented in `unified_de1.mmr.dart`, which itself rides the standard `Endpoint.readFromMMR` / `Endpoint.writeToMMR` endpoints. MMR is not a parallel wire path.

### Interfaces that lift the closed enums

`LogicalEndpoint`:

```dart
abstract class LogicalEndpoint {
  String? get uuid;            // BLE characteristic UUID, null if BLE-unsupported
  String? get representation;  // serial single-char id, null if serial-unsupported
  String get name;
}

// Existing
enum Endpoint implements LogicalEndpoint { ... }

// In bengle/integrated_scale_capability.dart:
enum BengleScaleEndpoint implements LogicalEndpoint {
  weight('B001', 'W'),
  control('B002', 'X');
  ...
}
```

`UnifiedDe1Transport` switches on the active wire and reads the appropriate field. `null` on the active wire → throw a clear "endpoint not supported on this transport" error. This makes FW gaps (Bengle features that have BLE wire support but not serial yet, or vice versa) explicit at the code level.

`MmrAddress`:

```dart
enum MmrValueKind {
  int32,        // signed 32-bit int
  int16,        // signed 16-bit int
  scaledFloat,  // int with read/write scale (current scale-config use)
  boolean,      // 0/1 int
  bytes,        // raw bytes, no decoding
  string,       // null-terminated or length-prefixed string
}

abstract class MmrAddress {
  int get address;
  int get length;
  String get name;
  MmrValueKind get kind;
}

enum MMRItem implements MmrAddress { ... }   // existing — gains a kind per entry
// Capability mixins ship their own enums implementing MmrAddress.
```

`MmrValueKind` documents the value shape on the address itself. Helpers validate kind: calling `readMmrInt` on a `scaledFloat` address throws `StateError`. Catches "wrong helper for this address" mistakes at runtime; opens up debug printers / API autogen that group MMRs by type. Migration to a fully generic `MmrAddress<T>` (encode/decode pair on the address) is open if `_MMRConfig` ever merits collapsing into the address itself, but is out of scope for the foundation step.

The existing `_MMRConfig` map in `unified_de1.mmr.dart` (scales + bounds, keyed by `MMRItem`) stays. Capability MMR enums that need scaling can either supply a similar config or use the raw `int` helpers.

### Protected surface on `UnifiedDe1`

```dart
class UnifiedDe1 implements De1Interface {
  // Existing private state stays private:
  // final UnifiedDe1Transport _transport;
  // final Logger _log = Logger("DE1");

  // Endpoint primitives (transport-aware: dispatches BLE vs. serial inside UnifiedDe1Transport)
  @protected
  Future<void> writeEndpoint(LogicalEndpoint endpoint, Uint8List data, {bool withResponse = true});

  @protected
  Future<ByteData> readEndpoint(LogicalEndpoint endpoint, {Duration? timeout});

  @protected
  Stream<ByteData> notificationsFor(LogicalEndpoint endpoint);

  // MMR helpers (build on Endpoint.readFromMMR/writeToMMR; protocol from unified_de1.mmr.dart)
  @protected
  Future<int> readMmrInt(MmrAddress addr);

  @protected
  Future<double> readMmrScaled(MmrAddress addr, {required double readScale});

  @protected
  Future<void> writeMmrInt(MmrAddress addr, int value, {int? min, int? max});

  @protected
  Future<void> writeMmrScaled(MmrAddress addr, double value, {required double writeScale, int? min, int? max});

  @protected
  Future<List<int>> readMmrRaw(MmrAddress addr);

  @protected
  Future<void> writeMmrRaw(MmrAddress addr, List<int> data);

  // Template-method hooks
  @protected
  Future<void> beforeFirmwareUpload() async {} // default no-op

  // Logger access for capability mixins
  @protected
  Logger get log;
}
```

### Lifecycle convention for stateful capabilities

Stateful mixins ship matched `init/disposeXyz()` methods. `Bengle.onConnect` / `onDisconnect` calls each one it carries, in order. No magic, no reflection — explicit.

```dart
mixin IntegratedScaleCapability on UnifiedDe1 {
  StreamSubscription<ByteData>? _weightSub;
  final _weight = BehaviorSubject<WeightSample>();

  @protected
  Future<void> initIntegratedScale() async {
    _weightSub = notificationsFor(BengleScaleEndpoint.weight).listen(_handle);
  }

  @protected
  Future<void> disposeIntegratedScale() async {
    await _weightSub?.cancel();
    await _weight.close();
  }
}
```

Convention: every stateful capability mixin exposes `init<Name>()` + `dispose<Name>()`. `Bengle` orchestrates them.

### FW upload prelude

`unified_de1.firmware.dart:13-14` already gestures at the right pattern:

```dart
// TODO: move to Machine impl that needs this
// await requestState(MachineState.fwUpgrade);
```

Resolve the TODO as a template-method hook:

```dart
// In unified_de1.dart
@protected
Future<void> beforeFirmwareUpload() async {} // default no-op

// In _updateFirmware (firmware extension), after requestState(sleeping):
await beforeFirmwareUpload();   // replaces the commented-out line

// In bengle.dart
@override
Future<void> beforeFirmwareUpload() async {
  await requestState(MachineState.fwUpgrade); // 0x22 — already in MachineState enum
}
```

## Capability boundaries (forward reference)

This step does not implement these. Listed here as evidence the abstraction can carry them — and to set up where each capability's code will land.

- **`CupWarmerCapability`** — likely an extension on `Bengle` (stateless), single MMR write. 1 new `MmrAddress`. No lifecycle.
- **`IntegratedScaleCapability`** — mixin. Owns weight stream, target weight, SAW state. New `LogicalEndpoint`s for weight notify and control. Lifecycle: `initIntegratedScale` / `disposeIntegratedScale`.
- **`LedStripCapability`** — mixin (probably). Color/pattern state. New `MmrAddress`(es). Optional cache hydration in `initLedStrip`.
- **`MilkProbeCapability`** — mixin. Temperature stream + presence detection. New notify endpoint. Lifecycle. (May alternatively be modelled as a separate `Sensor` device — decided in later step.)

Per-capability impl design lives in its own design doc when the time comes (steps 4–7 of the broader Bengle roadmap, tracked in vault note `Professional/Decent/Bengle/ReaPrime Integration.md`).

## Refactor sequence

1. Introduce `LogicalEndpoint` abstract class in `lib/src/models/device/transport/`. `Endpoint implements LogicalEndpoint`. `UnifiedDe1Transport` methods take `LogicalEndpoint` instead of `Endpoint`. Pure rename + interface lift.
2. Introduce `MmrAddress` abstract class in `lib/src/models/device/impl/de1/`. `MMRItem implements MmrAddress`. `unified_de1.mmr.dart` helpers accept `MmrAddress`. Pure rename + interface lift.
3. Add `@protected` surface methods on `UnifiedDe1` that wrap the existing extensions. The MMR/firmware/profile/raw `part of` files stay structurally unchanged.
4. Resolve `unified_de1.firmware.dart:14` TODO — add `beforeFirmwareUpload()` hook on `UnifiedDe1` (default no-op). Call from `_updateFirmware` after `requestState(sleeping)`.
5. Override `beforeFirmwareUpload()` on `Bengle` to request `MachineState.fwUpgrade` (`0x22`).

After (1)–(5) the abstraction is in place. Capability mixins added in later steps without further base-class churn.

## Files to change

- `lib/src/models/device/transport/logical_endpoint.dart` — new. `LogicalEndpoint` abstract class.
- `lib/src/models/device/impl/de1/de1.models.dart` — `Endpoint implements LogicalEndpoint`. `MMRItem implements MmrAddress`.
- `lib/src/models/device/impl/de1/mmr_address.dart` — new. `MmrAddress` abstract class.
- `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart` — accept `LogicalEndpoint` instead of `Endpoint` in subscribe/write/read methods. No behavior change.
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.mmr.dart` — helpers accept `MmrAddress` instead of `MMRItem`. `_MMRConfig` map keyed by `MmrAddress`.
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` — add `@protected` surface methods (delegating to existing transport / extension internals). Add `beforeFirmwareUpload()` hook. Expose `Logger get log` as `@protected`.
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.firmware.dart` — call `beforeFirmwareUpload()` after `requestState(sleeping)` in `_updateFirmware`. Remove the obsolete commented-out line.
- `lib/src/models/device/impl/bengle/bengle.dart` — override `beforeFirmwareUpload()`.

## Testing

Existing behavior must not regress. The lifts are mechanical interface changes; existing tests should pass without modification once the type signatures match.

- **Unit**: existing `unified_de1` and transport tests must pass.
- **Unit (new)**: `bengle.beforeFirmwareUpload()` requests `MachineState.fwUpgrade` (1 test). Default `UnifiedDe1.beforeFirmwareUpload()` is a no-op (1 test).
- **Integration**: existing DE1 BLE/serial connect smoke tests must pass.
- **End-to-end**: `scripts/sb-dev.sh` with `simulate=1` — connect, run a fake shot, verify no regression in machine snapshot stream. (No Bengle hardware needed yet — Bengle is still a `UnifiedDe1` after this step.)

No new end-to-end scenario for the FW prelude — gets exercised when actual Bengle hardware lands.

## Out of scope / deferred

- Roadmap steps 2–7 (simulated Bengle, real subclass + USB discovery, cup warmer impl, scale impl, LED impl, milk probe impl).
- USB-first vs. BLE-first for v1 Bengle path — decided when starting step 3.
- `ScaleController` integration (virtual `Scale` vs. third pathway) — decided in step 5.
- LED API surface (workflow setting vs. dedicated REST) — decided in step 6.
- LED transport (MMR vs. dedicated characteristic) — confirm with FW before step 6.
- Milk probe as `Sensor` vs. capability mixin — decided in step 7.
- API capability discovery wiring — deferred until at least one Bengle feature is end-to-end (after step 4 or 5).
