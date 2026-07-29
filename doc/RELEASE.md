# Release Guide

This document describes how to create releases for Decent.app.

## Creating a Release

Decent.app uses git tags to trigger automatic releases. When you push a tag, GitHub Actions will:
1. Build all supported platforms
2. Export the iOS archive for TestFlight
3. Generate release notes from merged pull requests using GitHub's release-notes generator
4. Create a GitHub release with those notes and the desktop, Android, Raspberry Pi, and unsigned iOS artifacts

### Step 1: Tag Your Release

```bash
# For a stable release
git tag v1.0.0
git push origin v1.0.0

# For a beta release (will be marked as pre-release)
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1

# For an alpha release (will be marked as pre-release)
git tag v1.0.0-alpha.1
git push origin v1.0.0-alpha.1
```

### Step 2: Monitor the Build

1. Go to https://github.com/tadelv/reaprime/actions
2. Watch the "Create Release" workflow
3. Wait for it to complete (usually 5-10 minutes)

### Step 3: Verify the Release

1. Go to https://github.com/tadelv/reaprime/releases
2. Your new release should appear with all platform artifacts attached
3. Download and test the relevant artifacts

## Version Numbering

Decent.app follows [Semantic Versioning](https://semver.org/):

- **MAJOR.MINOR.PATCH** (e.g., `v1.2.3`)
  - **MAJOR**: Breaking changes or major new features
  - **MINOR**: New features, backwards compatible
  - **PATCH**: Bug fixes, backwards compatible

### Pre-release Versions

- **Beta**: `v1.0.0-beta.1` - Feature complete, testing phase
- **Alpha**: `v1.0.0-alpha.1` - Early testing, incomplete features
- **RC**: `v1.0.0-rc.1` - Release candidate, final testing

## Update Channels

The app's update system recognizes these channels:

- **Stable**: Only final releases (v1.0.0, v2.1.0, etc.)
- **Beta**: Pre-releases and beta tags (v1.0.0-beta.1, etc.)
- **Development**: All releases including alphas

Pre-releases are automatically detected by:
- Version suffix (beta, alpha, rc)
- GitHub's pre-release flag

## Editing Release Notes

The workflow publishes GitHub's generated release notes. After the release is created, review them and edit the release when a shorter summary, screenshots, upgrade instructions, or corrections are needed.

## Workflow Files

- **`.github/workflows/release.yml`**: Builds and publishes releases on tag push
- **`.github/workflows/develop-builds.yml`**: Development builds on main branch

### Development Artifacts

Development builds use stable GitHub Actions artifact names, while the packaged filename includes the seven-character commit SHA:

| Platform | Actions artifact | Downloaded file |
| --- | --- | --- |
| Android | `decent-android-develop` | `decent-android-develop-<short-sha>.apk` |
| macOS | `decent-macos-develop` | `decent-macos-develop-<short-sha>.zip` |
| Linux x64 | `decent-linux-x64-develop` | `decent-linux-x64-develop-<short-sha>.tar.gz` |
| Linux ARM64 | `decent-linux-arm64-develop` | `decent-linux-arm64-develop-<short-sha>.tar.gz` |
| Windows x64 | `decent-windows-x64-develop` | `decent-windows-x64-develop-<short-sha>.zip` |
| iOS unsigned | `decent-ios-unsigned-develop` | `decent-ios-unsigned-develop-<short-sha>.ipa` |

Tagged release artifact naming remains unchanged. Development workflow artifacts are retained build outputs, not GitHub Releases or prereleases by themselves.

## Testing Before Release

```bash
# Build locally to test
./flutter_with_commit.sh build apk --release

# Check the version is correct
./flutter_with_commit.sh run
# Open Settings and verify version number
```

## Troubleshooting

### Release Failed to Build
- Check GitHub Actions logs for errors
- Ensure all tests pass locally
- Verify secrets are configured (ANDROID_KEYSTORE_B64)

### APK Not Attached to Release
- Check the workflow completed successfully
- Verify the APK was built (check workflow artifacts)
- Ensure GITHUB_TOKEN has `contents: write` permission
- Check that GitHub's release-notes generator returned a non-empty response

### Wrong Version Number
- Verify your tag follows the format `vX.Y.Z`
- Check `flutter_with_commit.sh` extracts version correctly
- Rebuild with correct tag

## iOS / TestFlight

iOS builds are uploaded to TestFlight automatically on tag push, running as an independent CI job (`build-ios`) alongside the other platform builds.

### Local TestFlight Upload

To build and upload an IPA locally:

```bash
./flutter_with_commit.sh build ipa --release
```

Then upload via Xcode Organizer (Window → Organizer → Distribute App → TestFlight & App Store).

### CI/CD

The `build-ios` job in `.github/workflows/release.yml`:
1. Builds one unsigned Xcode archive and packages an unsigned IPA for the GitHub Release
2. Exports that archive with the Apple Distribution certificate and App Store provisioning profile
3. Uploads the signed IPA to TestFlight via the App Store Connect API

The unsigned IPA is intended for self-signing and sideloading; it cannot be installed directly.

Required secrets: `APPLE_DISTRIBUTION_CERTIFICATE_P12`, `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_B64`, `IOS_PROVISIONING_PROFILE_NAME`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`, `TEAM_ID`.

### TestFlight Distribution

- **Internal testing**: Available immediately after processing (~10-30 min). Up to 100 testers (App Store Connect users).
- **External testing**: Requires App Review for first build per version. Up to 10,000 testers. Can use a public link.

## Future Enhancements

- [ ] Add multi-platform releases (macOS, Linux, Windows)
- [ ] Add checksums for security verification
- [ ] Add release approval workflow
