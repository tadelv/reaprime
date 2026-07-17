# Profile Upload Recovery: Design Rationale

## The Failure Mode

The DE1 firmware has a `ProfileDownloadInProgress` flag that is set when a
profile upload begins (header write) and cleared when the upload completes
successfully (tail write + flash commit). If the upload dies mid-sequence —
for example a GATT write timeout on a flaky BLE link — the flag stays set
indefinitely (no firmware timeout, no clear on disconnect). While the flag is
set, the machine silently ignores all start requests and pulses its group-head
LED (magenta, ~2 Hz), appearing bricked to the user.

The app could not self-heal because:

1. Two cache layers — the sync's `_lastPushedProfile` and the device-level
   `UnifiedDe1._currentProfile` — each prevented a same-profile re-upload.
2. The connect-time profile upload lived in `De1Controller._setDe1Defaults`,
   which was single-shot: its exception was caught only by the generic
   transport error handler, so a mid-sequence failure was invisible.
3. `_lastPushedProfile` was seeded optimistically from the persisted workflow
   at construction time, so the sync believed the machine already held the
   selected profile on first connect.

## Fix Summary

### Cache Layer 1: WorkflowDeviceSync._lastPushedProfile

- Starts null (never seeded from persistence).
- Cleared on every connection edge (`_onDe1Change(null)` sets it null).
- Invalidated on any upload failure (`_lastPushedProfile = null` in catch).
- Set only after a successful `setProfile` call returns.
- The equality guard (`profile == _lastPushedProfile`) deduplicates within
  one uninterrupted connection but never across a connection edge.

### Cache Layer 2: UnifiedDe1._currentProfile

- Cleared at the start of every `onConnect()` call — before the `_info` guard
  that would skip the rest of `onConnect()` on reconnect.
- Also nulled inside `_uploadProfileLocked` before the multi-write sequence
  starts, and set only after `_sendProfile` returns.
- This is the tightest defence: even a caller that bypasses
  `WorkflowDeviceSync` (e.g. `POST /api/v1/machine/profile`) and calls
  `setProfile` directly on a reused `UnifiedDe1` instance gets a complete
  upload after every connection edge.

### Startup Ordering

The on-connect profile push moved from `De1Controller._setDe1Defaults` to
`WorkflowDeviceSync._onInitSettled`. The trigger is a new
`De1Controller.initSettled` stream that fires after machine readiness AND
startup defaults complete. This preserves the old effective ordering:
startup/default writes first, profile synchronization afterward.

The push does NOT fire from the raw de1 stream event, which arrives during
`_connectToDe1` before `_initializeData` runs. A generation token on both
sides guards against stale init completions from a disconnected generation.

### Ownership

`WorkflowDeviceSync` owns all workflow-driven profile synchronization.
Neither `De1Controller._setDe1Defaults` nor any other path pushes a profile
on connect — they delegate entirely to the sync.

### Error Lifecycle

`profileUploadFailed` is a new `ConnectionErrorKind` that survives phase
transitions (not transient, not sticky — a third classification:
phase-persistent). It is emitted once per failing retry cycle, on the first
failure. It is retracted when:

- A retry successfully uploads the desired profile.
- The machine disconnects (terminating the retry cycle).
- The sync is disposed.

The `onUploadErrorCleared` callback is invoked on all three conditions.
`ConnectionManager.clearErrorOfKind` checks `kind` before clearing, so an
unrelated error that has replaced `profileUploadFailed` is never stomped.

### Alternatives Considered

1. **Expose a cache-reset method on UnifiedDe1.** Rejected because the
   production cache is owned by `UnifiedDe1` and should be reset by the
   connection lifecycle, not by an ad hoc external caller. Clearing in
   `onConnect()` is automatic and covers every path that uses the same
   device instance.

2. **Keep the push in _setDe1Defaults and add retry there.** Rejected because
   that path is called from `_initializeData` and would require threading
   retry/error logic through `De1Controller`, which has no business owning
   profile synchronization. The sync already has serialization, retry, and
   error surfacing — give it the trigger.

3. **Delay with Timer.** Rejected because a fixed delay is fragile (too short
   on slow transports, too long on fast ones). The `initSettled` signal is
   event-driven and race-free.

4. **Firmware-side fix.** A FW latch timeout or clear-on-disconnect would be
   more robust, but that's a separate change. The app-side fix is sufficient:
   a full re-upload on every connect clears the latch regardless.
