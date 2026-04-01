# Custom Skin Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix custom skin loading on Android/iOS by copying files into app storage, add delete UI for custom skins, and add an optional Android storage permission button for live-editing.

**Architecture:** Three changes to `settings_view.dart`: (1) change `_pickCustomSkinFolder` to install via copy instead of serving raw path, (2) add trash icons on non-bundled skins in the dropdown, (3) add a permission status/request widget for Android. One manifest change to declare `MANAGE_EXTERNAL_STORAGE`. All gated behind `!BuildInfo.appStore`.

**Tech Stack:** Flutter, `permission_handler` (already in pubspec), `file_picker` (already in pubspec), Android `MANAGE_EXTERNAL_STORAGE` permission.

---

### Task 1: Change custom skin picker to install-then-serve

**Files:**
- Modify: `lib/src/settings/settings_view.dart:765-808` (`_pickCustomSkinFolder`)

**Step 1: Rewrite `_pickCustomSkinFolder` to copy files into app storage**

Replace the current `_pickCustomSkinFolder` method (lines 765-808) with:

```dart
Future<void> _pickCustomSkinFolder(BuildContext context) async {
  final selectedDirectory = await FilePicker.platform.getDirectoryPath();

  if (selectedDirectory != null) {
    final indexFile = File('$selectedDirectory/index.html');
    final itExists = await indexFile.exists();

    if (itExists) {
      try {
        final skinId =
            await widget.webUIStorage.installFromPath(selectedDirectory);

        // Start serving the newly installed skin
        final skin = widget.webUIStorage.getSkin(skinId);
        if (skin != null) {
          await widget.webUIService.serveFolderAtPath(skin.path);
          await widget.webUIStorage.setDefaultSkin(skinId);
          setState(() => _selectedSkinId = skinId);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Expanded(
                    child: Text('Custom skin installed and loaded'),
                  ),
                  ShadButton.outline(
                    onPressed: () async {
                      await launchUrl(Uri.parse('http://localhost:3000'));
                    },
                    child: const Text("Open"),
                  ),
                ],
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to install skin: $e')),
          );
        }
        setState(
            () => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('index.html not found in selected folder'),
          ),
        );
      }
      setState(() => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
    }
  } else {
    setState(() => _selectedSkinId = widget.webUIStorage.defaultSkin?.id);
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/src/settings/settings_view.dart`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/src/settings/settings_view.dart
git commit -m "fix: install custom skins to app storage instead of serving raw path

Copies picked folder contents into app's web-ui directory via
installFromPath(), fixing Android scoped storage and iOS
temporary URL issues."
```

---

### Task 2: Add delete button to non-bundled skins in dropdown

**Files:**
- Modify: `lib/src/settings/settings_view.dart:626-679` (`_buildSkinSelector`)

**Step 1: Add a delete icon to each non-bundled skin row**

In `_buildSkinSelector`, modify the `installedSkins.map((skin) {...})` block to add a trailing delete `IconButton` for non-bundled skins, guarded by `!BuildInfo.appStore`. The delete button should:
- Call `widget.webUIStorage.removeSkin(skin.id)`
- If the deleted skin was the selected skin, reset to default
- If the deleted skin was being served, stop serving
- Call `setState` to rebuild

Replace the skin mapping (lines 644-665) with:

```dart
...installedSkins.map((skin) {
  return DropdownMenuItem(
    value: skin.id,
    child: Row(
      children: [
        Icon(
          skin.isBundled ? Icons.verified : Icons.folder,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(skin.name, overflow: TextOverflow.ellipsis),
        ),
        if (skin.version != null)
          Text(
            ' v${skin.version}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (!skin.isBundled && !BuildInfo.appStore)
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Remove skin?'),
                    content: Text(
                        'Remove "${skin.name}"? This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await widget.webUIStorage.removeSkin(skin.id);
                  if (_selectedSkinId == skin.id) {
                    _selectedSkinId =
                        widget.webUIStorage.defaultSkin?.id;
                    if (widget.webUIService.isServing) {
                      await widget.webUIService.stopServing();
                    }
                  }
                  setState(() {});
                }
              },
            ),
          ),
      ],
    ),
  );
}),
```

**Step 2: Run analyze**

Run: `flutter analyze lib/src/settings/settings_view.dart`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/src/settings/settings_view.dart
git commit -m "feat: add delete button for custom skins in skin selector

Shows a trash icon on non-bundled skins with confirmation dialog.
Hidden in app store builds."
```

---

### Task 3: Add Android storage permission button

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml` (add permission declaration)
- Modify: `lib/src/settings/settings_view.dart:450-495` (`_buildWebUISection`)

**Step 1: Declare MANAGE_EXTERNAL_STORAGE in AndroidManifest.xml**

Add after line 32 (after REQUEST_INSTALL_PACKAGES):

```xml
<!-- Storage permission for live-editing custom WebUI skins from external folders -->
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
```

**Step 2: Add import for permission_handler**

Add to imports at the top of `settings_view.dart`:

```dart
import 'package:permission_handler/permission_handler.dart';
```

**Step 3: Add a permission widget builder method**

Add a new method to `_SettingsViewState`:

```dart
Widget _buildStoragePermissionRow() {
  // Only show on Android, never in app store builds
  if (!Platform.isAndroid || BuildInfo.appStore) {
    return const SizedBox.shrink();
  }

  return FutureBuilder<PermissionStatus>(
    future: Permission.manageExternalStorage.status,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const SizedBox.shrink();

      final status = snapshot.data!;

      if (status.isGranted) {
        return const _SettingRow(
          label: 'Storage Access',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 16, color: Colors.green),
              SizedBox(width: 8),
              Text('Full storage access granted'),
            ],
          ),
        );
      }

      return _SettingRow(
        label: 'Storage Access',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grant full storage access to live-edit skins from external folders without copying.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ShadButton.outline(
              onPressed: () async {
                final result =
                    await Permission.manageExternalStorage.request();
                if (result.isPermanentlyDenied) {
                  await openAppSettings();
                }
                setState(() {});
              },
              child: const Text('Grant Storage Access'),
            ),
          ],
        ),
      );
    },
  );
}
```

**Step 4: Insert the permission widget into `_buildWebUISection`**

In `_buildWebUISection` (line 450-495), add `_buildStoragePermissionRow()` after the skin selector row and before the Divider. Insert after line 459:

```dart
_buildStoragePermissionRow(),
```

**Step 5: Run analyze**

Run: `flutter analyze lib/src/settings/settings_view.dart`
Expected: No issues

**Step 6: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml lib/src/settings/settings_view.dart
git commit -m "feat: add Android storage permission button for live skin editing

Shows permission status/request in Web Interface settings on Android.
Allows serving skins directly from external storage without copying.
Hidden in app store builds."
```

---

### Task 4: Verify on simulator

**Step 1: Run flutter analyze on the full project**

Run: `flutter analyze`
Expected: No issues

**Step 2: Run full test suite**

Run: `flutter test`
Expected: All tests pass

**Step 3: Run app in simulate mode for visual verification**

Run: `flutter run --dart-define=simulate=1`
Expected: Settings → Web Interface section shows skin selector with delete icons on custom skins. On Android, shows storage permission row.
