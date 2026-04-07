# Android SAF Import Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix de1app folder import on Android 11+ by using SAF APIs to copy files to app cache before scanning/importing.

**Architecture:** On Android, replace `file_picker` folder picker with `saf_util` + `saf_stream`. A new `SafFolderCopier` class copies the relevant subdirectories to app cache, then the existing `De1appScanner`/`De1appImporter` operate on the cached copy. Desktop path unchanged.

**Tech Stack:** `saf_util`, `saf_stream` (Android SAF), `path_provider` (app cache dir), `dart:io` (for cleanup + desktop path)

---

### Task 1: Add saf_util and saf_stream dependencies

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Add packages**

```yaml
# In dependencies section:
saf_util: ^2.0.0
saf_stream: ^2.0.0
```

**Step 2: Run pub get**

Run: `flutter pub get`
Expected: Resolving dependencies... success

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add saf_util and saf_stream for Android SAF support"
```

---

### Task 2: Create SafFolderCopier

**Files:**
- Create: `lib/src/import/saf_folder_copier.dart`

**Step 1: Implement SafFolderCopier**

This class encapsulates the SAF pick → enumerate → copy flow. It:
- Uses `saf_util` to pick a directory and list contents
- Uses `saf_stream` to copy files to app cache
- Only copies the folders we need: `history_v2/` (or `history/`), `profiles_v2/`, `plugins/DYE/`
- Reports progress via callback
- Provides cleanup method

```dart
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

final _log = Logger('SafFolderCopier');

/// Picks a folder via Android SAF, copies relevant de1app data to app cache,
/// and returns the local cache path for use with De1appScanner/Importer.
class SafFolderCopier {
  final _safUtil = SafUtil();
  final _safStream = SafStream();

  String? _cachePath;

  /// Shows the SAF folder picker and copies de1app data to app cache.
  /// Returns the local cache path, or null if the user cancelled.
  ///
  /// [onProgress] reports (copiedFiles, totalFiles) for UI updates.
  Future<String?> pickAndCopy({
    void Function(int copied, int total)? onProgress,
  }) async {
    // 1. Pick directory via SAF
    final dir = await _safUtil.pickDirectory(
      writePermission: false,
      persistablePermission: false,
    );
    if (dir == null) return null;

    return copyFromUri(dir.uri, onProgress: onProgress);
  }

  /// Copies de1app data from a SAF tree URI to app cache.
  /// Returns the local cache path.
  Future<String?> copyFromUri(
    String treeUri, {
    void Function(int copied, int total)? onProgress,
  }) async {
    // 2. Set up local staging directory
    final cacheDir = await getTemporaryDirectory();
    final stagingDir = Directory('${cacheDir.path}/de1app_import_staging');
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }
    await stagingDir.create(recursive: true);
    _cachePath = stagingDir.path;

    // 3. List top-level contents to find relevant subdirs
    final topLevel = await _safUtil.list(treeUri);

    // Folders we want to copy
    const targetDirs = ['history_v2', 'history', 'profiles_v2'];
    const targetFiles = ['plugins/DYE/grinders.tdb'];

    // 4. Count total files for progress
    var totalFiles = 0;
    final dirsToProcess = <(SafDocumentFile, String)>[]; // (safDir, localSubdir)

    for (final entry in topLevel) {
      if (entry.isDir && targetDirs.contains(entry.name)) {
        final children = await _safUtil.list(entry.uri);
        final fileCount = children.where((c) => !c.isDir).length;
        totalFiles += fileCount;
        dirsToProcess.add((entry, entry.name));
      }
    }

    // Check for DYE grinders.tdb
    SafDocumentFile? dyeGrinderFile;
    try {
      final pluginsDir = topLevel.where((e) => e.isDir && e.name == 'plugins').firstOrNull;
      if (pluginsDir != null) {
        final pluginContents = await _safUtil.list(pluginsDir.uri);
        final dyeDir = pluginContents.where((e) => e.isDir && e.name == 'DYE').firstOrNull;
        if (dyeDir != null) {
          final dyeContents = await _safUtil.list(dyeDir.uri);
          dyeGrinderFile = dyeContents.where((e) => !e.isDir && e.name == 'grinders.tdb').firstOrNull;
          if (dyeGrinderFile != null) totalFiles++;
        }
      }
    } catch (e) {
      _log.warning('Failed to check for DYE grinders', e);
    }

