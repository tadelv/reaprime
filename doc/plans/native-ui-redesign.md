# Native UI Redesign — Design Document

> **Status:** Design approved via grill session (2026-06-09)
> **Branch:** `feature/native-ui-redesign`
> **PR strategy:** Incremental — 4 PRs, each reviewable and mergeable independently
> **Basecamp:** [9211874487](https://3.basecamp.com/3671212/buckets/42895019/todos/9211874487)

## Problem

The native Flutter UI ("back office") has discoverability issues. Users can't find data management, settings are buried in a long scrollable page, and the HomeScreen duplicates what skins already show. Android 9/10 users hit degraded WebView/BLE performance with no guidance.

## Design Decisions

### Mental Model

Native UI = back office. Skins are the daily driver. The native UI handles:
- First-time setup (onboarding)
- Settings and configuration
- Device management
- Data management (export/import)
- Skin selection
- Account management
- Diagnostics

It does NOT compete with skins for dashboard, shot execution, or history.

### Launcher (replaces HomeScreen)

The screen users see when exiting the skin. Phone home-screen metaphor: status bar + app grid.

**Status bar (top):**
- Machine: name + state (idle/heating/ready/sleep)
- Scale: name + connection state
- Battery: level + charging (mobile only — Android/iOS)
- Water level: bar indicator
- QR icon: tap to show QR overlay with webUI URL

**Grid destinations:**
1. **Settings** — theme, gateway mode, presence, advanced, about
2. **Devices** — device management, connection preferences
3. **Data** — export/import shots, profiles, beans, grinders, logs
4. **Skins** — skin selector, download
5. **Account** — Decent login (conditional: only when `DecentAccountService` available)
6. **Plugins** — plugin management (conditional: only when plugins loaded)
7. **Advanced** — debug views, log level, simulated devices

**"Return to Skin" button:**
- Most prominent action — not in the grid, above it or as a hero element
- Conditionally visible: only when `WebUIService.isServing == true` AND platform supports WebView
- When hidden: show explanation of why (skin not running, no WebView support, etc.) with actionable options (send feedback, export logs, open skin selector)

**Browser redirect hero card (conditional):**
- Shown when: no WebView support OR degraded Android (SDK < 31)
- Contains: URL (`http://{ip}:3000?_={timestamp}`), Copy button, Open Browser button, inline QR code
- Positioned above the grid

### LandingFeature Absorbed

No separate LandingFeature. The launcher handles both paths:
- Normal: status bar + return-to-skin + grid
- Degraded/no-WebView: status bar + browser hero card + grid (no return-to-skin)

The launcher widget is shared; conditional widgets handle the difference.

### Settings (Flattened)

After extracting heavy sub-pages to the launcher grid, Settings becomes a flat list (~5-6 rows):
- Appearance (theme: System/Light/Dark)
- Gateway mode (Full/Restricted/None)
- Battery charging mode (mobile only)
- Presence (keep-alive settings)
- Advanced (debug logging, simulated devices)
- About (version, build info)

Style: iOS Settings — flat rows, current value inline on the right, tap to edit or navigate to sub-page.

### Standalone Sub-Pages

Each launcher destination opens a dedicated page via `Navigator.push`:
- **Data Management** — already exists, extracted from settings
- **Device Management** — already exists, extracted from settings
- **Skin Selector** — already exists in WebUI settings section
- **Account** — already exists as a settings section
- **Plugins** — already exists as `PluginsSettingsView`

These pages get restyled to match the new visual language but keep their existing logic.

### Navigation

Stack-based `Navigator.pushNamed` — no change from current pattern. No go_router needed.

Status bar appears on the launcher only. Sub-pages get a standard AppBar with back arrow.

### Android Degraded-Experience Warning

New onboarding step, shown when `SDK < 31` (Android 12):
- Dismissible warning — not blocking
- Message: "Your Android version may have reduced performance and WebView issues. The full experience works best on Android 12+."
- "Continue" button proceeds with onboarding normally
- Dismissal persisted in `SettingsService` — shown once, ever

### Onboarding Restyle

Keep the existing flow (welcome → login → permissions → init → scan → connect). Add Android warning step before welcome. Restyle all steps to match the new visual language (same card style, typography, spacing as the launcher).

### Visual Language

- **Toolkit:** shadcn_ui (unchanged)
- **Launcher:** spacious, large tap targets (tablet-first)
- **Sub-pages:** iOS Settings style — flat rows, clean spacing
- **Theme:** System/Light/Dark (unchanged)
- **Icons:** LucideIcons (unchanged)

### Widget Previews

Set up Flutter Widget Previewer before building screens. Every new component gets a preview wrapper for visual iteration without running the full app.

## Scope

### v1 (this effort)

1. Widget preview infrastructure
2. Launcher (HomeScreen replacement) with status bar + grid + QR
3. Browser redirect hero card (conditional)
4. Return-to-skin with conditional visibility + explanation
5. Settings flattening + standalone sub-pages
6. Data Management as standalone page
7. Device Management as standalone page
8. Skin Selector as standalone page
9. Account as standalone page
10. Onboarding restyle + Android warning step
11. LandingFeature → launcher integration

### Deferred

- Realtime shot/steam screen redesign (skin territory)
- History screen redesign (skin territory)
- Plugin management redesign (niche)
- Diagnostics/debug view redesign (dev-only)
- go_router migration (not needed)

## PR Breakdown

| PR | Scope | Depends on |
|----|-------|-----------|
| PR1 | Widget preview infra + launcher component (status bar + grid) | — |
| PR2 | Settings flattening + standalone sub-pages | PR1 |
| PR3 | Onboarding restyle + Android warning step | PR1 |
| PR4 | LandingFeature → launcher integration + browser hero card + QR | PR1 |

## Rejected Alternatives

- **Native UI as daily-driver competing with skins** — too much scope, skins are already better at this
- **Drawer/tab navigation** — over-engineered for 6-7 destinations, stack push is simpler
- **Blocking Android gate** — app still works on Android 9, just degraded; blocking is hostile
- **Separate LandingFeature** — same launcher widget with conditional content is cleaner
- **go_router** — stack-based navigation is sufficient for the back office
