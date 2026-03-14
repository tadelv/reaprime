# Data Sync Feature Design

## Overview

Add a sync endpoint to the existing data export/import group that enables two Bridge instances to exchange data over HTTP. Builds on the existing ZIP-based export/import infrastructure.

## Endpoint

```
POST /api/v1/data/sync
```

### Request Body

```json
{
  "target": "http://192.168.1.50:8080",
  "mode": "pull | push | two_way",
  "onConflict": "skip | overwrite",
  "sections": ["profiles", "beans", "grinders"]
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `target` | yes | — | Base URL of the other Bridge instance |
| `mode` | yes | — | `pull`, `push`, or `two_way` |
| `onConflict` | no | `skip` | Conflict strategy: `skip` or `overwrite` |
| `sections` | no | all | Which data sections to sync |

### Modes

| Mode | Steps |
|------|-------|
| `pull` | GET `{target}/api/v1/data/export` → import locally |
| `push` | Export locally → POST to `{target}/api/v1/data/import?onConflict={strategy}` |
| `two_way` | Pull first, then push |

### Response

```json
{
  "pull": { "profiles": { "imported": 5, "skipped": 2 }, ... },
  "push": { "profiles": { "imported": 3, "skipped": 1 }, ... }
}
```

- `pull`-only: just pull results (no `push` key)
- `push`-only: just push results (no `pull` key)
- `two_way`: both keys

### Error Responses

- **Target unreachable** — HTTP 502:
  ```json
  { "error": "Target unreachable", "message": "Could not connect to ...: Connection refused" }
  ```

- **Target returns non-200** — forward status and body:
  ```json
  { "error": "Target error", "status": 400, "message": "..." }
  ```

- **Two-way partial failure** — HTTP 207 (multi-status):
  ```json
  {
    "pull": { "profiles": { "imported": 5 } },
    "push": { "error": "Target unreachable", "message": "..." }
  }
  ```

## Architecture

### Approach: Internal reuse (Approach A)

The sync handler reuses `DataExportHandler`'s export/import logic directly — no localhost HTTP round-trips, no duplication.

### Refactoring `DataExportHandler`

Extract two public methods from existing private handler logic:

- **`exportToBytes({List<String>? sections})`** → `Future<List<int>>` — returns ZIP bytes, optionally filtered to specific sections
- **`importFromBytes(List<int> zipBytes, ConflictStrategy strategy, {List<String>? sections})`** → `Future<Map<String, dynamic>>` — imports from ZIP bytes, returns per-section results

Existing `_handleExport` and `_handleImport` become thin wrappers around these. No behavior change to existing endpoints.

### Section filtering

Filtering happens at export time — only requested sections are included in the ZIP. This means push/two_way works with any target Bridge version (target imports everything in the ZIP, which is already filtered).

### New `DataSyncHandler`

Standalone handler (not `part of webserver_service.dart`). Dependencies:

- `DataExportHandler` — for `exportToBytes()` and `importFromBytes()`
- `http.Client` — for HTTP calls to target (injected for testability)

## Testing

### Unit tests

Mock `http.Client` and `DataExportHandler`. Cover:
- Each mode (pull/push/two_way)
- Section filtering
- Error cases: target unreachable, non-200 responses, partial two-way failures
- Request validation: missing target, invalid mode, invalid onConflict

### Integration tests

Real `DataExportHandler` with mock sections + mock HTTP client. Verify end-to-end: pull imports, push exports and sends.

### MCP verification

Sync a local mac instance with another Bridge instance on the network to verify real-world behavior.
