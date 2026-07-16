# #319 Phase 1 — bundled DE1 firmware delivery plan

Date: 2026-07-15

Implemented with official de1app firmware build 1352 from commit `74cacdcd2106f968c89c3a94c0fbcb615234913a`. The real-DE1 release gate remains required before shipping.

## Goal and phase boundary

Phase 1 ships one known-good DE1 firmware image inside Decent.app, exposes it
through the local API, and allows a skin to apply it without selecting a file.
Preserve the existing raw firmware upload endpoint for developers and recovery.

This phase does not implement remote catalog checks, downloads, caching, or
automatic notification. It therefore does not close #319. A later phase will
make network delivery the primary update path without requiring an app release.
The bundled artifact remains the offline fallback when that phase ships.

No native managed firmware-update screen is planned in this phase. The managed
API is the skin UX seam. The existing native debug file picker remains a raw,
developer-oriented upload path and shares the same machine-level operation
owner as the API.

## Agreed design

### Firmware sources

- Phase 1 source: bundled Flutter asset.
- Future source: remote catalog plus downloaded/cacheable artifact.
- Bundled firmware is always available offline.
- Future remote artifacts augment rather than replace bundled artifacts.
- HTTPS is the initial remote trust boundary. Stronger signature/key metadata
  is deferred until the remote source is designed.
- Raw API and native file-picker uploads are operations, not catalog artifacts;
  there is no `manual` artifact source.

### Artifact and manifest model

Represent managed firmware as metadata plus bytes, not as an opaque filename.
The catalog-facing artifact metadata includes:

- stable artifact ID
- source (`bundled` in Phase 1; `remote` is added with the remote source)
- machine family and canonical supported model IDs
- numeric DE1 firmware build for ordering
- human-readable version label
- image format
- byte length
- SHA-256 digest
- release channel and release notes

Source-specific locators are private implementation details. The bundled
manifest contains an asset path, but the REST response does not expose it.
Remote URL and signature fields are not added until remote delivery is
implemented.

The bundled manifest has a top-level `schemaVersion` and one or more artifact
entries. Each entry includes the metadata above plus:

- internal asset path
- expected DE1 header board marker
- expected image-body byte count
- expected CPU byte count
- provenance/build reference sufficient to identify the supplied official
  image

Artifact IDs must be unique. Unknown manifest schema versions, unknown machine
families/models, malformed digests, duplicate IDs, and inconsistent image
metadata fail catalog validation.

Use the existing numeric `MachineInfo.version` as the installed DE1 build.
Unknown or non-numeric installed versions make update comparison unavailable;
they are not treated as older.

### DE1 image validation

Before a managed operation can erase the machine, parse the DE1 firmware header
using the canonical image format documented by de1app. Validate at least:

- the header is present and structurally complete
- board marker is `0xDE100001` and matches the manifest
- header firmware version equals the manifest build
- actual file length equals the manifest byte length
- header image-body byte count and CPU byte count match the manifest and are
  internally sane
- SHA-256 of the complete image equals the manifest digest
- checksum/header fields are structurally valid and, where the canonical
  algorithm is available, verify successfully
- machine family and connected model are compatible

All managed checks complete before the erase request. `force` never bypasses
image integrity, header, family, or model validation.

The legacy raw endpoint does not use artifact selection, manifest policy, or
`force`, preserving its developer/recovery role. It must still reject an empty
request body before invoking `updateFirmware()`. Other raw-image validation is
unchanged in Phase 1.

### Bundled layout

```text
assets/firmware/
  manifest.json
  de1/
    <artifact-id>.bin
```

Declare the firmware asset directory in `pubspec.yaml`. The first manifest
contains one DE1 artifact using the supplied firmware build and compatible
model list. Record the image source/build reference, SHA-256, redistribution
approval, and compatible hardware in the PR.

### Update policy

- Normal managed apply permits only a valid, compatible artifact newer than the
  installed build.
- `force` is optional and defaults to `false`.
- `force: true` permits developer reinstall/downgrade, but never bypasses
  integrity, header, machine-family, or model checks.
