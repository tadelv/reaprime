# Decaid display-name and distribution rename

## Goal

Rename the user-visible application and distributed build packages to **Decaid**, and install the supplied Android/iOS icon artwork. Preserve application identity and existing technical/historical naming.

## Research findings

- Platform display names are independently configured for Android, iOS, macOS, Linux, Windows, web, and Flutter window/menu metadata.
- macOS product-name changes also require updating the shared Xcode scheme, test-host paths, codesign/notarization paths, and workflow archive commands.
- Android currently points at a legacy `launcher_icon` adaptive-icon set. The supplied set uses the standard `ic_launcher` and `ic_launcher_round` resources, so the manifest and complete resource set must move together.
- The supplied iOS catalog covers the current deployment target and contains 1024 px marketing artwork. That source can generate the standard macOS 16–1024 px catalog without introducing another design source.
- Tagged-release and development workflows package all six platforms with `decent-*` filenames. The tagged GitHub release title also uses the old display name.
- Android update discovery accepts any `.apk` release asset, so changing the filename prefix does not break update checks. Internal repo, bundle IDs, Firebase config, package name, MethodChannels, telemetry salt, API schema names, and database names need no migration.

## Scope

1. Change app/window/launcher/menu names and app-specific permission copy to `Decaid` on every platform.
2. Change package metadata shown to users, including web metadata and the GitHub release title.
3. Replace Android and iOS app icon catalogs; derive the macOS catalog from the supplied iOS 1024 px image.
4. Rename development and tagged-release package filenames and branded Actions artifact names from `decent-*` to `decaid-*`.
5. Update release documentation only where it defines the package filenames. Leave general `Decent.app` and ReaPrime references intact.

## Explicitly preserved

- Dart package and repository: `reaprime`, `tadelv/reaprime`
- Application/bundle ID: `net.tadel.reaprime`
- Firebase app registrations and signing/provisioning identity
- MethodChannel names, telemetry salt, database name, API schemas, plugin APIs
- Decent Espresso company/product references, profile authors, device names, user agents, and historical/internal `Decent.app` / ReaPrime documentation

## Verification

- Validate JSON, plist, XML, and YAML syntax.
- Verify every supplied icon size and confirm generated macOS dimensions.
- Grep platform and workflow surfaces for stale display/package names and audit all remaining hits against the keep-list.
- Run `dart format lib test`, `flutter analyze`, and the full `flutter test` suite.
- Build Android APK and macOS app locally where the installed Apple toolchain permits.
