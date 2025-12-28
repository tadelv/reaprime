
# Rea Plugin Development Guide

## Overview

Rea plugins are JavaScript modules that extend the functionality of REA.
Plugins run in a sandboxed JavaScript environment and can react to machine events,
store data, make HTTP requests, and emit events through REA api.

## Plugin Structure

A Rea plugin consists of two required files:

### 1. `manifest.json` - Plugin metadata and configuration

```json
{
  "id": "unique.plugin.id",
  "author": "Your Name",
  "name": "Plugin Display Name",
  "description": "What your plugin does",
  "version": "1.0.0",
  "apiVersion": 1,
  "permissions": [
    "log",
    "api",
    "emit",
    "pluginStorage"
  ],
  "settings": {
    "SettingName": {
      "type": "string",
      "secure": false,
      "description": "Setting description"
    }
  },
  "api": [
    {
      "id": "eventName",
      "type": "websocket",
      "data": {
        "field1": {
          "type": "number",
          "description": "Field description"
        }
      }
    }
  ]
}
```

#### Manifest Fields

- **id**: Unique identifier using reverse domain notation (e.g., `com.example.plugin`)
- **permissions**: Array of capabilities the plugin needs:
  - `log`: Access to logging
  - `api`: Ability to make HTTP requests
  - `emit`: Emit events to the Flutter app
  - `pluginStorage`: Persistent storage
- **settings**: User-configurable options with `type` (`string`, `number`, `boolean`) and optional `secure` flag for passwords
- **api**: Events this plugin emits, used for documentation and type checking

### 2. `plugin.js` - Main plugin implementation

```javascript
function createPlugin(host) {
  "use strict";

  // Internal state
  let state = {};

  function log(msg) {
    host.log(`[plugin-id] ${msg}`);
  }

  return {
    id: "unique.plugin.id",
    version: "1.0.0",

    onLoad(settings) {
      // Called when plugin loads
      // `settings` contains user-configured values
    },

    onUnload() {
      // Clean up resources
    },

    onEvent(event) {
      // Handle events from Flutter app
      // event.name: string, event.payload: object
    }
  };
}
```

## Host API

The `host` object provides these methods:

### `host.log(message)`
Log messages to the Flutter app's logger.

### `host.emit(eventName, payload)`
Emit events to the Flutter app. These can be listened to by other parts of the application.

### `host.storage(command)`
Interact with persistent storage. Commands:
```javascript
// Read from storage
host.storage({
  type: "read",
  key: "keyName",
  namespace: "plugin.id"
});

// Write to storage
host.storage({
  type: "write",
  key: "keyName",
  namespace: "plugin.id",
  data: { foo: "bar" }
});
```

**Note:** namespace is not used by Rea internally, the plugin storage is namespaced to the plugins' identifier.

## Events System

### Events from Flutter → Plugin

Plugins receive events in the `onEvent` method:

- **`stateUpdate`**: Machine state changes (temperature, pressure, flow, etc.)

  ```javascript
  {
    name: "stateUpdate",
    payload: {
      groupTemperature: 93.5,
      targetGroupTemperature: 94.0,
      pressure: 9.2,
      flow: 2.1,
      // ... other machine metrics
    }
  }
  ```

- **`shutdown`**: Plugin is about to be unloaded
- **`storageRead`**: Response to a storage read request

  ```javascript
  {
    name: "storageRead",
    payload: {
      key: "lastUploadedShot",
      value: "shot-12345"
    }
  }
  ```

- **`storageWrite`**: Confirmation of storage write

### Events from Plugin → Flutter

Plugins can emit custom events that the Flutter app can listen to:

```javascript
host.emit("timeToReady", {
  remainingTimeMs: 120000,
  heatingRate: 0.5,
  status: "heating",
  message: "02:00 remaining"
});
```

The event name is tied to the api endpoint, defined in the plugin manifest.
When Rea matches an external request to an endpoint that is defined in the
plugins manifest,
it will send over events emitted by the plugin.

Example:

```bash
npx wscat -c ws://localhost:8080/ws/v1/plugins/time-to-ready.reaplugin/timeToReady

```
Will open a websocket through wich Rea will forward all the `timeToReady` events

## HTTP Requests

Plugins can make HTTP requests using the standard `fetch` API (polyfilled by the host):

```javascript
// Basic GET request
const response = await fetch("https://api.example.com/data");
const data = await response.json();

// POST with authentication
const authHeader = "Basic " + btoa(username + ":" + password);
const upload = await fetch("https://api.example.com/upload", {
  method: "POST",
  headers: {
    "Authorization": authHeader,
    "Content-Type": "application/json"
  },
  body: JSON.stringify(data)
});
```

**Note**: The JavaScript environment has limited APIs. Currently available:

- `fetch()` for HTTP requests
- `btoa()` for base64 encoding (polyfilled)
- Standard JavaScript language features

## Plugin Lifecycle

