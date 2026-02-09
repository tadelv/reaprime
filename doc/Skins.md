# Skins.md

## WebUI Development Guide for Streamline-Bridge

This guide covers how to develop custom web-based user interfaces (skins) for the Streamline-Bridge gateway application. Skins connect to the Streamline-Bridge API to control espresso machines, read sensor data, and create custom user experiences.

### What is a Skin?

A **skin** is a web application that communicates with the Streamline-Bridge gateway via REST and WebSocket APIs. Skins can:
- Display real-time machine state (temperatures, pressures, flow rates)
- Control espresso shot execution and machine state
- Manage profiles and workflows
- Visualize shot data in real-time
- Customize the user experience with different UI/UX paradigms

### Example Skin

The **Streamline Project** is a reference implementation:
- Repository: https://github.com/allofmeng/streamline_project
- Demonstrates all core API interactions
- Shows best practices for WebSocket handling
- Provides real-time shot visualization

---

## Architecture Overview

### Connection Model

```
┌─────────────────┐
│   Web Browser   │
│   (Your Skin)   │
└────────┬────────┘
         │ HTTP/WS
         │ (REST & WebSocket)
         ▼
┌─────────────────┐
│ Streamline-     │
│ Bridge Gateway  │
│   :8080         │
└────────┬────────┘
         │ BLE/Serial
         ▼
┌─────────────────┐
│  DE1 Machine    │
│  Scales/Sensors │
└─────────────────┘
```

### API Structure

- **REST API**: Port 8080 - Control commands, configuration, data retrieval
- **WebSocket API**: Port 8080 - Real-time state updates, shot telemetry
- **API Documentation**: Port 4001 - Interactive API docs (when enabled)

---

## Getting Started

### 1. Basic Connection

Connect to the gateway at `http://<gateway-ip>:8080`

```javascript
const GATEWAY_URL = 'http://192.168.1.100:8080';
const WS_URL = 'ws://192.168.1.100:8080';

// Test connection
fetch(`${GATEWAY_URL}/api/v1/machine/state`)
  .then(res => res.json())
  .then(data => console.log('Machine state:', data))
  .catch(err => console.error('Connection failed:', err));
```

### 2. WebSocket Connection for Real-Time Updates

The primary way to receive real-time machine updates is via the **snapshot WebSocket**:

```javascript
const ws = new WebSocket(`${WS_URL}/ws/v1/machine/snapshot`);

ws.onopen = () => {
  console.log('Connected to machine snapshot stream');
};

ws.onmessage = (event) => {
  const snapshot = JSON.parse(event.data);
  updateUI(snapshot);
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

ws.onclose = () => {
  console.log('WebSocket closed, attempting reconnect...');
  setTimeout(connectWebSocket, 1000);
};
```

### 3. Snapshot Data Structure

The snapshot WebSocket sends complete machine state at regular intervals:

```json
{
  "timestamp": "2026-02-06T10:30:45.123Z",
  "state": {
    "state": "espresso",
    "substate": "pouring"
  },
  "flow": 2.5,
  "pressure": 9.1,
  "targetFlow": 2.5,
  "targetPressure": 9.0,
  "mixTemperature": 93.2,
  "groupTemperature": 93.0,
  "targetMixTemperature": 93.0,
  "targetGroupTemperature": 93.0,
  "profileFrame": 2,
  "steamTemperature": 135.5
}
```

---

## Core API Endpoints

### Device Management

#### Get Available Devices
```http
GET /api/v1/devices
```

Returns all discovered devices with their connection states.

**Response:**
```json
[
  {
    "name": "DE1",
    "id": "F4:12:FA:5C:3D:8E",
    "state": "connected",
    "type": "machine"
  },
  {
    "name": "Decent Scale",
    "id": "AA:BB:CC:DD:EE:FF",
    "state": "connected",
    "type": "scale"
  }
]
```

#### Scan for Devices
```http
GET /api/v1/devices/scan?connect=false&quick=false
```

Triggers a device scan. Use `connect=true` to auto-connect to discovered scales. Use `quick=true` to return immediately without waiting for scan results.

#### Connect to Device
```http
PUT /api/v1/devices/connect?deviceId=F4:12:FA:5C:3D:8E
```

Connects to a specific device by ID.

---

### Machine Control

#### Get Machine Info
```http
GET /api/v1/machine/info
```

Returns machine hardware information.

**Response:**
```json
{
  "version": "1.5.0",
  "model": "DE1+",
  "serialNumber": "DE1XL-12345",
  "GHC": true,
  "extra": {}
}
```

#### Get Machine State
```http
GET /api/v1/machine/state
```

Returns current machine state snapshot.

**Response:**
```json
{
  "timestamp": "2026-02-06T10:30:45.123Z",
  "state": {
    "state": "idle",
    "substate": "idle"
  },
  "flow": 0.0,
  "pressure": 0.0,
  "targetFlow": 0.0,
  "targetPressure": 0.0,
  "mixTemperature": 92.5,
  "groupTemperature": 92.3,
  "targetMixTemperature": 93.0,
  "targetGroupTemperature": 93.0,
  "profileFrame": 0,
  "steamTemperature": 135.0
}
```

**Machine States:**
- `idle` - Machine ready
- `booting` - Starting up
- `sleeping` - Power saving mode
- `heating` - Warming up
- `preheating` - Preparing for shot
- `espresso` - Brewing espresso
- `hotWater` - Dispensing hot water
- `flush` - Flushing group
- `steam` - Steaming mode
- `steamRinse` - Cleaning steam wand
- `cleaning` - Cleaning cycle
- `descaling` - Descaling cycle
- `needsWater` - Water tank empty
- `error` - Error state

**Machine Substates:**
- `idle` - Idle
- `preparingForShot` - Pre-shot preparation
- `preinfusion` - Pre-infusion phase
- `pouring` - Extracting espresso
- `pouringDone` - Shot complete
- `cleaningStart` - Starting cleaning
- `cleaingGroup` - Cleaning group head
- `cleanSoaking` - Soaking during clean
- `cleaningSteam` - Steam cleaning

#### Request State Change
```http
PUT /api/v1/machine/state/{newState}
```

Request a machine state change. Valid states: `idle`, `sleeping`, `espresso`, `steam`, `hotWater`, `flush`.

**Example:**
```javascript
// Put machine into espresso mode
await fetch(`${GATEWAY_URL}/api/v1/machine/state/espresso`, {
  method: 'PUT'
});
```

#### Upload Profile to Machine
```http
POST /api/v1/machine/profile
Content-Type: application/json

{
  "version": "2",
  "title": "My Profile",
  "author": "MySkin",
  "notes": "Custom profile",
  "beverage_type": "espresso",
  "steps": [...],
  "target_volume": 0,
  "target_weight": 36,
  "tank_temperature": 0
}
```

Uploads a complete profile to the machine.

#### Update Shot Settings
```http
POST /api/v1/machine/shotSettings
Content-Type: application/json

{
  "steamSetting": 2,
  "targetSteamTemp": 140,
  "targetSteamDuration": 60,
  "targetHotWaterTemp": 95,
  "targetHotWaterVolume": 200,
  "targetHotWaterDuration": 30,
  "targetShotVolume": 36,
  "groupTemp": 93.0
}
```

#### Get Machine Settings
```http
GET /api/v1/machine/settings
```

**Response:**
```json
{
  "usb": false,
  "fan": 50,
  "flushTemp": 88,
  "flushFlow": 4.0,
  "flushTimeout": 5,
  "hotWaterFlow": 4.0,
  "steamFlow": 1.5,
  "tankTemp": 85
}
```

#### Update Machine Settings
```http
POST /api/v1/machine/settings
Content-Type: application/json

{
  "usb": true,
  "fan": 60,
  "tankTemp": 88
}
```

You can update individual settings - only include the fields you want to change.

#### Toggle USB Charger
```http
PUT /api/v1/machine/usb/enable
PUT /api/v1/machine/usb/disable
```

Enables or disables USB charging port on the machine.

#### Update Water Level Threshold
```http
POST /api/v1/machine/waterLevels
Content-Type: application/json

{
  "warningThresholdPercentage": 20
}
```

---

### Scale Integration

