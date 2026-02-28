# Device Management Page — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract device management into a standalone settings page where users can pick preferred (auto-connect) devices from the list of currently known devices.

**Architecture:** New `DeviceManagementPage` follows the Presence/Battery standalone page pattern. `SettingsView` gets a `DeviceController` dependency and its device management section becomes a summary with a "Configure" button. The new page lists known devices split by type with radio selection for preferred device.

**Tech Stack:** Flutter, shadcn_ui, RxDart (StreamBuilder on deviceStream)

---

### Task 1: Add DeviceController to SettingsView

**Files:**
- Modify: `lib/src/settings/settings_view.dart:33-49` (constructor)
- Modify: `lib/src/app.dart:204-210` (instantiation)

**Step 1: Add DeviceController field to SettingsView**

In `lib/src/settings/settings_view.dart`, add the import and constructor parameter:

```dart
// Add import at top (after existing imports, around line 10)
import 'package:reaprime/src/controllers/device_controller.dart';
```

Add to constructor and fields (lines 33-49):

```dart
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.controller,
    required this.persistenceController,
    required this.deviceController,       // ADD
    required this.webUIService,
    required this.webUIStorage,
    this.updateCheckService,
  });

  static const routeName = '/settings';

  final SettingsController controller;
  final PersistenceController persistenceController;
  final DeviceController deviceController;  // ADD
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;
  final UpdateCheckService? updateCheckService;
```

**Step 2: Pass DeviceController from app.dart**

In `lib/src/app.dart:204-210`, add the parameter:

```dart
return SettingsView(
  controller: widget.settingsController,
  persistenceController: widget.persistenceController,
  deviceController: widget.deviceController,  // ADD
  webUIService: widget.webUIService,
  webUIStorage: widget.webUIStorage,
  updateCheckService: widget.updateCheckService,
);
```

**Step 3: Run analyze to verify**

Run: `flutter analyze`
Expected: No new errors.

**Step 4: Commit**

```
feat: pass DeviceController to SettingsView
```

---

### Task 2: Create DeviceManagementPage

**Files:**
- Create: `lib/src/settings/device_management_page.dart`

**Step 1: Create the new page file**

Create `lib/src/settings/device_management_page.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({
    super.key,
    required this.settingsController,
    required this.deviceController,
  });

  final SettingsController settingsController;
  final DeviceController deviceController;

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  late StreamSubscription<List<Device>> _deviceSubscription;
  List<Device> _devices = [];

  @override
  void initState() {
    super.initState();
    _devices = widget.deviceController.devices;
    _deviceSubscription = widget.deviceController.deviceStream.listen((devices) {
      if (mounted) {
        setState(() => _devices = devices);
      }
    });
  }

  @override
  void dispose() {
    _deviceSubscription.cancel();
    super.dispose();
  }

  List<Device> get _machines =>
      _devices.where((d) => d.type == DeviceType.machine).toList();

  List<Device> get _scales =>
      _devices.where((d) => d.type == DeviceType.scale).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Management')),
      body: ListenableBuilder(
        listenable: widget.settingsController,
        builder: (context, _) {
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  _buildSection(
                    title: 'Preferred Machine',
                    icon: Icons.coffee_outlined,
                    devices: _machines,
                    selectedId: widget.settingsController.preferredMachineId,
                    emptyLabel: 'machines',
                    onSelected: (id) async {
                      await widget.settingsController.setPreferredMachineId(id);
                      if (mounted) _showSavedSnackbar();
                    },
                  ),
                  _buildSection(
                    title: 'Preferred Scale',
                    icon: Icons.scale_outlined,
                    devices: _scales,
                    selectedId: widget.settingsController.preferredScaleId,
                    emptyLabel: 'scales',
                    onSelected: (id) async {
                      await widget.settingsController.setPreferredScaleId(id);
                      if (mounted) _showSavedSnackbar();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Device> devices,
    required String? selectedId,
    required String emptyLabel,
    required Future<void> Function(String?) onSelected,
  }) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // "None" option
          _buildDeviceRadio(
            name: 'None',
            subtitle: 'No auto-connect',
            isSelected: selectedId == null,
            onTap: () => onSelected(null),
          ),
          // Device list
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No $emptyLabel currently known. Connect to devices first, then return here to set a preference.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
            )
          else
            ...devices.map((device) => _buildDeviceRadio(
                  name: device.name,
                  subtitle: _truncatedId(device.deviceId),
                  isSelected: selectedId == device.deviceId,
                  onTap: () => onSelected(device.deviceId),
                )),
        ],
      ),
    );
  }

  Widget _buildDeviceRadio({
    required String name,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _truncatedId(String id) {
    if (id.length > 8) {
      return 'ID: ...${id.substring(id.length - 8)}';
    }
    return 'ID: $id';
  }

  void _showSavedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preference saved. Takes effect on next app start.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze`