    if (totalFiles == 0) {
      // No relevant data found
      await cleanup();
      return null;
    }

    // 5. Copy files
    var copiedFiles = 0;

    for (final (safDir, localSubdir) in dirsToProcess) {
      final localDir = Directory('${stagingDir.path}/$localSubdir');
      await localDir.create(recursive: true);

      final children = await _safUtil.list(safDir.uri);
      for (final child in children) {
        if (child.isDir) continue;
        final localPath = '${localDir.path}/${child.name}';
        try {
          await _safStream.copyToLocalFile(child.uri, localPath);
          copiedFiles++;
          onProgress?.call(copiedFiles, totalFiles);
        } catch (e) {
          _log.warning('Failed to copy ${child.name}', e);
        }
      }
    }

    // Copy DYE grinders.tdb if found
    if (dyeGrinderFile != null) {
      final dyeLocalDir = Directory('${stagingDir.path}/plugins/DYE');
      await dyeLocalDir.create(recursive: true);
      try {
        await _safStream.copyToLocalFile(
          dyeGrinderFile.uri,
          '${dyeLocalDir.path}/grinders.tdb',
        );
        copiedFiles++;
        onProgress?.call(copiedFiles, totalFiles);
      } catch (e) {
        _log.warning('Failed to copy DYE grinders.tdb', e);
      }
    }

    _log.info('Copied $copiedFiles/$totalFiles files to staging');
    return stagingDir.path;
  }

  /// Deletes the staging directory.
  Future<void> cleanup() async {
    if (_cachePath != null) {
      final dir = Directory(_cachePath!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _log.info('Cleaned up staging directory');
      }
      _cachePath = null;
    }
  }
}
```

**Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/src/import/saf_folder_copier.dart`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/src/import/saf_folder_copier.dart
git commit -m "feat: add SafFolderCopier for Android SAF directory import"
```

---

### Task 3: Update ImportSourcePicker for Android SAF

**Files:**
- Modify: `lib/src/import/widgets/import_source_picker.dart:18-24`

The `_pickFolder` method currently uses `FilePicker.platform.getDirectoryPath()`. On Android, replace with `SafFolderCopier`. The widget needs to report the local cache path (not the SAF URI) to `onDe1appFolderSelected`.

**Step 1: Modify _pickFolder to use SAF on Android**

Change `ImportSourcePicker` to use `SafFolderCopier` on Android and keep `file_picker` on desktop:

```dart
import 'dart:io';
// add imports for SafFolderCopier

Future<void> _pickFolder(BuildContext context) async {
  if (Platform.isAndroid) {
    final copier = SafFolderCopier();
    final localPath = await copier.pickAndCopy();
    if (localPath != null && context.mounted) {
      onDe1appFolderSelected(localPath);
    }
  } else {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your de1plus folder',
    );
    if (path != null && context.mounted) {
      onDe1appFolderSelected(path);
    }
  }
}
```

Note: `SafFolderCopier` instance needs to be accessible for cleanup later. Two options:
- Pass it out via a new callback, or
- Have the import_step manage the copier and pass `pickAndCopy` as the action.

Simpler: make the widget stateful to hold the copier reference, or better — let `import_step.dart` own the `SafFolderCopier` and pass the pick method down. Since import_step already orchestrates the flow, it should own the copier lifecycle.

**Revised approach:** Instead of modifying `ImportSourcePicker`, modify `import_step.dart` `_onFolderSelected` to use SAF on Android. The source picker just calls the callback with a folder path — on Android, the import step intercepts and uses SAF before calling scanner.

**Step 2: Modify import_step.dart _onFolderSelected**

In `_ImportStepViewState`, add a `SafFolderCopier?` field. Modify `_onFolderSelected`:

```dart
// At class level:
SafFolderCopier? _safCopier;