#### Tare Scale
```http
PUT /api/v1/scale/tare
```

Zeros the connected scale.

**Response:** 200 OK if successful, 404 if scale not connected.

---

### Workflow Management

Workflows combine profiles, dose settings, coffee data, grinder settings, and all machine operation parameters (steam, hot water, rinse) into a complete brewing recipe. **This is the recommended API** for managing all brewing parameters in one cohesive operation.

#### Why Use Workflow API?

Instead of uploading profiles and updating settings separately:
- **Atomic updates**: All settings applied together as a complete recipe
- **Simpler code**: One API call instead of multiple endpoint calls
- **Consistency**: Settings are guaranteed to be uploaded to the machine as a complete set
- **Better organization**: Natural grouping of all brewing parameters

#### Get Current Workflow
```http
GET /api/v1/workflow
```

Retrieves the complete current workflow including profile, dose settings, grinder data, coffee information, and all machine settings (steam, hot water, rinse).

**Response:**
```json
{
  "id": "workflow-uuid",
  "name": "Morning Espresso",
  "description": "My daily shot",
  "profile": {
    "version": "2",
    "title": "Classic Profile",
    "author": "Me",
    "notes": "Balanced extraction",
    "beverage_type": "espresso",
    "steps": [...],
    "target_volume": 0,
    "target_weight": 36,
    "tank_temperature": 0
  },
  "doseData": {
    "doseIn": 18.0,
    "doseOut": 36.0
  },
  "grinderData": {
    "setting": "2.5",
    "manufacturer": "Niche",
    "model": "Zero"
  },
  "coffeeData": {
    "name": "Ethiopia Yirgacheffe",
    "roaster": "Local Roaster"
  },
  "steamSettings": {
    "targetTemperature": 150,
    "duration": 50,
    "flow": 0.8
  },
  "hotWaterData": {
    "targetTemperature": 75,
    "duration": 30,
    "volume": 50,
    "flow": 10.0
  },
  "rinseData": {
    "targetTemperature": 90,
    "duration": 10,
    "flow": 6.0
  }
}
```

#### Update Workflow
```http
PUT /api/v1/workflow
Content-Type: application/json
```

You can update the complete workflow or just specific fields. Any fields provided will be updated and automatically uploaded to the machine.

**Complete Workflow Update:**
```json
{
  "name": "Evening Decaf",
  "description": "Gentle evening shot",
  "profile": {
    "version": "2",
    "title": "Gentle Profile",
    "steps": [...]
  },
  "doseData": {
    "doseIn": 18.5,
    "doseOut": 37.0
  },
  "grinderData": {
    "setting": "2.8",
    "manufacturer": "Niche",
    "model": "Zero"
  },
  "coffeeData": {
    "name": "Colombia Decaf",
    "roaster": "Local Roaster"
  },
  "steamSettings": {
    "targetTemperature": 155,
    "duration": 60,
    "flow": 0.9
  },
  "hotWaterData": {
    "targetTemperature": 80,
    "duration": 35,
    "volume": 60,
    "flow": 12.0
  },
  "rinseData": {
    "targetTemperature": 92,
    "duration": 12,
    "flow": 6.5
  }
}
```

**Partial Update Examples:**

Update just dose and grinder settings:
```json
{
  "doseData": {
    "doseIn": 18.5,
    "doseOut": 37.0
  },
  "grinderData": {
    "setting": "2.8"
  }
}
```

Update just steam settings:
```json
{
  "steamSettings": {
    "targetTemperature": 155,
    "duration": 60,
    "flow": 0.9
  }
}
```

Update just the profile:
```json
{
  "profile": {
    "version": "2",
    "title": "New Profile",
    "steps": [...]
  }
}
```

**Response:** Returns the complete updated workflow object.

#### Workflow Data Structure Reference

**DoseData:**
- `doseIn` (number): Input dose (dry coffee weight in grams)
- `doseOut` (number): Target output dose (beverage weight in grams)

**GrinderData:**
- `setting` (string): Grinder setting (e.g., "2.5", "15")
- `manufacturer` (string, optional): Grinder manufacturer name
- `model` (string, optional): Grinder model name

**CoffeeData:**
- `name` (string): Coffee name or variety
- `roaster` (string, optional): Roaster name

**SteamSettings:**
- `targetTemperature` (integer): Target steam temperature in Celsius
- `duration` (integer): Steam duration in seconds
- `flow` (number): Steam flow rate

**HotWaterData:**
- `targetTemperature` (integer): Target hot water temperature in Celsius
- `duration` (integer): Hot water dispensing duration in seconds
- `volume` (integer): Target hot water volume in milliliters
- `flow` (number): Hot water flow rate

**RinseData:**
- `targetTemperature` (integer): Target rinse water temperature in Celsius
- `duration` (integer): Rinse duration in seconds
- `flow` (number): Rinse flow rate

---

### Shot History

#### Get All Shot IDs
```http
GET /api/v1/shots/ids
```

Returns array of all shot identifiers.

**Response:**
```json
[
  "shot-2026-02-06-103045",
  "shot-2026-02-06-094521",
  "shot-2026-02-05-173042"
]
```

#### Get Shots
```http
GET /api/v1/shots?ids=shot-abc123,shot-def456
```

Returns shot records for the specified IDs. Omit `ids` parameter to get all shots.

**Response:**
```json
[
  {
    "id": "shot-2026-02-06-103045",
    "timestamp": "2026-02-06T10:30:45Z",
    "measurements": [
      {
        "machine": {
          "timestamp": "2026-02-06T10:30:45.100Z",
          "state": { "state": "espresso", "substate": "pouring" },
          "flow": 2.5,
          "pressure": 9.1,
          "mixTemperature": 93.2
        },
        "scale": {
          "timestamp": "2026-02-06T10:30:45.100Z",
          "weight": 18.5,
          "weightFlow": 2.1,
          "batteryLevel": 85
        },
        "volume": 15.3
      }
    ],
    "workflow": {
      "name": "Morning Shot",
      "doseData": { "doseIn": 18.0, "doseOut": 36.0 }
    }
  }
]
```

#### Get Latest Shot
```http
GET /api/v1/shots/latest
```

Returns the most recent shot record.

#### Get Specific Shot
```http
GET /api/v1/shots/{id}
```

Returns a single shot record by ID.

**Response:** Same as shot object in array above, plus optional `shotNotes` and `metadata` fields.

#### Update Shot
```http
PUT /api/v1/shots/{id}
Content-Type: application/json

{
  "id": "shot-2026-02-06-103045",
  "timestamp": "2026-02-06T10:30:45Z",
  "measurements": [...],
  "workflow": {...},
  "shotNotes": "Excellent extraction! Bright acidity with chocolate notes.",
  "metadata": {
    "rating": 4.5,
    "tags": ["morning", "sweet"],
    "favorite": true,
    "barista": "Alice"
  }
}
```

Updates an existing shot record. Commonly used to add tasting notes or metadata after the fact.

**Metadata Field**: The `metadata` object is a flexible dictionary that can store any custom data:
- `rating`: Numerical rating (e.g., 1-5)
- `tags`: Array of strings for categorization
- `favorite`: Boolean flag
- `barista`: Name of person who pulled the shot
- Any custom fields your application needs

**Response:** Returns the updated shot record.

#### Delete Shot
```http
DELETE /api/v1/shots/{id}
```

Permanently deletes a shot record.

**Response:**
```json
{
  "success": true,
  "id": "shot-2026-02-06-103045"
}
```

---

### Profiles API

Streamline-Bridge uses content-based hashing for profile IDs. Profile IDs are calculated from execution-relevant fields, meaning identical profiles have the same ID across all devices.

#### List All Profiles
```http
GET /api/v1/profiles?visibility=visible&includeHidden=false
```

**Query parameters:**
- `visibility`: Filter by `visible`, `hidden`, or `deleted`
- `includeHidden`: Include hidden profiles (default: false)
- `parentId`: Filter profiles by parent ID (version tracking)

