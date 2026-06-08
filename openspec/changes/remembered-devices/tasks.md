## 1. Registry model & persistence

- [ ] 1.1 Add a `RememberedDevice` value type `{id, name, type}` (with `toJson`/`fromJson`) in `lib/src/models/device/` (or `lib/src/controllers/`)
- [ ] 1.2 Extend `SettingsService` (interface + shared_preferences impl) with `rememberedDevices()` / `setRememberedDevices(List<RememberedDevice>)` persisted as a JSON-list key; add the `SettingsKeys` entry
- [ ] 1.3 Write unit tests for the JSON round-trip and the settings read/write (in-memory `MockSettingsService`)

## 2. RememberedDevicesController

- [ ] 2.1 Write unit tests (fake controllers/streams): connecting a machine remembers it; connecting a scale remembers it; merely-discovered device is NOT remembered; `forget(id)` removes + persists; registry restores from settings on init; preferred ids fold into the registry
- [ ] 2.2 Implement `RememberedDevicesController` in `lib/src/controllers/`: load registry from settings on `initialize()`; subscribe to `De1Controller.de1` (machine connect → remember) and `ScaleController.connectionState` (connected → remember via `connectedScale()`); expose `remembered` (list + change stream) and `Future<void> forget(String id)`; persist on every change

## 3. Availability in the device API

- [ ] 3.1 Write tests for the merged snapshot: present device → `available: true`; remembered-absent → `available: false`; reappearance flips to true; a non-remembered absent device does not appear
- [ ] 3.2 In `DevicesStateAggregator` / `devices_handler.dart`, inject `RememberedDevicesController` and build the device list as the union of live devices (`available: true`) and remembered-absent entries (`available: false`, `state: "disconnected"`); add the `available` field to every entry
- [ ] 3.3 Ensure both the REST `GET /api/v1/devices` and the devices WebSocket snapshot carry `available`

## 4. Forget endpoint

- [ ] 4.1 Write a handler test: `PUT /api/v1/devices/{id}/forget` removes the device from the registry; an absent device then drops from the list; a present device stays (as available) but is no longer remembered
- [ ] 4.2 Add the `PUT /api/v1/devices/<id>/forget` route in `DevicesHandler` calling `RememberedDevicesController.forget(id)`

## 5. Wiring

- [ ] 5.1 Construct `RememberedDevicesController` in `main.dart` (with `De1Controller`, `ScaleController`, `SettingsController`/`SettingsService`); call `initialize()`; pass it into `startWebServer` → `DevicesHandler` / `DevicesStateAggregator`
- [ ] 5.2 Confirm `DeviceController`, discovery services, and the `Device` interface are unchanged

## 6. API spec & docs

- [ ] 6.1 Update `assets/api/rest_v1.yml`: add `available` to the device list item schema; add the `PUT /api/v1/devices/{id}/forget` path
- [ ] 6.2 Update `assets/api/websocket_v1.yml`: add `available` to `DeviceInfo`
- [ ] 6.3 Update `doc/Api.md` (device list + forget endpoint) and `doc/DeviceManagement.md` (remembered-devices concept, availability, the macOS-USB-id limitation)

## 7. GUI (streamline.js skin — separate repo)

- [ ] 7.1 Render `available: false` device entries greyed/"unavailable" in the device list
- [ ] 7.2 Add a Forget button on remembered entries that calls `PUT /api/v1/devices/{id}/forget`
- [ ] 7.3 Tapping an unavailable entry triggers a rescan (to reconnect when it reappears) rather than a direct connect

## 8. Verification

- [ ] 8.1 `flutter analyze` clean; `flutter test` green (new unit/handler tests + existing devices_handler / device_controller / settings tests)
- [ ] 8.2 End-to-end: connect a device, take it away (BLE out-of-range / unplug) → appears `available:false`; bring it back → `available:true`; forget → removed. Verify via `curl /api/v1/devices` and the devices WebSocket
- [ ] 8.3 GUI: confirm unavailable rendering + Forget button against a running instance
