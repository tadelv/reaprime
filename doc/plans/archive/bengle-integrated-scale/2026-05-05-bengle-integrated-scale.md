# Bengle integrated scale — step 5

Branch: `feat/bengle-integrated-scale`. Step 5 of [Bengle/ReaPrime Integration](../../../) (the obsidian plan). API surface + mock-first ship; real-hardware wire identifiers stub out as `null` until FW slots are allocated.

## Context

Bengle is the next-gen Decent machine. It has a built-in scale on the drip tray — the headline differentiator versus DE1 ("no separate HDS needed"). FW for the scale isn't ready and there's no bench unit; this ship lands the SB-side surface so the API works end-to-end on `MockBengle` and the real implementation only has to fill in wire identifiers later.

Capability foundation already in place (PRs #207, #208, #212): `Bengle extends UnifiedDe1`, `LogicalEndpoint` + `MmrAddress` interfaces, `@protected` MMR helpers, capability-discovery via `GET /api/v1/machine/capabilities`, cup warmer Phase 1 as the precedent.

## Decisions

### D1 — Bengle integrated scale routes through `ScaleController` as a virtual `Scale`

Bengle's onboard scale is exposed as a `BengleVirtualScale extends Scale` adapter. `ConnectionManager` auto-connects it to `ScaleController` after the machine connects. Skins, plugins, `ShotController`, and the existing `/api/v1/scale/*` + `/ws/v1/scale/snapshot` surface all stay transport-agnostic.

**Rejected — separate pathway** (a new `BengleScaleController` + `/api/v1/machine/scale/*`): doubles the API surface and forces every skin and `ShotController` to learn a second weight source. The benefit (concurrent dual-stream support) doesn't outweigh the cost.

**Rejected — hybrid** (virtual Scale primary, parallel raw stream secondary): premature; YAGNI until someone needs simultaneous Bengle+HDS streams.

**Trade-off accepted.** `ScaleController._scale` is a single slot — can't have both an external scale and the virtual Bengle scale active. Resolved by **always** picking the virtual scale when Bengle is the machine (D3). External-scale scanning is skipped for the duration of the Bengle connection. Multi-scale concurrent streams (including external scale alongside Bengle integrated scale) logged as a follow-up in the ReaPrime TODO (P2).

### D2 — Stop-at-weight stays in software (`ShotController`)

Bengle FW exposes a SAW MMR (BC `9319446541`), but for v1 we keep the existing `ShotController` software SAW: it already watches `weightSnapshot` and calls `de1.requestState(idle)` when target is hit. With the virtual scale feeding `weightSnapshot` like any other scale, SAW works for free.

**Rejected — push target to FW MMR.** Real latency win (≈ 50–200 ms) but small relative to typical SAW lead-time tuning, and it forces Bengle-specific branching in `ShotController`. Reserved as a perf optimisation if field data justifies it.

### D3 — Integrated scale always wins on Bengle; external-scale scanning skipped

When `ConnectionManager.connectMachine` resolves a Bengle:
- Instantiate `BengleVirtualScale(machine)` and pass to `ScaleController.connectToScale`.
- **Skip the external scale-discovery phase entirely** for the duration of the Bengle connection. Even if the user has a `preferredScaleId` set, it is ignored while Bengle is the machine.

Resumes normal scale-discovery flow when the machine is non-Bengle (DE1).

**Rationale.** Bengle's integrated scale is the headline differentiator; making it compete with external scales is unnecessary friction. The design started with an external-scale-precedence rule (D1 implication), but per user clarification (2026-05-05): "If we connect to Bengle, the integrated scale always takes precedence, we do not scan for other scales (currently)." Multi-scale support — including external scale concurrent with Bengle's integrated scale — stays on the roadmap (logged in `ReaPrime/TODO.md` as P2).

**Rejected — discovery-surfaced virtual scale** (user picks "Bengle scale" from `DeviceDiscoveryView`): adds friction for the common case (Bengle owners) and duplicates lifecycle logic into the user's mental model.

**Rejected — honor `preferredScaleId` even when Bengle is connected**: makes the connection flow conditional on a setting that pre-dates Bengle support. Cleaner to defer to multi-scale phase (TODO P2).

### D4 — `/api/v1/machine/capabilities` lists `"integratedScale"`

Mirrors the cup-warmer precedent. Skins use `if ("integratedScale" in caps)` to gate "internal scale" UX hints. String-array shape unchanged.

### D5 — No new REST endpoints in v1

Existing `PUT /api/v1/scale/tare`, `PUT /api/v1/scale/timer/*`, and `GET /ws/v1/scale/snapshot` all work through the virtual scale. `setTargetWeight` and `enableStopAtWeight` from the plan's capability draft are unnecessary because target weight already lives in `WorkflowContext.doseData.weight` and `ShotController` consumes it directly.

### D6 — `ScaleSnapshot.batteryLevel` stays non-nullable; Bengle reports `100`

Integrated scale shares machine power → no scale battery. Sentinel value `100` keeps the existing field shape and skips a ripple change across seven scale impls. WebSocket payload's already-nullable `WeightSnapshot.battery` is unaffected.

## Architecture

### Capability mixin

New file `lib/src/models/device/impl/de1/unified_de1/integrated_scale_capability.dart`:

```dart
mixin IntegratedScaleCapability on UnifiedDe1 {
  final BehaviorSubject<ScaleSnapshot> _weight = BehaviorSubject();
  StreamSubscription<ByteData>? _weightSub;
  double _tareOffset = 0.0;

  Stream<ScaleSnapshot> get weightSnapshot => _weight.stream;

  Future<void> initIntegratedScale() async {
    _weightSub = notificationsFor(BengleScaleEndpoint.weight)
        .listen(_handleWeightFrame);
  }

  Future<void> disposeIntegratedScale() async {
    await _weightSub?.cancel();
    _weightSub = null;
    await _weight.close();
  }

  Future<void> tareIntegratedScale() async {
    // FW slot TBD; payload shape stubbed for now.
    await writeEndpoint(
      BengleScaleEndpoint.control,
      _encodeTareCommand(),
      withResponse: false,
    );
    _tareOffset = _weight.valueOrNull?.weight ?? 0.0;
  }

  void _handleWeightFrame(ByteData frame) { /* parse → emit ScaleSnapshot */ }
  List<int> _encodeTareCommand() => const [/* TBD */];
}
```

State-life-cycle discipline: every stateful capability mixin exposes `init<Name>()` + `dispose<Name>()`. Bengle's connect/disconnect orchestrate them.

### Wire identifiers (stubs)

New enum `BengleScaleEndpoint implements LogicalEndpoint` in the same file:

```dart
enum BengleScaleEndpoint implements LogicalEndpoint {
  weight, // notify
  control; // write — tare command bytes

  @override
  String? get uuid => null; // FW slot TBD

  @override
  String? get representation => null; // FW slot TBD
}
```

New `MmrAddress` stub `BengleMmr.scaleTare` (similarly null-wire) for any MMR-shaped tare path the FW eventually picks. Both forms ship as stubs so the mixin compiles; real Bengle on real HW won't emit weight until FW lands.

### Virtual `Scale` adapter

New file `lib/src/models/device/impl/bengle/bengle_virtual_scale.dart`:

```dart
class BengleVirtualScale extends Scale {
  final BengleInterface _machine;
  BengleVirtualScale(this._machine);

  @override
  String get deviceId => 'bengle-internal-${_machine.deviceId}';

  @override
  String get name => 'Bengle scale';

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _machine.weightSnapshot;

  @override
  Future<void> tare() => _machine.tareIntegratedScale();

  @override
  Stream<ConnectionState> get connectionState => _machine.connectionState;

  @override
  Future<void> sleepDisplay() async {} // no display
  @override
  Future<void> wakeDisplay() async {}
  @override
  Future<void> startTimer() async {} // ShotController owns shot timer
  @override
  Future<void> stopTimer() async {}
  @override
  Future<void> resetTimer() async {}
}
```

`weightSnapshot` is a new public method on `BengleInterface` (the mixin promotes it on `Bengle` and `MockBengle`).

### `ConnectionManager` wiring

Extend `ConnectionManager.connect()` so that on Bengle machine resolution:

1. Instantiate `BengleVirtualScale(machine)` and pass to `ScaleController.connectToScale`.
2. **Skip `_applyScalePolicy` entirely** for the duration of the Bengle connection — no scan for external scales, `preferredScaleId` ignored.

For non-Bengle machines, the existing scale-discovery flow runs unchanged.

`ScaleController` stays a single-slot holder unaware of "internal vs external"; the integrated-scale logic lives in one place (`ConnectionManager`).

### Capabilities endpoint

`Bengle.machineCapabilities` returns `["cupWarmer", "integratedScale"]`. Plain `UnifiedDe1` continues to return `[]`. Existing `info_handler` route unchanged.

## Mock + simulation

`MockBengle` mixes in `IntegratedScaleCapability`-equivalent behavior using flow integration off `MockDe1`'s simulated shot stream:

- Subscribe to own shot-sample stream on `onConnect`.
- For each sample: `delta = sample.flow * dt`; `_accumulatedFlow += delta`; emit `ScaleSnapshot(weight: _accumulatedFlow - _tareOffset, batteryLevel: 100, …)`.
- `tareIntegratedScale()` sets `_tareOffset = _accumulatedFlow` so the next emit has weight `0`.
- `onDisconnect` cancels subscription, closes subject, resets accumulator.

End-to-end demo (`scripts/sb-dev.sh` + simulate=1, machine=bengle):

1. `curl :8080/api/v1/machine/capabilities` → `["cupWarmer", "integratedScale"]`.
2. `websocat ws://:8080/ws/v1/scale/snapshot` (background).
3. `curl PUT :8080/api/v1/scale/tare` → next snapshot weight ≈ 0.
4. `curl PUT :8080/api/v1/de1/state/espresso` → weight rises during simulated shot.
5. With workflow target weight 36 g, shot transitions to `idle` when weight ≥ 36. Software SAW exercised end-to-end.

## Testing

**Unit.**
- `test/models/device/integrated_scale_capability_test.dart` — init subscribes, weight-frame parse, tare writes correct payload, dispose cancels and closes.
- `test/models/device/bengle_virtual_scale_test.dart` — proxies the mixin's stream, `tare()` delegates, no-op timer + display methods, `deviceId` derivation.
- `test/models/device/mock_bengle_scale_test.dart` — flow integration accumulator, tare zeroes next emit, reset on disconnect, battery `100`.
- Extend existing capabilities test — Bengle returns `["cupWarmer", "integratedScale"]`; plain DE1 unchanged.

**Integration.**
- `test/integration/bengle_scale_auto_connect_test.dart` — `ConnectionManager.connect()` with Bengle preferred-device + no external scale → `ScaleController.currentConnectionState == connected`, snapshot stream emits.
- `test/integration/bengle_scale_precedence_test.dart` — Bengle connects, external `MockScale` connects → controller swaps to external; external disconnects → controller swaps back to virtual.

**End-to-end.** New scenario `.agents/skills/streamline-bridge/scenarios/bengle-integrated-scale.md` codifying the demo above.

**Spec + docs.**
- `assets/api/rest_v1.yml` — capabilities example response includes `"integratedScale"`.
- `doc/Api.md` — capabilities table notes the new value.
- `doc/DeviceManagement.md` — short paragraph on integrated-scale auto-connect + external-scale precedence.

## Out of scope

- Bengle FW wire identifiers (UUIDs, serial chars, MMR slot for tare). Stubs land null; real Bengle on real HW won't emit weight until FW lands.
- Hardware SAW MMR — D2 deferral.
- Multi-scale concurrent streams — logged in ReaPrime TODO as P2 follow-up.
- LED strip (step 6) and milk probe (step 7).
- Bengle-specific UI (e.g. "internal scale" badge in skins) — capability flag exposed; UI work is downstream.

## FW data needed (post-ship)

- `BengleScaleEndpoint.weight` notify — UUID (BLE) + char representation (serial); frame layout for parsing.
- `BengleScaleEndpoint.control` write — UUID + serial char; tare command payload encoding.
- Tare-via-MMR vs tare-via-control-endpoint — pick one; MMR stub exists for either.
- Scale battery / power telemetry, if any. Default sentinel `100` until proven otherwise.
