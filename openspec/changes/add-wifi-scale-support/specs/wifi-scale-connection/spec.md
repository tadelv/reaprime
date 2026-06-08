## ADDED Requirements

### Requirement: Connect over WebSocket with an HDS handshake

The system SHALL connect to the Half Decent Scale by opening a WebSocket to `ws://<address>:80/snapshot` and performing the connect handshake: request the fast stream rate, enable events, and request status. The WebSocket library type SHALL remain encapsulated behind the transport boundary (a `DataTransport` implementation), not leaked into scale or controller code.

#### Scenario: Successful connect handshake

- **WHEN** the WebSocket to `ws://<address>:80/snapshot` opens
- **THEN** the system sends `rate 10k`, then `events on`, then `status`, and begins listening for JSON frames

#### Scenario: WebSocket fails to open

- **WHEN** the WebSocket connection cannot be established
- **THEN** the system reports the scale as disconnected and does not mark it connected

### Requirement: Recognize a genuine Half Decent Scale before reporting connected

The system SHALL NOT report the scale as connected until it receives a valid Half Decent Scale frame (a weight sample or a status frame). If no valid frame arrives within a recognition timeout, the system SHALL treat the endpoint as not an HDS and fail the connection.

#### Scenario: First valid frame confirms the scale

- **WHEN** the system receives a frame containing `grams` (or a `status` frame) within the recognition timeout after connecting
- **THEN** the system marks the scale connected and begins emitting weight snapshots

#### Scenario: Recognition timeout

- **WHEN** no valid HDS frame arrives within the recognition timeout after the WebSocket opens
- **THEN** the system closes the connection and reports a recognition/validation failure rather than a connected scale

### Requirement: Parse the JSON wire protocol into scale snapshots

The system SHALL parse the scale's UTF-8 JSON WebSocket frames into the domain `Scale` snapshot model. An untyped frame containing `grams` (no `type` field) SHALL be treated as a weight sample. A `status` frame SHALL update battery level and charging state. The parser SHALL ignore unknown frame types without error.

#### Scenario: Weight frame

- **WHEN** the system receives `{"grams": 25.66, "ms": 12345}`
- **THEN** it emits a scale snapshot with weight `25.66`

#### Scenario: Status frame

- **WHEN** the system receives a `status` frame containing `battery_percent` and `charging`
- **THEN** it updates the scale's reported battery level and charging state

#### Scenario: Unknown frame type

- **WHEN** the system receives a frame whose `type` is not recognized
- **THEN** it ignores the frame without raising an error or dropping the connection

### Requirement: Support tare, timer, and display commands

The system SHALL implement the `Scale` interface operations for the WiFi scale by sending the corresponding protocol commands over the WebSocket: tare, timer start/stop/reset, and display sleep/wake.

#### Scenario: Tare

- **WHEN** a tare is requested on the WiFi scale
- **THEN** the system sends the `tare` command over the WebSocket

#### Scenario: Timer and display commands

- **WHEN** a timer (start/stop/reset) or display (on/off) operation is requested
- **THEN** the system sends the corresponding protocol command over the WebSocket

### Requirement: Detect a stalled stream and reconnect with backoff

The system SHALL monitor the continuous weight-frame stream with a watchdog. If no frame arrives within the watchdog interval, the system SHALL treat the connection as stale, mark it disconnected, and attempt to reconnect using exponential backoff (preferring the cached IP). This watchdog-and-reconnect loop is the mechanism that makes the WiFi link reliable under network churn.

#### Scenario: Stream stalls

- **WHEN** no weight frame has been received for longer than the watchdog interval
- **THEN** the system marks the scale disconnected and initiates a reconnect attempt

#### Scenario: Reconnect backoff

- **WHEN** reconnect attempts fail repeatedly
- **THEN** the system increases the delay between attempts (exponential backoff up to a capped maximum) rather than retrying in a tight loop

#### Scenario: Stream resumes after reconnect

- **WHEN** a reconnect succeeds and valid frames resume
- **THEN** the system marks the scale connected again and continues emitting snapshots without requiring user intervention
