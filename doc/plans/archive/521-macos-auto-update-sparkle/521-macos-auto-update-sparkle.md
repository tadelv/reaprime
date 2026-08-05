# Issue #521 — macOS auto-update with Sparkle 2

> **Status:** Architecture approved; implemented in PR #563
> **Issue:** [#521 — Add auto-update to macOS](https://github.com/decentespresso/decaid/issues/521)
> **Priority:** P2, required for Decaid 1.0
> **Decision:** Keep App Sandbox and use Sparkle 2's Installer XPC service. Do not port SideStep's shell-based bundle replacement.

> **Amendment (review of PR #563):** the appcast is stored on the `gh-pages`
> branch (Pages deploys from that branch) and the publish job reads it through
> git, not the Pages CDN — a transient Pages/TLS failure can never be mistaken
> for a first publication. Missing feeds are only allowed through an explicit
> `SPARKLE_APPCAST_BOOTSTRAP` repo variable, and the job asserts item counts
> never decrease. The plan's original deploy-pages flow and the Sparkle tools
> download now also pin a SHA-256 checksum.

## Goal

A signed GitHub-distributed macOS build checks for Stable or Beta updates, presents Sparkle's native update UI, securely downloads the existing notarized ZIP release asset, replaces `Decaid.app` outside the host sandbox through Sparkle's Installer XPC service, and relaunches.

## Why Sparkle instead of a direct SideStep port

The pinned [SideStep updater](https://github.com/johnbuckman/SideStep/blob/8f297608373c95dfbf380f8b4bdbf8cad66f5de9/InstallerApp/UpdateChecker.swift) establishes the desired product and security behavior:

- check a hosted release feed on a schedule;
- accept ZIP/DMG application releases;
- prompt before updating;
- validate downloaded code before replacing the app;
- quit, atomically replace, and relaunch.

SideStep performs replacement through an unsandboxed shell process. Decaid's Release build has `com.apple.security.app-sandbox=true`; a child process inherits that restriction and cannot safely replace an app in `/Applications`. Removing App Sandbox would also change current data-container behavior and pull #508 into this feature.

Sparkle 2 supplies the missing sandbox escape as a signed Installer XPC service and provides atomic replacement, relaunch, permission handling, archive-signature verification, and Apple code-signing validation. Decaid retains its sandbox and existing data locations.

## Current state

- `UpdateCheckService` schedules checks every 12 hours and owns the Flutter/API update state.
- `AndroidUpdater` reads GitHub Releases, but only accepts `.apk` assets and only installs through `ApkInstaller`.
- Settings already expose:
  - Automatic update checks, default on;
  - Stable/Beta channel;
  - Check for updates.
- macOS releases already publish `decaid-macos-<version>.zip` containing `Decaid.app`.
- The macOS app is already signed with Developer ID Team `XLS3XF57J8`, notarized, and stapled.
- The release workflow currently re-signs with `codesign --deep`; Sparkle explicitly warns against this for sandboxed XPC services.
- There is no GitHub Pages site or `gh-pages` branch yet.

## Scope

### In scope

- Sparkle 2.9.5 through Swift Package Manager.
- Sandboxed Installer XPC integration.
- Stable and Beta update channels.
- Existing Flutter update settings as the user-facing controls.
- A signed appcast hosted by GitHub Pages.
- Correct signing, notarization, stapling, and verification of Sparkle's nested helpers.
- Production-like update smoke tests.

### Out of scope

- Silent forced updates or critical-update policy.
- A custom update dialog or download progress UI.
- Delta updates in the first version.
- DMG creation; #507 owns native installer packaging and the existing ZIP is supported by Sparkle.
- Mac App Store builds; the store owns updates there and self-update must remain disabled for any future `APP_STORE=true` macOS build.
- Changing REST/WebSocket update contracts. Their in-app install capability remains Android-only in this change.
- Removing App Sandbox or migrating application data (#508).
- Refactoring the Android updater or correcting unrelated legacy repository strings.

## Design

### 1. Native Sparkle integration

Add the `Sparkle` SPM product from `https://github.com/sparkle-project/Sparkle`, pinned to 2.9.5 in `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`, and link/embed it in the Runner target.

Add these production defaults to `macos/Runner/Info.plist`:

| Key | Value | Reason |
|---|---|---|
| `SUFeedURL` | `https://decentespresso.github.io/decaid/appcast.xml` | Stable feed location independent of a release tag |
| `SUPublicEDKey` | generated public Ed25519 key | Verify every update archive |
| `SUEnableInstallerLauncherService` | `true` | Required to update a sandboxed app |
| `SUEnableAutomaticChecks` | `true` | Preserve Decaid's existing default without Sparkle's second-launch permission prompt |
| `SUScheduledCheckInterval` | `43200` | Preserve the existing 12-hour interval |
| `SUAutomaticallyUpdate` | `false` | Check automatically, but ask before download/install like SideStep |
| `SUVerifyUpdateBeforeExtraction` | `true` | Reject a bad archive before extraction |
| `SURequireSignedFeed` | `true` | Prevent a compromised feed from spoofing update metadata or links |

Add Sparkle's required Mach lookup exceptions to both `Release.entitlements` and `DebugProfile.entitlements`:

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
</array>
```

Keep `com.apple.security.app-sandbox` and `com.apple.security.network.client`. Do not enable `SUEnableDownloaderService`; Decaid already has outbound network permission.

Add `macos/Runner/MacOSUpdater.swift`:

- `@MainActor final class MacOSUpdater: NSObject, SPUUpdaterDelegate`.
- Own one `SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)`.
- Start once after Flutter supplies the persisted Decaid settings.
- Map Stable to an empty allowed-channel set and Beta to `Set(["beta"])`; Sparkle always includes the default Stable channel.
- On a channel change, update the delegate state and call `resetUpdateCycleAfterShortDelay()`.
- Forward manual checks to `updater.checkForUpdates()` so Sparkle owns all UI and error presentation.
- Forward automatic-check changes to `updater.automaticallyChecksForUpdates` only in response to initial migration or a user setting change.
- Return structured `FlutterError`s for configuration/start failures; never expose downloaded paths or implement replacement code in Dart.

Register one method channel after creating the macOS `FlutterViewController`:

```text
net.tadel.reaprime/macos_updater
```

Methods:

| Method | Arguments |
|---|---|
| `configure` | `{automaticChecks: bool, channel: "stable" | "beta"}` |
| `setAutomaticChecks` | `{enabled: bool}` |
| `setChannel` | `{channel: "stable" | "beta"}` |
| `checkForUpdates` | none |

`configure` is idempotent. Use a native migration marker so the existing Flutter `automaticUpdateCheck` value is copied into Sparkle only once; afterwards both settings surfaces are updated together when the user changes the Flutter switch.

Do not add another custom dialog or menu item in the first pass. Settings already provides the manual check, while Sparkle supplies the native update window.

### 2. Flutter bridge and settings

Add `lib/src/services/macos_updater.dart` as a thin, injectable MethodChannel wrapper. It must be a no-op off macOS and expose the four commands above.

Wire it by constructor injection:

1. Construct it in `main.dart` on macOS.
2. After `SettingsController.loadSettings()`, call `configure` immediately with `automaticUpdateCheck` and `updateChannel`; do not wait for the current 10-minute Dart update timer.
3. Thread it through `AppRoot` and `MyApp` to `SettingsView`.
4. In `SettingsView`:
   - automatic-check changes update the existing setting, then Sparkle on macOS and `UpdateCheckService` elsewhere;
   - channel changes update the existing setting, then Sparkle on macOS and perform the existing Dart re-check elsewhere;
   - manual macOS checks call Sparkle and do not show the current misleading immediate “latest version” Snackbar;
   - Android behavior remains unchanged.

Prevent duplicate app checks on macOS:

- Add an injectable macOS-platform flag to `UpdateCheckService`.
- On macOS, periodic initialization may continue scheduling skin updates, but must skip the APK-based `checkForUpdate()` call.
- `requestCheck()`/`checkForUpdate()` from the existing REST/WS update API remain non-installing on macOS; do not claim `installable=true` or mirror partial Sparkle state into `AppUpdateState`.
- Preserve Windows/Linux behavior in this issue.

This keeps a single macOS updater scheduler—Sparkle—without splitting or rewriting the existing skin-update scheduling.

### 3. Release signing

Update both `.github/workflows/release.yml` and `.github/workflows/develop-builds.yml`.

Replace top-level `codesign --deep` signing with Xcode archive/export using Developer ID wherever practical. Sparkle recommends `xcodebuild archive` + `xcodebuild -exportArchive` because Xcode correctly signs its Installer XPC service and helper tools while preserving their entitlements.

The exported app must then pass these gates before notarization:

1. `codesign --verify --deep --strict --verbose=4 Decaid.app`.
2. Host signature has Team ID `XLS3XF57J8` and Hardened Runtime.
3. Host entitlements still contain App Sandbox, network client, and expanded `net.tadel.reaprime-spks`/`net.tadel.reaprime-spki` names.
4. `Sparkle.framework`, `Installer.xpc`, `Autoupdate`, and `Updater.app` are present and signed by the same Team ID.
5. No Sparkle helper retains `com.apple.security.get-task-allow` in a distribution build.
6. `spctl --assess --type execute --verbose Decaid.app` succeeds after notarization.
7. `xcrun stapler validate Decaid.app` succeeds.

If Flutter's generated project prevents archive/export, explicitly sign Sparkle's nested components deepest-first using Sparkle's documented commands, preserve Downloader entitlements if that unused service remains embedded, sign the framework, then sign the host app last. Do not restore `--deep` as a signing operation.

Keep the existing release ZIP name and `ditto --keepParent` packaging. Preserve framework symlinks and executable bits.

### 4. Sparkle key and appcast publishing

One-time maintainer setup:

1. Run Sparkle 2.9.5 `generate_keys` on a trusted Mac.
2. Put the public value in `SUPublicEDKey`.
3. Export the private key and store it as the GitHub Actions secret `SPARKLE_ED_PRIVATE_KEY`.
4. Enable GitHub Pages for `decentespresso/decaid` with GitHub Actions as its source.
5. Verify `https://decentespresso.github.io/decaid/appcast.xml` is publicly reachable before shipping the first Sparkle-enabled build.

Add a serialized `publish-appcast` job after `create-release`, running on macOS so the GitHub release asset exists before the feed advertises it.

The job should:

1. Download pinned Sparkle 2.9.5 release tools.
2. Create a staging directory and fetch the currently deployed `appcast.xml` when present.
3. Download/copy the current `decaid-macos-<version>.zip` into staging.
4. Save generated GitHub release notes beside it with the same basename and `.md` extension.
5. Read `CFBundleVersion` from the ZIP and fail unless it is greater than every existing appcast item. This catches beta→stable tags made from the same commit because `flutter_with_commit.sh` uses commit count as the machine version.
6. Run `generate_appcast` with:
   - private key through standard input via `--ed-key-file -`;
   - `--download-url-prefix https://github.com/decentespresso/decaid/releases/download/<tag>/`;
   - `--embed-release-notes`;
   - `--versions <current CFBundleVersion>`;
   - `--maximum-deltas 0` for the first version;
   - `--maximum-versions 0` so existing items remain in the feed;
   - `--channel beta` only when the GitHub release is a prerelease.
7. Validate the output with `xmllint` and assert the current item has the expected build number, GitHub asset URL, EdDSA signature, and Beta channel when applicable.
8. Deploy only the feed/static page through `actions/configure-pages`, `actions/upload-pages-artifact`, and `actions/deploy-pages`.

Use workflow concurrency with cancellation disabled so two tags cannot race and overwrite the feed.

Stable appcast items have no channel. Beta items use `<sparkle:channel>beta</sparkle:channel>`. The native delegate allows Beta users to see both Beta and default Stable items, preserving issue #82 semantics.

### 5. Version policy

Sparkle compares `CFBundleVersion`, not Dart's prerelease semantic version. Decaid currently sets it from the `origin/main` commit count.

Therefore every published macOS release, including beta→beta and beta→stable, must have a strictly greater commit count than the previously published macOS item. The appcast job must reject equal or lower values rather than publishing an update Sparkle cannot select.

`CFBundleShortVersionString` remains Apple's numeric `MAJOR.MINOR.PATCH`; prerelease identity is represented by the appcast Beta channel and GitHub release title. Do not put `-beta.N` into the bundle short version.

## Test-first implementation order

### Phase 1 — Feed and signing proof

1. Add a CI-only fixture or script test that inspects a minimal existing appcast, appends Stable/Beta items, and rejects a non-increasing build number.
2. Integrate Sparkle through SPM and make archive/export signing pass locally or in a branch workflow.
3. Add entitlements and Info.plist configuration.
4. Verify the exported artifact before touching Flutter settings.

**Exit:** a signed/notarized sandboxed Decaid artifact contains correctly signed Sparkle helpers and a generated, validated appcast item.

### Phase 2 — Native coordinator

1. Replace the placeholder `RunnerTests.swift` test with focused tests for Stable/Beta allowed-channel mapping and idempotent configuration/start behavior where it can be tested without launching an installer.
2. Add `MacOSUpdater.swift` and the MethodChannel registration.
3. Run Runner XCTest on macOS.

**Exit:** native manual checks open Sparkle's standard UI against a test feed; Stable excludes Beta and Beta includes both.

### Phase 3 — Flutter integration

1. Add MethodChannel wrapper tests using a mocked binary messenger.
2. Add/update Settings widget tests proving:
   - macOS manual check delegates to Sparkle without the false “latest” Snackbar;
   - toggle and channel changes send the expected native calls;
   - Android keeps the existing dialog/install flow.
3. Add `UpdateCheckService` tests proving macOS skips APK checks while skin scheduling remains available.
4. Wire the bridge through `main.dart`, `AppRoot`, `MyApp`, and `SettingsView`.

**Exit:** one scheduler owns macOS app updates and existing Android behavior remains green.

### Phase 4 — End-to-end update

Use two Developer-ID-signed, notarized test builds with increasing `CFBundleVersion` values and a temporary signed feed:

1. Install the older build in `/Applications` and launch it once.
2. Stable channel: publish a Beta item only; manual check must report no Stable update.
3. Switch to Beta; manual check must offer the Beta update.
4. Accept; verify download, sandboxed XPC installation, relaunch, new build number, same bundle ID, same application data, and retained settings.
5. Publish a newer Stable item; both channels must offer it.
6. Tamper with one byte of the ZIP; Sparkle must reject it before extraction.
7. Sign an archive with a different EdDSA key or app signing identity; Sparkle must reject it.
8. Disable automatic checks, relaunch, and confirm no scheduled check occurs; manual check must still work.

The first public Sparkle-enabled release is a baseline: older Decaid builds cannot self-update into it. Do not close #521 until baseline→newer-build updating has been demonstrated with production-equivalent signatures.

## Verification commands/gates

```bash
dart format lib test
flutter analyze
flutter test
flutter build macos --release

xcodebuild test \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=macOS'

codesign --verify --deep --strict --verbose=4 Decaid.app
codesign -d --entitlements :- Decaid.app
spctl --assess --type execute --verbose=4 Decaid.app
xcrun stapler validate Decaid.app
xmllint --noout appcast.xml
```

Also run the full tagged-release workflow in a safe prerelease before claiming completion.

## Expected files

### New

- `macos/Runner/MacOSUpdater.swift`
- `lib/src/services/macos_updater.dart`
- focused Dart tests for the bridge/settings behavior
- focused Runner XCTest coverage
- appcast validation helper/test only if shell assertions become unreadable in workflow YAML

### Modified

- `macos/Runner.xcodeproj/project.pbxproj`
- `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `macos/Runner/AppDelegate.swift` or `MainFlutterWindow.swift` for channel registration
- `macos/Runner/Info.plist`
- `macos/Runner/Release.entitlements`
- `macos/Runner/DebugProfile.entitlements`
- `macos/RunnerTests/RunnerTests.swift`
- `lib/main.dart`
- `lib/src/app.dart`
- `lib/src/settings/settings_view.dart`
- `lib/src/services/update_check_service.dart`
- `.github/workflows/release.yml`
- `.github/workflows/develop-builds.yml`
- `doc/RELEASE.md`
- `doc/AI_BUILD_NOTES.md` if signing/XPC diagnostics reveal a reusable footgun

No REST or WebSocket spec changes are expected.

## Acceptance criteria

- [ ] App Sandbox remains enabled.
- [ ] A signed/notarized ZIP update installs from `/Applications` and relaunches through Sparkle's Installer XPC service.
- [ ] Every archive and the appcast are EdDSA-signed; tampering is rejected.
- [ ] Apple code-signing continuity resolves to Team ID `XLS3XF57J8`.
- [ ] Automatic checks default on and run every 12 hours without a duplicate Dart app-update check.
- [ ] The existing switch enables/disables Sparkle scheduling.
- [ ] Stable sees only default-channel releases.
- [ ] Beta sees Beta and Stable releases.
- [ ] Manual checks use Sparkle's native UI.
- [ ] Android update behavior and tests remain unchanged.
- [ ] REST/WS still report macOS in-app installation as unsupported rather than presenting inaccurate Sparkle state.
- [ ] Release CI refuses non-increasing macOS bundle versions.
- [ ] Appcast deployment occurs only after the GitHub ZIP asset exists.
- [ ] Existing application data and settings survive update/relaunch.

## Rollback

If the updater fails after release:

1. Remove or fix the latest appcast item; existing builds stop offering it without changing binaries.
2. Keep the GitHub ZIP available for manual installation.
3. Publish a corrected release with a strictly higher `CFBundleVersion`; never replace a signed archive in place under the same appcast version.
4. Do not rotate the EdDSA key and Developer ID identity in the same update.

## References

- [SideStep `UpdateChecker.swift` at the issue-pinned commit](https://github.com/johnbuckman/SideStep/blob/8f297608373c95dfbf380f8b4bdbf8cad66f5de9/InstallerApp/UpdateChecker.swift)
- [Sparkle basic setup and security](https://sparkle-project.org/documentation/)
- [Sparkle sandboxing/XPC setup](https://sparkle-project.org/documentation/sandboxing/)
- [Sparkle programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)
- [Sparkle appcast publishing and channels](https://sparkle-project.org/documentation/publishing/)
- [Sparkle settings behavior](https://sparkle-project.org/documentation/preferences-ui/)
- [GitHub Pages custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
