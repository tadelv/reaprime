# Bounded-Memory Backup Export, Import, and Sync (issue #555)

## Problem

The backup pipeline keeps several full representations of the same data in
memory at once. On the server, `DataExportHandler` materializes section
models, JSON strings, an in-memory `Archive`, and the final ZIP byte list.
Import buffers the entire request with `toList()`, then decodes the full ZIP
and section JSON. The native caller accumulates an export in a `BytesBuilder`
and reads an entire import file before uploading. `DataSyncHandler` builds on
the same byte-oriented APIs. As shot history grows (especially with
measurement arrays) these overlapping copies can terminate constrained iOS
devices.

Root cause on the ZIP layer (verified against `archive` 4.0.9 source):
`ZipEncoder.add()` compresses each deflate entry into an in-memory
`OutputMemoryStream` (a section-sized compressed buffer), and
`ZipDecoder.decodeStream()` materializes every entry's compressed bytes with
`input.readBytes(compressedSize)`. `ZipFileEncoder` does not fix this — it
routes through the same `ZipEncoder.add()`. So "use `InputFileStream` /
`ArchiveFile.stream` / `ZipFileEncoder.addFile()`" is not sufficient.

## Approach

Replace byte-oriented ZIP handling with:

1. a small, dependency-free **streaming ZIP writer** (raw-deflate via
   `dart:io` `ZLibCodec(raw: true)` chunked conversion, data descriptors,
   central directory written last) — bounded per-record, streaming straight
   into a uniquely owned temporary file;
2. a small, dependency-free **file-backed ZIP reader** (EOCD + central
   directory scan, per-entry bounded inflate from a `RandomAccessFile`,
   CRC/size verification) — never materializes a whole entry;
3. a real **incremental JSON parser** (token-level state machine with
   string/escape/nesting/UTF-8 handling) yielding bounded values at a
   configurable depth, backed by a strict validation pass before import;
4. a new **streaming section contract** replacing
   `DataExportSection.export()/import(dynamic, ...)`;
5. storage paging seams (keyset cursors) for shots/steams, and
   documented-bounded paging for beans, grinders, profiles, and KV data;
6. staged temp-file transport for HTTP bodies, native transfer, and sync.

## Memory model (peak live data per stage)

| Stage | Peak live memory |
|-------|------------------|
| Server export | 1 page of records (default 200) + 1 encoded record (≤ `maxRecordBytes`) + deflate windows (~64 KiB). Singleton sections (settings/workflow) materialize ≤ `maxRecordBytes` (justified: fixed small payloads, hard-capped). |
| Server import | 1 record + incremental-parser buffers ≤ `maxRecordBytes` + inflate windows. Entry decompressed on the fly from the staged ZIP file; never a whole entry. |
| Native export | Response chunks streamed to a temp file (no `BytesBuilder`); share sheet consumes the temp file. |
| Native import | Picker file streamed into the request (`request.addStream`); no `readAsBytes()`. |
| Sync pull | Response streamed to temp ZIP; import reads from the file. |
| Sync push | Export written to temp ZIP; `File.openRead()` → `StreamedRequest` with `contentLength`. |
| Anywhere | One temp directory per operation; deleted in `finally`. |

Memory scales with batch/record size, never backup size.

## Streaming section contract (`data_export_section.dart`)

```dart
class JsonValueEvent { final int depth; final List<String> keys; final Object? value; }

abstract class JsonSink {
  void writeRaw(String fragment);            // pre-encoded JSON; capped at maxRecordBytes per call
}

abstract class SectionJsonInput {
  Future<JsonContainerKind> open();          // array | object; structural check
  Stream<JsonValueEvent> valuesAtDepth(int depth); // depth 0 = whole doc
}

abstract class DataExportSection {
  String get filename;
  Future<void> exportJson(JsonSink output);
  Future<SectionImportResult> importJson(SectionJsonInput input, ConflictStrategy strategy);
}
```

- Array sections (shots, steams, beans, grinders, profiles) read/write
  elements at depth 1 (beans embed their per-bean `batches` array inside the
  record value).
- KV store reads/writes `{"namespaces": {ns: {k: v}}}` at depth 3.
- Settings/workflow are singletons: read the whole value at depth 0 (capped).
- Import is two-pass per section in the handler: pass 1 validates the whole
  payload structurally (full parse, no mutation); pass 2 imports. Malformed
  JSON (truncation, bad UTF-8, garbage, invalid structure) fails the section
  with an error and imports nothing. Valid JSON with individually invalid
  records keeps current partial-result semantics (per-record try/catch,
  `imported/skipped/errors` accounting).