**Response:**
```json
[
  {
    "id": "profile:a1b2c3d4e5f6g7h8",
    "profile": {
      "version": "2",
      "title": "Classic Blooming",
      "author": "Decent",
      "notes": "Gentle pre-infusion profile",
      "beverage_type": "espresso",
      "steps": [...],
      "target_volume": 0,
      "target_weight": 36,
      "tank_temperature": 0
    },
    "metadataHash": "3f4e5d6c7b8a9...",
    "compoundHash": "9a8b7c6d5e4f3...",
    "parentId": null,
    "visibility": "visible",
    "isDefault": true,
    "createdAt": "2026-01-15T12:00:00Z",
    "updatedAt": "2026-01-15T12:00:00Z",
    "metadata": {}
  }
]
```

#### Get Profile by ID
```http
GET /api/v1/profiles/{id}
```

Returns a single profile record.

#### Create New Profile
```http
POST /api/v1/profiles
Content-Type: application/json

{
  "profile": {
    "version": "2",
    "title": "My Custom Profile",
    "author": "Me",
    "notes": "Testing new recipe",
    "beverage_type": "espresso",
    "steps": [...],
    "target_volume": 0,
    "target_weight": 36,
    "tank_temperature": 0
  },
  "parentId": null,
  "metadata": {
    "tags": ["experimental"]
  }
}
```

**Response:** 201 Created with full profile record including auto-generated ID.

#### Update Profile
```http
PUT /api/v1/profiles/{id}
Content-Type: application/json

{
  "profile": {
    "version": "2",
    "title": "Updated Title",
    ...
  },
  "metadata": {
    "tags": ["updated"]
  }
}
```

**Note:** Cannot modify default profiles' content, only metadata.

#### Delete Profile (Soft Delete)
```http
DELETE /api/v1/profiles/{id}
```

Soft deletes user profiles or hides default profiles.

#### Change Profile Visibility
```http
PUT /api/v1/profiles/{id}/visibility
Content-Type: application/json

{
  "visibility": "hidden"
}
```

Valid values: `visible`, `hidden`, `deleted`

#### Get Profile Lineage
```http
GET /api/v1/profiles/{id}/lineage
```

Returns the full version history tree (parents and children) for a profile.

#### Permanently Delete Profile
```http
DELETE /api/v1/profiles/{id}/purge
```

**Warning:** Permanently removes profile. Cannot purge default profiles. Use with caution.

#### Export All Profiles
```http
GET /api/v1/profiles/export?includeHidden=false&includeDeleted=false
```

Exports all profiles as JSON array for backup purposes.

#### Import Profiles
```http
POST /api/v1/profiles/import
Content-Type: application/json

[
  { "id": "profile:...", "profile": {...}, ... },
  { "id": "profile:...", "profile": {...}, ... }
]
```

Batch import profiles from backup.

**Response:**
```json
{
  "imported": 5,
  "skipped": 2,
  "failed": 0,
  "errors": []
}
```

#### Restore Default Profile
```http
POST /api/v1/profiles/restore/{filename}
```

Restores a bundled default profile from assets by filename.

---

### Sensors API

Streamline-Bridge supports extensible sensor devices that can provide custom data streams.

#### List Connected Sensors
```http
GET /api/v1/sensors
```

**Response:**
```json
[
  {
    "name": "Basket Sensor",
    "info": {
      "id": "sensor:basket:001",
      "name": "Acme Basket Sensor",
      "vendor": "Acme",
      "dataChannels": [
        {
          "key": "temperature",
          "type": "number",
          "unit": "°C"
        }
      ],
      "commands": []
    }
  }
]
```

#### Get Sensor Manifest
```http
GET /api/v1/sensors/{id}
```

Returns full manifest for a specific sensor, including available commands.

#### Execute Sensor Command
```http
POST /api/v1/sensors/{id}/execute
Content-Type: application/json

{
  "commandId": "calibrate",
  "params": {
    "mode": "quick"
  }
}
```

**Response:**
```json
{
  "timestamp": "2026-02-06T10:30:45Z",
  "result": {
    "success": true,
    "message": "Calibration complete"
  }
}
```

---

### REA Settings

Configure Streamline-Bridge gateway behavior.

#### Get REA Settings
```http
GET /api/v1/settings
```

**Response:**
```json
{
  "gatewayMode": "full",
  "webUiPath": "/path/to/webui",
  "logLevel": "INFO",
  "weightFlowMultiplier": 1.0,
  "volumeFlowMultiplier": 0.3,
  "scalePowerMode": "disabled",
  "preferredMachineId": "F4:12:FA:5C:3D:8E"
}
```

**Settings Fields:**
- `gatewayMode`: Gateway operation mode (`disabled`, `full`, `tracking`)
- `webUiPath`: Path to custom WebUI folder on filesystem
- `logLevel`: Log verbosity level
- `weightFlowMultiplier`: Multiplier for projected weight calculation (default: 1.0)
- `volumeFlowMultiplier`: Multiplier for projected volume calculation (default: 0.3)
- `scalePowerMode`: Automatic scale power management (`disabled`, `displayOff`, `disconnect`)
- `preferredMachineId`: Device ID for auto-connect on startup

**Gateway Modes:**
- `disabled`: No gateway features
- `full`: Full gateway mode with UI
- `tracking`: Control shots (stop at weight) but no UI graphs

**Scale Power Modes:**
- `disabled`: No automatic power management
- `displayOff`: Turn off scale display when machine sleeps
- `disconnect`: Disconnect scale when machine sleeps

#### Update Streamline-Bridge Settings
```http
POST /api/v1/settings
Content-Type: application/json

{
  "gatewayMode": "full",
  "logLevel": "WARNING",
  "preferredMachineId": "F4:12:FA:5C:3D:8E"
}
```

Only include fields you want to update. Changes take effect immediately.

---

### Key-Value Store

Streamline-Bridge provides a simple key-value store for client applications to persist data.

#### List Keys in Namespace
```http
GET /api/v1/store/{namespace}
```

**Response:**
```json
["config", "preferences", "lastShot"]
```

#### Get Value
```http
GET /api/v1/store/{namespace}/{key}
```

Returns the JSON value stored under the key. Returns 404 if key doesn't exist.

#### Set Value
```http
POST /api/v1/store/{namespace}/{key}
Content-Type: application/json

{
  "setting1": "value1",
  "setting2": 42
}
```

Stores any JSON value under the key.

#### Delete Key
```http
DELETE /api/v1/store/{namespace}/{key}
```

**Response:**
```json
{
  "deleted": true
}
```

---

### Plugins API

Query loaded plugins and their settings.

#### List Loaded Plugins
```http
GET /api/v1/plugins
```

**Response:**
```json
[
  {
    "id": "example-plugin",
    "name": "Example Plugin",
    "author": "Decent",
    "description": "Example plugin for testing",
    "version": "1.0.0",
    "apiVersion": "1.0",
    "permissions": ["log", "emit"],
    "settings": {
      "enabled": { "type": "boolean", "default": true }
    },
    "api": [
      {
        "id": "customEvent",
        "type": "websocket"
      }
    ]
  }
]
```

#### Get Plugin Settings
```http
GET /api/v1/plugins/{id}/settings
```

Returns current settings for the plugin.

#### Update Plugin Settings
```http
POST /api/v1/plugins/{id}/settings
Content-Type: application/json

{
  "enabled": true,
  "customSetting": "value"
}
```

---

## WebSocket Endpoints

All WebSocket endpoints are at `ws://<gateway-ip>:8080/ws/v1/...`

### 1. Machine Snapshot Stream

**Endpoint:** `ws/v1/machine/snapshot`

**Update Frequency:** ~10 Hz (100ms intervals)

**Purpose:** Primary real-time data feed for UI updates

**Message Format:**
```json
{
  "timestamp": "2026-02-06T10:30:45.123Z",
  "state": {
    "state": "espresso",
    "substate": "pouring"
  },
  "flow": 2.5,
  "pressure": 9.1,
  "targetFlow": 2.5,
  "targetPressure": 9.0,
  "mixTemperature": 93.2,
  "groupTemperature": 93.0,
  "targetMixTemperature": 93.0,
  "targetGroupTemperature": 93.0,
  "profileFrame": 2,
  "steamTemperature": 135.5
}
```

