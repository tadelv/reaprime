# DE1 firmware build 1352 real-hardware test

Date: 2026-07-16

## Setup

- Tablet: M50 Mini, Android, Decent.app API at `m50mini.home:8080`
- Transport: USB serial, `usb-1a86-55d3-5B1F091925`
- Machine: DE1Pro serial 9486 with GHC
- Installed build before test: 1356
- Artifact: `de1-1352`, forced downgrade
- Artifact SHA-256: `d9433b85167566d7b457e03e2151e860c10ff5d3b4e41b163667b8314aeb2927`

## Result

The catalog correctly reported the artifact as `not_newer`, with no recommendation and `updateAvailable: false`. Forced managed apply started at 09:38:01 and terminated after 427 seconds with:

```json
{"status":"error","progress":-1.0,"error":"Bad state: Firmware verification failed at 0x004800"}
```

The machine remained connected and continued reporting installed build 1356. It was not power-cycled.

The application log showed the final firmware-map response at 09:45:05:

```text
FW map recv: 0, 0, 1, err: 0x004800
```

The first mismatching address was `0x004800`. Android USB serial was configured for batches of 32 16-byte writes followed by a 400 ms pause. This demonstrates that batch size 32 overruns this DE1/USB path despite the pause. The serial batch size was reduced to the established conservative value of 8 before retrying.

The failed NDJSON stream was retained during the test as `/tmp/de1-firmware-1352-20260716-093801.ndjson` on the development host.

## Conservative-pacing retry

After rebuilding with batches of 8 writes and a 400 ms pause, the same forced managed apply was retried over Android USB serial. It started at 10:05:48 and completed after 1,530 seconds. The terminal NDJSON event was:

```json
{"status":"done","progress":1.0}
```

The application log confirmed successful machine verification before `done`:

```text
FW map recv: 0, 0, 1, err: 0xfffffd
```

The operation returned to `idle`. The successful stream was retained as `/tmp/de1-firmware-1352-retry-20260716-100548.ndjson` on the development host. The machine continued reporting the running build 1356 until the required power cycle.

## Post-update boot verification

After power-cycling, Android did not automatically reconnect the unavailable preferred USB device. The discovered BLE device `D9:11:0B:E6:9F:86` was connected explicitly through `PUT /api/v1/devices/connect`. The machine then reported:

```json
{
  "version": "1352",
  "model": "DE1Pro",
  "serialNumber": "9486",
  "GHC": true
}
```

The firmware catalog reported machine build 1352, `updateAvailable: false`, `not_newer`, and operation `idle`. This confirms that the verified image booted successfully and that the managed update completed over USB serial with post-update reconnection and build confirmation over BLE.
