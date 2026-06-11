# Launcher Scan & Connect — Design Document

> **Status:** Design approved via brainstorm (2026-06-11)
> **Branch:** `feature/launcher-scan`
> **Tracker:** ReaPrime/TODO.md L113 (`P1`, native-ui-redesign remaining item) — {{I:high}} {{E:medium}}
> **Completion:** leave as-is (no PR/merge yet)

## Problem

The native UI redesign replaced the old `home_feature` dashboard with `LauncherView`. The
old dashboard had a scan button (shown when no machine/scale was connected) letting users
discover and connect devices. The launcher dropped it.

Skins are the daily driver, but we can't force a skin to expose device discovery. So a user
whose machine drops after onboarding has **no in-app path to reconnect from the launcher** —
the launcher status bar shows "No machine" but offers no way to act on it.

## Scope

**In scope:** a launcher entry point that drives `ConnectionManager.connect()` when no machine
is connected.

**Out of scope (deferred to the sibling TODO item, L114):**
- Tappable status-bar chips. These will navigate to the machine debug view, *not* trigger a
  scan — a different concern, handled with the debug-view-refresh work.
- Scale-only reconnect from the launcher. `ConnectionManager` already auto-retries a preferred
  scale; manual scale reconnect belongs with the chip/debug work.

## Design Decisions

### Mental model

Launcher = back office. When the machine is gone, the launcher's top priority is getting it
back. A full `connect()` scan also grabs the scale, so machine-only coverage is sufficient for
the common "everything dropped" case.

### Connect-hero card

A **"Connect your machine"** hero card, styled to match the existing launcher hero cards
(`BrowserHeroCard`, `SkinUnavailableCard`).

- **Visibility:** shown only when no machine is connected — i.e. `de1Controller.de1` emits
  `null`. Hidden once a machine connects.
- **Placement:** stacked *above* the skin slot. Both can co-occur in the narrow "machine down
  + skin still serving" case; reconnecting is presented first, Return-to-Skin remains reachable
  below. A skin can serve without a machine, so the hero must not hide the skin slot.
- **Action:** tap pushes the full-screen scan page (below).

### Scan flow — reuse the onboarding flow

Tapping the hero pushes a **dedicated full-screen scan page** that reuses the onboarding scan
state machine. The onboarding flow already handles every state we need: scanning progress with
coffee messages, "taking too long" help sheet, device pickers when multiple machines/scales are
found, adapter-off errors, troubleshoot wizard, demo mode, and log export. Reusing it means one
code path — no divergence between onboarding-scan and launcher-scan.

- On `ConnectionPhase.ready` → `Navigator.pop` back to the launcher (now showing connected
  state, hero gone).
- On user exit/cancel → halt the BLE scan via `deviceController.stopScan()`, then `Navigator.pop`.
  This is **launcher-specific** behaviour: onboarding's exit deliberately lets the background
  connect continue (the device connects while the user finishes onboarding), so the stop lives in
  the launcher page's `onExit` closure, not in `ScanFlowView`'s generic `onExit`. `stopScan()`
  halts scanning only — an already-in-flight connect runs to completion/timeout.

### Architecture

**1. Extract `ScanFlowView`** (new: `lib/src/onboarding_feature/widgets/scan_flow_view.dart`,
or a shared location — see "Open implementation detail" below).

Pull the scan state machine out of `ScanStepView` (`scan_step.dart`). The extracted widget owns
all the view-state logic (`_scanningView`, `_connectingView`, `_devicePickerView`,
`_noDevicesFoundView`, `_errorView`, `_adapterErrorView`, the too-long timer, guardian
subscription, status subscription, device subscription) and the `initState` `connect()` kick.

It depends on, via constructor:
- `ConnectionManager connectionManager`
- `DeviceController deviceController`
- `SettingsController settingsController`
- `ScanStateGuardian scanStateGuardian`
- `VoidCallback onConnected` — invoked once when phase first reaches `ready`
- `VoidCallback onExit` — invoked when the user chooses to leave without connecting
  (the current "Dashboard" / "Continue to Dashboard" affordances)
- `String exitLabel` — button copy for the exit affordance

