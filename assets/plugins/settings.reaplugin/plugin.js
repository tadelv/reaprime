/* settings.reaplugin
 *
 * Contract:
 * - This file must define a function named 'createPlugin'
 * - Factory function receives 'host' object as parameter
 * - Returns a plugin object with onLoad, onUnload, onEvent methods
 */

// Standard factory function - receives host object from PluginManager
function createPlugin(host) {
  "use strict";

  let state = {
    refreshInterval: 5,
  };

  function log(msg) {
    host.log(`[settings] ${msg}`);
  }

  /**
   * Fetch REA application settings
   */
  async function fetchReaSettings() {
    try {
      const res = await fetch("http://localhost:8080/api/v1/settings");
      if (!res.ok) {
        log(`Failed to fetch REA settings: ${res.status}`);
        return null;
      }
      return await res.json();
    } catch (e) {
      log(`Error fetching REA settings: ${e.message}`);
      return null;
    }
  }

  /**
   * Fetch DE1 machine settings
   */
  async function fetchDe1Settings() {
    try {
      const res = await fetch("http://localhost:8080/api/v1/de1/settings");
      if (!res.ok) {
        log(`Failed to fetch DE1 settings: ${res.status}`);
        return null;
      }
      return await res.json();
    } catch (e) {
      log(`Error fetching DE1 settings: ${e.message}`);
      return null;
    }
  }

  /**
   * Fetch DE1 advanced settings
   */
  async function fetchDe1AdvancedSettings() {
    try {
      const res = await fetch("http://localhost:8080/api/v1/de1/settings/advanced");
      if (!res.ok) {
        log(`Failed to fetch DE1 advanced settings: ${res.status}`);
        return null;
      }
      return await res.json();
    } catch (e) {
      log(`Error fetching DE1 advanced settings: ${e.message}`);
      return null;
    }
  }

  /**
   * Generate HTML page with all settings
   */
  function generateSettingsHTML(reaSettings, de1Settings, de1AdvancedSettings) {
    const refreshScript = state.refreshInterval > 0 
      ? `<script>setTimeout(() => location.reload(), ${state.refreshInterval * 1000});</script>`
      : '';

    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>REA Settings</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: #f5f5f5;
            padding: 20px;
            line-height: 1.6;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 2em;
        }
        .timestamp {
            color: #666;
            font-size: 0.9em;
            margin-bottom: 20px;
        }
        .section {
            background: white;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .section h2 {
            color: #2c3e50;
            margin-bottom: 15px;
            font-size: 1.5em;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        .settings-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 15px;
        }
        .setting-item {
            display: flex;
            justify-content: space-between;
            padding: 12px;
            background: #f8f9fa;
            border-radius: 6px;
            border-left: 3px solid #3498db;
        }
        .setting-label {
            font-weight: 600;
            color: #2c3e50;
        }
        .setting-value {
            color: #555;
            font-family: 'Courier New', monospace;
        }
        .error {
            background: #fee;
            border-left-color: #e74c3c;
            color: #c0392b;
            padding: 12px;
            border-radius: 6px;
        }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-ok {
            background: #2ecc71;
        }
        .status-error {
            background: #e74c3c;
        }
    </style>
    ${refreshScript}
</head>
<body>
    <div class="container">
        <h1>REA Settings Dashboard</h1>
        <div class="timestamp">
            <span class="status-indicator ${reaSettings && de1Settings ? 'status-ok' : 'status-error'}"></span>
            Last updated: ${new Date().toLocaleString()}
        </div>

        <!-- REA Application Settings -->
        <div class="section">
            <h2>REA Application Settings</h2>
            ${reaSettings ? `
                <div class="settings-grid">
                    <div class="setting-item">
                        <span class="setting-label">Gateway Mode</span>
                        <span class="setting-value">${reaSettings.gatewayMode || 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Web UI Path</span>
                        <span class="setting-value">${reaSettings.webUiPath || 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Log Level</span>
                        <span class="setting-value">${reaSettings.logLevel || 'N/A'}</span>
                    </div>
                </div>
            ` : '<div class="error">Failed to load REA settings</div>'}
        </div>

        <!-- DE1 Machine Settings -->
        <div class="section">
            <h2>DE1 Machine Settings</h2>
            ${de1Settings ? `
                <div class="settings-grid">
                    <div class="setting-item">
                        <span class="setting-label">Fan Threshold</span>
                        <span class="setting-value">${de1Settings.fan !== undefined ? de1Settings.fan + '°C' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">USB Charger Mode</span>
                        <span class="setting-value">${de1Settings.usb !== undefined ? (de1Settings.usb ? 'Enabled' : 'Disabled') : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Flush Temperature</span>
                        <span class="setting-value">${de1Settings.flushTemp !== undefined ? de1Settings.flushTemp + '°C' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Flush Timeout</span>
                        <span class="setting-value">${de1Settings.flushTimeout !== undefined ? de1Settings.flushTimeout + 's' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Flush Flow</span>
                        <span class="setting-value">${de1Settings.flushFlow !== undefined ? de1Settings.flushFlow + ' ml/s' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Hot Water Flow</span>
                        <span class="setting-value">${de1Settings.hotWaterFlow !== undefined ? de1Settings.hotWaterFlow + ' ml/s' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Steam Flow</span>
                        <span class="setting-value">${de1Settings.steamFlow !== undefined ? de1Settings.steamFlow + ' ml/s' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Tank Temperature Threshold</span>
                        <span class="setting-value">${de1Settings.tankTemp !== undefined ? de1Settings.tankTemp + '°C' : 'N/A'}</span>
                    </div>
                </div>
            ` : '<div class="error">Failed to load DE1 settings (machine may not be connected)</div>'}
        </div>

        <!-- DE1 Advanced Settings -->
        <div class="section">
            <h2>DE1 Advanced Settings</h2>
            ${de1AdvancedSettings ? `
                <div class="settings-grid">
                    <div class="setting-item">
                        <span class="setting-label">Heater Phase 1 Flow</span>
                        <span class="setting-value">${de1AdvancedSettings.heaterPh1Flow !== undefined ? de1AdvancedSettings.heaterPh1Flow + ' ml/s' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Heater Phase 2 Flow</span>
                        <span class="setting-value">${de1AdvancedSettings.heaterPh2Flow !== undefined ? de1AdvancedSettings.heaterPh2Flow + ' ml/s' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Heater Idle Temperature</span>
                        <span class="setting-value">${de1AdvancedSettings.heaterIdleTemp !== undefined ? de1AdvancedSettings.heaterIdleTemp + '°C' : 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Heater Phase 2 Timeout</span>
                        <span class="setting-value">${de1AdvancedSettings.heaterPh2Timeout !== undefined ? de1AdvancedSettings.heaterPh2Timeout + 's' : 'N/A'}</span>
                    </div>
                </div>
            ` : '<div class="error">Failed to load DE1 advanced settings (machine may not be connected)</div>'}
        </div>
    </div>
</body>
</html>`;
  }

  // Return the plugin object
  return {
    id: "settings.reaplugin",
    version: "1.0.0",

    onLoad(settings) {
      state.refreshInterval = settings.RefreshInterval !== undefined ? settings.RefreshInterval : 5;
      log(`Loaded with refresh interval: ${state.refreshInterval}s`);
    },

    onUnload() {
      log("Unloaded");
    },

    // HTTP request handler for the 'settings' endpoint
    __httpRequestHandler(request) {
      log(`Received HTTP request for ${request.endpoint}: ${request.method}`);

      if (request.endpoint === "ui") {
        // Fetch all settings and generate HTML
        return Promise.all([
          fetchReaSettings(),
          fetchDe1Settings(),
          fetchDe1AdvancedSettings()
        ]).then(([reaSettings, de1Settings, de1AdvancedSettings]) => {
          const html = generateSettingsHTML(reaSettings, de1Settings, de1AdvancedSettings);
          
          return {
            requestId: request.requestId,
            status: 200,
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              'Cache-Control': 'no-cache'
            },
            body: html
          };
        }).catch((error) => {
          log(`Error generating settings page: ${error.message}`);
          return {
            requestId: request.requestId,
            status: 500,
            headers: {
              'Content-Type': 'text/plain'
            },
            body: `Error generating settings page: ${error.message}`
          };
        });
      }

      // Default 404 response
      return {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: "Endpoint not found" })
      };
    },

    onEvent(event) {
      if (!event || !event.name) return;

      // This plugin doesn't need to respond to state updates
      // It only serves HTTP requests on demand
      switch (event.name) {
        case "shutdown":
          log("Shutdown event received");
          break;
      }
    },
  };
}