- Change notifications keep current semantics: shots/steams notify once if
  `imported > 0`.

## ZIP writer (`streaming_zip_writer.dart`)

Local header (flag bits 3 + 11: data descriptor + UTF-8, method 8) with zero
crc/sizes; content fed through `ZLibCodec(raw: true, level: 6)` chunked
conversion whose output sink writes synchronously to a `RandomAccessFile`;
incremental CRC32 via `archive`'s `getCrc32(bytes, crc)`; per-entry data
descriptor (sig + crc + compressed size + uncompressed size); central
directory + EOCD written on `close()`. All offsets/sizes tracked as `int`,
guarded < 4 GiB (no Zip64; documented limit). The ZIP is only complete after
`close()`; the handler returns an error and deletes the temp file if any
section or archive step fails. Compatible with `archive`'s `ZipDecoder`
(data-descriptor support confirmed in `ZipFile.read` flags & 0x08 handling).

## ZIP reader (`streaming_zip_reader.dart`)

Reads the staged temp ZIP via `RandomAccessFile`:

1. EOCD scan from the file tail (max 64 KiB + 22 B window); parse entry
   count, CD offset/size; Zip64 markers (`0xFFFF`/`0xFFFFFFFF`) rejected.
2. Bounded central-directory walk: ≤ `maxEntryCount` entries; per-entry
   name/extra/comment length caps; duplicate filenames rejected; encrypted
   (flag bit 0) and unsupported methods rejected; directory entries skipped;
   symlink entries with a recognized section filename rejected as
   masquerades.
3. Pre-validation: per-entry uncompressed size ≤ `maxEntryUncompressedBytes`;
   sum ≤ `maxTotalUncompressedBytes`.
4. Per-entry streaming inflate with hard output cap (ZIP-bomb protection) and
   CRC + declared-size verification; truncated input and CRC failures fail the
   entry/archive.

## Incremental JSON parser (`incremental_json_parser.dart`)

