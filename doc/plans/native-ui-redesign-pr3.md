# PR3 — Onboarding Restyle + Android Warning Step

> **Design doc:** `doc/plans/native-ui-redesign.md` (PR3 row)
> **Branch:** `feat/native-ui-redesign-onboarding`
> **Completion:** local commits only — no push/PR until explicitly told.
> **This file:** step-by-step tasks. Delete after shipping (commit chain is authoritative).

## Locked decisions (grill, 2026-06-10)

1. **Reach:** onboarding step only. New installs on Android SDK<31 see a dismissible
   step before Welcome. Existing (already-onboarded) users do **not** — no launcher
   surface. A dedicated `androidWarningDismissed` flag still gates it so a re-run of
   onboarding won't repeat it.
2. **Threshold:** SDK < 31 (Android 12). Informational + dismissible, **never blocks**.
   Layered above the existing `WebViewCompatibilityChecker` hard floor (SDK<29).
3. **Restyle depth:** extract a shared `OnboardingScaffold` (centered, maxWidth,
   ShadCard/typography/spacing matching the launcher), apply to all 6 steps, fold in
   the welcome `Decent app`→`DE1 app` copy fix. New step uses the scaffold too.

## Visual language to match (from launcher)

`ShadTheme.of(context)` · `theme.textTheme.{h3,p,muted,table,small}` ·
`theme.colorScheme.{secondary,foreground,primary,...}` · `ShadCard` · `Semantics`
wrappers · `@Preview` widget previews (`package:flutter/widget_previews.dart`).
welcome_step is already ~80% aligned (ShadTheme + ShadButton + centered maxWidth 400).

## Work

### 1. Dismissal flag — `androidWarningDismissed` (sb-052 triad, mirror `accountStepSeen`)
- [ ] `settings_service.dart`: add `SettingsKeys.androidWarningDismissed` enum entry;
      abstract `Future<bool> androidWarningDismissed()` + `setAndroidWarningDismissed`;
      prefs impl `?? false`.
- [ ] `settings_controller.dart`: `_androidWarningDismissed` field, sync getter,
      load in `loadSettings()`, `setAndroidWarningDismissed()` (early-return on
      no-change, persist, `notifyListeners()`).
- [ ] `test/helpers/mock_settings_service.dart`: field + getter/setter.
      Default `true` (skip in tests, like `_accountStepSeen`).
- **verify:** `flutter analyze lib/src/settings test/helpers` clean.

### 2. Shared `OnboardingScaffold`
- [ ] Create `lib/src/onboarding_feature/widgets/onboarding_scaffold.dart` —
      centered `ConstrainedBox(maxWidth: ~440)`, padding 24, ShadTheme typography,
      slots: title, body/children, primary action, optional secondary action,
      `Semantics(explicitChildNodes, label:)`. Extracted from welcome_step's shape.
- [ ] `@Preview` for the scaffold (group 'Onboarding').
- **verify:** preview compiles; `flutter analyze` clean.

### 3. Android warning step (testable per sb-013 — inject SDK provider)
- [ ] Create `lib/src/onboarding_feature/steps/android_warning_step.dart`:
      `createAndroidWarningStep({ required SettingsController settingsController,
      Future<int?> Function()? sdkVersionProvider })`.
      - Default provider: `Platform.isAndroid` → `DeviceInfoPlugin().androidInfo
        .version.sdkInt`, else `null`.
      - `shouldShow`: `final v = await provider(); return v != null && v < 31 &&
        !settingsController.androidWarningDismissed;`
      - View built with `OnboardingScaffold`. Copy from design doc: title + "Your
        Android version may have reduced performance and WebView issues. The full
        experience works best on Android 12+." `Continue` button →
        `setAndroidWarningDismissed(true)` then `controller.advance()`.
      - `@Preview`.
- [ ] `app.dart`: insert `createAndroidWarningStep(settingsController: ...)` as the
      **first** entry in the onboarding `steps:` list (before welcome).
- **verify:** `flutter analyze lib/src/onboarding_feature lib/src/app.dart` clean.

### 4. Light restyle pass — apply scaffold to existing steps
- [ ] `welcome_step.dart`: reframe on `OnboardingScaffold`; fix copy
      `Coming from the Decent app?` → `Coming from the DE1 app?`.
- [ ] `login_step.dart`, `permissions_step.dart`, `initialization_step.dart`,
      `import_step.dart`, `scan_step.dart`: adopt `OnboardingScaffold` where it fits
      without changing behavior/logic. Surgical — only structural/visual alignment,
      no flow changes. Steps with bespoke layouts (scan results, progress) keep their
      inner content, just sit inside the shared scaffold chrome.
- **verify:** `flutter analyze lib/src/onboarding_feature` clean; visual spot-check
      via `flutter run --dart-define=simulate=1` (onboarding path) if feasible.

### 5. Tests (TDD — write first where practical)
- [ ] `test/onboarding/android_warning_step_test.dart`:
      - shouldShow true when provider returns 30 & flag false.
      - shouldShow false when provider returns 31.
      - shouldShow false when provider returns null (non-Android).
      - shouldShow false when flag already dismissed.
      - Continue persists `androidWarningDismissed=true` and calls `advance()`
        (widget test with a real OnboardingController + MockSettingsService).
- [ ] `test/settings/...` (or existing settings test): flag persists round-trip via
      controller (mirror an existing `accountStepSeen`/`onboardingCompleted` test if
      one exists; else minimal controller test).
- **verify:** `flutter test` — full suite green (was 1470).

### 6. Wrap
- [ ] `flutter analyze` clean (whole tree touched dirs).
- [ ] `flutter test` full suite green.
- [ ] Commit locally (no push). Trailer:
      `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- [ ] Leave design docs in `doc/plans/` (PR4 still pending). Delete THIS pr3 file +
      the PR3 section of the implementation plan only when the whole effort ships.

## Out of scope (deferred)
- Launcher banner for existing degraded users (decided against).
- PR4 work: browser hero card wiring, `_isDegradedAndroid` SDK check in launcher,
  LandingFeature removal.
- Any logic/flow change to existing onboarding steps beyond visual scaffolding.

## Risks / notes
- `sb-022`: ListTile under ShadCard/DecoratedBox needs a `Material` ancestor on CI
  Flutter — if the scaffold wraps any ListTile-bearing step, ensure `Material`.
- `sb-013`: SDK provider injected for testability — keep one un-injected default path.
- Don't gate the warning on `onboardingCompleted` (would couple it to the whole
  first-run lifecycle); the dedicated flag is the single source of truth.