`ScanStepView` becomes a thin wrapper that constructs `ScanFlowView` with:
- `onConnected: () => onboardingController.advance()`
- `onExit: onSkipToDashboard ?? () => onboardingController.advance()`
- `exitLabel: 'Dashboard'`

This keeps the onboarding public API and behaviour identical, so the existing onboarding scan
tests guard the refactor.

**2. New widget `ConnectDeviceHeroCard`**
(`lib/src/launcher/widgets/connect_device_hero_card.dart`).

Static presentational card (icon + "Connect your machine" + explanation + a Scan button),
matching the visual language of the other launcher hero cards. Takes an `onScan` callback.

**3. New page `LauncherScanPage`** (`lib/src/launcher/launcher_scan_page.dart`) with a
`routeName`. Builds `ScanFlowView` with:
- `onConnected: () => Navigator.of(context).pop()`
- `onExit: () { deviceController.stopScan(); Navigator.of(context).pop(); }`
- `exitLabel: 'Cancel'`

**4. `LauncherView` changes.** Add constructor deps: `connectionManager`, `deviceController`,
`settingsController`, `scanStateGuardian`. In the scrollable content column, wrap the skin-slot
region so that when `de1Controller.de1` is `null`, the `ConnectDeviceHeroCard` renders above
`_buildSkinSlot(...)`. A `StreamBuilder<De1Interface?>` on `de1Controller.de1` drives
visibility. Tapping the hero pushes `LauncherScanPage.routeName`.

**5. `app.dart` wiring.** Pass the new deps into `LauncherView` (all already available in
`app.dart`). Register the `LauncherScanPage` route in the route switch, constructed with the
same controllers the onboarding scan step uses (`connectionManager`, `deviceController`,
`settingsController`, `scanStateGuardian`).

### Data flow

1. Machine drops → `de1Controller.de1` emits `null` → launcher `StreamBuilder` rebuilds →
   `ConnectDeviceHeroCard` appears above the skin slot.
2. User taps Scan → `Navigator.push(LauncherScanPage)`.
3. `ScanFlowView.initState` calls `connectionManager.connect()`; status stream drives the view
   through scanning → connecting → (picker if ambiguous) → ready.
4. On `ready`, `onConnected` pops the page. Launcher rebuilds with a non-null machine → hero
   gone.

## Testing (TDD per CLAUDE.md)

- **Refactor safety:** existing onboarding `scan_step` tests must stay green after the
  `ScanFlowView` extraction (run first, before and after the move).
- **Launcher hero visibility (widget):** with a machine-null stream the hero renders; with a
  connected machine it does not.
- **Hero tap (widget):** tapping the hero navigates to `LauncherScanPage.routeName`.
- **Scan page ready→pop (widget):** mock `ConnectionManager.status` emitting `ready` causes the
  page to pop (`onConnected` fired once).
- **Cancel stops scan (widget):** tapping the launcher scan page's exit affordance calls
  `deviceController.stopScan()` and pops. (Onboarding exit must NOT call `stopScan` — guarded by
  the existing onboarding tests staying green.)
- **Analyze:** `flutter analyze` clean; **full `flutter test`** green before claiming done.

## Open implementation detail

- **Where `ScanFlowView` lives:** keep it under `onboarding_feature/widgets/` (minimal import
  churn) vs. promote to a shared `lib/src/device_discovery_feature/` or `lib/src/shared/`
  location (cleaner ownership, since both onboarding and launcher consume it). Decide during
  planning; leaning toward a shared location since it now has two consumers.

## Rejected alternatives

- **Tappable status-bar chips for scan** — easy to miss as the sole entry, and the chips are
  already earmarked for debug-view navigation (L114). Rejected for this item.
- **Bottom sheet / inline-card scan** — the scan flow's pickers + troubleshoot wizard need
  full-screen room; a sheet/inline surface would still need an overlay, doubling the work.
- **Replace the skin slot with the hero** — over-couples device state to skin access; a skin can
  serve without a machine.
- **Adaptive machine+scale hero** — scale-only reconnect is auto-handled and many users run no
  scale; a permanent "Connect your scale" hero would nag. Deferred to the chip/debug item.