1. **Initialization**: Plugin directory is copied to app storage
2. **Loading**: `createPlugin()` is called, then `onLoad(settings)`
3. **Running**: Plugin receives events via `onEvent()` and can emit events
4. **Unloading**: `onUnload()` is called for cleanup
5. **Removal**: Plugin files are deleted from storage

## Example: Temperature Monitoring Plugin

```javascript
function createPlugin(host) {
  "use strict";

  let temperatureHistory = [];

  function log(msg) {
    host.log(`[temp-monitor] ${msg}`);
  }

  return {
    id: "com.example.tempmonitor",
    version: "1.0.0",

    onLoad(settings) {
      log("Temperature monitor loaded");
      // Load previous state from storage
      host.storage({
        type: "read",
        key: "history",
        namespace: "com.example.tempmonitor"
      });
    },

    onUnload() {
      log("Saving temperature history");
      host.storage({
        type: "write",
        key: "history",
        namespace: "com.example.tempmonitor",
        data: temperatureHistory
      });
    },

    onEvent(event) {
      if (event.name === "stateUpdate") {
        const temp = event.payload.groupTemperature;
        temperatureHistory.push({
          timestamp: Date.now(),
          temperature: temp
        });

        // Keep only last 100 readings
        if (temperatureHistory.length > 100) {
          temperatureHistory.shift();
        }

        // Emit if temperature exceeds threshold
        if (temp > 95) {
          host.emit("highTemperature", {
            temperature: temp,
            timestamp: Date.now()
          });
        }
      } else if (event.name === "storageRead") {
        if (event.payload.key === "history") {
          temperatureHistory = event.payload.value || [];
        }
      }
    }
  };
}
```

## Best Practices

1. **Error Handling**: Always wrap async operations in try-catch
2. **Resource Cleanup**: Clear timeouts/intervals in `onUnload()`
3. **Storage**: Use the plugin's ID as namespace for storage isolation
4. **Logging**: Use descriptive log messages with plugin identifier prefix
5. **Settings Validation**: Validate user settings in `onLoad()`
6. **State Management**: Keep plugin state in memory; persist to storage only what's necessary

## Development Workflow

1. Create a directory with your plugin ID (e.g., `myplugin.reaplugin/`)
2. Add `manifest.json` and `plugin.js` files
3. Test locally by placing in the app's plugin directory
4. Use `host.log()` for debugging
5. Package as a `.reaplugin` directory (or zip file) for distribution

## Machine Data Structure

When receiving `stateUpdate` events, the payload contains:

```javascript
{
  groupTemperature: 93.5,        // Current group head temperature (°C)
  targetGroupTemperature: 94.0,  // Target temperature (°C)
  mixTemperature: 92.8,          // Mix temperature (°C)
  targetMixTemperature: 93.5,    // Target mix temperature (°C)
  pressure: 9.2,                 // Current pressure (bar)
  targetPressure: 9.0,           // Target pressure (bar)
  flow: 2.1,                     // Current flow rate (ml/s)
  targetFlow: 2.0,               // Target flow rate (ml/s)
  state: {                       // Machine state
    substate: "preinfusion"      // Current substate
  },
  // Scale data if available
  scale: {
    weight: 18.5,                // Current weight (g)
    weightFlow: 1.8              // Weight-based flow rate (g/s)
  }
}
```

## Troubleshooting

### Common Issues

1. **Plugin not loading**: Check manifest `id` matches plugin directory name
2. **Storage not working**: Ensure `pluginStorage` permission is in manifest
3. **HTTP requests failing**: Verify network connectivity and CORS headers
4. **Events not received**: Check event names match exactly (case-sensitive)

### Debugging

- Use `host.log()` extensively during development
- Check Flutter app logs for JavaScript errors
- Test with simple plugins first, then add complexity
- When iterating, it helps to debug on a platform that can access Rea
documents. This way, you can edit plugin source directly and simply reload
it in Rea UI.

## API Reference

### Available in JavaScript Runtime

- **Global Functions**: `fetch()`, `btoa()`, `setTimeout()`, `clearTimeout()`
- **Objects**: `Promise`, `JSON`, `Math`, `Date`, `Array`, `Object`
- **Constants**: `undefined`, `null`, `Infinity`, `NaN`

### Not Available

- `XMLHttpRequest`, `FormData`, `Blob`, `FileReader`
- `localStorage`, `sessionStorage`, `indexedDB`
- DOM APIs (`document`, `window`, etc.)
- Node.js modules (`require`, `module`, `process`)

## Security Considerations

- Plugins run in a sandboxed JavaScript environment
- HTTP requests are proxied through Flutter (respects system proxy settings)
- Storage is isolated per plugin
- No filesystem access beyond the plugin's own directory
- No network access to localhost/private IPs (except for REA API)

## Next Steps

1. Review the example plugins in `assets/plugins/`
2. Start with a simple plugin that logs `stateUpdate` events
3. Add settings and persistent storage
4. Implement HTTP communication with external services
5. Emit custom events for the Flutter UI to display

For questions or issues, refer to the example plugins or check the app logs for error messages.
