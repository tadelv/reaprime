# Release Guide

This document describes how to create releases for ReaPrime.

## Creating a Release

ReaPrime uses git tags to trigger automatic releases. When you push a tag, GitHub Actions will:
1. Build the Android APK
2. Create a GitHub release
3. Attach the APK to the release
4. Auto-generate release notes

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
2. Your new release should appear with the APK attached
3. Download and test the APK

## Version Numbering

ReaPrime follows [Semantic Versioning](https://semver.org/):

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

After the release is created, you can edit it to:
1. Add detailed changelog
2. Add screenshots
3. Highlight important changes
4. Add upgrade instructions

## Workflow Files

- **`.github/workflows/release.yml`**: Builds and publishes releases on tag push
- **`.github/workflows/develop-builds.yml`**: Development builds on main branch

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
- Ensure GITHUB_TOKEN has proper permissions

### Wrong Version Number
- Verify your tag follows the format `vX.Y.Z`
- Check `flutter_with_commit.sh` extracts version correctly
- Rebuild with correct tag

## Future Enhancements

- [ ] Add multi-platform releases (macOS, Linux, Windows)
- [ ] Add checksums for security verification
- [ ] Add automatic changelog generation from commits
- [ ] Add release approval workflow
