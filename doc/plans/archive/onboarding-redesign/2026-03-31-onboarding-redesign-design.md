# Onboarding Flow Redesign — Design Document

**Date:** 2026-03-31
**Branch:** `feat/onboarding-update`

## Problem

The current onboarding experience has several pain points:

1. **No scan observability** — when no devices are found, the user has no idea whether zero BLE devices were seen, a machine was found but connection failed, or the preferred device is simply off. All scenarios look identical.
2. **No "taking too long" escape hatch** — users stare at coffee messages with no recourse during long scans.
3. **No troubleshooting guidance** — the "no devices found" screen offers "Scan Again" and "Export Logs" but no actionable steps.
4. **Scan state desynchronization** — when the app is backgrounded or Bluetooth is toggled, the UI can show stale scan state.
5. **Not extensible** — the current permissions → scan flow has no mechanism for inserting future onboarding steps (data import, setup, etc.).

## Approach: Onboarding Flow Controller + Scan State Guardian

Two new abstractions:
- **OnboardingController** — manages a linear sequence of onboarding steps, evaluated each launch.
- **ScanStateGuardian** — monitors BLE adapter state and app lifecycle, reconciling scan UI with reality. Reusable beyond onboarding.

## Design

### 1. Onboarding Flow Controller

**New file:** `lib/src/onboarding_feature/onboarding_controller.dart`

An `OnboardingController` manages an ordered list of `OnboardingStep`s. Each step defines:
- A **widget builder** — the screen to display
- A **`shouldShow` predicate** — evaluated at flow start (async, can query system state)
- A **`canAdvance` stream** — step signals when it's complete

The controller tracks `currentStepIndex` and exposes it as a stream. The hosting widget (`OnboardingView`) renders the current step's widget with transitions.

**Step registration:**
```
steps: [
  PermissionsStep,     // shouldShow: queries actual permission status per-platform
  // future: DataImportStep, SetupStep, etc.
  ScanStep,            // shouldShow: always true — always last
]
```

**Key behaviors:**
- **Forward-only navigation.** No back button. Each step calls `controller.advance()` when done.
- **System navigation blocked.** `OnboardingView` wraps content in `PopScope(canPop: false)` — Android back button and iOS swipe-to-go-back are suppressed during the entire onboarding flow.
- **Runs every launch.** `shouldShow` predicates filter steps each time. A returning user with all permissions granted skips straight to the scan step.
- **PermissionsStep.shouldShow** queries actual permission status (platform-specific). If a user revokes BLE permission between launches, the permissions step reappears.
- **ScanStep.shouldShow** always returns `true`.

### 2. Scan Step — "Taking Too Long" UX

The scan step replaces the current `DeviceDiscoveryView` scan experience.

| Time | UI State |
|------|----------|
| 0–8s | Progress indicator + random coffee messages. No action buttons. |
| 8s+  | "This is taking a while..." button fades in (subtle animation). |

Tapping the "taking too long" button opens a **bottom sheet** with:
- **Re-start scan** — stops current scan, starts fresh
- **Export logs** — existing log export flow
- **Continue to Dashboard** — exits onboarding without a connection

**Scan completes with devices:** Existing picker/auto-connect behavior. Exits onboarding after connection.

**Scan completes with no devices:** Shows the Scan Results Summary (Section 4).

The 8-second threshold is a named constant, easy to tune.

### 3. Troubleshooting Wizard

Presented as a **modal dialog** (works across screen sizes). Triggered from the Scan Results Summary via a "Troubleshoot" button. Not auto-opened — user opts in after seeing what happened.

**Wizard steps** (sequential, user confirms each before advancing):

1. **Is your machine powered on?**
   - "Make sure your Decent Espresso machine is turned on and has finished its startup sequence."
   - Button: "Yes, it's on" → advance

2. **Is Bluetooth enabled?** *(iOS only — `shouldShow` checks platform + adapter state)*
   - Shows adapter status. Offers "Open Settings" deep link if off.
   - Skipped on Android/desktop.

3. **Is another app connected?**
   - "Only one app can connect to your machine via Bluetooth at a time. Close any other Decent apps and try again."
   - Button: "I've closed other apps" → advance

Completing the wizard **dismisses the dialog** and returns to the Scan Results Summary. No re-scan is triggered automatically — the user chooses "Scan Again" from the summary.

### 4. Scan Telemetry — `ScanReport`

Currently, scan results and connection attempts are only logged as text. We need structured data.

**New model: `ScanReport`**

| Field | Type | Purpose |
|-------|------|---------|
| `totalBleDevicesSeen` | `int` | Raw count of all BLE advertisements received |
| `matchedDevices` | `List<MatchedDevice>` | Devices that passed `DeviceMatcher` name matching |
| `scanDuration` | `Duration` | How long the scan ran |
| `adapterStateAtStart` | `AdapterState` | BLE adapter state when scan began |
| `adapterStateAtEnd` | `AdapterState` | BLE adapter state when scan ended |
| `scanTerminationReason` | `ScanTerminationReason` | Completed, timed out, cancelled, adapter changed |
| `preferredMachineId` | `String?` | Preferred machine from settings (if set) |
| `preferredScaleId` | `String?` | Preferred scale from settings (if set) |

