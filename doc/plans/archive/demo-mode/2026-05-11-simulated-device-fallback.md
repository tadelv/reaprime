# Simulated Device Fallback on Empty Scan

**P0 | DE User Lens | 2026-05-11**

## Problem

When user scans and finds no real hardware, app dead-ends at "No Decent Machines Found" with only "Scan Again" or "Continue to Dashboard" (useless without device). Zero path to demo/use app without manually enabling simulated devices via `--dart-define=simulate=` or Settings → Devices.

## Solution

Add "Try Demo Mode" button to empty-scan views. Tap enables simulated machine + scale **ephemerally** for this session only — no SharedPreferences write, gone on restart.

## Views that show demo button

| Context | View | File |
|---------|------|------|
| Discovery page, no devices | `_noDevicesFoundView` | `device_discovery_view.dart` |
| Discovery page, BLE off | `_noDevicesFoundView` (body below error banner) | Same — already rendered in this case |
| Onboarding, no devices | `ScanResultsSummary` via `_noDevicesFoundView` | `scan_results_summary.dart` + `scan_step.dart` |
| Onboarding, BLE off | `_adapterErrorView` | `scan_step.dart` |

## Design

### Ephemeral enablement

New synchronous method on `SettingsController`:

```dart
void enableSimulatedDevicesForSession(Set<SimulatedDevicesTypes> devices) {
  _simulatedDevices = devices;
  notifyListeners(); // triggers main.dart listener → pushes to SimulatedDeviceService
  // No _settingsService.setSimulatedDevices() call — no persistence
}
```

No equality guard — always sets + notifies. If `_simulatedDevices` already equals the target, `notifyListeners()` still fires and main.dart listener still pushes current value to `SimulatedDeviceService`.

On restart, `loadSettings()` reads from prefs → `_simulatedDevices` reset to stored value.

### Signaling chain (all synchronous)

```
enableSimulatedDevicesForSession({machine, scale})
  → _simulatedDevices = {machine, scale}
  → notifyListeners()
  → main.dart listener: simulatedDevicesService.enabledDevices = 
      {...dartDefineDevices, ...settingsController.simulatedDevices}
  → connect() → scanForDevices()
  → SimulatedDeviceService.scanForDevices() sees enabledDevices
  → creates MockDe1 + MockScale
  → policy resolver: 1 machine → auto-connect, 1 scale → auto-connect
  → phase → ready
```

### Flow

1. Scan completes, no devices (or BLE off) → relevant empty/error view shown
2. "Try Demo Mode" button visible alongside existing actions
3. User taps → `settingsController.enableSimulatedDevicesForSession({machine, scale})` → `connectionManager.connect()`
4. Re-scan finds MockDe1 + MockScale → auto-connects both
5. Normal app flow proceeds with simulated hardware

### Onboarding auto-advance

Onboarding already auto-advances when `ConnectionPhase.ready` — no special handling needed.

### Settings UI consistency

During session, Settings → Devices → simulated toggles show machine + scale as enabled (reads from `SettingsController._simulatedDevices`). User can disable them there at any time via normal `setSimulatedDevices()` which persists.

## Files to touch

| File | Change |
|------|--------|
| `lib/src/settings/settings_controller.dart` | Add `void enableSimulatedDevicesForSession(Set<SimulatedDevicesTypes>)` |
| `lib/src/device_discovery_feature/device_discovery_view.dart` | "Try Demo Mode" button in `_noDevicesFoundView` |
| `lib/src/onboarding_feature/steps/scan_step.dart` | Demo button in `_adapterErrorView` + wire `onTryDemoMode` for `ScanResultsSummary` |
| `lib/src/onboarding_feature/widgets/scan_results_summary.dart` | New `onTryDemoMode` callback + demo button in action section |

## UI layout changes

### DeviceDiscoveryView._noDevicesFoundView

```
Existing:
  [ Scan Again ]
  [ Export Logs ] [ Continue to Dashboard ]

New:
  [ Scan Again ]
  [🎮 Try Demo Mode]          ← ShadButton.outline
  [ Export Logs ] [ Continue to Dashboard ]
```

### ScanStep._adapterErrorView

```
Existing:
  [ Try Again ]

New:
  [ Try Again ]
  [🎮 Try Demo Mode]          ← ShadButton.outline
```

### ScanResultsSummary

```
Existing:
  [ Scan Again ]
  [ Troubleshoot ] [ Export Logs ]
  [ Continue to Dashboard ]

New:
  [ Scan Again ]
  [🎮 Try Demo Mode]          ← ShadButton.outline, after Scan Again
  [ Troubleshoot ] [ Export Logs ]
  [ Continue to Dashboard ]
```

## Edge cases handled

| Case | Behavior |
|------|----------|
| User taps demo twice | Idempotent — sets same values, notifies, re-scans |
| User has `--dart-define=simulate=1` | Simulated already on → empty scan never happens → button never shown |
| Real device appears during demo re-scan | Both mock + real devices in results → picker shown |
| BLE off during demo mode | BLE service fails (harmless), simulated service produces devices |
| User disables simulated in Settings after demo | Normal `setSimulatedDevices` writes to prefs → overwrites ephemeral state |
| App restart | `loadSettings()` reads prefs → simulated back to off |

## Testing

| Tier | Test |
|------|------|
| Unit | `SettingsController.enableSimulatedDevicesForSession` — sets `_simulatedDevices`, notifies, does NOT call service |
| Widget | `DeviceDiscoveryView._noDevicesFoundView` — renders demo button, tap calls controller + connect |
| Widget | `ScanResultsSummary` — renders demo button when `onTryDemoMode` provided |
| Widget | `ScanStep._adapterErrorView` — renders demo button, tap clears error + enables simulated + connects |
| Integration | Tap demo → simulated enabled → re-scan → MockDe1+MockScale appear → auto-connect |
| Integration | Restart app → simulated back to off |
| Integration | BLE-off: error banner + demo button → tap → simulated devices connect |

## Steps

1. Add `enableSimulatedDevicesForSession()` to `SettingsController` — unit test
2. Add demo button to `DeviceDiscoveryView._noDevicesFoundView` — widget test
3. Add `onTryDemoMode` callback to `ScanResultsSummary`, render demo button — widget test
4. Wire demo button in `ScanStep._noDevicesFoundView` → passes callback to `ScanResultsSummary`
5. Add demo button to `ScanStep._adapterErrorView`
6. Run full `flutter test` — all 1135+ tests must pass
7. Smoke test: `flutter run` (no simulate flag) → scan → tap demo → MockDe1 connects
