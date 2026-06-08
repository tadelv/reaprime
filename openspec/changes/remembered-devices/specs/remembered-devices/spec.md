## ADDED Requirements

### Requirement: Remember connected and preferred devices

The system SHALL persist, across app restarts, a registry of devices the user has connected to or set as preferred. Each entry SHALL store the device's identity, display name, and type. A device that has only been discovered (never connected, not preferred) SHALL NOT be remembered.

#### Scenario: Connecting a device remembers it

- **WHEN** the user connects to a machine or scale
- **THEN** the system adds that device's `{id, name, type}` to the remembered registry and persists it

#### Scenario: Remembered devices survive a restart

- **WHEN** the app is relaunched
- **THEN** previously remembered devices are still in the registry

#### Scenario: A merely-discovered device is not remembered

- **WHEN** a device appears in discovery but the user never connects to it and it is not preferred
- **THEN** it is not added to the remembered registry

### Requirement: Surface remembered-but-absent devices as unavailable

The system SHALL include remembered devices that are not currently present in the device list exposed by the API, marked unavailable, rather than omitting them. A device that is currently present SHALL be marked available.

#### Scenario: Unplugged/out-of-range remembered device stays listed

- **WHEN** a remembered device is no longer present (unplugged, out of range, powered off)
- **THEN** the device list still includes it with `available: false`

#### Scenario: A present device is available

- **WHEN** a device is currently present in discovery
- **THEN** it appears in the device list with `available: true`

#### Scenario: Reappearing device flips to available

- **WHEN** a remembered, currently-unavailable device reappears in discovery
- **THEN** its entry changes to `available: true` without the user re-adding it

### Requirement: Expose availability in the device API

The system SHALL add an `available` boolean field to every device entry in the REST device list and the devices WebSocket snapshot. The field SHALL be `true` for a currently-present device and `false` for a remembered device that is not present. Existing device fields SHALL be unchanged.

#### Scenario: REST device list carries availability

- **WHEN** a client requests the device list
- **THEN** each entry includes `available` alongside the existing `id`, `name`, `type`, and `state` fields

#### Scenario: WebSocket snapshot carries availability

- **WHEN** the devices WebSocket emits a snapshot
- **THEN** each device entry includes the `available` field

### Requirement: Forget a remembered device

The system SHALL provide a way to forget a remembered device via the API and the GUI. Forgetting SHALL remove the device from the persistent registry; if the device is not currently present, it SHALL then no longer appear in the device list.

#### Scenario: Forget via API removes it from the registry

- **WHEN** a client calls the forget endpoint for a remembered device's id
- **THEN** the device is removed from the remembered registry and persisted, and a currently-absent device no longer appears in the device list

#### Scenario: Forgetting a present device

- **WHEN** the user forgets a device that is currently present
- **THEN** it is removed from the remembered registry but, being present, still appears as a normal available device (it is simply no longer remembered when it later goes away)

#### Scenario: Forget is available in the GUI

- **WHEN** the user views a remembered/unavailable device in the GUI
- **THEN** a Forget action is offered that calls the forget endpoint