Real token-level state machine over decoded text chunks: whitespace, strings
with `\` escapes and `\uXXXX` (surrogate pairs), strict JSON numbers, nested
objects/arrays, depth cap (256). Emits `JsonValueEvent`s when a value at a
requested depth completes (key path included for object ancestors). Collects
the raw span of each yielded value (≤ `maxRecordBytes`) and decodes it with
`jsonDecode`. Throws on: unexpected characters, unclosed containers at EOF,
unterminated strings, trailing garbage after document close, nesting depth
overrun, oversize values. UTF-8 boundaries handled by `dart:convert`
`Utf8Decoder` (malformed input throws). Never splits on commas/braces.

## Limits (`data_transfer_limits.dart`, injectable for tests)

| Limit | Value | Justification |
|-------|-------|---------------|
| `maxImportRequestBytes` | 4 GiB − 1 | Hard stream cap while staging; below Zip64 threshold. Bounded by device temp disk; a full-history backup fits. |
| `maxExportTotalUncompressedBytes` | 2 GiB | Sum of section entry sizes; above this export fails atomically (500). |
| `maxEntryUncompressedBytes` | 1 GiB | Per-section cap (also enforced during inflate). |
| `maxEntryCount` | 4096 | Archive has ≤ 10 sections; unknown entries tolerated but bounded. |
| `maxMetadataBytes` | 64 KiB | metadata.json is small. |
| `maxRecordBytes` | 64 MiB | Single record (shot with measurements, profile, KV value, singleton payload). |
| `maxKeyBytes` | 64 KiB | JSON object key in streamed input. |
| `maxFilenameBytes` / `maxExtraFieldBytes` / `maxCommentBytes` | 256 B / 64 KiB / 64 KiB | ZIP header field caps. |
| `maxNestingDepth` | 256 | JSON nesting cap (parser + decode safety). |
| `maxSyncRequestBytes` | 1 MiB | Sync request JSON body. |
| `maxSyncResponseBytes` | 8 MiB | Target import response read cap. |
| `maxImportResponseBytes` | 8 MiB | Native import response read cap. |
| Sync timeouts | connect/header 10 s, idle 30 s, overall 10 min | Distinguish phases; overall bounds the whole transfer. |

Limits are centralized named constants; tests inject tiny values and probe
below/at/above boundaries. Externally visible limits are documented in the
OpenAPI spec and `doc/Api.md`.

## Temporary file ownership and cleanup

Every operation creates one unique temp directory
(`Directory.systemTemp.createTemp('reaprime-...')`):

- Server export: temp dir owns the ZIP; deleted when the response stream
  completes, errors, or the consumer cancels (`onCancel` cleanup).
- Server import: temp dir owns the staged body ZIP; deleted in `finally` on
  success, validation failure, oversized body, stream error, or timeout.
- Sync pull/push: temp dir per phase, deleted in `finally`.
- Native export: temp file is handed to the OS share sheet; immediate
  deletion would race the receiving app, so cleanup is deferred (grace
  timer) — a documented exception. Desktop path deletes after the copy.
- Native import: no temp file (picker path/stream feeds the request).

Concurrent transfers use isolated temp directories; nothing cross-deletes.

## Cancellation, timeout, stream-error behavior

- Import body stream: cancelled on completion, error, size rejection, or
  timeout; no stranded readers.
- Export response stream: `onCancel`/`onError`/`onDone` all delete the temp
  dir exactly once (idempotent).
- Sync: connect/header timeout on `send()`, idle timeout on the response
  stream, overall timeout around the whole phase; each phase's temp dir is
  deleted in `finally` regardless of which failure fired.
- All failures preserve the existing JSON error shapes and `200`/`207`/`400`
  semantics.

## Compatibility

- ZIP entry names and JSON shapes unchanged (including `store.json`'s
  `namespaces` wrapper and beans' embedded `batches`).
- `metadata.json` format/version behavior unchanged; version > supported
  rejected as today.
- Conflict strategies, selected-section behavior, unknown-file tolerance,
  missing-section behavior, platform-mismatch warnings, atomic export,
  non-transactional section isolation, and sync phase/result semantics
  unchanged.
- New exports are readable by `archive` `ZipDecoder` (the previous decoder).
- Old in-memory-generated backups import through the new reader.

## Native page changes (`data_management_page.dart`)

Export: validate HTTP status and `application/zip` MIME before presenting a
destination; stream the localhost response to a temp file (no `BytesBuilder`);
iOS/Android share the temp file via `share_plus` (already a dependency,
`SharePlus.instance.share(ShareParams(files: [XFile(path)]))`); desktop uses
`FilePicker.saveFile` without bytes to obtain a path and `File.copy`s the temp
file; cancellation never reports success.

Import: `FilePicker.pickFiles(withReadStream: true)`; prefer `file.path`
(`File.openRead()`), else `file.readStream` (cloud/provider files); stream
into `HttpClientRequest.addStream` with known `contentLength`; read the JSON
response with a byte cap.

Native export/import logic extracted into a testable helper
(`BackupTransferService`) with injectable HTTP client, share, and picker
functions, so tests run without platform pickers/sheets.

## Sync changes (`data_sync_handler.dart`)

- Pull: `client.send` (streamed GET) → validate status → stream response to
  temp ZIP → `importFromZipFile`.
- Push: export to temp ZIP → `http.StreamedRequest` with `contentLength` and
  `addStream(File.openRead())`.
- Two-way keeps pull-before-push and `continueOnPullFailure` semantics.
- Response bodies read with `maxSyncResponseBytes` cap; timeouts as above.
- Result classification (`_failure`, `_response`, legacy flat + structured
  `phases`) unchanged.

## Tests (mapped to acceptance criteria)

1. Old in-memory `ZipEncoder` backup imports through the new file path.
2. New streamed export decodes with `ZipDecoder`.
3. Entry names and decoded JSON values identical.
4. Large synthetic shot/steam/bean datasets exported+imported incrementally.
5. Instrumented page source proves bounded paging (page-size assertions, call
   counts; no whole-collection call).
6. Lazy/infinite page source: export pulls only as many pages as records
   exist; a source that throws when asked for the full collection must never
   be asked.
7. Export atomic when a later section fails (no partial ZIP exposed).
8. Selected-section export/import and all sync modes preserve behavior.
9. Truncated/malformed section JSON imports nothing (no valid prefix).
10. Individually invalid records keep partial-result behavior.
11. Limits probed below/at/above boundaries (request bytes, entry count,
    entry/record size, uncompressed total, metadata size, timeouts).
12. ZIP bombs, duplicates, encrypted/unsupported entries, CRC failures,
    truncation, stream errors fail safely.
13. Temp artifacts removed after success, section failure, malformed import,
    HTTP stream failure, timeout, consumer cancellation, picker/share
    cancellation, sync failure.
14. Concurrent transfers use isolated temp locations.
15. Native helper logic tested without real picker/share.

No physical hardware required.

## Out of scope (recorded follow-ups)

- Legacy "Export Shots", log export, and the DE1-app folder importer keep
  their current in-memory paths unless a shared helper must change; any
  remaining unbounded buffering there is tracked as follow-up work, not fixed
  here.
- Issue #559 is not addressed and must not be claimed fixed/closed by this PR.