**Example:**
```javascript
const ws = new WebSocket('ws://192.168.1.100:8080/ws/v1/machine/snapshot');

ws.onmessage = (event) => {
  const snapshot = JSON.parse(event.data);
  
  // Update temperature displays
  document.getElementById('steam-temp').textContent = 
    snapshot.steamTemperature.toFixed(1);
  
  // Update pressure gauge
  updatePressureGauge(snapshot.pressure);
  
  // Update shot timer if brewing
  if (snapshot.state.state === 'espresso' && snapshot.state.substate === 'pouring') {
    updateShotTimer();
  }
};
```

### 2. Scale Snapshot Stream

**Endpoint:** `ws/v1/scale/snapshot`

**Update Frequency:** Variable (based on scale model, typically 5-10 Hz)

**Message Format:**
```json
{
  "timestamp": "2026-02-06T10:30:45.123Z",
  "weight": 18.5,
  "batteryLevel": 85
}
```

### 3. Shot Settings Stream

**Endpoint:** `ws/v1/machine/shotSettings`

**Purpose:** Real-time updates when shot settings change

**Message Format:**
```json
{
  "steamSetting": 2,
  "targetSteamTemp": 140,
  "targetSteamDuration": 60,
  "targetHotWaterTemp": 95,
  "targetHotWaterVolume": 200,
  "targetHotWaterDuration": 30,
  "targetShotVolume": 36,
  "groupTemp": 93.0
}
```

### 4. Water Levels Stream

**Endpoint:** `ws/v1/machine/waterLevels`

**Purpose:** Real-time water level updates

**Message Format:**
```json
{
  "currentLevel": 45,
  "refillLevel": 10
}
```

### 5. Machine Raw BLE Data

**Endpoint:** `ws/v1/machine/raw`

**Purpose:** Raw BLE messages for debugging and advanced integrations

**Message Format:**
```json
{
  "type": "response",
  "operation": "notify",
  "characteristicUUID": "a00e",
  "payload": "0102030405060708"
}
```

**Types:** `request`, `response`  
**Operations:** `read`, `write`, `notify`

### 6. Sensor Snapshot Stream

**Endpoint:** `ws/v1/sensors/{id}/snapshot`

**Purpose:** Real-time sensor data for specific sensor

**Message Format:**
```json
{
  "timestamp": "2026-02-06T10:30:45.123Z",
  "id": "sensor:basket:001",
  "values": {
    "temperature": 92.5,
    "pressure": 9.1
  }
}
```

### 7. Plugin Event Streams

**Endpoint:** `ws/v1/plugins/{pluginId}/{endpoint}`

**Purpose:** Custom events emitted by plugins

**Message Format:** Defined by plugin (any JSON)

**Example:**
```javascript
const pluginWs = new WebSocket('ws://192.168.1.100:8080/ws/v1/plugins/custom-logger/shotComplete');

pluginWs.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Plugin event:', data);
};
```

### 8. Logs Stream

**Endpoint:** `ws/v1/logs`

**Purpose:** Subscribe to REA log messages

**Message Format:**
```json
{
  "timestamp": "2026-02-06T10:30:45.123Z",
  "level": "INFO",
  "message": "Machine state changed to espresso"
}
```

---

## Best Practices

### 1. Connection Management

Always implement reconnection logic for WebSockets:

```javascript
class GatewayConnection {
  constructor(url) {
    this.url = url;
    this.ws = null;
    this.reconnectDelay = 1000;
    this.maxReconnectDelay = 30000;
  }
  
  connect() {
    this.ws = new WebSocket(this.url);
    
    this.ws.onopen = () => {
      console.log('Connected');
      this.reconnectDelay = 1000; // Reset delay on successful connection
    };
    
    this.ws.onclose = () => {
      console.log(`Reconnecting in ${this.reconnectDelay}ms`);
      setTimeout(() => this.connect(), this.reconnectDelay);
      this.reconnectDelay = Math.min(this.reconnectDelay * 2, this.maxReconnectDelay);
    };
    
    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error);
      this.ws.close();
    };
    
    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      this.handleMessage(data);
    };
  }
  
  handleMessage(data) {
    // Override in subclass
  }
}
```

### 2. Data Buffering for Charts

For smooth chart updates, buffer incoming data points:

```javascript
class ShotChart {
  constructor(maxPoints = 500) {
    this.data = {
      time: [],
      pressure: [],
      flow: [],
      temperature: []
    };
    this.maxPoints = maxPoints;
    this.startTime = null;
  }
  
  addPoint(snapshot) {
    if (!this.startTime) {
      this.startTime = new Date(snapshot.timestamp);
    }
    
    const elapsed = (new Date(snapshot.timestamp) - this.startTime) / 1000;
    
    // Add new data point
    this.data.time.push(elapsed);
    this.data.pressure.push(snapshot.pressure);
    this.data.flow.push(snapshot.flow);
    this.data.temperature.push(snapshot.mixTemperature);
    
    // Trim if exceeds max points
    if (this.data.time.length > this.maxPoints) {
      Object.keys(this.data).forEach(key => {
        this.data[key].shift();
      });
    }
    
    this.render();
  }
  
  reset() {
    this.startTime = null;
    Object.keys(this.data).forEach(key => {
      this.data[key] = [];
    });
  }
}
```

### 3. Error Handling

Always handle API errors gracefully:

```javascript
async function sendCommand(endpoint, method = 'GET', body = null) {
  try {
    const options = {
      method,
      headers: body ? { 'Content-Type': 'application/json' } : {},
    };
    
    if (body) {
      options.body = JSON.stringify(body);
    }
    
    const response = await fetch(`${GATEWAY_URL}${endpoint}`, options);
    
    if (!response.ok) {
      let errorMsg;
      try {
        const error = await response.json();
        errorMsg = error.message || error.e || `HTTP ${response.status}`;
      } catch {
        errorMsg = `HTTP ${response.status}`;
      }
      throw new Error(errorMsg);
    }
    
    // Some endpoints return 204 No Content
    if (response.status === 204) {
      return null;
    }
    
    return await response.json();
  } catch (error) {
    console.error(`Command failed: ${endpoint}`, error);
    showErrorToast(error.message);
    throw error;
  }
}
```

### 4. State Management

Maintain local state synchronized with machine state:

```javascript
class MachineState {
  constructor() {
    this.state = 'idle';
    this.substate = 'idle';
    this.pressure = 0;
    this.flow = 0;
    this.mixTemperature = 0;
    this.steamTemperature = 0;
    this.listeners = [];
  }
  
  update(snapshot) {
    const stateChanged = this.state !== snapshot.state.state;
    
    this.state = snapshot.state.state;
    this.substate = snapshot.state.substate;
    this.pressure = snapshot.pressure;
    this.flow = snapshot.flow;
    this.mixTemperature = snapshot.mixTemperature;
    this.steamTemperature = snapshot.steamTemperature;
    
    if (stateChanged) {
      this.notifyListeners('stateChange', this.state);
    }
    
    this.notifyListeners('update', snapshot);
  }
  
  on(event, callback) {
    this.listeners.push({ event, callback });
  }
  
  notifyListeners(event, data) {
    this.listeners
      .filter(l => l.event === event)
      .forEach(l => l.callback(data));
  }
}

// Usage
const machine = new MachineState();

machine.on('stateChange', (newState) => {
  console.log('Machine state changed to:', newState);
  if (newState === 'espresso') {
    startShotTimer();
  }
});

// In WebSocket handler
ws.onmessage = (event) => {
  const snapshot = JSON.parse(event.data);
  machine.update(snapshot);
};
```

### 5. Handling Machine State Transitions

Different machine states allow different operations:

```javascript
const ALLOWED_OPERATIONS = {
  idle: ['setState', 'uploadProfile', 'updateSettings'],
  sleeping: ['setState'],
  heating: ['setState'],
  preheating: ['setState'],
  espresso: ['stopShot'],
  steam: ['setState'],
  hotWater: ['setState']
};

function canExecute(operation, currentState) {
  return ALLOWED_OPERATIONS[currentState]?.includes(operation) ?? false;
}

async function startShot() {
  if (!canExecute('startShot', machine.state)) {
    showError(`Cannot start shot in ${machine.state} state`);
    return;
  }
  
  // First ensure machine is in espresso state
  await sendCommand('/api/v1/machine/state/espresso', 'PUT');
  
  // Wait for state transition (listen to WebSocket)
  await waitForState('espresso');
  
  // Now you could start the shot if you had a start shot endpoint
  // The actual shot start is triggered by the machine when ready
}
```

