# Phase 2 Context: Integration & Error Detection

## Decisions (LOCKED)

1. **Global log listener** — Single `Logger.root.onRecord` handler for WARNING+ that calls `telemetryService.recordError()` with the log buffer attached. No per-component injection for error reporting.

2. **Custom keys: only existing fields** — No need to add RSSI or other fields that don't already exist on the transport interfaces. Use what's available: device type, connection state.

3. **Device snapshot via always-updated custom keys (Option A)** — DeviceController calls `telemetryService.setCustomKey()` on connect/disconnect events to keep device state in sync. Every error report automatically includes the latest device state. No snapshot-at-error-time needed.

4. **Log export endpoint** — Simple `GET /api/v1/logs` returning the log buffer contents. No elaborate filtering or pagination.

## Claude's Discretion

- How to split work into plans
- Implementation details of the log listener registration
- Where exactly to place `setCustomKey` calls in DeviceController
- Handler implementation details for the REST endpoint

## Deferred Ideas

- RSSI tracking on BLE transport interface
- Per-component telemetry injection for error reporting (global listener handles this instead)
- Complex log export with filtering/pagination
