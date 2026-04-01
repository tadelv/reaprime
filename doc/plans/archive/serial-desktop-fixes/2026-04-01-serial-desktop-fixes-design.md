# Serial Desktop Fixes Design

## Context

Three bugs in the desktop serial service, reported via Firebase crash report and GitHub issue #123.

## Bug 1: hexToBytes crash on fragmented serial reads

**Root cause:** The message regex `(\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n|$)` in `unified_de1_transport.dart` uses `$` as a lookahead anchor. When serial data arrives in multiple chunks, `$` matches end-of-buffer, causing incomplete hex payloads to be parsed. `hexToBytes` throws on the odd-length string.

**Fix:**
- Remove `$` from the regex lookahead: `(?=\[|\n)` — messages are only matched when terminated by newline or next message prefix. Partial data stays in `_currentBuffer`.
- In `_processDe1Response`, wrap the `hexToBytes` call in try-catch. On FormatException, report non-fatal error to telemetry and skip the message. Keep the throw in `hexToBytes` itself.

## Bug 2: Duplicate DE1 detection (issue #123)

**Root cause:** In `serial_service_desktop.dart:79-83`, deduplication compares `device.deviceId` (which is `_port.address`) against port path strings from `SerialPort.availablePorts`. These are different values, so the filter never matches.

**Fix:** Store the port path used to create the device. Use port paths (not device IDs) for the `connectedIds` set in the scan filter.

## Bug 3: Write errors don't disconnect

**Root cause:** Serial write failures throw but never update connection state. Read errors properly call `disconnect()`, but write errors leave a stale "connected" state.

**Fix:** In the serial write path, catch write failures and call `disconnect()` to update the connection state stream, matching read error behavior.
