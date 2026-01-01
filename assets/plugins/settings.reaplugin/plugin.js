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
   * Generate HTML page with all settings (with editable controls)
   */
  function generateSettingsHTML(reaSettings, de1Settings, de1AdvancedSettings) {
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
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        .timestamp {
            color: #666;
            font-size: 0.9em;
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
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 15px;
        }
        .setting-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px;
            background: #f8f9fa;
            border-radius: 6px;
            border-left: 3px solid #3498db;
        }
        .setting-label {
            font-weight: 600;
            color: #2c3e50;
            flex: 1;
        }
        .setting-control {
            display: flex;
            gap: 8px;
            align-items: center;
        }
        input[type="number"], input[type="text"], select {
            padding: 6px 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            width: 120px;
        }
        select {
            width: 140px;
            cursor: pointer;
        }
        .btn {
            padding: 6px 12px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            transition: background 0.2s;
        }
        .btn-primary {
            background: #3498db;
            color: white;
        }
        .btn-primary:hover {
            background: #2980b9;
        }
        .btn-refresh {
            background: #2ecc71;
            color: white;
        }
        .btn-refresh:hover {
            background: #27ae60;
        }
        .error {
            background: #fee;
            border-left-color: #e74c3c;
            color: #c0392b;
            padding: 12px;
            border-radius: 6px;
        }
        .success-toast {
            position: fixed;
            top: 20px;
            right: 20px;
            background: #2ecc71;
            color: white;
            padding: 15px 20px;
            border-radius: 6px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
            animation: slideIn 0.3s ease-out;
            z-index: 1000;
        }
        .error-toast {
            position: fixed;
            top: 20px;
            right: 20px;
            background: #e74c3c;
            color: white;
            padding: 15px 20px;
            border-radius: 6px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
            animation: slideIn 0.3s ease-out;
            z-index: 1000;
        }
        @keyframes slideIn {
            from { transform: translateX(400px); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
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
        .readonly {
            color: #888;
            font-family: 'Courier New', monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>REA Settings Dashboard</h1>
            <button class="btn btn-refresh" onclick="location.reload()">Refresh</button>
        </div>
        <div class="timestamp">
            <span class="status-indicator ${reaSettings && de1Settings ? 'status-ok' : 'status-error'}"></span>
            Last updated: <span id="timestamp">${new Date().toLocaleString()}</span>
        </div>

        <!-- REA Application Settings -->
        <div class="section">
            <h2>REA Application Settings</h2>
            ${reaSettings ? `
                <div class="settings-grid">
                    <div class="setting-item">
                        <span class="setting-label">Gateway Mode</span>
                        <div class="setting-control">
                            <select id="gatewayMode">
                                <option value="disabled" ${reaSettings.gatewayMode === 'disabled' ? 'selected' : ''}>Disabled</option>
                                <option value="tracking" ${reaSettings.gatewayMode === 'tracking' ? 'selected' : ''}>Tracking</option>
                                <option value="full" ${reaSettings.gatewayMode === 'full' ? 'selected' : ''}>Full</option>
                            </select>
                            <button class="btn btn-primary" onclick="updateReaSetting('gatewayMode', document.getElementById('gatewayMode').value)">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Log Level</span>
                        <div class="setting-control">
                            <select id="logLevel">
                                <option value="ALL" ${reaSettings.logLevel === 'ALL' ? 'selected' : ''}>ALL</option>
                                <option value="FINEST" ${reaSettings.logLevel === 'FINEST' ? 'selected' : ''}>FINEST</option>
                                <option value="FINER" ${reaSettings.logLevel === 'FINER' ? 'selected' : ''}>FINER</option>
                                <option value="FINE" ${reaSettings.logLevel === 'FINE' ? 'selected' : ''}>FINE</option>
                                <option value="CONFIG" ${reaSettings.logLevel === 'CONFIG' ? 'selected' : ''}>CONFIG</option>
                                <option value="INFO" ${reaSettings.logLevel === 'INFO' ? 'selected' : ''}>INFO</option>
                                <option value="WARNING" ${reaSettings.logLevel === 'WARNING' ? 'selected' : ''}>WARNING</option>
                                <option value="SEVERE" ${reaSettings.logLevel === 'SEVERE' ? 'selected' : ''}>SEVERE</option>
                                <option value="SHOUT" ${reaSettings.logLevel === 'SHOUT' ? 'selected' : ''}>SHOUT</option>
                                <option value="OFF" ${reaSettings.logLevel === 'OFF' ? 'selected' : ''}>OFF</option>
                            </select>
                            <button class="btn btn-primary" onclick="updateReaSetting('logLevel', document.getElementById('logLevel').value)">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Web UI Path</span>
                        <span class="readonly">${reaSettings.webUiPath || 'N/A'}</span>
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
                        <span class="setting-label">Fan Threshold (°C)</span>
                        <div class="setting-control">
                            <input type="number" id="fan" value="${de1Settings.fan !== undefined ? de1Settings.fan : ''}" step="1" min="0" max="100">
                            <button class="btn btn-primary" onclick="updateDe1Setting('fan', parseInt(document.getElementById('fan').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">USB Charger Mode</span>
                        <div class="setting-control">
                            <select id="usb">
                                <option value="enable" ${de1Settings.usb ? 'selected' : ''}>Enabled</option>
                                <option value="disable" ${!de1Settings.usb ? 'selected' : ''}>Disabled</option>
                            </select>
                            <button class="btn btn-primary" onclick="updateDe1Setting('usb', document.getElementById('usb').value)">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Flush Temperature (°C)</span>
                        <div class="setting-control">
                            <input type="number" id="flushTemp" value="${de1Settings.flushTemp !== undefined ? de1Settings.flushTemp : ''}" step="0.1" min="0" max="100">
                            <button class="btn btn-primary" onclick="updateDe1Setting('flushTemp', parseFloat(document.getElementById('flushTemp').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Flush Timeout (s)</span>
                        <div class="setting-control">
                            <input type="number" id="flushTimeout" value="${de1Settings.flushTimeout !== undefined ? de1Settings.flushTimeout : ''}" step="0.1" min="0" max="300">
                            <button class="btn btn-primary" onclick="updateDe1Setting('flushTimeout', parseFloat(document.getElementById('flushTimeout').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Flush Flow (ml/s)</span>
                        <div class="setting-control">
                            <input type="number" id="flushFlow" value="${de1Settings.flushFlow !== undefined ? de1Settings.flushFlow : ''}" step="0.1" min="0" max="10">
                            <button class="btn btn-primary" onclick="updateDe1Setting('flushFlow', parseFloat(document.getElementById('flushFlow').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Hot Water Flow (ml/s)</span>
                        <div class="setting-control">
                            <input type="number" id="hotWaterFlow" value="${de1Settings.hotWaterFlow !== undefined ? de1Settings.hotWaterFlow : ''}" step="0.1" min="0" max="10">
                            <button class="btn btn-primary" onclick="updateDe1Setting('hotWaterFlow', parseFloat(document.getElementById('hotWaterFlow').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Steam Flow (ml/s)</span>
                        <div class="setting-control">
                            <input type="number" id="steamFlow" value="${de1Settings.steamFlow !== undefined ? de1Settings.steamFlow : ''}" step="0.1" min="0" max="10">
                            <button class="btn btn-primary" onclick="updateDe1Setting('steamFlow', parseFloat(document.getElementById('steamFlow').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Tank Temperature (°C)</span>
                        <div class="setting-control">
                            <input type="number" id="tankTemp" value="${de1Settings.tankTemp !== undefined ? de1Settings.tankTemp : ''}" step="1" min="0" max="100">
                            <button class="btn btn-primary" onclick="updateDe1Setting('tankTemp', parseInt(document.getElementById('tankTemp').value))">Save</button>
                        </div>
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
                        <span class="setting-label">Heater Phase 1 Flow (ml/s)</span>
                        <div class="setting-control">
                            <input type="number" id="heaterPh1Flow" value="${de1AdvancedSettings.heaterPh1Flow !== undefined ? de1AdvancedSettings.heaterPh1Flow : ''}" step="0.1" min="0" max="10">
                            <button class="btn btn-primary" onclick="updateDe1AdvancedSetting('heaterPh1Flow', parseFloat(document.getElementById('heaterPh1Flow').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Heater Phase 2 Flow (ml/s)</span>
                        <div class="setting-control">
                            <input type="number" id="heaterPh2Flow" value="${de1AdvancedSettings.heaterPh2Flow !== undefined ? de1AdvancedSettings.heaterPh2Flow : ''}" step="0.1" min="0" max="10">
                            <button class="btn btn-primary" onclick="updateDe1AdvancedSetting('heaterPh2Flow', parseFloat(document.getElementById('heaterPh2Flow').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Heater Idle Temperature (°C)</span>
                        <div class="setting-control">
                            <input type="number" id="heaterIdleTemp" value="${de1AdvancedSettings.heaterIdleTemp !== undefined ? de1AdvancedSettings.heaterIdleTemp : ''}" step="0.1" min="0" max="100">
                            <button class="btn btn-primary" onclick="updateDe1AdvancedSetting('heaterIdleTemp', parseFloat(document.getElementById('heaterIdleTemp').value))">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Heater Phase 2 Timeout (s)</span>
                        <div class="setting-control">
                            <input type="number" id="heaterPh2Timeout" value="${de1AdvancedSettings.heaterPh2Timeout !== undefined ? de1AdvancedSettings.heaterPh2Timeout : ''}" step="0.1" min="0" max="300">
                            <button class="btn btn-primary" onclick="updateDe1AdvancedSetting('heaterPh2Timeout', parseFloat(document.getElementById('heaterPh2Timeout').value))">Save</button>
                        </div>
                    </div>
                </div>
            ` : '<div class="error">Failed to load DE1 advanced settings (machine may not be connected)</div>'}
        </div>
    </div>

    <script>
        function showToast(message, isError = false) {
            const toast = document.createElement('div');
            toast.className = isError ? 'error-toast' : 'success-toast';
            toast.textContent = message;
            document.body.appendChild(toast);
            
            setTimeout(() => {
                toast.remove();
            }, 3000);
        }

        async function updateReaSetting(key, value) {
            try {
                const payload = {};
                payload[key] = value;
                
                const response = await fetch('http://localhost:8080/api/v1/settings', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok) {
                    showToast('REA setting updated successfully');
                    document.getElementById('timestamp').textContent = new Date().toLocaleString();
                } else {
                    const error = await response.text();
                    showToast('Failed to update REA setting: ' + error, true);
                }
            } catch (e) {
                showToast('Error updating REA setting: ' + e.message, true);
            }
        }

        async function updateDe1Setting(key, value) {
            try {
                const payload = {};
                payload[key] = value;
                
                const response = await fetch('http://localhost:8080/api/v1/de1/settings', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok || response.status === 202) {
                    showToast('DE1 setting updated successfully');
                    document.getElementById('timestamp').textContent = new Date().toLocaleString();
                } else {
                    const error = await response.text();
                    showToast('Failed to update DE1 setting: ' + error, true);
                }
            } catch (e) {
                showToast('Error updating DE1 setting: ' + e.message, true);
            }
        }

        async function updateDe1AdvancedSetting(key, value) {
            try {
                const payload = {};
                payload[key] = value;
                
                const response = await fetch('http://localhost:8080/api/v1/de1/settings/advanced', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok || response.status === 202) {
                    showToast('DE1 advanced setting updated successfully');
                    document.getElementById('timestamp').textContent = new Date().toLocaleString();
                } else {
                    const error = await response.text();
                    showToast('Failed to update DE1 advanced setting: ' + error, true);
                }
            } catch (e) {
                showToast('Error updating DE1 advanced setting: ' + e.message, true);
            }
        }
    </script>
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