---

## Advanced Features

### 1. Custom Profile Creation

Create and upload custom profiles programmatically:

```javascript
async function createAndUploadProfile() {
  const customProfile = {
    version: "2",
    title: "My Custom Profile",
    author: "MySkin",
    notes: "Pressure ramping experiment",
    beverage_type: "espresso",
    steps: [
      {
        name: "preinfusion",
        temperature: 93.0,
        sensor: "water",
        pump: "pressure",
        transition: "fast",
        pressure: 4.0,
        flow: 2.0,
        seconds: 8.0,
        exit_type: 0, // exit on time
        exit_condition: 8.0,
        exit_flow_over: 0,
        exit_flow_under: 0,
        exit_pressure_over: 0,
        exit_pressure_under: 0,
        limiter_value: 0,
        limiter_range: 0
      },
      {
        name: "ramp_up",
        temperature: 93.0,
        sensor: "water",
        pump: "pressure",
        transition: "smooth",
        pressure: 9.0,
        flow: 2.5,
        seconds: 5.0,
        exit_type: 0,
        exit_condition: 5.0,
        exit_flow_over: 0,
        exit_flow_under: 0,
        exit_pressure_over: 0,
        exit_pressure_under: 0,
        limiter_value: 0,
        limiter_range: 0
      },
      {
        name: "hold",
        temperature: 93.0,
        sensor: "water",
        pump: "pressure",
        transition: "fast",
        pressure: 9.0,
        flow: 2.5,
        seconds: 20.0,
        exit_type: 0,
        exit_condition: 20.0,
        exit_flow_over: 0,
        exit_flow_under: 0,
        exit_pressure_over: 0,
        exit_pressure_under: 0,
        limiter_value: 0,
        limiter_range: 0
      }
    ],
    target_volume: 0,
    target_weight: 36,
    target_volume_count_start: 0,
    tank_temperature: 0
  };

  // Create profile in REA
  const created = await sendCommand('/api/v1/profiles', 'POST', {
    profile: customProfile,
    parentId: null,
    metadata: {
      tags: ["custom", "experimental"]
    }
  });

  console.log('Created profile:', created.id);

  // Upload to machine
  await sendCommand('/api/v1/machine/profile', 'POST', created.profile);
  
  console.log('Profile uploaded to machine');
  
  return created;
}
```

### 2. Workflow-Based Brewing

Use workflows to manage complete brewing recipes including all machine settings:

```javascript
async function setupCompleteWorkflow() {
  const workflow = {
    name: "Morning Shot",
    description: "My daily espresso routine",
    profile: await getProfileById('profile:a1b2c3d4e5f6'),
    doseData: {
      doseIn: 18.0,
      doseOut: 36.0
    },
    grinderData: {
      setting: "2.5",
      manufacturer: "Niche",
      model: "Zero"
    },
    coffeeData: {
      name: "Ethiopia Yirgacheffe",
      roaster: "Local Roaster"
    },
    steamSettings: {
      targetTemperature: 150,
      duration: 50,
      flow: 0.8
    },
    hotWaterData: {
      targetTemperature: 75,
      duration: 30,
      volume: 50,
      flow: 10.0
    },
    rinseData: {
      targetTemperature: 90,
      duration: 10,
      flow: 6.0
    }
  };
  
  await sendCommand('/api/v1/workflow', 'PUT', workflow);
  console.log('Complete workflow updated and uploaded to machine');
}

async function updateJustSteamSettings() {
  // You can also update just specific parts
  const partialWorkflow = {
    steamSettings: {
      targetTemperature: 155,
      duration: 60,
      flow: 0.9
    }
  };
  
  await sendCommand('/api/v1/workflow', 'PUT', partialWorkflow);
  console.log('Steam settings updated');
}

async function getProfileById(id) {
  const profile = await sendCommand(`/api/v1/profiles/${id}`);
  return profile.profile;
}
```

### 3. Real-Time Shot Recording

Combine machine and scale data for shot recording:

```javascript
class ShotRecorder {
  constructor() {
    this.recording = false;
    this.measurements = [];
    this.startTime = null;
    this.machineWs = null;
    this.scaleWs = null;
    this.latestMachine = null;
    this.latestScale = null;
  }
  
  start() {
    this.recording = true;
    this.measurements = [];
    this.startTime = Date.now();
    
    // Connect to both streams
    this.machineWs = new WebSocket('ws://192.168.1.100:8080/ws/v1/machine/snapshot');
    this.scaleWs = new WebSocket('ws://192.168.1.100:8080/ws/v1/scale/snapshot');
    
    this.machineWs.onmessage = (event) => {
      this.latestMachine = JSON.parse(event.data);
      this.recordMeasurement();
    };
    
    this.scaleWs.onmessage = (event) => {
      this.latestScale = JSON.parse(event.data);
    };
  }
  
  recordMeasurement() {
    if (!this.recording) return;
    
    this.measurements.push({
      machine: { ...this.latestMachine },
      scale: this.latestScale ? { ...this.latestScale } : null,
      volume: null // Volume calculation would need to be added
    });
  }
  
  async stop() {
    this.recording = false;
    this.machineWs?.close();
    this.scaleWs?.close();
    
    const workflow = await sendCommand('/api/v1/workflow');
    
    const shotRecord = {
      id: `shot-${Date.now()}`,
      timestamp: new Date(this.startTime).toISOString(),
      measurements: this.measurements,
      workflow: workflow
    };
    
    // Save to your own storage or send to custom backend
    console.log('Shot recorded:', shotRecord);
    
    return shotRecord;
  }
}

// Usage
const recorder = new ShotRecorder();

machine.on('stateChange', (newState) => {
  if (newState === 'espresso') {
    recorder.start();
  } else if (recorder.recording) {
    recorder.stop();
  }
});
```

### 4. Plugin Integration

Listen to plugin events for extended functionality:

```javascript
// Connect to plugin event stream
const pluginWs = new WebSocket('ws://192.168.1.100:8080/ws/v1/plugins/shot-logger/shotComplete');

pluginWs.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Shot completed:', data);
  
  // Update UI with plugin data
  showNotification(`Shot logged: ${data.weight}g in ${data.time}s`);
};
```

---

## Example: Minimal Working Skin

Here's a complete minimal skin implementation:

