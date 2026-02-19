# Preferred Device Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add preferred scale support (mirroring existing preferred machine) with a two-column device selection UI, parallel auto-connect, and settings management.

**Architecture:** Extend the existing preferred-machine pattern (SettingsService → SettingsController → UI/API) to scales. Generalize `DeviceSelectionWidget` to work with any `DeviceType`. Modify `ScaleController` to honor a preferred scale ID instead of blindly connecting to the first scale found. Update the discovery UI to show machines and scales side-by-side.

**Tech Stack:** Flutter/Dart, SharedPreferences, RxDart, shadcn_ui, shelf (REST API), JavaScript (settings plugin)

---

### Task 1: Add `preferredScaleId` to Settings Persistence

**Files:**
- Modify: `lib/src/settings/settings_service.dart:186` (SettingsKeys enum)
- Modify: `lib/src/settings/settings_service.dart:91-101` (after preferredMachineId methods)
- Modify: `lib/src/settings/settings_controller.dart:37` (after _preferredMachineId field)
- Modify: `lib/src/settings/settings_controller.dart:61` (after getter)
- Modify: `lib/src/settings/settings_controller.dart:82` (in loadSettings)
- Modify: `lib/src/settings/settings_controller.dart:187-194` (after setPreferredMachineId)

**Step 1: Add `preferredScaleId` to `SettingsKeys` enum**

In `lib/src/settings/settings_service.dart`, add `preferredScaleId` after `preferredMachineId` (line 186):

```dart
enum SettingsKeys {
  themeMode,
  gatewayMode,
  logLevel,
  recordShotPreheat,
  simulateDevices,
  weightFlowMultiplier,
  volumeFlowMultiplier,
  scalePowerMode,
  preferredMachineId,
  preferredScaleId,       // <-- ADD THIS
  skinExitButtonPosition,
  // ... rest unchanged
}
```

**Step 2: Add getter/setter to `SettingsService`**

After the `setPreferredMachineId` method (line 101), add:

```dart
  Future<String?> preferredScaleId() async {
    return await prefs.getString(SettingsKeys.preferredScaleId.name);
  }

  Future<void> setPreferredScaleId(String? scaleId) async {
    if (scaleId == null) {
      await prefs.remove(SettingsKeys.preferredScaleId.name);
    } else {
      await prefs.setString(SettingsKeys.preferredScaleId.name, scaleId);
    }
  }
```

**Step 3: Add field, getter, loader, and setter to `SettingsController`**

In `lib/src/settings/settings_controller.dart`:

After `String? _preferredMachineId;` (line 37), add:
```dart
  String? _preferredScaleId;
```

After `String? get preferredMachineId` (line 61), add:
```dart
  String? get preferredScaleId => _preferredScaleId;
```

In `loadSettings()`, after line 82 (`_preferredMachineId = ...`), add:
```dart
    _preferredScaleId = await _settingsService.preferredScaleId();
```

After `setPreferredMachineId` method (line 194), add:
```dart
  Future<void> setPreferredScaleId(String? scaleId) async {
    if (scaleId == _preferredScaleId) {
      return;
    }
    _preferredScaleId = scaleId;
    await _settingsService.setPreferredScaleId(scaleId);
    notifyListeners();
  }
```

**Step 4: Run analyzer**

Run: `flutter analyze lib/src/settings/`
Expected: No issues

**Step 5: Commit**

```bash
git add lib/src/settings/settings_service.dart lib/src/settings/settings_controller.dart
git commit -m "feat: add preferredScaleId to settings persistence (#11)"
```

---

### Task 2: Add `preferredScaleId` to REST API

**Files:**
- Modify: `lib/src/services/webserver/settings_handler.dart:25` (GET handler)
- Modify: `lib/src/services/webserver/settings_handler.dart:97-106` (POST handler)

**Step 1: Add to GET response**

In `settings_handler.dart`, inside the GET handler, after line 25 (`final preferredMachineId = ...`), add:

```dart
      final preferredScaleId = _controller.preferredScaleId;
```

And add to the return map after `'preferredMachineId': preferredMachineId,` (line 35):

```dart
        'preferredScaleId': preferredScaleId,
```

**Step 2: Add to POST handler**

After the `preferredMachineId` POST block (lines 97-106), add:

```dart
      if (json.containsKey('preferredScaleId')) {
        final value = json['preferredScaleId'];
        if (value == null || value is String) {
          await _controller.setPreferredScaleId(value);
        } else {
          return Response.badRequest(
            body: {'message': 'preferredScaleId must be a string or null'},
          );
        }
      }
```

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/services/webserver/`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/services/webserver/settings_handler.dart
git commit -m "feat: expose preferredScaleId in settings REST API (#11)"
```

---

