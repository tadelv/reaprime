# Phase 4: WebView Integration - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Capture JavaScript console output from WebUI skins in a separate log stream. WebView logs are fully isolated from app logs — different file, different stream, different API endpoints. Skin developers get a live WebSocket stream for development. User feedback flows can include webview logs when submitting reports.

</domain>

<decisions>
## Implementation Decisions

### Capture scope
- Capture ALL console methods: log, warn, error, debug, info — everything the skin outputs
- No filtering or rate limiting — skins are responsible for their own noise level
- WebView logs are fully isolated from app logs — never cross over to package:logging or telemetry
- Full metadata per line: `[timestamp] [skinId] [level] message`

### Log file lifecycle
- Clear webview_console.log on app restart — fresh log each launch
- Maximum file size: 1MB cap
- When cap is hit: truncate oldest entries (drop first half, keep recent)
- File location: same directory as existing app logs (~/Download/REA1/ on Android, app documents on other platforms)
- Log entries persist across skin reloads within the same app session

### API exposure
- Separate REST endpoint: `GET /api/v1/webview/logs` (not merged with existing /api/v1/logs)
- REST returns raw text (plain log file contents)
- WebSocket live stream at `ws/v1/webview/logs` — mirrors existing `ws/v1/logs` pattern
- WebSocket streams all levels, no server-side filtering — clients filter if needed

### Multi-skin handling
- Single shared log file for all skins — skin ID in metadata distinguishes entries
- Only one skin runs at a time in practice (active/displayed skin)
- Log entries persist across skin reloads until app restart or size cap

### Claude's Discretion
- Whether to include skin ID in every WebSocket message or only when relevant
- Internal implementation of the log capture bridge between WebView and Dart
- Exact truncation strategy when hitting 1MB cap

</decisions>

<specifics>
## Specific Ideas

- Existing `ws/v1/logs` endpoint serves as the pattern — webview WS should feel the same to consumers
- Skin developers are the primary audience for the WebSocket stream — they need it during development to debug their skins without opening the WebView devtools
- The existing separate webview log file concept was already a decision from Phase 1 context ("Separate webview log file — isolates skin debug output")

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-webview-integration*
*Context gathered: 2026-02-16*
