# BLE Scanning Refactor Proposal — reaprime

## Problem

The current scanning implementation relies on service UUID filtering to discover coffee machine peripherals. Research shows this approach is fragile across the platforms reaprime targets. On Android (9–15), UUID filters only match UUIDs present in the **primary advertisement packet** — but many devices put their 128-bit UUID in the scan response instead, causing silent misses. Android also throttles scan starts to 5 per 30 seconds (since Android 7), silently returns zero results when exceeded, and pauses unfiltered scans when the screen is off (since Android 8.1). On Linux/BlueZ, UUID filtering is a software-side mechanism in the daemon, not a hardware gate — and with shared discovery sessions, another process's open scan can override our filter entirely.

## Proposed Approach

Replace UUID-based scan filtering with a **two-phase strategy**: broad scan with name-prefix matching, followed by post-connection service verification.

**Phase 1 — Scan:** Start a scan with a minimal `ScanFilter` (Android) or `transport: "le"` only (BlueZ). This satisfies Android's screen-off requirement without relying on UUID matching. In the scan result callback, filter devices by name prefix in software (e.g. `"DE1"`, `"Decent"`, or whatever the machine advertises). Use `SCAN_MODE_LOW_LATENCY` for the initial foreground scan, `SCAN_MODE_BALANCED` for anything longer than 30 seconds. Strictly track scan start count to stay within the 5-per-30s limit.

**Phase 2 — Verify:** After connecting, call `discoverServices()` and confirm the expected service UUIDs exist before proceeding. Cache the MAC address on first successful connection so subsequent reconnects bypass scanning entirely and go straight to `connectToDevice(address)`.

## Benefits

This approach is more reliable on firmware we don't control, survives Android version fragmentation, avoids BlueZ filter-merge edge cases, and makes the code easier to reason about — the scan finds candidates, the connection verifies them.