### Task 3: Generalize `DeviceSelectionWidget`

**Files:**
- Modify: `lib/src/home_feature/widgets/device_selection_widget.dart` (full file)
- Modify: `lib/src/permissions_feature/permissions_view.dart:537-545` (caller site)

This is the biggest refactor. The current widget is hardcoded to `De1Interface`. We need it to work with any `Device` type.

**Step 1: Refactor widget parameters**

Replace the current widget class with a generalized version. Key changes:

- Replace `Function(De1Interface) onDeviceTapped` with `Function(dev.Device) onDeviceTapped`
- Add `dev.DeviceType deviceType` parameter to filter devices
- Replace `SettingsController? settingsController` with explicit `String? preferredDeviceId` and `Function(String?)? onPreferredChanged`
- Change the internal list from `List<De1Interface>` to `List<dev.Device>`
- Filter by `deviceType` instead of hardcoded `DeviceType.machine`
- The checkbox calls `onPreferredChanged` instead of directly calling `settingsController.setPreferredMachineId`

New constructor signature:

```dart
class DeviceSelectionWidget extends StatefulWidget {
  final DeviceController deviceController;
  final dev.DeviceType deviceType;
  final Function(dev.Device) onDeviceTapped;
  final bool showHeader;
  final String? headerText;
  final String? connectingDeviceId;
  final String? errorMessage;
  final String? preferredDeviceId;
  final Function(String?)? onPreferredChanged;
  // ...
}
```

Internal state changes:
- `List<De1Interface> _discoveredDevices` → `List<dev.Device> _discoveredDevices`
- Filter: `.where((device) => device.type == widget.deviceType)` instead of hardcoded `DeviceType.machine`
- Remove `.cast<De1Interface>()`
- Checkbox: call `widget.onPreferredChanged?.call(value ? device.deviceId : null)`
- Auto-connect label: use `widget.deviceType == DeviceType.machine ? 'Auto-connect to this machine' : 'Auto-connect to this scale'`

**Step 2: Update the caller in `permissions_view.dart`**

In `_resultsView` (line 537), update the `DeviceSelectionWidget` construction:

```dart
DeviceSelectionWidget(
  deviceController: widget.deviceController,
  deviceType: dev.DeviceType.machine,
  showHeader: true,
  headerText: "Select a machine from the list",
  connectingDeviceId: _connectingDeviceId,
  errorMessage: _connectionError,
  preferredDeviceId: widget.settingsController.preferredMachineId,
  onPreferredChanged: (id) => widget.settingsController.setPreferredMachineId(id),
  onDeviceTapped: (device) => _handleDeviceTapped(device as De1Interface),
),
```

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/home_feature/widgets/ lib/src/permissions_feature/`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/home_feature/widgets/device_selection_widget.dart lib/src/permissions_feature/permissions_view.dart
git commit -m "refactor: generalize DeviceSelectionWidget for any device type (#11)"
```

---

### Task 4: Two-Column Discovery UI

**Files:**
- Modify: `lib/src/permissions_feature/permissions_view.dart:492` (`_resultsView`)
- Modify: `lib/src/permissions_feature/permissions_view.dart:317-336` (`_handleDeviceTapped`)

**Step 1: Add scale state tracking**

In `_DeviceDiscoveryState`, add fields alongside existing machine state:

```dart
  String? _connectingScaleId;
  String? _scaleConnectionError;
```

**Step 2: Refactor `_resultsView` to two columns**

Replace the current `SizedBox(height: 500, width: 300, ...)` (line 492) with a wider two-column layout:

```dart
Widget _resultsView(BuildContext context) {
  final theme = ShadTheme.of(context);

  return Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 16,
    children: [
      // Scanning indicator
      if (_isScanning)
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            Text('Scanning for devices...', style: theme.textTheme.muted),
          ],
        ),

      // Two-column device lists
      SizedBox(
        height: 400,
        width: 600,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Machine column
            Expanded(
              child: DeviceSelectionWidget(
                deviceController: widget.deviceController,
                deviceType: dev.DeviceType.machine,
                showHeader: true,
                headerText: "Machines",
                connectingDeviceId: _connectingDeviceId,
                errorMessage: _connectionError,
                preferredDeviceId: widget.settingsController.preferredMachineId,
                onPreferredChanged: (id) =>
                    widget.settingsController.setPreferredMachineId(id),
                onDeviceTapped: (device) =>
                    _handleDeviceTapped(device as De1Interface),
              ),
            ),
            SizedBox(width: 16),
            // Scale column
            Expanded(
              child: DeviceSelectionWidget(
                deviceController: widget.deviceController,
                deviceType: dev.DeviceType.scale,
                showHeader: true,
                headerText: "Scales",
                connectingDeviceId: _connectingScaleId,
                errorMessage: _scaleConnectionError,
                preferredDeviceId: widget.settingsController.preferredScaleId,
                onPreferredChanged: (id) =>
                    widget.settingsController.setPreferredScaleId(id),
                onDeviceTapped: _handleScaleTapped,
              ),
            ),
          ],
        ),
      ),

      // Action buttons
      if (!_isScanning)
        SizedBox(
          width: 300,
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: _retryScan,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Icon(LucideIcons.refreshCw, size: 16),
                      Text('ReScan'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ShadButton.secondary(
                  onPressed: () {
                    Navigator.popAndPushNamed(context, HomeScreen.routeName);
                  },
                  child: Text('Dashboard'),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
```