```html
<!DOCTYPE html>
<html>
<head>
  <title>Minimal Streamline-Bridge Skin</title>
  <style>
    body {
      font-family: 'Segoe UI', system-ui, sans-serif;
      padding: 20px;
      max-width: 800px;
      margin: 0 auto;
      background: #1a1a1a;
      color: #fff;
    }
    
    h1 { margin-bottom: 30px; }
    
    .status {
      background: #2a2a2a;
      padding: 20px;
      border-radius: 8px;
      margin-bottom: 20px;
    }
    
    .status-item {
      display: flex;
      justify-content: space-between;
      margin: 10px 0;
      padding: 5px 0;
      border-bottom: 1px solid #3a3a3a;
    }
    
    .status-label {
      color: #888;
    }
    
    .status-value {
      font-weight: bold;
      color: #4CAF50;
    }
    
    .controls {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
    }
    
    button {
      padding: 12px 24px;
      font-size: 14px;
      border: none;
      border-radius: 6px;
      background: #4CAF50;
      color: white;
      cursor: pointer;
      transition: background 0.3s;
    }
    
    button:hover {
      background: #45a049;
    }
    
    button:disabled {
      background: #555;
      cursor: not-allowed;
    }
    
    .error {
      background: #d32f2f;
      color: white;
      padding: 10px;
      border-radius: 4px;
      margin-top: 10px;
      display: none;
    }
    
    .connection-status {
      display: inline-block;
      width: 10px;
      height: 10px;
      border-radius: 50%;
      margin-right: 8px;
    }
    
    .connection-status.connected {
      background: #4CAF50;
    }
    
    .connection-status.disconnected {
      background: #d32f2f;
    }
  </style>
</head>
<body>
  <h1>
    <span class="connection-status disconnected" id="connection-indicator"></span>
    Streamline-Bridge Control
  </h1>
  
  <div class="status">
    <div class="status-item">
      <span class="status-label">Machine State:</span>
      <span class="status-value" id="state">-</span>
    </div>
    <div class="status-item">
      <span class="status-label">Substate:</span>
      <span class="status-value" id="substate">-</span>
    </div>
    <div class="status-item">
      <span class="status-label">Mix Temperature:</span>
      <span class="status-value" id="mix-temp">-</span>
    </div>
    <div class="status-item">
      <span class="status-label">Steam Temperature:</span>
      <span class="status-value" id="steam-temp">-</span>
    </div>
    <div class="status-item">
      <span class="status-label">Pressure:</span>
      <span class="status-value" id="pressure">-</span>
    </div>
    <div class="status-item">
      <span class="status-label">Flow:</span>
      <span class="status-value" id="flow">-</span>
    </div>
    <div class="status-item">
      <span class="status-label">Scale Weight:</span>
      <span class="status-value" id="weight">-</span>
    </div>
  </div>
  
  <div class="controls">
    <button onclick="setMachineState('espresso')">Espresso Mode</button>
    <button onclick="setMachineState('steam')">Steam Mode</button>
    <button onclick="setMachineState('idle')">Idle</button>
    <button onclick="setMachineState('sleeping')">Sleep</button>
    <button onclick="tareScale()">Tare Scale</button>
  </div>
  
  <div class="error" id="error"></div>
  
  <script>
    const GATEWAY = 'http://192.168.1.100:8080';
    let machineWs = null;
    let scaleWs = null;
    let reconnectDelay = 1000;
    const maxReconnectDelay = 30000;
    
    function connectWebSockets() {
      // Machine snapshot stream
      machineWs = new WebSocket(`ws://192.168.1.100:8080/ws/v1/machine/snapshot`);
      
      machineWs.onopen = () => {
        console.log('Machine WebSocket connected');
        document.getElementById('connection-indicator').className = 'connection-status connected';
        reconnectDelay = 1000;
      };
      
      machineWs.onmessage = (event) => {
        const data = JSON.parse(event.data);
        document.getElementById('state').textContent = data.state.state;
        document.getElementById('substate').textContent = data.state.substate;
        document.getElementById('mix-temp').textContent = data.mixTemperature.toFixed(1) + '°C';
        document.getElementById('steam-temp').textContent = data.steamTemperature.toFixed(1) + '°C';
        document.getElementById('pressure').textContent = data.pressure.toFixed(1) + ' bar';
        document.getElementById('flow').textContent = data.flow.toFixed(1) + ' ml/s';
      };
      
      machineWs.onerror = (error) => {
        console.error('Machine WebSocket error:', error);
      };
      
      machineWs.onclose = () => {
        console.log('Machine WebSocket closed, reconnecting...');
        document.getElementById('connection-indicator').className = 'connection-status disconnected';
        setTimeout(connectWebSockets, reconnectDelay);
        reconnectDelay = Math.min(reconnectDelay * 2, maxReconnectDelay);
      };
      
      // Scale snapshot stream
      scaleWs = new WebSocket(`ws://192.168.1.100:8080/ws/v1/scale/snapshot`);
      
      scaleWs.onmessage = (event) => {
        const data = JSON.parse(event.data);
        document.getElementById('weight').textContent = data.weight.toFixed(1) + ' g';
      };
      
      scaleWs.onerror = (error) => {
        console.error('Scale WebSocket error:', error);
      };
      
      scaleWs.onclose = () => {
        console.log('Scale WebSocket closed');
        document.getElementById('weight').textContent = '- g';
      };
    }
    
    async function setMachineState(state) {
      try {
        hideError();
        const response = await fetch(`${GATEWAY}/api/v1/machine/state/${state}`, {
          method: 'PUT'
        });
        
        if (!response.ok) {
          throw new Error(`Failed to set state: ${response.status}`);
        }
        
        console.log(`State changed to ${state}`);
      } catch (error) {
        showError(error.message);
      }
    }
    
    async function tareScale() {
      try {
        hideError();
        const response = await fetch(`${GATEWAY}/api/v1/scale/tare`, {
          method: 'PUT'
        });
        
        if (!response.ok) {
          if (response.status === 404) {
            throw new Error('Scale not connected');
          }
          throw new Error(`Failed to tare scale: ${response.status}`);
        }
        
        console.log('Scale tared');
      } catch (error) {
        showError(error.message);
      }
    }
    
    function showError(message) {
      const errorDiv = document.getElementById('error');
      errorDiv.textContent = message;
      errorDiv.style.display = 'block';
    }
    
    function hideError() {
      document.getElementById('error').style.display = 'none';
    }
    
    // Initialize
    connectWebSockets();
  </script>
</body>
</html>
```

---

## Deployment

### Serving Your Skin

**1. Local Development:**
```bash
# Python
python3 -m http.server 8000

# Node.js
npx http-server -p 8000

# PHP
php -S localhost:8000
```

Then access at `http://localhost:8000`

**2. Configure Streamline-Bridge to Serve Your Skin:**

Update Streamline-Bridge settings to serve your skin:

```javascript
await fetch('http://192.168.1.100:8080/api/v1/settings', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    webUiPath: '/path/to/your/skin'
  })
});
```

**3. Remote Hosting:**
- Host on any web server
- Update CORS settings if needed
- Ensure your skin can reach the gateway IP

---

## Troubleshooting

### WebSocket Connection Fails
- Verify gateway is running: `curl http://<ip>:8080/api/v1/machine/state`
- Check firewall rules on the gateway device
- Ensure you're using `ws://` (not `wss://`) unless TLS is configured
- Check browser console for specific error messages

### Snapshot Data Stops Flowing
- Check browser console for WebSocket errors
- Verify connection state: `ws.readyState` (1 = OPEN)
- Implement reconnection logic (see Best Practices)
- Check if machine is actually connected to Streamline-Bridge

### Commands Don't Execute
- Check HTTP response status codes
- Verify machine is in correct state for the operation
- Review Streamline-Bridge logs: Connect to `ws://<ip>:8080/ws/v1/logs`
- Ensure machine is connected: `GET /api/v1/devices`

### Profile Upload Fails
- Validate profile JSON structure (use v2 format)
- Ensure all required fields are present
- Check that `steps` array is properly formatted
- Verify machine is in `idle` or `sleeping` state

### Scale Not Responding
- Check scale is connected: `GET /api/v1/devices`
- Try reconnecting scale: `GET /api/v1/devices/scan?connect=true`
- Check scale battery level via scale snapshot stream

---

## API Reference

For complete, interactive API documentation, visit:
```
http://<gateway-ip>:4001
```

This serves OpenAPI/Swagger documentation with:
- All REST endpoints
- Request/response schemas
- Try-it-out functionality
- WebSocket endpoint documentation

---

## Next Steps

1. **Study the Streamline Project** reference implementation for real-world patterns
2. **Start with the minimal example** above and expand incrementally
3. **Build interactive charts** using Chart.js, D3.js, or Plotly
4. **Explore workflow automation** for recurring brewing recipes
5. **Consider plugin development** for advanced custom functionality (see `Plugins.md`)

---

## Contributing

If you develop a skin and want to share it:
1. Add it to the Streamline-Bridge community showcase (coming soon)
2. Include screenshots and setup instructions
3. Document any custom features or requirements
4. Share on the Decent Diaspora forums

For questions or issues:
- Open issues on the Streamline-Bridge GitHub repository
- Join discussions on Decent Diaspora forums

Happy brewing and coding!

---

## Skin Development & Deployment

This section covers how to develop, build, and deploy custom WebUI skins for Streamline-Bridge, including support for modern web frameworks like Next.js, React, Vue, Svelte, and others.

### Understanding Skin Distribution

Streamline-Bridge supports multiple skin installation methods:

1. **Bundled Asset Skins**: Skins packaged with the Flutter app (in `assets/web/`)
2. **Remote Bundled Skins**: Skins auto-downloaded from hardcoded GitHub URLs on app startup
3. **User-Installed Skins**: Skins manually installed by users from local paths or URLs

