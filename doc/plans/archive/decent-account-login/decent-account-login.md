# Decent account login — initial comms

Branch: `feature/account-login` · TODO ref: `^582a45` (P1)

## Background

de1app authenticates against `decentespresso.com/support/api/` using HTTP Basic
Auth (email:password, base64-encoded). Three endpoints exist: `login_test`,
`sn` (list serials), `upload_shot` (disabled). No OAuth, no JWT — sessionless
Basic Auth on every request. HTTPS confirmed working.

Decent.app needs to match this contract so users can use their existing Decent
account. Phase 1 scope: auth comms only — no sync, no shot upload.

## Scope

1. **Real `CredentialStore`** — `flutter_secure_storage`-backed impl
2. **Settings pane** — "Decent Account" section in DataManagementPage showing
   login status, email, login/logout
3. **Onboarding step** — optional step after welcome: email + password + login

Out of scope: cross-device sync, shot upload, machine transfer, serial
registration beyond verification, privacy tiers.

## Phase 1 — `SecureCredentialStore`

New file: `lib/src/services/account/credential_store.dart`

Wraps `FlutterSecureStorage` with the `CredentialStore` interface already
defined in tests. Add `flutter_secure_storage` to pubspec.

## Phase 2 — Wire into DataManagementPage

Add `_buildDecentAccountSection()` card to `DataManagementPage`:
- Not logged in → "Link your Decent Espresso Account" button → login dialog
- Logged in → email + "Unlink" button
- Inject `DecentAccountService` into `DataManagementPage`

## Phase 3 — Onboarding step

New file: `lib/src/onboarding_feature/steps/login_step.dart`

`OnboardingStep` with `shouldShow: !loggedIn`. Widget: email, password, Login
button, Skip link. After welcome step, before scan step.

## Wire-up

- `main.dart`: provide `DecentAccountService` (via Riverpod or manual DI)
- `settings_view.dart`: pass `DecentAccountService` to `DataManagementPage`
- Onboarding steps list: insert login step