Expected: No errors (file is self-contained).

**Step 3: Commit**

```
feat: add DeviceManagementPage for preferred device selection
```

---

### Task 3: Replace settings section with summary + Configure button

**Files:**
- Modify: `lib/src/settings/settings_view.dart:314-415` (`_buildDeviceManagementSection`)
- Modify: `lib/src/settings/settings_view.dart:1193-1258` (remove `_showPreferredDeviceInfo`)

**Step 1: Add import for new page**

At the top of `settings_view.dart`, add:

```dart
import 'package:reaprime/src/settings/device_management_page.dart';
```

**Step 2: Replace `_buildDeviceManagementSection` with summary**

Replace lines 314-415 with a summary section that follows the same pattern as `_buildPresenceSection` (lines 249-312):

```dart
Widget _buildDeviceManagementSection() {
  // Resolve device names from DeviceController if available
  final machineId = widget.controller.preferredMachineId;
  final scaleId = widget.controller.preferredScaleId;

  final machineName = _resolveDeviceName(machineId);
  final scaleName = _resolveDeviceName(scaleId);

  return ShadCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.devices_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Device Management',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Configure preferred auto-connect devices',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
        ),
        const SizedBox(height: 16),
        Text(
          'Machine: ${machineName ?? "Not set"}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Scale: ${scaleName ?? "Not set"}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        ShadButton.outline(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DeviceManagementPage(
                  settingsController: widget.controller,
                  deviceController: widget.deviceController,
                ),
              ),
            );
          },
          child: const Text('Configure'),
        ),
        const Divider(height: 32),
        // Simulated Devices toggle stays here
        ShadSwitch(
          value: widget.controller.simulatedDevices,
          onChanged: (v) async {
            _log.info("toggle sim to $v");
            await widget.controller.setSimulatedDevices(v);
          },
          label: const Text("Show simulated devices"),
          sublabel: const Text(
            "Whether simulated devices should be shown in scan results",
          ),
        ),
      ],
    ),
  );
}
```

**Step 3: Add the `_resolveDeviceName` helper**

Add this helper method to `_SettingsViewState` (near the other helpers):

```dart
String? _resolveDeviceName(String? deviceId) {
  if (deviceId == null) return null;
  try {
    final device = widget.deviceController.devices.firstWhere(
      (d) => d.deviceId == deviceId,
    );
    return device.name;
  } catch (_) {
    // Device not currently known — show truncated ID
    if (deviceId.length > 8) {
      return '...${deviceId.substring(deviceId.length - 8)}';
    }
    return deviceId;
  }
}
```

**Step 4: Remove `_showPreferredDeviceInfo` method**

Delete the `_showPreferredDeviceInfo` method (around lines 1193-1258) and the `_InfoPoint` widget if it's only used there.

**Step 5: Run analyze and tests**

Run: `flutter analyze && flutter test`
Expected: All pass.

**Step 6: Commit**

```
feat: replace device management section with summary and Configure navigation
```

---

### Task 4: Verify in simulator

**Step 1: Run the app with simulated devices**

Run: `flutter run --dart-define=simulate=1`

**Step 2: Verify settings page**

- Open Settings
- Device Management section shows summary with "Machine: Not set" / "Scale: Not set"
- Simulated Devices toggle is present
- "Configure" button navigates to DeviceManagementPage

**Step 3: Verify device management page**

- Two sections: Preferred Machine and Preferred Scale
- "None" option selected by default for both
- If simulated devices are enabled and a connection was made, devices appear in the lists
- Selecting a device saves the preference and shows snackbar
- Going back to settings summary shows updated names

**Step 4: Commit any fixes if needed**
