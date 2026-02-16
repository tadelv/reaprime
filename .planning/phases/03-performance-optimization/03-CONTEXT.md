# Phase 3: Performance Optimization - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Ensure the telemetry system (built in Phases 1-2) adds zero UI overhead under real-world BLE operation. Primary focus is connection diagnostics — reliably capturing scan/connect failures without impacting the scan/connect flow itself. NOT about surviving high-frequency data floods during shots.

</domain>

<decisions>
## Implementation Decisions

### Degradation strategy
- UI always wins — zero tolerance for jank from telemetry
- When telemetry would impact UI, defer reports to a bounded queue (not drop)
- Queue cap: bounded (e.g., max 10 pending reports), FIFO eviction when full (drop oldest, keep newest)
- Rate limiter from Phase 2 (60-second dedup window) remains as first line of defense
- Queue sits on top of rate limiter as additional backpressure

### Verification scope
- Priority platforms: Android tablet + macOS
- Key profiling scenario: scan for devices → attempt connections (some fail) → verify telemetry captures useful diagnostics without impacting scan/connect flow
- Shot-time BLE throughput is NOT the primary concern
- Manual profiling via DevTools timeline, not automated benchmarks
- Connection failure diagnostics are the telemetry priority — understanding why connections fail so remedies can be built

### Long-running behavior
- App runs as headless gateway for hours (8-12+) — memory management must account for this
- 16kb log buffer cap is sufficient memory safeguard — no additional self-monitoring needed
- BLE reconnections are continuations, not new sessions — same telemetry context, reconnection logged as event with duration-disconnected
- Report queue is in-memory only — app restart loses queued reports, and that's acceptable

### Carry-forward fixes
- Fix LogBuffer size enforcement bug (premature break in while loop) — fits naturally in performance phase
- Skip ErrorReportThrottle unit tests — not in scope for this phase

### Claude's Discretion
- Queue implementation approach (isolate, microtask, or sync with async send)
- Exact queue capacity number
- DevTools profiling methodology details
- LogBuffer fix implementation

</decisions>

<specifics>
## Specific Ideas

- Connection failure diagnostics are the real value — "figure out how to remedy failed connection attempts"
- The app runs on DE1 tablets as a gateway serving WebUI skins — long-running is the primary mode
- Reconnection events should capture how long the device was disconnected

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-performance-optimization*
*Context gathered: 2026-02-16*