- An unknown/non-numeric installed build makes normal apply unavailable; a
  compatible, valid artifact may be applied with `force: true`.
- Require an active machine connection for raw or managed apply.
- Retain the current local-LAN trust model. This phase does not add endpoint
  authentication or change the broader API trust boundary.

## Module boundary

Create a standalone, thin `FirmwareHandler`; do not add the managed firmware
logic to the existing `part of` `De1Handler`.

Use constructor injection:

- a concrete `BundledFirmwareCatalog`, backed by an injected `AssetBundle`
- the connected-machine dependency needed by the handler
- focused artifact validation and update-policy collaborators where they make
  the catalog module deeper and independently testable

The application composition root constructs and wires these dependencies.
Production code does not read `rootBundle` through a service locator.

Do not add a speculative `FirmwareSource` interface in Phase 1. Introduce the
source abstraction when the remote implementation creates a real second
adapter. Keep the bundled catalog's public API source-agnostic enough to
extract that seam later.

## Machine-level operation contract

`UnifiedDe1` is the authoritative operation owner for every caller: raw API,
managed API, native debug UI, and future callers. Do not add an API-only
coordinator.

Add a typed `FirmwareUpdateState` exposed read-only through `De1Interface`:

- `idle`
- `erasing`
- `uploading`
- `verifying`
- `cancelling`

The state is observational for GET/UI reporting; callers must not use a
check-then-start sequence as the concurrency lock.

Implement `updateFirmware()` as a non-`async` wrapper that synchronously:

1. throws `FirmwareUpdateInProgressException` unless state is `idle`
2. creates the operation's cancellation token
3. reserves the operation and sets state to `erasing`
4. starts a private asynchronous firmware-update future
5. returns that future with identity-safe cleanup in `whenComplete`

Because reservation and the busy exception occur synchronously, an API handler
can call `updateFirmware()` inside `try` before returning the NDJSON response.
A busy request therefore receives HTTP `409`, not a `200` stream containing an
error event. The same exception is caught by the native debug UI and presented
as a friendly busy error. MockDe1 mirrors the same concurrency, state, and
cancellation contract so simulated API and skin development remain realistic.

Release operation state on success, verification failure, cancellation, and
disconnect. Cleanup must only clear the token/state belonging to the completing
operation.

## Firmware protocol correctness

Preserve the public NDJSON event set, but make machine completion mean verified
completion.

- Subscribe to firmware map responses before sending protocol requests.
- Ignore seeded/stale map values and correlate responses with the current
  operation phase.
- Do not begin upload until the erase-complete response is observed, subject to
  a bounded timeout.
- After upload, send the final map/verification request and await its response.
- Treat the canonical `FF FF FD` first-error value as successful verification;
  any other result or timeout fails the operation.
- `updateFirmware()` completes only after successful verification.
- Always cancel the map-response subscription in `finally`.

No new NDJSON `verifying` event is added. During this period GET operation state
may report `verifying`, while the NDJSON connection remains open without a new
progress event.

## Cancellation contract

Keep `De1Interface.cancelFirmwareUpload()` as the shared machine-level
cancellation operation.

- Cancellation is checked while waiting for erase, between upload writes and
  pacing delays, and while waiting for final verification.
- Cancellation moves operation state to `cancelling` and terminates with a
  typed `FirmwareUpdateCancelledException`.
- `cancelFirmwareUpload()` is a true no-op when state is `idle`; it must not put
  an idle machine to sleep.
- Disconnect requests cancellation before transport teardown and releases the
  operation through normal identity-safe cleanup.
- Client disconnect invokes the same cancellation method.
- Failure and cancellation always close protocol subscriptions and terminate
  the operation future.

`DELETE /api/v1/machine/firmware` is idempotent. It returns `202` with the
resulting operation snapshot whether an active operation moves to `cancelling`
or the operation was already `idle`.

## API

### Raw compatibility endpoint

- `POST /api/v1/machine/firmware`
  - request: raw `application/octet-stream`
  - rejects an empty body with `400`
  - purpose: manual/developer/recovery upload
  - preserves the existing NDJSON progress contract
  - uses the shared synchronous machine-level concurrency guard