**Skin Directory Structure:**
```
ApplicationDocuments/
└── web-ui/
    ├── my-skin-id/
    │   ├── index.html        # Required entry point
    │   ├── manifest.json     # Optional metadata
    │   ├── assets/
    │   ├── _next/            # Next.js example
    │   └── ...
    ├── another-skin/
    └── .rea_metadata.json    # Version tracking (managed by REA)
```

### Skin Metadata: manifest.json

While optional, including a `manifest.json` helps Streamline-Bridge display better skin information:

```json
{
  "id": "my-nextjs-skin",
  "name": "Beautiful Espresso UI",
  "description": "Modern Next.js skin with real-time shot visualization",
  "version": "1.2.0",
  "author": "Your Name",
  "repository": "https://github.com/username/repo"
}
```

**Important**: If `manifest.json` is missing, the skin ID will be the directory name.

---

## Local Development Workflow

### 1. Develop Your Skin Locally

Use any modern web framework. Here's a Next.js example:

**Create Next.js App:**
```bash
npx create-next-app@latest my-espresso-skin
cd my-espresso-skin
```

**Configure for Static Export** (`next.config.js`):
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',  // Enable static HTML export
  images: {
    unoptimized: true  // Required for static export
  },
  // Optional: Add base path if serving from subdirectory
  // basePath: '/my-skin',
  // assetPrefix: '/my-skin',
}

module.exports = nextConfig
```

**Build Your Skin:**
```bash
npm run build
```

This creates an `out/` directory with static HTML/CSS/JS files.

### 2. Test Locally with Streamline-Bridge

**Option A: Install from Local Path** (Flutter Dart code example):

```dart
// In your Flutter app or via API
await webUIStorage.installFromPath('/path/to/my-espresso-skin/out');
```

**Option B: Manual Copy** (for quick testing):

```bash
# Find your app documents directory
# Android: /sdcard/Android/data/com.example.reaprime/files/
# macOS: ~/Library/Containers/com.example.reaprime/Data/Documents/
# Linux: ~/.local/share/reaprime/

# Copy your build output
cp -r ./out ~/path/to/app/documents/web-ui/my-skin-id/
```

**Option C: Serve Locally and Point Browser** (during development):

```bash
# In your Next.js project
npm run dev

# Access directly at http://localhost:3000
# Connect to Streamline-Bridge API at http://<gateway-ip>:8080
```

### 3. Connect to Gateway During Development

When developing locally, your skin needs to connect to the Streamline-Bridge gateway:

```javascript
// Use environment variable or config
const GATEWAY_URL = process.env.NEXT_PUBLIC_GATEWAY_URL || 'http://192.168.1.100:8080';
const WS_URL = process.env.NEXT_PUBLIC_WS_URL || 'ws://192.168.1.100:8080';

// In your API client
export const apiClient = {
  async getMachineState() {
    const response = await fetch(`${GATEWAY_URL}/api/v1/machine/state`);
    return response.json();
  },
  
  connectSnapshot() {
    return new WebSocket(`${WS_URL}/ws/v1/machine/snapshot`);
  }
};
```

**Development `.env.local`:**
```bash
NEXT_PUBLIC_GATEWAY_URL=http://192.168.1.100:8080
NEXT_PUBLIC_WS_URL=ws://192.168.1.100:8080
```

---

## Production Deployment via GitHub Releases

For production distribution, use GitHub Releases to publish built skins. This approach provides:
- Semantic versioning via Git tags
- Automatic update detection
- Clean separation of source code vs. distribution files
- Professional software distribution workflow

### Method 1: GitHub Actions Automated Release

**Create `.github/workflows/release.yml`:**

```yaml
name: Build and Release WebUI Skin

on:
  push:
    tags:
      - 'v*'  # Trigger on version tags like v1.0.0, v1.2.3, etc.
  workflow_dispatch:  # Allow manual triggering from GitHub UI

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'
          
      - name: Install dependencies
        run: npm ci
        
      - name: Build Next.js app
        run: npm run build
        
      - name: Create manifest.json
        run: |
          cat > out/manifest.json << EOF
          {
            "id": "my-nextjs-skin",
            "name": "Beautiful Espresso UI",
            "description": "Modern Next.js skin with real-time shot visualization",
            "version": "${{ github.ref_name }}",
            "author": "Your Name",
            "repository": "${{ github.repository }}"
          }
          EOF
      
      - name: Create release archive
        run: |
          cd out
          zip -r ../my-skin-${{ github.ref_name }}.zip .
          cd ..
          
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: my-skin-${{ github.ref_name }}.zip
          tag_name: ${{ github.ref_name }}
          name: Release ${{ github.ref_name }}
          draft: false
          prerelease: false
          generate_release_notes: true
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Usage:**
```bash
# Create and push a version tag
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions will automatically:
# 1. Build your Next.js app
# 2. Create manifest.json with version
# 3. Package as ZIP
# 4. Create GitHub Release with the ZIP attached
```

### Method 2: Distribution Branch (Alternative)

If you prefer not to use GitHub Releases, deploy to a separate `dist` branch:

**Create `.github/workflows/build-dist.yml`:**

```yaml
name: Build to Dist Branch

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'
          
      - name: Install and build
        run: |
          npm ci
          npm run build
          
      - name: Create manifest
        run: |
          cat > out/manifest.json << EOF
          {
            "id": "my-nextjs-skin",
            "name": "Beautiful Espresso UI",
            "version": "$(git rev-parse --short HEAD)",
            "author": "Your Name"
          }
          EOF
      
      - name: Deploy to dist branch
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./out
          publish_branch: dist
          force_orphan: true  # Keep dist branch clean (no history)
```

Then install from the `dist` branch:
```dart
// In webui_storage.dart _remoteWebUISources
'https://github.com/username/repo/archive/refs/heads/dist.zip'
```

---

## Configuring Streamline-Bridge for Auto-Download

### For Remote Bundled Skins (Auto-Download on Startup)

Edit `lib/src/webui_support/webui_storage.dart`:

```dart
/// Remote WebUI source configuration
static const List<Map<String, dynamic>> _remoteWebUISources = [
  // GitHub Release (recommended for production)
  {
    'type': 'github_release',
    'repo': 'username/my-skin-repo',
    'asset': 'my-skin.zip',  // Optional: specific asset name
    'prerelease': false,      // Optional: include pre-releases
  },
  // GitHub Branch Archive
  {
    'type': 'github_branch',
    'repo': 'username/my-skin-repo',
    'branch': 'main',
  },
  // Direct URL
  {
    'type': 'url',
    'url': 'https://example.com/skin.zip',
  },
];
```

**Streamline-Bridge will:**
- Download skins on first app startup
- Check for updates on subsequent startups
- For GitHub releases: checks for new release tags
- For branches/URLs: uses HTTP ETag/Last-Modified headers
- Only re-download if remote version has changed
- Mark these skins as "bundled" (users cannot remove them)

### For User-Installable Skins (via REST API)

Users can install skins dynamically via REST API without recompiling the app:

**Install from GitHub Release:**
```bash
curl -X POST http://localhost:8080/api/v1/webui/skins/install/github-release \
  -H "Content-Type: application/json" \
  -d '{
    "repo": "username/my-skin-repo",
    "asset": "my-skin.zip",
    "prerelease": false
  }'
```

**Install from GitHub Branch:**
```bash
curl -X POST http://localhost:8080/api/v1/webui/skins/install/github-branch \
  -H "Content-Type: application/json" \
  -d '{
    "repo": "username/my-skin-repo",
    "branch": "main"
  }'
```

**Install from URL:**
```bash
curl -X POST http://localhost:8080/api/v1/webui/skins/install/url \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://example.com/skin.zip"
  }'
```

**List Installed Skins:**
```bash
curl http://localhost:8080/api/v1/webui/skins
```

**Get Specific Skin:**
```bash
curl http://localhost:8080/api/v1/webui/skins/my-skin-id
```

**Remove Skin (user-installed only):**
```bash
curl -X DELETE http://localhost:8080/api/v1/webui/skins/my-skin-id
```

