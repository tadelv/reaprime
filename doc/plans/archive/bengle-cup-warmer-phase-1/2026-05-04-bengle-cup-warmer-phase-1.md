# Bengle cup warmer — Phase 1

Branch: `feat/bengle-cup-warmer-phase-1`. Will be copied to `doc/plans/` on the feature branch before implementation per CLAUDE.md (design docs live with the code).

## Context

Bengle is the next-gen Decent espresso machine; SB needs to expose its peripherals (cup warmer, integrated scale, LED, milk probe) via REST so skins can drive them. Foundation shipped (PR #207, #208): `Bengle extends UnifiedDe1`, `LogicalEndpoint` + `MmrAddress` interfaces, `@protected` MMR helpers. **Phase 1 lands the first capability — cup warmer — and the discovery pattern that steps 5–7 will reuse.** Schedule (preheat-cups-before-wake) is deferred to Phase 2 pending FW data on whether the mat heats while machine sleeps.

FW info (Vid, 2026-05-04):
- MMR `MatSetPoint` at `0x00803874`, length 4, perm RWD.
- Raw IEEE-754 float32, little-endian (matches existing MMR endianness).
- Range 0.0 – 80.0 °C, FW-clamped. App clamps before write to avoid silent rejects.
- `0.0` = off. No separate enable flag.
- API: `setCupWarmerTemperature(double)` / `getCupWarmerTemperature()`. No boolean.
- No actual-temperature MMR confirmed → no WS topic in Phase 1.

## Approach

### 1. New MMR value kind: `float32`

Add to existing `MmrValueKind` enum in `lib/src/models/device/impl/de1/mmr_address.dart:12-30`:

```dart
/// IEEE-754 float32 stored as raw 4 bytes (little-endian on the wire).
/// Bounds declared via [MmrAddress.minDouble] / [MmrAddress.maxDouble].
float32,
```

Add to `MmrAddress` interface (same file, after the `int? max` getter):

```dart
/// Optional minimum bound for float32 kind; null = no lower clamp.
double? get minDouble => null;

/// Optional maximum bound for float32 kind; null = no upper clamp.
double? get maxDouble => null;
```

No clash — `int? min`/`max` and `double? minDouble`/`maxDouble` coexist. Existing `_writeMMRInt` / `writeMmrScaled` callers untouched.

### 2. Float32 read/write helpers on `UnifiedDe1`

Two new `@protected` methods in `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` (after `writeMmrScaled` at line 593):

```dart
@protected
Future<double> readMmrFloat32(MmrAddress addr) async {
  _assertKind(addr, const {MmrValueKind.float32}, 'readMmrFloat32');
  final raw = (addr is MMRItem) ? await _mmrRead(addr) : await _mmrReadRaw(addr.address);
  return _unpackMMRFloat32(raw);
}

@protected
Future<void> writeMmrFloat32(MmrAddress addr, double value) async {
  _assertKind(addr, const {MmrValueKind.float32}, 'writeMmrFloat32');
  final clamped = (addr.minDouble != null && addr.maxDouble != null)
      ? value.clamp(addr.minDouble!, addr.maxDouble!)
      : value;
  final bytes = _packMMRFloat32(clamped.toDouble());
  if (addr is MMRItem) return _mmrWrite(addr, bytes);
  return _mmrWriteRaw(addr.address, bytes);
}
```

Pack/unpack helpers in `lib/src/models/device/impl/de1/unified_de1/unified_de1.mmr.dart` paralleling `_packMMRInt` / `_unpackMMRInt`:

```dart
double _unpackMMRFloat32(List<int> buffer) {
  if (buffer.length < 20) {
    throw StateError('MMR response buffer too short (got ${buffer.length}, need 20)');
  }
  final bytes = ByteData(20);
  for (var i = 0; i < 20; i++) { bytes.setUint8(i, buffer[i]); }
  return bytes.getFloat32(4, Endian.little);
}

Uint8List _packMMRFloat32(double value) {
  final bytes = ByteData(4);
  bytes.setFloat32(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}
```

### 3. Bengle cup warmer surface

**New file** `lib/src/models/device/impl/bengle/bengle_mmr.dart`:

```dart
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';

/// Bengle-only MMR addresses. Future Bengle peripherals (LED, integrated
/// scale, milk probe) add entries here as their FW MMR slots are confirmed.
enum BengleMmr implements MmrAddress {
  matSetPoint(0x00803874, 4, MmrValueKind.float32, 'MatSetPoint',
      minDouble: 0.0, maxDouble: 80.0);

  const BengleMmr(this.address, this.length, this.kind, this.description,
      {this.minDouble, this.maxDouble});

  @override final int address;
  @override final int length;
  @override final MmrValueKind kind;
  final String description;
  @override final double? minDouble;
  @override final double? maxDouble;

  @override
  String get name => (this as Enum).name;
}
```

**Edit** `lib/src/models/device/bengle_interface.dart` — add 2 abstract methods:

```dart
/// Set cup-warmer mat target temperature in °C. Range 0.0–80.0.
/// `0.0` turns the mat off. Values outside the range are clamped.
Future<void> setCupWarmerTemperature(double celsius);

/// Read the current cup-warmer mat setpoint in °C.
Future<double> getCupWarmerTemperature();
```

**Edit** `lib/src/models/device/impl/bengle/bengle.dart` — implement:

```dart
@override
Future<void> setCupWarmerTemperature(double celsius) =>
    writeMmrFloat32(BengleMmr.matSetPoint, celsius);

@override
Future<double> getCupWarmerTemperature() =>
    readMmrFloat32(BengleMmr.matSetPoint);
```

Cup warmer is stateless — no mixin needed, no `onConnect` override. Direct calls to the protected MMR helpers prove the abstraction works.

### 4. MockBengle in-memory mirror

**Edit** `lib/src/models/device/impl/bengle/mock_bengle.dart` — add field + 2 method overrides (matches `MockDe1` pattern A from `mock_de1.dart`):

```dart
double _cupWarmerTemp = 0.0;

@override
Future<void> setCupWarmerTemperature(double celsius) async {
  _cupWarmerTemp = celsius.clamp(0.0, 80.0);
}

@override
Future<double> getCupWarmerTemperature() async => _cupWarmerTemp;
```

### 5. REST endpoints

**Edit** `lib/src/services/webserver/de1handler.dart`. Add 3 routes inside `addRoutes`:

```dart
app.get('/api/v1/machine/capabilities', (Request _) async {
  return withDe1((de1) async {
    final caps = <String>[];
    if (de1 is BengleInterface) caps.add('cupWarmer');
    return jsonOk({'capabilities': caps});
  });
});

app.get('/api/v1/machine/cupWarmer', (Request _) async {
  return withDe1((de1) async {
    if (de1 is! BengleInterface) {
      return Response.notFound(jsonEncode({'error': 'cupWarmer not supported'}));
    }
    final t = await de1.getCupWarmerTemperature();
    return jsonOk({'temperature': t});
  });
});

app.post('/api/v1/machine/cupWarmer', (Request r) async {
  return withDe1((de1) async {
    if (de1 is! BengleInterface) {
      return Response.notFound(jsonEncode({'error': 'cupWarmer not supported'}));
    }
    final json = jsonDecode(await r.readAsString());
    if (json['temperature'] == null) {
      return Response.badRequest(body: jsonEncode({'error': 'temperature required'}));
    }
    final t = parseDouble(json['temperature']);
    if (t < 0.0 || t > 80.0) {
      return Response.badRequest(body: jsonEncode({'error': 'temperature out of range 0.0-80.0'}));
    }
    await de1.setCupWarmerTemperature(t);
    return jsonAccepted();
  });
});
```

Notes:
- `BengleInterface` import added at top of `de1handler.dart`.
- 404 (not 500) when machine connected but isn't Bengle — explicit "feature absent" vs. "no machine".
- 400 for out-of-range — surfaced to clients before silent FW clamp.
- POST + 202 mirrors existing `/machine/settings` convention.

### 6. OpenAPI spec

**Edit** `assets/api/rest_v1.yml`. Add 3 paths in the `/api/v1/machine/...` section, plus 2 components schemas (`CupWarmerState`, `Capabilities`). Mirror the existing `/machine/info` (GET) and `/machine/profile` (POST) entry styles.

### 7. doc/Api.md

**Edit** `doc/Api.md` — add 3 rows to the Machine table:

```markdown
| GET | `/api/v1/machine/capabilities` | List of capability strings supported by current machine | `de1handler.dart` |
| GET | `/api/v1/machine/cupWarmer` | Read cup-warmer setpoint (Bengle only) | `de1handler.dart` |
| POST | `/api/v1/machine/cupWarmer` | Set cup-warmer setpoint °C 0.0-80.0 (Bengle only) | `de1handler.dart` |
```

### 8. Tests

**Tier breakdown** (per `tdd-workflow` skill):

**Unit:**
- `test/models/device/mmr_address_test.dart` — new `MmrValueKind.float32` exists; `minDouble`/`maxDouble` default null.
- `test/models/device/unified_de1_float32_test.dart` — write+read round-trip for `BengleMmr.matSetPoint` using `FakeBleTransport`. Cover: round-trip mid-range value (50.0 °C), clamp on over-range write (90.0 → clamped), clamp on negative (-5.0 → 0.0). Add `queueMmrResponseFloat32(addr, value)` helper to `test/helpers/fake_ble_transport.dart` (small wrapper around `queueMmrResponseRaw` + `setFloat32(0, value, little)` packing).
- `test/models/device/unified_de1_assert_kind_test.dart` (extend existing or new) — `readMmrFloat32` on a non-float32 address throws `StateError`; `readMmrInt` on float32 address throws.
- `test/models/device/mock_bengle_test.dart` — set then get round-trip; clamp behavior.

**Integration:**
- `test/services/webserver/de1handler_cup_warmer_test.dart` — three handler tests via in-process router: `GET /capabilities` returns `cupWarmer` when DE1 controller has Bengle, empty list otherwise; `GET /cupWarmer` 404 on plain DE1, 200 with body on MockBengle; `POST /cupWarmer` 400 on out-of-range body, 202 + state mutation on valid body.

**End-to-end:**
- `.agents/skills/streamline-bridge/scenarios/bengle-cup-warmer.md` — new recipe. Boots app via `scripts/sb-dev.sh start --connect-machine MockBengle`, exercises:
  1. `curl /capabilities` → assert `["cupWarmer"]`.
  2. `curl /cupWarmer` → assert `temperature: 0.0`.
  3. `curl POST /cupWarmer {temperature: 60}` → 202.
  4. `curl /cupWarmer` → assert `temperature: 60.0`.
  5. `curl POST /cupWarmer {temperature: 100}` → 400.

## Files

| Path | Change |
|---|---|
| `lib/src/models/device/impl/de1/mmr_address.dart` | Add `float32` to enum, add `minDouble`/`maxDouble` getters |
| `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` | Add `readMmrFloat32`/`writeMmrFloat32` protected methods |
| `lib/src/models/device/impl/de1/unified_de1/unified_de1.mmr.dart` | Add `_packMMRFloat32`/`_unpackMMRFloat32` |
| `lib/src/models/device/impl/bengle/bengle_mmr.dart` | NEW — `BengleMmr` enum |
| `lib/src/models/device/bengle_interface.dart` | Add 2 abstract methods |
| `lib/src/models/device/impl/bengle/bengle.dart` | Implement 2 methods |
| `lib/src/models/device/impl/bengle/mock_bengle.dart` | Add field + 2 method overrides |
| `lib/src/services/webserver/de1handler.dart` | Add 3 routes (capabilities, cupWarmer GET/POST) |
| `assets/api/rest_v1.yml` | Add 3 paths + 2 schemas |
| `doc/Api.md` | Add 3 table rows |
| `test/helpers/fake_ble_transport.dart` | Add `queueMmrResponseFloat32` helper |
| `test/models/device/unified_de1_float32_test.dart` | NEW — float32 round-trip + clamp |
| `test/models/device/unified_de1_assert_kind_test.dart` | NEW — kind mismatch errors |
| `test/models/device/mock_bengle_test.dart` | NEW — mock state mirror |
| `test/services/webserver/de1handler_cup_warmer_test.dart` | NEW — handler integration |
| `.agents/skills/streamline-bridge/scenarios/bengle-cup-warmer.md` | NEW — e2e recipe |
| `doc/plans/2026-05-04-bengle-cup-warmer-phase-1.md` | NEW — copy this plan onto branch (per CLAUDE.md) |

## Reused

- `withDe1`, `jsonOk`, `jsonAccepted`, `parseDouble` — webserver_service helpers (`de1handler.dart:44+`).
- `FakeBleTransport.queueOnConnectResponses` — boots a fake DE1 to `connected` state for tests.
- `FakeBleTransport.queueMmrResponseRaw` — base for the new float32 helper.
- `_mmrRead` / `_mmrReadRaw` / `_mmrWrite` / `_mmrWriteRaw` (`unified_de1.mmr.dart`) — wire-protocol layer the new helpers ride on, no changes.
- `_assertKind` (`unified_de1.dart:606`) — kind validation.
- `MockDe1` Pattern A (field + getter, e.g. `_flushFlow`) — MockBengle mirror.

## Verification

1. `flutter analyze` — must be clean.
2. `flutter test` — full suite + the 4 new test files.
3. End-to-end smoke via `.agents/skills/streamline-bridge/scenarios/bengle-cup-warmer.md`:
   - `scripts/sb-dev.sh start --connect-machine MockBengle`
   - Walk steps 1–5 with `curl` + `jq -e` assertions.
   - `scripts/sb-dev.sh stop`.
4. Regression sweep: walk `.agents/skills/streamline-bridge/scenarios/build-info.md` and any existing `/machine/*` recipe to confirm no neighbouring breakage.
5. Real-hw smoke deferred (no bench Bengle right now); will run when available.

## Out of scope (Phase 2 / later)

- Cup-warmer wake schedule integration (`WakeSchedule.cupWarmerLeadMinutes` + `cupWarmerTemperature`). Gated on FW: does the mat heat while machine `sleeping`?
- WS topic for actual mat temperature. Gated on FW: is there a readable mat-temp MMR?
- App-side runaway protection / auto-off. Gated on FW: does FW have its own?
- Capability negotiation in plugin/skin permission system.

## Branch + PR

- Branch already created: `feat/bengle-cup-warmer-phase-1` (off `main`).
- Commit per logical step (helpers / Bengle wiring / mock / REST + spec + doc / tests / scenario).
- PR on `main` after `flutter test` + `flutter analyze` + e2e scenario all green. PR body: what + why per global instructions.
