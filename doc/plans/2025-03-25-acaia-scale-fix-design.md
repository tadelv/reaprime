# Acaia Scale Fix — Design Spec

**Issue:** [#110](https://github.com/tadelv/reaprime/issues/110) — Can't pair with Acaia Lunar

**Date:** 2026-03-25

## Problem

Reaprime's Acaia scale support has three issues:

1. **Name matching too narrow** — Only matches names containing `"acaia"`. Newer Acaia scales advertise as `"LUNAR"`, `"PEARL"`, `"PEARLS"`, `"PROCH"`, or `"PYXIS"` without the "Acaia" prefix. These are invisible to Reaprime.

2. **No init retry loop** — de1app and Decenza retry the ident+config handshake up to 10 times at 500ms intervals. Reaprime retries once, which is insufficient for scales that are slow to respond.

3. **Single tare unreliable** — de1app and Decenza send tare 3 times (0ms, 100ms, 200ms) because Acaia Lunar hardware is unreliable with single tare commands. Reaprime sends once.

## Design

### Approach: Unified AcaiaScale with Protocol Auto-Detection

Merge `AcaiaScale` (IPS) and `AcaiaPyxisScale` into a single `AcaiaScale` class that auto-detects the protocol at connection time based on discovered BLE services.

**Rationale:** Matches the Decenza approach. More robust than name-based protocol routing because it's immune to Acaia changing their naming conventions.

### 1. Name Matching (`device_matcher.dart`)

Single catch-all rule replacing the current split:

```
nameLower contains: "acaia" | "lunar" | "pearl" | "proch" | "pyxis" → AcaiaScale
```

Order matters: check these BEFORE the generic contains matches. The `"pyxis"` check no longer routes to a separate class.

Remove `AcaiaPyxisScale` import.

### 2. Protocol Auto-Detection (`acaia_scale.dart`)

```dart
enum AcaiaProtocol { ips, pyxis }
```

In `onConnect()`, after `discoverServices()`:
- If Pyxis service UUID (`49535343-fe7d-4ae5-8fa9-9fafd205e455`) found → `AcaiaProtocol.pyxis`
- Else if IPS service UUID (`1820`) found → `AcaiaProtocol.ips`
- Else → throw (not an Acaia scale)

Protocol affects:
- **Service/characteristic UUIDs** used for subscribe/write
- **Write type**: IPS = `withResponse: false`, Pyxis = `withResponse: true`
- **Watchdog timer**: Pyxis only (5s timeout, matches existing behavior)
- **Notification enable delay**: IPS = 100ms, Pyxis = 500ms

Everything else is shared: encoding, parsing, heartbeat, tare, weight decoding.

### 3. Init Retry Loop

After enabling notifications:
1. Send ident (0x0B)
2. Wait 200ms, send config (0x0C)
3. Wait 500ms
4. If `_receivingNotifications` is still false, repeat from step 1
5. Max 10 retries, then give up (log warning, continue — scale may still work)
6. Once notifications received, start heartbeat timer (3s interval, matching Decenza)

### 4. Tare Reliability

Send tare command 3 times with 100ms spacing:
```dart
Future<void> tare() async {
  _sendTare();
  await Future.delayed(Duration(milliseconds: 100));
  _sendTare();
  await Future.delayed(Duration(milliseconds: 100));
  _sendTare();
}
```

### 5. File Changes

| File | Change |
|------|--------|
| `lib/src/services/device_matcher.dart` | Unified Acaia name matching, remove AcaiaPyxisScale import |
| `lib/src/models/device/impl/acaia/acaia_scale.dart` | Rewrite: auto-detect protocol, init retry, 3x tare, watchdog for Pyxis |
| `lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart` | Delete |
| Tests referencing `AcaiaPyxisScale` | Update to use `AcaiaScale` |

### 6. BLE Identifiers Reference

**IPS Protocol (older ACAIA, PROCH):**
- Service: `0000-1820-0000-1000-8000-00805f9b34fb`
- Characteristic (notify+write): `0000-2a80-0000-1000-8000-00805f9b34fb`

**Pyxis Protocol (LUNAR, PEARL, PEARLS, PYXIS, newer ACAIA):**
- Service: `49535343-fe7d-4ae5-8fa9-9fafd205e455`
- Status (notify): `49535343-1e4d-4bd9-ba61-23c647249616`
- Command (write): `49535343-8841-43f4-a8d4-ecbe34729bb3`

### 7. Testing

- Unit test: name matching covers all Acaia variants (ACAIA, Lunar, PEARL-S, PROCH, PYXIS, mixed case)
- Unit test: protocol auto-detection selects correct protocol based on discovered services
- Manual: verify with actual Acaia Lunar hardware if available