Future<void> _onFolderSelected(String folderPath) async {
  setState(() {
    _phase = _ImportPhase.scanning;
  });

  // On Android, folderPath from file_picker can't access subdirs.
  // Use SAF to copy to local cache first.
  String effectivePath = folderPath;
  if (Platform.isAndroid) {
    _safCopier = SafFolderCopier();
    final localPath = await _safCopier!.pickAndCopy();
    if (localPath == null) {
      if (mounted) {
        setState(() => _phase = _ImportPhase.pickSource);
      }
      return;
    }
    effectivePath = localPath;
  }

  final scanResult = await De1appScanner.scan(effectivePath);
  // ... rest unchanged
}
```

Wait — this doesn't work cleanly because `_onFolderSelected` is called AFTER the user picks a folder via ImportSourcePicker. On Android the file_picker path is useless. Better approach: **on Android, skip the file_picker entirely and have ImportSourcePicker call SAF directly**.

**Final approach:** Modify `ImportSourcePicker._pickFolder` to use SAF on Android. The copier is created and used within the method. The path returned to `onDe1appFolderSelected` is the local cache path. Cleanup happens in import_step after import completes.

To support cleanup, add a new optional `onCleanup` callback to the import flow, or simply have `_onFolderSelected` track the staging path and clean up in `_onComplete` and `dispose`.

Actually simplest: `SafFolderCopier.cleanup()` is static-friendly — we can just always try to delete the staging dir in `dispose()` and after import completes. The staging dir path is deterministic (`getTemporaryDirectory()/de1app_import_staging`).

**Step 3: Run `flutter analyze`**

**Step 4: Commit**

```bash
git add lib/src/import/widgets/import_source_picker.dart lib/src/onboarding_feature/steps/import_step.dart
git commit -m "feat: use SAF folder picker on Android for de1app import"
```

---

### Task 4: Update data_management_page.dart for Android SAF

**Files:**
- Modify: `lib/src/settings/data_management_page.dart:562-583`

The `_importFromDe1app` method also uses `FilePicker.platform.getDirectoryPath()` directly. Apply the same SAF pattern.

**Step 1: Modify _importFromDe1app**

On Android, use `SafFolderCopier` instead of `FilePicker.platform.getDirectoryPath()`:

```dart
Future<void> _importFromDe1app() async {
  String? folderPath;

  if (Platform.isAndroid) {
    final copier = SafFolderCopier();
    _showProgressDialog(context, 'Copying files...');
    folderPath = await copier.pickAndCopy();
    if (mounted) Navigator.of(context).pop(); // dismiss progress
  } else {
    folderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Decent app folder',
    );
  }

  if (folderPath == null) return;
  if (!mounted) return;

  // ... rest of method unchanged (scan, summary dialog, import)
  // Add cleanup at the end:
  if (Platform.isAndroid) {
    await SafFolderCopier().cleanup(); // static staging dir, new instance is fine
  }
}
```

**Step 2: Run `flutter analyze`**

**Step 3: Commit**

```bash
git add lib/src/settings/data_management_page.dart
git commit -m "feat: use SAF folder picker in settings import on Android"
```

---

### Task 5: Add cleanup to import_step.dart

**Files:**
- Modify: `lib/src/onboarding_feature/steps/import_step.dart`

**Step 1: Add cleanup after import completes**

In `_onComplete` and in the error paths, clean up the staging directory on Android:

```dart
Future<void> _cleanupSafStaging() async {
  if (Platform.isAndroid) {
    await SafFolderCopier().cleanup();
  }
}

// Call in _onComplete:
Future<void> _onComplete() async {
  await _cleanupSafStaging();
  await widget.settingsController.setOnboardingCompleted(true);
  widget.controller.advance();
}

// Also in dispose:
@override
void dispose() {
  _cleanupSafStaging();
  super.dispose();
}
```

**Step 2: Run `flutter analyze`**

**Step 3: Commit**

```bash
git add lib/src/onboarding_feature/steps/import_step.dart
git commit -m "feat: clean up SAF staging directory after import"
```

---

### Task 6: Test on Android + verify desktop unchanged

**Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass (scanner/importer are untouched)

**Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 3: Test on Android device/emulator**

Run app on Android with `simulate=1`, navigate to import, pick a de1plus folder. Verify:
- SAF picker appears (not file_picker)
- Files copy to cache with progress
- Scanner finds shots/profiles
- Import succeeds
- Staging directory cleaned up after

**Step 4: Test on macOS (desktop)**

Run: `flutter run --dart-define=simulate=1 -d macos`
Navigate to import, pick a folder. Verify existing file_picker flow still works.

**Step 5: Commit any fixes**

---

### Task 7: Archive plan and update issue

**Step 1: Move plan to archive**

```bash
mkdir -p doc/plans/archive/android-saf-import
mv doc/plans/2026-04-07-android-saf-import-design.md doc/plans/2026-04-07-android-saf-import.md doc/plans/archive/android-saf-import/
```

**Step 2: Commit**

```bash
git add doc/plans/
git commit -m "chore: archive SAF import plan docs"
```
