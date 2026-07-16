# #319 — DE1 firmware delivery research

Date: 2026-07-15

## Request and intended direction

The app should ship with a known-good firmware image for each supported
machine family, expose that image through the local API, and let a skin or
other API client flash it. Manual firmware upload remains useful as an
advanced fallback. A future service should be able to advertise and deliver
new firmware without requiring an app release.

## Current ReaPrime implementation

- `POST /api/v1/machine/firmware` in
  `lib/src/services/webserver/de1handler.dart` accepts an arbitrary raw binary
  body and invokes `De1Interface.updateFirmware()`.
- The response is an NDJSON progress stream with `erasing`, `uploading`,
  `done`, and `error` events. Client disconnect invokes
  `cancelFirmwareUpload()`.
- The current implementation sends the final verification request after all
  MMR writes and emits `done` only after `updateFirmware()` returns. It does
  not emit a separate `verifying` event. The plan must verify that this stream
  remains observable through verification; it should not assume that DE1 CRC
  verification is intrinsically slow or that the missing event is a firmware
  limitation.
- `De1Interface.updateFirmware()` is the existing machine abstraction. The
  shared DE1 implementation handles erase, 16-byte writes, progress, final
  verification request, and cancellation; subclasses can participate through
  `beforeFirmwareUpload()` and transport-specific pacing.
- `GET /api/v1/machine/info` already exposes the connected machine's firmware
  version through `MachineInfo.version`. This can be used for compatibility
  and update decisions, but the current firmware endpoint does not validate
  the image against the machine before flashing.
- API contract files currently document only the raw upload endpoint:
  `assets/api/rest_v1.yml` and `doc/Api.md`.
- Flutter already bundles binary-capable assets via `pubspec.yaml` and loads
  binary assets with `rootBundle.load()`. Existing bundled profile and skin
  assets provide patterns for manifests and runtime asset lookup.

## Relevant external facts

- Flutter's official asset documentation says files declared in `pubspec.yaml`
  are included in the app asset bundle and binary resources can be loaded via
  `AssetBundle.load()` / `rootBundle.load()`.
  [Flutter assets documentation](https://docs.flutter.dev/ui/assets/assets-and-images)
- The original DE1 app is the project's stated protocol authority, and its
  public repository describes release/download artifacts as separate from the
  source checkout.
  [decentespresso/de1app](https://github.com/decentespresso/de1app)

## Design implications

1. Treat a firmware image as a typed artifact with machine family, firmware
   build/version, file format, byte length, digest, and compatibility metadata;
   do not expose a directory of opaque files as the long-term API.
2. Keep the flash operation behind `De1Interface`; the new layer should select
   and validate an image, then call the existing upload path.
3. Separate sources from policy: bundled firmware is an offline source,
   network firmware is a later source, and the API/skin decides whether to
   inspect, download, or flash.
4. Prefer a manifest as the stable contract. It can describe bundled and
   remotely discovered artifacts without making clients know asset paths.
5. Treat firmware flashing as a destructive operation: require an explicit
   action, report the selected artifact and compatibility result, preserve the
   existing manual raw-upload path, and make failures/cancellation observable.
6. A future network endpoint should return signed or otherwise authenticated
   metadata plus a digest (and ideally a signature) for the image. The app
   should download to a temporary file/cache, verify it, then promote it to a
   usable artifact before flashing.

## Open decisions for the plan

- Which machine families are in the first bundled release: DE1 only, or DE1
  plus Bengle/other implementations?
- Is the first public API intended to return firmware bytes directly, or should
  clients first list metadata and then request/download a selected artifact?
- What is the authoritative firmware version/build representation and where is
  the source image supplied from during the app build?
- Should bundled firmware be automatically selected only when it is newer than
  the connected build, or should the API expose it and leave that policy to the
  skin?
- What security level is required for remote firmware: HTTPS plus digest first,
  or signed metadata/images from the first network release?
- Does flashing need to be restricted by machine state, power/connection type,
  or app/platform capabilities beyond the current upload implementation?