**Get Default Skin:**
```bash
curl http://localhost:8080/api/v1/webui/skins/default
```

---

## Version Management & Updates

Streamline-Bridge tracks skin metadata in `.rea_metadata.json`:

```json
{
  "my-nextjs-skin": {
    "skinId": "my-nextjs-skin",
    "sourceUrl": "https://github.com/username/repo/archive/refs/heads/dist.zip",
    "etag": "\"abc123def456\"",
    "lastModified": "Wed, 01 Feb 2026 12:00:00 GMT",
    "commitHash": "branch:dist",
    "installedAt": "2026-02-01T12:00:00Z",
    "lastChecked": "2026-02-09T10:30:00Z"
  }
}
```

**Update Detection:**
- Remote skins are checked for updates when `downloadRemoteSkins()` is called
- Uses HTTP `ETag` and `Last-Modified` headers for efficient version checking
- Only downloads if remote version differs from installed version
- Updates are automatic for remote bundled skins

---

## Best Practices for Skin Development

### 1. Environment Variables for Gateway URL

Always use environment variables for API endpoints:

```javascript
// .env.local (development)
NEXT_PUBLIC_GATEWAY_URL=http://192.168.1.100:8080
NEXT_PUBLIC_WS_URL=ws://192.168.1.100:8080

// .env.production (build)
NEXT_PUBLIC_GATEWAY_URL=http://localhost:8080
NEXT_PUBLIC_WS_URL=ws://localhost:8080
```

**Why localhost in production?** When served by Streamline-Bridge, the skin runs on the same device as the gateway.

### 2. Static Export Configuration

Ensure your framework is configured for static export:

**Next.js** (`next.config.js`):
```javascript
module.exports = {
  output: 'export',
  images: { unoptimized: true }
}
```

**Vite** (`vite.config.js`):
```javascript
export default {
  base: './',  // Use relative paths
  build: {
    outDir: 'dist',
    assetsDir: 'assets'
  }
}
```

**Create React App**:
```bash
npm run build  # Already static by default
```

### 3. Handle Missing manifest.json

If you don't include `manifest.json`, ensure your directory name is descriptive:

```bash
# Build output structure
out/
├── index.html
├── _next/
└── assets/

# Will be installed as:
web-ui/
└── out/  # <- Skin ID will be "out" (not great!)
```

**Better:** Always include `manifest.json` with proper `id` field.

### 4. Test Before Release

Before creating a GitHub release:

1. **Build locally:**
   ```bash
   npm run build
   ```

2. **Test the build output:**
   ```bash
   npx serve out
   # Open http://localhost:3000
   ```

3. **Verify all assets load** (check browser console for 404s)

4. **Test WebSocket connections** to your development gateway

5. **Create manifest.json** and verify metadata

6. **Only then create release tag**

### 5. Versioning Strategy

Use semantic versioning for skin releases:

- `v1.0.0` - Initial release
- `v1.1.0` - New features, backward compatible
- `v1.1.1` - Bug fixes
- `v2.0.0` - Breaking changes

---

## Framework-Specific Examples

### Next.js

```bash
# Create app
npx create-next-app@latest my-skin

# Configure next.config.js for static export
# Build
npm run build

# Output is in ./out/
```

### React (Vite)

```bash
# Create app
npm create vite@latest my-skin -- --template react

# Build
npm run build

# Output is in ./dist/
```

### Vue

```bash
# Create app
npm create vue@latest my-skin

# Build
npm run build

# Output is in ./dist/
```

### Svelte

```bash
# Create app
npm create svelte@latest my-skin

# Install adapter-static
npm install -D @sveltejs/adapter-static

# Configure svelte.config.js
# Build
npm run build

# Output is in ./build/
```

---

## Troubleshooting

### Build Output Missing index.html

Ensure your framework is configured for static HTML generation:
- Next.js needs `output: 'export'`
- SvelteKit needs `@sveltejs/adapter-static`
- Some frameworks require explicit configuration

### Assets Not Loading (404 Errors)

Check asset paths are relative:
- Next.js: Automatically handled with `output: 'export'`
- Vite: Set `base: './'` in config
- Check browser console for failing asset URLs

### WebSocket Connection Fails

During development with skin on `localhost:3000` and gateway on `192.168.1.100:8080`:
- Ensure CORS is enabled on gateway (it is by default)
- Use explicit gateway IP in `NEXT_PUBLIC_WS_URL`
- Check browser console for connection errors

### Skin Not Appearing in Streamline-Bridge

- Verify directory name or `manifest.json` `id` field
- Check `ApplicationDocuments/web-ui/` directory exists
- Ensure `index.html` is at root of skin directory
- Review Streamline-Bridge logs for installation errors

### Updates Not Detected

For remote bundled skins:
- GitHub must return different `ETag` or `Last-Modified` headers
- Branch archives update when branch changes
- Releases have stable ETags (won't auto-update)
- Force re-download by deleting skin directory and restarting app

---

## Example: Complete Next.js Skin Project

**Project Structure:**
```
my-espresso-skin/
├── .github/
│   └── workflows/
│       └── release.yml
├── src/
│   ├── app/
│   │   ├── page.tsx
│   │   └── layout.tsx
│   ├── components/
│   │   ├── MachineStatus.tsx
│   │   └── ShotChart.tsx
│   └── lib/
│       └── api-client.ts
├── public/
├── next.config.js
├── package.json
├── .env.local
└── README.md
```

**next.config.js:**
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  images: { unoptimized: true }
}

module.exports = nextConfig
```

**.env.local:**
```bash
NEXT_PUBLIC_GATEWAY_URL=http://192.168.1.100:8080
NEXT_PUBLIC_WS_URL=ws://192.168.1.100:8080
```

**src/lib/api-client.ts:**
```typescript
const GATEWAY_URL = process.env.NEXT_PUBLIC_GATEWAY_URL!;
const WS_URL = process.env.NEXT_PUBLIC_WS_URL!;

export const api = {
  async getMachineState() {
    const res = await fetch(`${GATEWAY_URL}/api/v1/machine/state`);
    return res.json();
  },
  
  async setMachineState(state: string) {
    await fetch(`${GATEWAY_URL}/api/v1/machine/state/${state}`, {
      method: 'PUT'
    });
  },
  
  connectSnapshot() {
    return new WebSocket(`${WS_URL}/ws/v1/machine/snapshot`);
  }
};
```

**package.json scripts:**
```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "release": "npm run build && echo 'Ready to tag and push!'"
  }
}
```

**Deployment:**
```bash
# Development
npm run dev

# Production build
npm run build

# Create release
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions builds and creates release automatically
```

---

## Advanced: Multiple Skins in One Repository

You can manage multiple skins in a monorepo:

```
espresso-skins/
├── packages/
│   ├── minimal/
│   │   ├── package.json
│   │   └── src/
│   ├── advanced/
│   │   ├── package.json
│   │   └── src/
│   └── experimental/
│       ├── package.json
│       └── src/
├── .github/
│   └── workflows/
│       ├── release-minimal.yml
│       ├── release-advanced.yml
│       └── release-experimental.yml
└── package.json (root)
```

Each skin can have its own release workflow targeting different GitHub Release tags.

---

## Contributing Your Skin

Once your skin is ready for public use:

1. **Document it well:**
   - Add screenshots to README
   - Document unique features
   - Provide setup instructions

2. **Add to community list:**
   - Submit PR to Streamline-Bridge documentation
   - Share on Decent Diaspora forums

3. **Consider open-sourcing:**
   - Choose appropriate license (MIT, Apache, GPL, etc.)
   - Welcome contributions and issues

---

## Summary

**For Development:**
- Build your skin with any modern web framework
- Configure for static HTML export
- Test locally using `npm run dev` or by copying build to `web-ui/`
- Connect to gateway API using environment variables

**For Distribution:**
- Use GitHub Actions to automate builds
- Create releases with version tags (recommended)
- OR use a `dist` branch for continuous deployment
- Always include `manifest.json` with proper metadata

**For Auto-Updates:**
- Add your skin to `_remoteWebUISources` in `webui_storage.dart`
- Streamline-Bridge will auto-download and check for updates
- Uses HTTP headers for efficient version detection

Happy skin development!




















