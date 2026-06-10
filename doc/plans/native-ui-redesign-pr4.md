# PR4 — LandingFeature → Launcher Integration

> **Design doc:** `doc/plans/native-ui-redesign.md` (PR4 row)
> **Branch:** `feat/native-ui-redesign-onboarding` (commit on top of PR3).
> **Completion:** push + ONE PR covering PR3 + PR4 (double, like PR1+PR2 last time) — when told.
> **This file:** step-by-step tasks. Delete after shipping.

## Locked decisions (grill, 2026-06-10)

1. **WebView gate = platform + SDK only.** `supportsWebView` stays the static platform
   list (Linux = no). `degradedAndroid` = Android SDK < 31. The heavy runtime
   `WebViewCompatibilityChecker` is NOT pulled into the launcher — `SkinView` already
   runs it at render and shows its own incompatibility fallback (Teclast GPU, old
   Android, WebView2-missing). Launcher stays sync.
2. **Remove LandingFeature fully.** Delete `landing_feature.dart` + its route, collapse
   `_navigateAfterOnboarding` to always land on the Launcher, and repoint
   `device_discovery_view.dart`'s 3 dead `LandingFeature.routeName` navigations to
   `LauncherView.routeName`.

## Launcher composition (target)

Browser hero is mutually exclusive with the return/skin-unavailable slot:

- `showBrowserHero = !supportsWebView || degradedAndroid` → **BrowserHeroCard only**
  (no Return-to-Skin, no skin-unavailable card). Matches design: degraded/no-WebView =
  "status bar + browser hero + grid (no return-to-skin)".
- else (WebView-capable, not degraded):
  - `webUIService.isServing` → **Return-to-Skin** hero button
  - else → **SkinUnavailableCard(notServing)**

Net change from current code: `_isDegradedAndroid` is no longer stubbed; `_canReturnToSkin`
also excludes degraded; the build no longer shows the skin-unavailable card AND the browser
hero at the same time. `SkinUnavailableReason.noWebView` becomes unused in the launcher
(browser hero owns that case) — leave the enum value (not an orphan).

## Work

### 1. LauncherView — wire degraded + restructure (sb-013: inject, keep sync)
- [ ] Add `final bool isDegradedAndroid;` constructor param (default `false`).
- [ ] Replace the stubbed `_isDegradedAndroid` getter body with the field.
- [ ] `_canReturnToSkin => _supportsWebView && !isDegradedAndroid && webUIService.isServing`.
- [ ] Restructure `build`: if `_showBrowserHero` → BrowserHeroCard alone; else the
      return/skin-unavailable branch. (Remove the separate always-evaluated browser-hero
      block.)
- **verify:** `flutter analyze lib/src/launcher` clean.

### 2. app.dart — resolve degraded once, rework post-onboarding nav, drop Landing
- [ ] `_MyAppState`: `bool _degradedAndroid = false;` resolved in `initState` via
      `DeviceInfoPlugin().androidInfo.version.sdkInt < 31` (Android only; guard
      `Platform.isAndroid`), `setState` when known.
- [ ] `onGenerateRoute` `LauncherView(...)`: pass `isDegradedAndroid: _degradedAndroid`.
- [ ] Rewrite `_navigateAfterOnboarding`:
      - Always `pushNamedAndRemoveUntil(LauncherView.routeName)`.
      - If `supportsWebView && !_degradedAndroid`: ensure WebUI serving (keep the
        existing serve-start attempt); if serving, `pushNamed(SkinView.routeName)` on
        top. On serve-failure or no default skin: stay on Launcher (it shows
        skin-unavailable). Drop all three `LandingFeature` branches.
      - else (unsupported / degraded): stay on Launcher (browser hero).
- [ ] Remove `case LandingFeature.routeName` from `onGenerateRoute` and the
      `landing_feature.dart` import. Fix the stale doc-comment at app.dart:220-223
      (mentions HomeScreen/LandingFeature).
- **verify:** `flutter analyze lib/src/app.dart` clean.

### 3. device_discovery_view.dart — repoint dead Landing refs
- [ ] Swap `import .../landing_feature/landing_feature.dart` →
      `.../launcher/launcher_view.dart`.
- [ ] 3× `LandingFeature.routeName` → `LauncherView.routeName`.
- **verify:** `flutter analyze lib/src/device_discovery_feature` clean.

### 4. Delete LandingFeature
- [ ] `rm lib/src/landing_feature/landing_feature.dart` (dir too if empty).
- [ ] Grep-confirm zero remaining `LandingFeature` references.
- **verify:** `flutter analyze` whole tree — no broken refs.

### 5. Tests — LauncherView composition (new `test/launcher/launcher_view_test.dart`)
Use a fake/stub `WebUIService` with a settable `isServing`, plus the controllers the
launcher needs (reuse existing test doubles; the launcher only reads streams for the
status bar — pump, don't settle, per CLAUDE.md StatusBar has animations).
- [ ] `degradedAndroid: true` → BrowserHeroCard present, Return-to-Skin absent.
- [ ] non-WebView platform path (if practically testable) → BrowserHeroCard present.
- [ ] capable + serving → Return-to-Skin present, no browser hero, no skin-unavailable.
- [ ] capable + not serving → SkinUnavailableCard present, no Return-to-Skin, no hero.
- **verify:** `flutter test test/launcher/...` green.

### 6. Wrap
- [ ] `flutter analyze` clean (project sources).
- [ ] `flutter test` full suite green.
- [ ] Commit on top of PR3 (local; push when told).
- [ ] Before the PR: move `native-ui-redesign.md` (design) to
      `doc/plans/archive/native-ui-redesign/`; delete the pr3 + pr4 + implementation
      task-list files (commit chain is authoritative). Update docs if any device/skin
      flow docs reference LandingFeature.

## Risks / notes
- `sb-022`: any ListTile under ShadCard needs a Material ancestor on CI Flutter —
  watch the launcher cards in widget tests.
- Status bar uses real streams/animations — widget tests must `pump()`, not
  `pumpAndSettle()` (CLAUDE.md).
- Degraded resolution is async but the launcher must stay sync — resolve once in
  app.dart and inject the bool (don't FutureBuilder inside the launcher).
- The SDK<31 threshold now appears in two places (android_warning_step + app.dart
  degraded resolve). Acceptable duplication; centralize only if a third consumer
  appears.
