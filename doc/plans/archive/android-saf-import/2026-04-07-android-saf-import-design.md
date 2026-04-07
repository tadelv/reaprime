# Android SAF Import Fix — Design

**Issue:** [#137](https://github.com/tadelv/reaprime/issues/137)
**Date:** 2026-04-07

## Problem

`file_picker`'s `getDirectoryPath()` returns a filesystem path string on Android, not a SAF content URI. The import code uses `dart:io` `Directory`/`File` on that path, which fails with `PathAccessException: Permission denied` on Android 11+ because the path has no SAF permission context.

## Approach: SAF Pick → Copy to App Cache → Import

1. **Replace `file_picker` folder picker** with `saf_util`'s `pickDirectory()` on Android. Returns a proper tree URI with recursive access. Keep `file_picker` for desktop (where `dart:io` works fine).
2. **Copy selected folder contents** to app cache using `saf_stream`'s `copyToLocalFile()`. Only copy the subdirectories we need: `history_v2/` (or `history/`), `profiles_v2/`, and `plugins/DYE/grinders.tdb`.
3. **Run existing scanner/importer** on the cached copy — no changes to `De1appScanner` or `De1appImporter`.
4. **Clean up** the staging folder after import completes (success or failure).

## Packages

- `saf_util` — directory picker, listing, child navigation (Android only)
- `saf_stream` — `copyToLocalFile(safUri, localPath)` (Android only)

## Architecture

New class: `SafFolderCopier` in `lib/src/import/saf_folder_copier.dart`
- Encapsulates the SAF pick → enumerate → copy flow
- Returns a local path to the cached copy
- Provides progress callback (for UI)
- Has a `cleanup()` method

The `import_source_picker.dart` widget changes:
- On Android: use `SafFolderCopier` instead of `FilePicker.platform.getDirectoryPath()`
- On desktop: keep existing `file_picker` flow (unchanged)

## Data Flow

```
Android:
  safUtil.pickDirectory()
    → tree URI with recursive SAF access
    → SafFolderCopier.copy(treeUri)
      → safUtil.list() + safUtil.child() to find subdirs
      → safStream.copyToLocalFile() per file → app cache
      → returns local cache path
    → De1appScanner.scan(cachePath)  // existing code, unchanged
    → De1appImporter.import(scanResult)  // existing code, unchanged
    → SafFolderCopier.cleanup()

Desktop:
  FilePicker.getDirectoryPath()
    → filesystem path (dart:io works fine)
    → De1appScanner.scan(path)  // unchanged
    → De1appImporter.import(scanResult)  // unchanged
```

## Scope

- Only the folder import path is affected. ZIP import works fine already.
- Only Android needs SAF. Desktop/iOS continue using `file_picker`.
- Scanner and importer code remain untouched.

## Testing

- Unit test `SafFolderCopier` with mocked `saf_util`/`saf_stream`
- Manual test on Android 11+ tablet with real de1plus folder
- Verify desktop import still works unchanged
