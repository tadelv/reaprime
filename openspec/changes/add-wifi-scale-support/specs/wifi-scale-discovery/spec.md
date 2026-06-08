## ADDED Requirements

### Requirement: Discover the Half Decent Scale over the local network

The system SHALL discover a Half Decent Scale on the local network using DNS-SD (mDNS), browsing for the service type `_decentscale._tcp`, and surface each discovered scale into the unified device stream as a scale device. Discovery SHALL function on all supported platforms (Android, iOS, macOS, Windows, Linux).

#### Scenario: A WiFi scale is found during a scan

- **WHEN** a device discovery scan runs and a host advertising `_decentscale._tcp` is present on the network
- **THEN** the system resolves the service to a network address and emits a scale device representing the WiFi Half Decent Scale into the device stream

#### Scenario: No WiFi scale present

- **WHEN** a discovery scan runs and no `_decentscale._tcp` service is advertised
- **THEN** the system emits no WiFi scale device and the scan completes without error

#### Scenario: Discovery unavailable on the platform

- **WHEN** the platform's mDNS responder is unavailable (e.g. Linux without a running Avahi daemon)
- **THEN** the system completes the scan without crashing and the user can still add a scale via the manual-IP fallback

### Requirement: Add a WiFi scale manually by address

The system SHALL allow a user to add a WiFi Half Decent Scale by entering its address (IP, optionally with port), without requiring DNS-SD discovery. This manual path SHALL be available on all supported platforms and serves as the fallback when discovery is unavailable.

#### Scenario: User enters a valid IP

- **WHEN** the user enters the IP address of a reachable Half Decent Scale
- **THEN** the system attempts to connect to `ws://<address>:80/snapshot` and, on successful HDS recognition, surfaces it as a connected WiFi scale

#### Scenario: User enters an unreachable or wrong address

- **WHEN** the user enters an address that is unreachable or is not a Half Decent Scale
- **THEN** the system reports a connection/validation failure to the user and does not persist the address as a usable scale

### Requirement: WiFi scale has a distinct, stable identity

The system SHALL assign each WiFi scale a device identity scoped to its WiFi transport, distinct from the BLE and USB identities of the same physical hardware. The same physical scale MAY therefore appear as separate BLE, USB, and WiFi entries.

#### Scenario: WiFi identity is transport-scoped

- **WHEN** a WiFi Half Decent Scale is discovered or added at host `H`
- **THEN** its `deviceId` is derived from the WiFi transport and host (e.g. `wifi:<host>`) and does not collide with the BLE or USB `deviceId` of the same physical scale

#### Scenario: Same scale reachable over multiple transports

- **WHEN** the same physical Half Decent Scale is reachable over BLE and WiFi simultaneously
- **THEN** the system presents two separate scale entries and the user selects which one to connect

### Requirement: Resolve once and cache the address

The system SHALL resolve a discovered scale's hostname to an IP address, prefer the IPv4 (A) record, and cache the resolved IP for reuse on subsequent connects rather than re-resolving on every reconnect.

#### Scenario: Reconnect uses the cached IP

- **WHEN** a previously discovered WiFi scale needs to reconnect
- **THEN** the system attempts the cached IP first and only performs a fresh mDNS resolution if the cached IP fails

#### Scenario: Stale cached IP is replaced

- **WHEN** the cached IP no longer responds and a fresh resolution succeeds with a different IP
- **THEN** the system updates the cached IP to the newly resolved address

### Requirement: Persist and auto-reconnect a preferred WiFi scale

The system SHALL persist a user's chosen WiFi scale and, on app start, reconnect to it through the existing preferred-scale policy.

#### Scenario: Preferred WiFi scale reconnects on app start

- **WHEN** the app starts and the preferred scale is a WiFi scale
- **THEN** the system attempts to reconnect to that scale (via cached IP, then resolution, then the stored manual address) without the user re-adding it
