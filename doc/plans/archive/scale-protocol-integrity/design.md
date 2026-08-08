# Scale Protocol Integrity

## Evidence

- PRs #512 and #518 are merged into `main`. This branch preserves their Decent Scale lifecycle, FFF4 readiness, display-state, BLE queue-recovery, and `universal_ble` 2.2.4 behavior.
- Issue #509's gist identifies `LUNAR-D4DFF3` as `AcaiaScale` using the Pyxis protocol. One shot stopped at a projected 356.207 g for a 36.5 g target, while adjacent shots ended near 36 g.
- Decenza bounds Acaia frames by their length byte, retains partial headers and frames, uses a 64-byte payload ceiling, treats event-11 selector 5 as weight and selector 7 as timer, and masks settings battery with `0x7F`.
- de1app accepts seven- and ten-byte Decent weight packets with commands `0xCE` and `0xCA`. OpenScale emits seven-byte `0xCE` packets. Decenza accepts `0xCE` and `0xCA` and documents checksum incompatibility on original Decent Scale hardware.
- The official Bookoo Mini Scale protocol defines a 20-byte weight packet with an XOR `DATASUM`; despresso uses the same six-byte tare and timer commands as ReaPrime.
- Issue #53's logs identify both Bookoo and Decent Scale sessions and successful tare requests, but do not capture timer command bytes, write type, characteristic, command ordering, or device acknowledgement.

## Invariants

- Only complete, structurally accepted frames update liveness or publish weight.
- Acaia reads never cross a calculated frame boundary, and every complete buffered frame is considered independently.
- Acaia readiness means a valid weight was decoded, not merely that a notification arrived.
- Bookoo accepts only complete, checksum-valid 20-byte `03 0B` packets.
- Decent accepts only complete seven- or ten-byte `03 CE` or `03 CA` weight packets.
- Periodic maintenance owns every Future, never overlaps itself, and cannot reschedule after its connection generation is invalidated.
- Notification recovery is single-flight and cannot reschedule after maintenance is invalidated.

## Compatibility Decisions

- Do not reject Acaia or Decent frames by checksum. Supported older devices do not have one compatible checksum contract.
- Keep both verified Decent weight lengths and both existing weight commands.
- Keep Bookoo command bytes unchanged and propagate public command write failures.
- Keep reconnection in ConnectionManager and preserve non-destructive transport-loss teardown.

## Rejected Alternatives

- Clearing the whole Acaia buffer drops concatenated frames and breaks split frames.
- Waiting on an unbounded Acaia length can park parsing indefinitely.
- Reading a short frame from the following frame recreates the bogus-weight failure.
- Treating the first ten Bookoo bytes as a complete packet bypasses the protocol checksum.
- `Timer.periodic` with asynchronous callbacks permits overlapping BLE operations and unowned failures.
- Strict checksum rejection would regress verified original Decent Scale compatibility.