**Step 3: Add `_handleScaleTapped` method**

Add a new method for scale connection (mirrors `_handleDeviceTapped` but doesn't gate navigation):

```dart
  Future<void> _handleScaleTapped(dev.Device scale) async {
    if (_connectingScaleId != null) return;
    setState(() {
      _connectingScaleId = scale.deviceId;
      _scaleConnectionError = null;
    });
    try {
      // ScaleController.connectToScale will be called — the scale is
      // already in the device stream, so ScaleController picks it up
      // if auto-connect is enabled, or we connect manually here.
      // For now, tapping a scale in the selection list is informational
      // (sets preference). The actual connection happens via ScaleController.
      await widget.settingsController.setPreferredScaleId(scale.deviceId);
      setState(() {
        _connectingScaleId = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectingScaleId = null;
          _scaleConnectionError = 'Failed: $e';
        });
      }
    }
  }
```

**Note:** The exact behavior of scale tapping (whether it immediately connects or just sets preference) should be decided during implementation. The simplest approach: tapping a scale sets it as preferred and lets `ScaleController` handle the actual connection via its device stream listener.

**Step 4: Update `_discoverySubscription` to also track scales**

In `initState()`, the existing listener (line 446) filters only `De1Interface`. Update it to transition to `foundMany` when either machines or scales are found:

```dart
    _discoverySubscription = widget.deviceController.deviceStream.listen((data) {
      final discoveredMachines = data.whereType<De1Interface>().toList();
      final discoveredScales = data.whereType<Scale>().toList();
      if (discoveredMachines.isEmpty && discoveredScales.isEmpty) return;

      // Auto-connect if the preferred machine appeared
      if (_autoConnectDeviceId != null && _connectingDeviceId == null) {
        final target = discoveredMachines.firstWhereOrNull(
          (d) => d.deviceId == _autoConnectDeviceId,
        );
        if (target != null) {
          _autoConnectDeviceId = null;
          _handleDeviceTapped(target);
          return;
        }
      }

      if (_state != DiscoveryState.directConnecting) {
        setState(() {
          _state = DiscoveryState.foundMany;
        });
      }
    });
```

This requires adding `import 'package:reaprime/src/models/device/scale.dart';` at the top.

**Step 5: Run analyzer**

Run: `flutter analyze lib/src/permissions_feature/`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/permissions_feature/permissions_view.dart
git commit -m "feat: two-column device selection with machines and scales (#11)"
```

---

### Task 5: ScaleController Preferred Scale Support

**Files:**
- Modify: `lib/src/controllers/scale_controller.dart:11-33`
- Modify: `lib/main.dart:309` (ScaleController construction)

**Step 1: Add `preferredScaleId` to `ScaleController`**

Add a `preferredScaleId` property and modify the device stream listener to honor it:

```dart
class ScaleController {
  final DeviceController _deviceController;
  String? _preferredScaleId;

  StreamSubscription<List<Device>>? _deviceStreamSubscription;

  Scale? _scale;

  StreamSubscription<ConnectionState>? _scaleConnection;
  StreamSubscription<ScaleSnapshot>? _scaleSnapshot;

  final Logger log = Logger('ScaleController');

  ScaleController({
    required DeviceController controller,
    String? preferredScaleId,
  }) : _deviceController = controller,
       _preferredScaleId = preferredScaleId {
    _deviceStreamSubscription = _deviceController.deviceStream.listen((devices) async {
      var scales = devices.whereType<Scale>().toList();
      if (_scale == null &&
          scales.isNotEmpty &&
          _deviceController.shouldAutoConnect) {
        if (_preferredScaleId != null) {
          // Connect only to the preferred scale
          final preferred = scales.firstWhereOrNull(
            (s) => s.deviceId == _preferredScaleId,
          );
          if (preferred != null) {
            await connectToScale(preferred);
          }
          // If preferred not found, don't connect to any scale
        } else {
          // No preference set — connect to first scale found (legacy behavior)
          await connectToScale(scales.first);
        }
      }
    });
  }

  set preferredScaleId(String? id) => _preferredScaleId = id;
```

This requires adding `import 'package:collection/collection.dart';` at the top for `firstWhereOrNull`.

**Step 2: Update `main.dart` to pass preferred scale ID**

At line 309, change:
```dart
  final scaleController = ScaleController(
    controller: deviceController,
    preferredScaleId: settingsController.preferredScaleId,
  );
```

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/controllers/scale_controller.dart lib/main.dart`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/controllers/scale_controller.dart lib/main.dart
git commit -m "feat: ScaleController honors preferredScaleId for auto-connect (#11)"
```

---

### Task 6: Settings View — Preferred Scale Display & Clear

**Files:**
- Modify: `lib/src/settings/settings_view.dart:174-236` (`_buildDeviceManagementSection`)
- Modify: `lib/src/settings/settings_view.dart:1015-1076` (`_showPreferredDeviceInfo`)

**Step 1: Add preferred scale subsection to `_buildDeviceManagementSection()`**

After the existing preferred machine section (after line 221's `],`) and before `const Divider(height: 32),` (line 222), add:

```dart
        const Divider(height: 32),
        // Auto-Connect Scale
        Row(
          children: [
            Expanded(
              child: Text(
                'Auto-Connect Scale',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.controller.preferredScaleId != null) ...[
          Text(
            'Scale ID: ${widget.controller.preferredScaleId}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ShadButton.destructive(
            onPressed: () async {
              await widget.controller.setPreferredScaleId(null);
            },
            child: const Text('Clear Auto-Connect Scale'),
          ),
        ] else ...[
          Text(
            'No auto-connect scale set',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'To set an auto-connect scale, check the "Auto-connect to this scale" checkbox when selecting a device during startup.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
```

**Step 2: Update the info dialog to mention scales**

In `_showPreferredDeviceInfo()` (line 1015), update the dialog to be more general. Change the title and description:

```dart
  void _showPreferredDeviceInfo(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Auto-Connect Devices'),
        description: const Text('Automatically connect to your preferred machine and scale on startup'),
```

Add an additional `_InfoPoint` after the existing three (after line 1043):

```dart
            _InfoPoint(
              icon: Icons.scale,
              text: 'Also connect to your preferred scale if set',
            ),
```

And update the "How to set" text (line 1051-1053) to mention scales:

```dart
            Text(
              'During device selection at startup, check the "Auto-connect" checkbox next to your preferred machine or scale.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
```

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/settings/settings_view.dart`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/settings/settings_view.dart
git commit -m "feat: add preferred scale display and clear button to settings view (#11)"
```

---

### Task 7: Settings Plugin — Add Scale ID Input

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js:411` (after preferredMachineId field)
- Modify: `assets/plugins/settings.reaplugin/manifest.json:6` (bump version)

**Step 1: Add scale ID input field to plugin HTML**

In `plugin.js`, after the `preferredMachineId` setting item (after line 411), add:

```html
                    <div class="setting-item">
                        <label class="setting-label" for="preferredScaleId">Auto-Connect Scale ID</label>
                        <div class="setting-control">
                            <input type="text" id="preferredScaleId" value="${reaSettings.preferredScaleId || ''}" placeholder="None set" aria-describedby="preferredScaleId-desc" style="width: 200px;">
                            <span id="preferredScaleId-desc" class="visually-hidden">Scale ID for automatic connection on startup. Leave empty to disable auto-connect for scales.</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('preferredScaleId', document.getElementById('preferredScaleId').value || null)" aria-label="Save preferred scale ID setting">Save</button>
                        </div>
                    </div>
```

No new JS logic needed — the existing `updateReaSetting()` function handles any key.

**Step 2: Bump plugin version**

In `manifest.json`, change `"version": "0.0.10"` to `"version": "0.0.11"`.

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js assets/plugins/settings.reaplugin/manifest.json
git commit -m "feat: add preferredScaleId to settings plugin UI (#11)"
```

---

### Task 8: Integration Verification

**Step 1: Run full analyzer**

Run: `flutter analyze`
Expected: No issues (or only pre-existing warnings)

**Step 2: Run tests**

Run: `flutter test`
Expected: All tests pass

**Step 3: Manual smoke test**

Run: `flutter run --dart-define=simulate=1`

Verify:
1. App starts and shows device selection screen with two columns (Machines | Scales)
2. Simulated machine appears in left column, simulated scale in right column
3. Tapping a machine allows proceeding
4. "Auto-connect" checkboxes work for both machines and scales
5. In Settings, both preferred machine and scale IDs are shown
6. "Clear" buttons work for both
7. On restart with preferences set, auto-connect happens for both devices

**Step 4: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: integration fixups for preferred device selection (#11)"
```
