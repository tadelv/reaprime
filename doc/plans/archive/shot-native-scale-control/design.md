# Native-Rate Shot Scale Control

## Evidence

- `ShotSequencer` currently uses `withLatestFrom`, so machine lifecycle waits for a scale sample and scale decisions only run at machine cadence.
- Scale commands are launched independently from machine transitions; reset, tare, start, and stop can overlap or be dropped by device-level in-flight guards.
- Issue #423 records concurrent machine-stop and scale-maintenance BLE writes, followed by a scale write timeout. PR #512 already prevents the transport-loss path from powering off the physical scale.
- Bengle exposes its integrated scale through `BengleVirtualScale`, while firmware owns final stop-at-weight and the app retains per-step weight exits.

## Invariants

- Machine samples alone drive lifecycle, volume integration, raw snapshots, persistence, and natural completion.
- Distinct native scale callbacks alone drive tare confirmation, freshness, target crossings, per-step exits, and final-yield refinement.
- Scale availability is explicit and can only degrade during a shot; disconnect, tare failure, tare timeout, and staleness cannot re-arm.
- Pour-time scale control arms only after the tare command succeeds and a distinct post-start sample is within 3 g of zero.
- Final and per-step crossings require two consecutive distinct native samples at or above the projected threshold.
- Shot scale commands run FIFO, once per transition, with local error ownership and generation guards.
- A stop request is latched once; `stopping` begins only after a later machine snapshot confirms the pour ended.

## Compatibility Decisions

- Preserve the public scale API, shot states, decision vocabulary, machine-cadence persistence, preparing-for-shot tare, volume fallback, and Bengle final-SAW bypass.
- Default tare-confirmation and freshness timeouts are two seconds and are injectable only through constructor durations.
- Use raw weight plus `controlWeightFlow` projection for actuation and keep display smoothing out of control decisions.
- Do not retry DE1 stop or skip requests automatically.

## Rejected Alternatives

- `combineLatest`, `merge`, or another combined stream could let scale events repeat machine lifecycle and volume integration.
- A universal weight or grams-per-second clamp would reject legitimate catch-up after transport pauses.
- Treating GATT write completion as physical tare completion can arm against cup weight.
- Reconnection inside the sequencer would conflict with ConnectionManager ownership and could silently re-arm mid-shot.
- Persisting at scale cadence would change the storage and public snapshot contract.
