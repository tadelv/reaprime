# v1 API Documentation

## Overview

This API provides endpoints to retrieve a list of Bluetooth devices, trigger a scan for new devices, manage DE1 espresso machine state and settings, and interact with a connected scale.

## Base URL

```
http://<tablet-ip>/api/v1
```

## Endpoints

### 1. Get Available Devices

**Endpoint:**

```
GET /api/v1/devices
```

**Description:**
Retrieves a list of available Bluetooth devices with their connection states.

**Response:**

- **200 OK**: Returns an array of devices with their IDs and connection states.
- **500 Internal Server Error**: Returns an error message if something goes wrong.

**Response Example:**

```json
[
  {
    "name": "DE1",
    "id": "<de1-bt-mac>",
    "state": "connected"
  },
  {
    "name": "Decent Scale",
    "id": "<decent-scale-mac>",
    "state": "disconnected"
  }
]
```

**Error Response Example:**

```json
{
  "e": "Error message",
  "st": "Stack trace"
}
```

---

### 2. Scan for Devices

**Endpoint:**

```
GET /api/v1/devices/scan
```

**Description:**
Triggers a Bluetooth device scan.

- The scanning operation does not return discovered devices immediately, only triggers the scan process.


Upon scanning, if a missing scale is detected, it will be connected automatically.

**Response:**

- **200 OK**: Returns an empty response body upon successful scan initiation.
- **500 Internal Server Error**: Returns an error message if scanning fails.

**Response Example:**

```
(empty response body)
```

---

### 3. Get DE1 State

**Endpoint:**

```
GET /api/v1/de1/state
```

**Description:**
Retrieves the current DE1 machine state, including a snapshot and USB charger mode.

**Response Example:**

```json
{
  "snapshot": { ... },
  "usbChargerEnabled": true
}
```

---

### 4. Request DE1 State Change

**Endpoint:**

```
PUT /api/v1/de1/state/<newState>
```

**Description:**
Requests a state change for the DE1 espresso machine.

**Response:**

- **200 OK**: If the request is successful.
- **400 Bad Request**: If the provided state is invalid.

---

### 5. Set DE1 Profile

**Endpoint:**

```
POST /api/v1/de1/profile
```

**Description:**
Uploads a new brewing profile to the DE1 machine.
Currently supports upload of v2 json profiles, that are present in the de1app.

**Request Body Example:**

```json
{
  "title": "Espresso Shot",
  "steps": [ ... ]
}
```

---

### 6. Update Shot Settings

**Endpoint:**

```
POST /api/v1/de1/shotSettings
```

**Description:**
Updates shot settings on the DE1 espresso machine.

**Request Body Example:**

```json
{
  "targetHotWaterTemp": 93.0,
  "targetSteamTemp": 9.0
}
```

---

### 7. Toggle USB Charger Mode

**Endpoint:**

```
PUT /api/v1/de1/usb/<state>
```

**Description:**
Enables or disables the USB charger mode on the DE1 machine.
if `<state>` is 'enable', it will enable USB charging, otherwise it will disable it.

**Response:**

- **200 OK**: If the setting was successfully updated.
- **500 Internal Server Error**: If an error occurs.

---

### 8. WebSocket Endpoints

#### Snapshot Updates

```
GET /ws/v1/de1/snapshot
```

Receives real-time snapshot data from the DE1 machine.

#### Shot Settings Updates

```
GET /ws/v1/de1/shotSettings
```

Receives real-time shot settings updates.

#### Water Levels Updates

```
GET /ws/v1/de1/waterLevels
```

Receives real-time water level updates.

---

### 9. Scale API

#### Tare Scale

```
PUT /api/v1/scale/tare
```

**Description:**
Tares the connected scale.

**Response:**

- **200 OK**: If the scale was successfully tared.
- **404 Not Found**: If an invalid command is provided.

#### WebSocket Scale Snapshot

```
GET /ws/v1/scale/snapshot
```

**Description:**
Receives real-time weight data from the scale.

---

## Models

### Scale Snapshot

```json
{
  "timestamp": "2025-02-01T12:34:56.789Z",
  "weight": 15.2,
  "batteryLevel": 80
}
```

### Machine Snapshot

```json
{
  "timestamp": "2025-02-01T12:34:56.789Z",
  "state": { "state": "espresso", "substate": "pouring" },
  "flow": 2.5,
  "pressure": 9.0,
  "targetFlow": 2.0,
  "targetPressure": 9.0,
  "mixTemperature": 93.5,
  "groupTemperature": 94.0,
  "targetMixTemperature": 93.0,
  "targetGroupTemperature": 94.0,
  "profileFrame": 3,
  "steamTemperature": 135.0
}
```

### Profile

```json
{
  "version": "1.0",
  "title": "Espresso Shot",
  "notes": "A classic espresso shot profile",
  "author": "John Doe",
  "beverage_type": "espresso",
  "steps": [
    {
      "type": "pressure",
      "value": 9.0,
      "duration": 30
    },
    {
      "type": "flow",
      "value": 2.5,
      "duration": 20
    }
  ],
  "target_volume": 30.0,
  "target_weight": 25.0,
  "target_volume_count_start": 0,
  "tank_temperature": 90.0
}
```

### Shot Settings

```json
{
  "steamSetting": 1,
  "targetSteamTemp": 150,
  "targetSteamDuration": 30,
  "targetHotWaterTemp": 90,
  "targetHotWaterVolume": 250,
  "targetHotWaterDuration": 15,
  "targetShotVolume": 30,
  "groupTemp": 93.0
}
```

### Water Levels

```json
{
  "currentPercentage": 80,
  "warningThresholdPercentage": 20
}
```

---

## Error Handling

- The API returns HTTP status code **500** when an internal error occurs.
- Error responses include details in the format:
  ```json
  {
    "e": "Error message",
    "st": "Stack trace"
  }
  ```
