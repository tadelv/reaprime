# TestFlight Submission Design

## Goal

Enable Streamline-Bridge iOS builds to be submitted to TestFlight for internal and public beta testing, both locally (for quick iterations) and via CI/CD (for automated releases).

## Decisions

- **Bundle ID**: Keep `net.tadel.reaprime` (already registered in App Store Connect)
- **Signing strategy**: Automatic signing locally, manual signing with provisioning profiles in CI
- **Deployment target**: iOS 17.6 (current, kept as-is)
- **Export compliance**: No encryption beyond standard HTTPS/TLS

## Changes

### 1. Info.plist Addition

Add `ITSAppUsesNonExemptEncryption` key set to `NO` in `ios/Runner/Info.plist`. This prevents Apple from prompting about export compliance on every TestFlight upload.

### 2. Local Build Workflow

No project changes needed. Local builds use automatic signing with team `XLS3XF57J8`.

Build command:
```bash
./flutter_with_commit.sh build ipa --release
```

Upload via:
- **Xcode Organizer**: Open archive -> Distribute App -> TestFlight
- **CLI**: `xcrun altool --upload-app`

Version and build number are already handled by `flutter_with_commit.sh` (version from git tag, build number from commit count).

### 3. CI/CD — New `build-ios` Job in release.yml

A new `build-ios` job on `macos-latest`, triggered by the same tag push (`v*`) as existing jobs.

#### Steps

1. **Checkout** with `fetch-depth: 0` (for version extraction)
2. **Flutter setup** (stable channel)
3. **Node.js setup** + DYE2 plugin build
4. **Import Apple Distribution certificate** into a temporary keychain (same pattern as existing `build-macos` job)
5. **Install App Store provisioning profile** for `net.tadel.reaprime`
6. **Generate ExportOptions.plist** with:
   - `method`: `app-store`
   - `teamID`: from secrets
   - `provisioningProfiles`: maps bundle ID to profile name
   - `signingCertificate`: `Apple Distribution`
   - `signingStyle`: `manual`
7. **Build IPA**: `./flutter_with_commit.sh build ipa --release --export-options-plist=ExportOptions.plist`
8. **Upload to TestFlight** via `xcrun altool --upload-app` using App Store Connect API key

#### New GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `APPLE_DISTRIBUTION_CERTIFICATE_P12` | Apple Distribution certificate, base64-encoded |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `IOS_PROVISIONING_PROFILE_B64` | App Store provisioning profile, base64-encoded |
| `APP_STORE_CONNECT_API_KEY_ID` | API key ID from App Store Connect |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from App Store Connect |
| `APP_STORE_CONNECT_API_KEY_P8` | .p8 private key contents, base64-encoded |
| `IOS_PROVISIONING_PROFILE_NAME` | Human-readable name of the provisioning profile |

#### Apple Developer Portal Setup Required

1. **Apple Distribution certificate** — created in Certificates, Identifiers & Profiles. Exported as .p12 with a password.
2. **App Store provisioning profile** — created for `net.tadel.reaprime`, linked to the Distribution certificate. Covers both TestFlight and App Store distribution.
3. **App Store Connect API key** — created in Users and Access -> Integrations -> App Store Connect API. Role: App Manager or Admin.

### 4. Release Workflow Integration

- The `build-ios` job runs in parallel with existing platform jobs (no dependency from `create-release`)
- iOS distribution is exclusively via TestFlight — no IPA in GitHub Release artifacts
- The release body is updated to mention iOS/TestFlight availability

## TestFlight Distribution

### Internal Testing
- Available immediately after upload processes (usually 10-30 minutes)
- Up to 100 internal testers (App Store Connect users with Admin, App Manager, Developer, or Marketing role)
- No App Review required

### External (Public) Testing
- Requires a brief App Review for the first build of each version
- Up to 10,000 external testers
- Can use a public TestFlight link

## Out of Scope

- App Store submission (separate process, not covered here)
- Fastlane setup (not needed for single-developer workflow)
- iPad-specific optimizations
- App Store screenshots/metadata