### Managed endpoints

- `GET /api/v1/machine/firmware`
  - always returns the bundled catalog without requiring a machine connection
  - includes connected machine model/build when available
  - reports per-artifact eligibility, recommended artifact, tri-state update
    availability, and machine-level operation state
  - does not expose asset paths or future download URLs

- `POST /api/v1/machine/firmware/apply`
  - JSON body: `{ "artifactId": "de1-1356", "force": false }`
  - resolves, loads, and validates the complete artifact before erase
  - performs the atomic machine-level start before opening the stream
  - returns the same NDJSON progress stream as the raw endpoint

- `DELETE /api/v1/machine/firmware`
  - requests cancellation through `cancelFirmwareUpload()` when connected and
    active
  - remains successful when already idle or no machine is connected
  - returns `202` with operation state `cancelling` or `idle`

### Catalog response

The GET response has this shape:

```json
{
  "artifacts": [
    {
      "id": "de1-1356",
      "source": "bundled",
      "machineFamily": "de1",
      "supportedModels": ["DE1Pro", "DE1XL", "DE1XXL", "DE1XXXL"],
      "build": 1356,
      "versionLabel": "1356",
      "imageFormat": "de1",
      "byteLength": 123456,
      "sha256": "...",
      "channel": "stable",
      "releaseNotes": "...",
      "eligibility": {
        "status": "applicable",
        "reasons": []
      }
    }
  ],
  "machine": {
    "model": "DE1Pro",
    "build": 1355
  },
  "recommendedArtifactId": "de1-1356",
  "updateAvailable": true,
  "operation": {
    "state": "idle"
  }
}
```

Without a connected machine:

- `machine` is `null`
- `recommendedArtifactId` is `null`
- `updateAvailable` is `null`
- per-artifact eligibility is `unknown` with reason
  `machine_not_connected`

Eligibility status is `applicable`, `notApplicable`, or `unknown`. Reasons use
stable machine-readable codes, including at least:

- `machine_not_connected`
- `machine_model_unknown`
- `installed_build_unknown`
- `model_incompatible`
- `artifact_invalid`
- `not_newer`

### HTTP outcomes

Use these pre-stream outcomes for raw and managed requests as applicable:

- `400`: malformed request, missing artifact ID, invalid `force`, or empty raw
  body
- `404`: unknown artifact ID
- `409`: firmware operation already active
- `422`: artifact validation, compatibility, or version-policy failure
- `503`: an apply/upload requires a machine but none is connected
- `202`: idempotent cancellation request accepted/already satisfied

Use a stable unavailable response such as:

```json
{
  "error": "machine_unavailable",
  "message": "No machine is connected"
}
```

`503 Service Unavailable` is used rather than `502`: the machine capability is
currently unavailable, while this repository uses `502` for an upstream HTTP
bridge that is unreachable or failed.

After an NDJSON stream begins, transport, protocol, verification, and
cancellation failures are terminal `error` events.

## NDJSON progress contract (#419)

Preserve the existing event set:

- `{"status":"erasing","progress":0.0}`
- `{"status":"uploading","progress":0.XX}`
- `{"status":"done","progress":1.0}`
- `{"status":"error","progress":-1.0,"error":"..."}`

Streaming regression tests must verify:

- the response remains open while final verification is pending
- `done` is emitted only after the machine reports successful verification and
  `updateFirmware()` completes
- verification failure/timeout emits `error`, never `done`
- the handler does not buffer or prematurely terminate the stream
- cancellation during erase, upload, and verification terminates correctly
- a busy request receives pre-stream `409`, not a streamed error

Update `assets/api/rest_v1.yml` and `doc/Api.md` with the NDJSON media type,
event schemas, ordering, progress granularity, actual verification behavior,
catalog schema, error schemas, and all response codes. Do not describe CRC
verification as intrinsically slow until real measurement confirms it.

## Implementation sequence

