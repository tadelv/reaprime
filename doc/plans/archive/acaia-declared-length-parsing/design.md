# Acaia Declared-Length Parsing

## Goal

Accept protocol-correct Lunar and Pyxis weight notifications without weakening frame isolation or readiness checks.

## Approach

1. Keep byte 3 as the declared span from the length byte through the semantic event records, with the two checksum bytes outside that span.
2. Isolate a complete frame before semantic parsing.
3. Validate direct weight bodies and tagged records within the isolated event payload.
4. Validate heartbeat wrappers and inner records without treating timer, button, unknown, or incomplete records as weight.
5. Preserve liveness updates only for structurally accepted frames and retain bounded resynchronization for impossible or malformed candidates.
6. Replace old synthetic fixtures with protocol-correct frames and cover real, split, concatenated, truncated, embedded-header, and initialization paths.

## Scope Decision

The notification-request timer interval is independent of the reported weight initialization failure. Compare it with the reference implementations and keep any correction clearly separate in the pull request with a focused test.

## Verification

Run formatting, the Acaia unit test, affected BLE tests, `flutter analyze`, and the full Flutter test suite where the repository environment permits.
