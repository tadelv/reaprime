# Tare lockout during shot (upstream issue #499)

## Problem

A programmatic `PUT /api/v1/scale/tare` call arriving mid-shot re-zeros the
scale and ruins stop-at-weight for the rest of the pour. The reporter
suspects a stray skin/browser window issued it, but the actual source is
unconfirmed — the fix is defensive: let the user opt into rejecting
programmatic tare while a shot is actively running. Manual tare via the
scale's own physical button never goes through this code path, so it is
unaffected by construction.

## Design

Mirrors the existing `blockOnNoScale` feature end-to-end (same settings
plumbing, same REST-handler-level gate, same typed-error convention).

- New persisted boolean setting: `blockTareDuringShot` (default `false` —
  opt-in, since the issue notes some users deliberately want mid-shot tare).
- Gate lives in `ScaleHandler` (the REST entry point for
  `PUT /api/v1/scale/tare`), **not** in `ScaleController.tare()`. The
  `ShotSequencer` and `HotWaterSequencer` call `ScaleController.tare()`
  directly for legitimate in-app tares (arm-before-pour, stop-at-weight) —
  gating the controller method would break the shot itself.
- "Shot in progress" = `De1Controller.currentShotState.state` is anything
  other than `ShotState.idle` / `ShotState.finished` (same vocabulary
  `de1_state_manager.dart` already uses for "shot active"). `ShotState` is
  specific to the espresso `ShotSequencer`, so steam/hot-water/rinse are
  unaffected — matches the issue's actual scenario (an espresso pour).
- **Full gateway mode is explicitly exempt**, via an explicit
  `gatewayMode == GatewayMode.full` check alongside the shot-state check —
  not left implicit. In `full` mode the skin owns the shot and the app
  normally never starts its own `ShotSequencer` for it, so `currentShotState`
  would usually stay idle anyway; but `De1StateManager._handleEspressoState`
  starts an app-owned `ShotSequencer` "regardless of mode" whenever the app's
  own home screen is foregrounded, even under `full` gateway mode. Relying on
  ShotSequencer-absence alone would let the lockout accidentally engage in
  that edge case, which is out of scope for the setting's intent (protecting
  app-tracked shots, not skin-owned ones) — hence the explicit check.
  (Maintainer feedback on the initial PR — see `doc/AI_API_NOTES.md`.)
- Blocked request returns `400` with
  `{"type": "block_tare_during_shot", "details": "..."}`, following the
  `block_no_scale` convention.

## Changes

1. `lib/src/settings/settings_service.dart` — add
   `SettingsKeys.blockTareDuringShot`, abstract + SharedPreferences-backed
   getter/setter (default `false`).
2. `lib/src/settings/settings_controller.dart` — field, getter,
   `loadSettings()` wiring, `setBlockTareDuringShot()`.
3. `lib/src/services/webserver/scale_handler.dart` — constructor takes
   `De1Controller` + `SettingsController`; `tare` case checks the flag +
   shot state before calling `_controller.tare()`.
4. `lib/src/services/webserver_service.dart` — pass `de1Controller` and
   `settingsController` into `ScaleHandler(...)`.
5. `lib/src/services/webserver/settings_handler.dart` — GET/POST support.
6. `lib/src/services/webserver/data_export/settings_export_section.dart` —
   export/import support.
7. `assets/api/rest_v1.yml` — `blockTareDuringShot` field on
   `ReaSettingsRequest`/`ReaSettings`; new `400` response on
   `/api/v1/scale/tare`.
8. `doc/Api.md`, `doc/Skins.md` — document the setting and the new tare
   error case.
9. Tests: settings round-trip (`MockSettingsService`,
   `settings_handler_test.dart`, export/import), and a new
   `scale_handler_tare_lockout_test.dart` covering blocked/allowed states
   (idle, preheating, pouring, stopping, finished) crossed with the flag
   on/off, plus a full-gateway-mode regression case.
10. `assets/plugins/settings.reaplugin/plugin.js` — Enabled/Disabled control
    for `blockTareDuringShot`, mirroring `blockOnNoScale`.

No Flutter settings-page UI toggle — `blockOnNoScale` and
`stopHotWaterAtWeight` set this precedent already: these scale-behavior
settings are configured via the REST API and the bundled settings skin, not
the native Flutter settings pages.