1. Add failing machine-level tests for synchronous concurrency reservation,
   state transitions, verified completion, phase-wide cancellation, disconnect,
   timeouts, and subscription cleanup.
2. Implement typed firmware operation state/errors, the non-`async` reservation
   wrapper, protocol verification, and cancellation in UnifiedDe1; mirror the
   contract in MockDe1 and update native debug UI busy handling.
3. Add failing handler tests for pre-stream `409`/`503`/empty-body responses,
   NDJSON verification ordering, client disconnect, and idempotent DELETE.
4. Extract and implement a standalone `FirmwareHandler` for the raw and DELETE
   routes, satisfying #418 and #419 before adding managed artifacts.
5. Add failing tests and fixtures for manifest parsing, DE1 header parsing,
   digest/header/length/model validation, policy evaluation, and catalog
   response derivation.
6. Implement the artifact model, concrete bundled catalog, AssetBundle
   injection, validators, and policy needed to satisfy those tests.
7. Add failing API tests for offline catalog GET, exact response schema,
   managed apply, version/`force` policy, and shared raw/managed concurrency;
   then implement the managed routes.
8. Add the first supplied DE1 firmware binary and manifest entry. Verify every
   manifest field against the actual bytes and record provenance and
   redistribution approval.
9. Update OpenAPI and API documentation for all raw and managed behavior.
10. Smoke-test simulated API/skin behavior, then complete the real-hardware
    release gate.

## Verification

### Automated

- Unit-test manifest schema/version parsing, duplicate IDs, unknown models,
  artifact selection, numeric build comparison, tri-state availability, model
  compatibility, force behavior, and stable eligibility reason codes.
- Unit-test DE1 header parsing, board marker, header/manifest build mismatch,
  body/CPU byte-count sanity, digest/length failures, and truncated images.
- Add a bundled-asset test that loads every manifest artifact through the
  Flutter asset bundle and verifies unique IDs, loadability, SHA-256, length,
  header metadata, build, and model metadata against the real bytes.
- Test UnifiedDe1 and MockDe1 concurrency across API and native-style direct
  callers.
- Test raw and managed API concurrency against the same connected fake machine.
- Test synchronous pre-stream `409`, no-machine `503`, malformed `400`, unknown
  `404`, policy `422`, and idempotent DELETE.
- Test raw and managed NDJSON ordering, delayed successful verification,
  verification failure/timeout, transport failure, client disconnect, and
  cancellation in every phase.
- Test disconnect releases/cancels the operation and protocol subscriptions are
  cleaned on every terminal path.
- Test direct debug UI upload behavior when an update is already active.
- Run `flutter analyze` and focused tests after each meaningful change.
- Run the full `flutter test` suite before considering implementation complete.

### Simulated smoke

Use the repository `sb-dev` flow and `curl` to verify:

- offline catalog GET with and without MockDe1 connected
- managed update eligibility and apply
- raw/managed shared busy response
- idempotent DELETE
- NDJSON streaming and terminal events

### Real DE1 release gate

Before shipping the bundled binary, test on every transport claimed as
supported, including BLE and USB/serial where available:

1. connect a compatible DE1 and confirm the installed model/build
2. confirm GET recommends the expected bundled artifact
3. apply it through the managed endpoint and observe the live NDJSON stream
4. confirm the response remains open until successful machine verification
5. power-cycle the DE1 as required by the firmware protocol
6. reconnect and confirm `MachineInfo.version` equals the artifact build
7. retain logs and measured timings as release evidence

Do not call the artifact known-good or ship it solely on simulated test results.

## Deferred Phase 2 remote work

Phase 2 completes #319. It introduces the real second source and only then
extracts a `FirmwareSource` abstraction. It should check authenticated HTTPS
metadata on startup and machine connection, throttled to approximately once per
24 hours, plus an explicit check-now operation. Checks must not block startup or
connection. A successful remote catalog is cached; failures retain bundled
firmware. Remote bytes are fetched only when a user/skin applies an artifact,
then validated before flashing.

Phase 2 also owns notification/selection UX in the target skin so network
delivery becomes the primary user path rather than merely an available API.
