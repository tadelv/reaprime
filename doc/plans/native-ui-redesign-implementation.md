# Native UI Redesign — Implementation Plan

> **Design doc:** `doc/plans/native-ui-redesign.md`
> **This file:** step-by-step implementation tasks. Delete after shipping (commit chain is authoritative).

## PR1: Widget Previews + Launcher

### Setup
- [ ] Add `widget_preview` dependency (or Flutter built-in previews if available)
- [ ] Create preview infrastructure: `lib/src/previews/` with app-level preview config
- [ ] Verify previews render in IDE

### Status Bar Component
- [ ] Create `lib/src/launcher/widgets/status_bar.dart`
  - Machine: name + state from `De1Controller.connectedDe1Stream` + `De1Controller.machineState`
  - Scale: name + state from `ScaleController.connectedScaleStream`
  - Battery: level + charging from `BatteryController` (conditional: mobile only)
  - Water level: from DE1 snapshot `waterLevelMl` / `waterCapacityMl`
  - QR icon button (opens QR overlay dialog)
- [ ] Create widget preview for status bar (with mock data)
- [ ] QR code overlay dialog — generate `http://{ip}:3000?_={timestamp}` URL, display as QR + copyable text

### Launcher Grid
- [ ] Create `lib/src/launcher/launcher_view.dart` — the new HomeScreen replacement
  - Status bar at top
  - "Return to Skin" hero button (conditional on `WebUIService.isServing` + WebView support)
  - Skin-unavailable explanation widget (conditional, mutually exclusive with return button)
  - Browser redirect hero card (conditional on no-WebView OR degraded Android)
  - Grid of destination cards: Settings, Devices, Data, Skins, Account, Plugins, Advanced
  - Account and Plugins conditionally visible
- [ ] Create widget preview for launcher (mock services)
- [ ] Create `lib/src/launcher/widgets/destination_card.dart` — reusable grid item (icon + label + optional badge)
- [ ] Create widget preview for destination card

### Wiring
- [ ] Update `app.dart` route table: replace HomeScreen route with LauncherView
- [ ] Update navigation from onboarding → launcher (was → HomeScreen)
- [ ] Update navigation from SkinView → launcher on exit
- [ ] Verify back-navigation from sub-pages returns to launcher
- [ ] Run `flutter test` — fix any broken references to HomeScreen
- [ ] Run `flutter analyze`

## PR2: Settings Flattening + Standalone Sub-Pages

### Extract Sub-Pages
- [ ] Create `lib/src/data_management/data_management_page.dart` — standalone page
  - Move export/import logic from `SettingsView` data management section
  - Add AppBar with back navigation
  - Restyle to iOS Settings row style
- [ ] Create `lib/src/device_management/device_management_page.dart` — standalone page
  - Move from `SettingsView` device management section (already partially standalone as `device_management_page.dart`)
  - Restyle
- [ ] Create `lib/src/skin_selector/skin_selector_page.dart` — standalone page
  - Move WebUI skin selection from `SettingsView`
  - Restyle
- [ ] Create `lib/src/account/account_page.dart` — standalone page
  - Move Decent account section from `SettingsView`
  - Restyle

### Flatten Settings
- [ ] Rewrite `settings_view.dart` — flat list with only:
  - Appearance (theme mode toggle)
  - Gateway mode (tap to change)
  - Battery charging mode (mobile only, tap to navigate)
  - Presence (tap to navigate)
  - Advanced (debug logging, simulated devices)
  - About (version info)
- [ ] Each row: iOS Settings style — label left, current value right, tap action
- [ ] Remove collapsible sections / accordion pattern
- [ ] Create widget preview for new SettingsView

### Route Registration
- [ ] Add routes for new standalone pages in `app.dart`
- [ ] Wire launcher grid destinations to new routes
- [ ] Run `flutter test` — fix any broken settings tests
- [ ] Run `flutter analyze`

## PR3: Onboarding Restyle + Android Warning

### Android Warning Step
- [ ] Create `lib/src/onboarding_feature/steps/android_warning_step.dart`
  - Check `Platform.isAndroid` + SDK version via `DeviceInfoPlugin` or platform channel
  - Dismissible warning message
  - "Continue" button calls `controller.advance()`
  - Persist dismissal flag in `SettingsService`
- [ ] Add step to `OnboardingController` — insert before welcome step, skip if not Android or SDK >= 31 or already dismissed

### Restyle Onboarding Steps
- [ ] Audit visual consistency: ensure all steps use same card style, typography, spacing as launcher
- [ ] Update `welcome_step.dart` — match new visual language
- [ ] Update `login_step.dart` — match new visual language
- [ ] Update `permissions_step.dart` — match new visual language
- [ ] Update `initialization_step.dart` — match new visual language
- [ ] Update `import_step.dart` — match new visual language
- [ ] Update `scan_step.dart` — match new visual language
- [ ] Create widget previews for key onboarding steps

### Tests
- [ ] Unit test: Android warning step shown/hidden based on SDK level
- [ ] Unit test: dismissal flag persisted and respected
- [ ] Run `flutter test`
- [ ] Run `flutter analyze`

## PR4: LandingFeature → Launcher Integration

### Browser Hero Card
- [ ] Create `lib/src/launcher/widgets/browser_hero_card.dart`
  - URL display: `http://{ip}:3000?_={timestamp}`
  - Copy URL button
  - Open Browser button (via `url_launcher`)
  - Inline QR code
- [ ] Create widget preview for hero card

### Conditional Launcher Composition
- [ ] Add WebView availability detection (platform check + potentially Android SDK check)
- [ ] Launcher shows browser hero card when: no WebView OR degraded Android
- [ ] Launcher hides "Return to Skin" when: no WebView available
- [ ] Launcher shows skin-unavailable explanation when return-to-skin hidden

### Cleanup
- [ ] Remove or deprecate `landing_feature.dart` (redirect any remaining references to launcher)
- [ ] Update route table
- [ ] Run `flutter test`
- [ ] Run `flutter analyze`

## Cross-PR Checklist

- [ ] All new widgets have previews
- [ ] Dark mode verified for all new screens
- [ ] Accessibility: semantic labels on all interactive elements
- [ ] Tablet layout (primary target) looks good at common resolutions
- [ ] Phone layout degrades gracefully
- [ ] Full `flutter test` green before each PR
- [ ] `flutter analyze` clean before each PR