**`MatchedDevice`** contains:
- `device` — name, id, type
- `connectionAttempted: bool`
- `connectionResult: ConnectionResult?` — success, failed (with error string), or skipped

**Built by:** `ConnectionManager` during the scan flow. It already has access to device streams and connection results — this structures what's currently only logged.

**Consumed by:**
- Scan Results Summary — human-readable display of what happened
- Troubleshooting wizard — contextual guidance
- Device picker — preferred-device-aware messaging
- Future: attach to exported logs or feedback reports

**Example summary messages derived from `ScanReport`:**
- "No Bluetooth devices were detected at all" → hardware/adapter issue
- "5 BLE devices found, but none matched a Decent machine" → machine off or already connected
- "Your preferred machine 'DE1 ABC123' was not found during the scan"
- "A Decent machine was found but connection failed: connection timeout"

### 5. Device Picker — Preferred Device Context

When preferred device(s) are configured but not found, and other devices exist, the picker gains context-aware messaging:

- Header changes from generic "Select a machine" to: **"Your preferred machine wasn't found, but we discovered these:"** (equivalent for scales)
- Device list behavior unchanged — tap to connect, auto-connect checkbox
- If the user connects to a different device, prompt whether to update their preference

The picker uses `ScanReport` to know *why* it's showing — ambiguity (multiple devices, no preference) vs. fallback (preferred device missing).

### 6. Adapter State Monitoring

#### Transport-Aware Service Hierarchy

Not all discovery services use BLE — serial/USB services have no adapter state concept. Adding `adapterStateStream` to the base `DeviceDiscoveryService` would pollute the interface. Instead, we introduce a `BleDiscoveryService` subclass:

```
DeviceDiscoveryService          (base — transport-agnostic, unchanged)
├── BleDiscoveryService         (new — adds adapterStateStream)
│   ├── BluePlusDiscoveryService
│   ├── LinuxBleDiscoveryService
│   └── UniversalBleDiscoveryService
├── SerialServiceDesktop        (unchanged)
├── SerialServiceAndroid        (unchanged)
└── SimulatedDeviceService      (unchanged)
```

**New file:** `lib/src/services/ble/ble_discovery_service.dart`

```dart
abstract class BleDiscoveryService extends DeviceDiscoveryService {
  Stream<AdapterState> get adapterStateStream;
}
```

**`AdapterState`** — new domain enum (transport-agnostic name, reusable for future Wi-Fi): `poweredOn`, `poweredOff`, `unavailable`, `unknown`.

Each BLE discovery service wraps its library's adapter state in this domain type. Serial/simulated services are unaffected.

**`DeviceController`** and **`DeviceScanner`** remain transport-blind — no adapter state on these interfaces.

#### Scan State Guardian

**New class:** `ScanStateGuardian`

Monitors BLE adapter state and app lifecycle, ensuring the scan UI reflects reality.

**Dependencies:**
- `BleDiscoveryService` — for `adapterStateStream`. Required — every platform has a BLE discovery service.
- `ConnectionManager` — to reconcile state
- `WidgetsBindingObserver` — for app lifecycle

**Behavior:**

| Event | Action |
|-------|--------|
| App resumes from background | Check if `ConnectionManager` thinks it's scanning but scan has actually stopped. If desynchronized, update state to `idle`. |
| BLE adapter turns off | If scanning, cancel scan and surface "Bluetooth was turned off" error. |
| BLE adapter turns back on | Notify UI that re-scan is possible. Don't auto-scan. |

**Wiring in `main.dart`:** The BLE service is already created as a distinct variable before being added to the services list. Type it as `BleDiscoveryService` and pass it separately to `ScanStateGuardian`. The `services` list type stays `List<DeviceDiscoveryService>`.

**Lifecycle:** Created in `main.dart` alongside other controllers. Reusable from dashboard or anywhere else that needs BLE state awareness.

## Flow Summary

```
App launch → OnboardingController evaluates steps:

1. PermissionsStep    (shouldShow: queries actual permission status)
2. [future steps]     (shouldShow: step-specific)
3. ScanStep           (shouldShow: always true)

PopScope(canPop: false) wraps entire flow.

ScanStep lifecycle:

  Scan starts
    ├── 0-8s: Progress indicator + coffee messages
    ├── 8s: "This is taking a while..." button fades in
    │     └── Tap → bottom sheet: Re-start scan / Export logs / Continue to Dashboard
    │
    ├── Devices found → picker/auto-connect → exit onboarding
    │     └── If preferred device missing: "Your preferred machine wasn't found,
    │         but we discovered these:" + offer to update preference
    │
    └── No devices found → Scan Results Summary
          ├── Shows ScanReport (what happened, how many devices, errors)
          ├── "Scan Again"
          ├── "Troubleshoot" → wizard dialog (3 steps) → dismisses back here
          ├── "Export Logs"
          └── "Continue to Dashboard" → exit onboarding

ScanStateGuardian runs alongside:
  - Watches adapter state via BleDiscoveryService.adapterStateStream (not DeviceScanner)
  - Watches app lifecycle via WidgetsBindingObserver
  - Reconciles ConnectionManager state on resume / adapter changes
```
