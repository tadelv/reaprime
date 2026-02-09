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
   * Fetch available WebUI skins
   */
  async function fetchWebUISkins() {
    try {
      const res = await fetch("http://localhost:8080/api/v1/webui/skins");
      if (!res.ok) {
        log(`Failed to fetch WebUI skins: ${res.status}`);
        return null;
      }
      return await res.json();
    } catch (e) {
      log(`Error fetching WebUI skins: ${e.message}`);
      return null;
    }
  }

  /**
   * Fetch machine settings
   */
  async function fetchDe1Settings() {
    try {
      const res = await fetch("http://localhost:8080/api/v1/machine/settings");
      if (!res.ok) {
        log(`Failed to fetch machine settings: ${res.status}`);
        return null;
      }
      return await res.json();
    } catch (e) {
      log(`Error fetching machine settings: ${e.message}`);
      return null;
    }
  }

  /**
   * Fetch machine advanced settings
   */
  async function fetchDe1AdvancedSettings() {
    try {
      const res = await fetch("http://localhost:8080/api/v1/machine/settings/advanced");
      if (!res.ok) {
        log(`Failed to fetch machine advanced settings: ${res.status}`);
        return null;
      }
      return await res.json();
    } catch (e) {
      log(`Error fetching machine advanced settings: ${e.message}`);
      return null;
    }
  }

  /**
   * Generate HTML page with all settings (with editable controls)
   */
  function generateSettingsHTML(reaSettings, de1Settings, de1AdvancedSettings, webUISkins) {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="REA Prime Settings Dashboard - Configure application and DE1 machine settings">
    <title>REA Settings Dashboard</title>
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
            border: 2px solid #999;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            width: 120px;
        }
        input[type="number"]:focus, input[type="text"]:focus, select:focus {
            outline: 3px solid #3498db;
            outline-offset: 2px;
            border-color: #3498db;
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
            font-weight: 600;
            transition: background 0.2s, transform 0.1s;
        }
        .btn:focus {
            outline: 3px solid #2c3e50;
            outline-offset: 2px;
        }
        .btn:active {
            transform: translateY(1px);
        }
        .btn-primary {
            background: #2980b9;
            color: white;
        }
        .btn-primary:hover, .btn-primary:focus {
            background: #1f5f8b;
        }
        .btn-refresh {
            background: #27ae60;
            color: white;
        }
        .btn-refresh:hover, .btn-refresh:focus {
            background: #1e8449;
        }
        .skip-link {
            position: absolute;
            top: -40px;
            left: 0;
            background: #2c3e50;
            color: white;
            padding: 8px 16px;
            text-decoration: none;
            border-radius: 0 0 4px 0;
            z-index: 100;
        }
        .skip-link:focus {
            top: 0;
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
            color: #555;
            font-family: 'Courier New', monospace;
        }
        .visually-hidden {
            position: absolute;
            left: -10000px;
            width: 1px;
            height: 1px;
            overflow: hidden;
        }
    </style>
</head>
<body>
    <a href="#main-content" class="skip-link">Skip to main content</a>
    <div class="container">
        <header class="header">
            <h1 id="page-title">REA Settings Dashboard</h1>
            <button class="btn btn-refresh" onclick="location.reload()" aria-label="Refresh all settings from server">
                Refresh
            </button>
        </header>
        <div class="timestamp" role="status" aria-live="polite" aria-atomic="true">
            <span class="status-indicator ${reaSettings && de1Settings ? 'status-ok' : 'status-error'}" 
                  role="img" 
                  aria-label="${reaSettings && de1Settings ? 'Settings loaded successfully' : 'Error loading settings'}"></span>
            Last updated: <span id="timestamp">${new Date().toLocaleString()}</span>
        </div>

        <main id="main-content">
            <!-- REA Application Settings -->
            <section class="section" aria-labelledby="rea-settings-heading">
                <h2 id="rea-settings-heading">REA Application Settings</h2>
            ${reaSettings ? `
                <div class="settings-grid" role="group" aria-label="REA application settings controls">
                    <div class="setting-item">
                        <label class="setting-label" for="gatewayMode">Gateway Mode</label>
                        <div class="setting-control">
                            <select id="gatewayMode" aria-describedby="gatewayMode-desc">
                                <option value="disabled" ${reaSettings.gatewayMode === 'disabled' ? 'selected' : ''}>Disabled</option>
                                <option value="tracking" ${reaSettings.gatewayMode === 'tracking' ? 'selected' : ''}>Tracking</option>
                                <option value="full" ${reaSettings.gatewayMode === 'full' ? 'selected' : ''}>Full</option>
                            </select>
                            <span id="gatewayMode-desc" class="visually-hidden">Controls how the gateway monitors and controls the espresso machine</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('gatewayMode', document.getElementById('gatewayMode').value)" aria-label="Save gateway mode setting">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <label class="setting-label" for="logLevel">Log Level</label>
                        <div class="setting-control">
                            <select id="logLevel" aria-describedby="logLevel-desc">
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
                            <span id="logLevel-desc" class="visually-hidden">Sets the verbosity of application logging output</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('logLevel', document.getElementById('logLevel').value)" aria-label="Save log level setting">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <span class="setting-label">Web UI Path</span>
                        <span class="readonly" aria-label="Web UI path is read-only">${reaSettings.webUiPath || 'N/A'}</span>
                    </div>
                    <div class="setting-item">
                        <label class="setting-label" for="weightFlowMultiplier">Weight Flow Multiplier</label>
                        <div class="setting-control">
                            <input type="number" id="weightFlowMultiplier" value="${reaSettings.weightFlowMultiplier !== undefined ? reaSettings.weightFlowMultiplier : 1.0}" step="0.1" min="0" max="5" aria-describedby="weightFlowMultiplier-desc">
                            <span id="weightFlowMultiplier-desc" class="visually-hidden">Multiplier for projected weight calculation. Higher values stop shots earlier.</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('weightFlowMultiplier', parseFloat(document.getElementById('weightFlowMultiplier').value))" aria-label="Save weight flow multiplier setting">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <label class="setting-label" for="volumeFlowMultiplier">Volume Flow Multiplier (s)</label>
                        <div class="setting-control">
                            <input type="number" id="volumeFlowMultiplier" value="${reaSettings.volumeFlowMultiplier !== undefined ? reaSettings.volumeFlowMultiplier : 0.3}" step="0.05" min="0" max="2" aria-describedby="volumeFlowMultiplier-desc">
                            <span id="volumeFlowMultiplier-desc" class="visually-hidden">Look-ahead time in seconds for projected volume calculation. Accounts for system lag.</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('volumeFlowMultiplier', parseFloat(document.getElementById('volumeFlowMultiplier').value))" aria-label="Save volume flow multiplier setting">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <label class="setting-label" for="scalePowerMode">Scale Power Management</label>
                        <div class="setting-control">
                            <select id="scalePowerMode" aria-describedby="scalePowerMode-desc">
                                <option value="disabled" ${reaSettings.scalePowerMode === 'disabled' ? 'selected' : ''}>Disabled</option>
                                <option value="displayOff" ${reaSettings.scalePowerMode === 'displayOff' ? 'selected' : ''}>Display Off</option>
                                <option value="disconnect" ${reaSettings.scalePowerMode === 'disconnect' ? 'selected' : ''}>Disconnect</option>
                            </select>
                            <span id="scalePowerMode-desc" class="visually-hidden">Controls automatic scale power management when machine sleeps. Display Off: turn off scale display. Disconnect: disconnect scale completely.</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('scalePowerMode', document.getElementById('scalePowerMode').value)" aria-label="Save scale power mode setting">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <label class="setting-label" for="preferredMachineId">Auto-Connect Device ID</label>
                        <div class="setting-control">
                            <input type="text" id="preferredMachineId" value="${reaSettings.preferredMachineId || ''}" placeholder="None set" aria-describedby="preferredMachineId-desc" style="width: 200px;">
                            <span id="preferredMachineId-desc" class="visually-hidden">Device ID for automatic connection on startup. Leave empty to disable auto-connect.</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('preferredMachineId', document.getElementById('preferredMachineId').value || null)" aria-label="Save preferred machine ID setting">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <label class="setting-label" for="defaultSkinId">Default WebUI Skin</label>
                        <div class="setting-control">
                            <select id="defaultSkinId" aria-describedby="defaultSkinId-desc" style="width: 200px;">
                                ${webUISkins ? webUISkins.map(skin => 
                                    `<option value="${skin.id}" ${reaSettings.defaultSkinId === skin.id ? 'selected' : ''}>${skin.name || skin.id}</option>`
                                ).join('') : '<option>Loading...</option>'}
                            </select>
                            <span id="defaultSkinId-desc" class="visually-hidden">WebUI skin to load by default on application startup</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('defaultSkinId', document.getElementById('defaultSkinId').value)" aria-label="Save default skin ID setting">Save</button>
                        </div>
                    </div>
                </div>
            ` : '<div class="error" role="alert" aria-live="assertive">Failed to load REA settings</div>'}
            </section>

            <!-- Machine Settings -->
            <section class="section" aria-labelledby="machine-settings-heading">
                <h2 id="machine-settings-heading">Machine Settings</h2>
            ${de1Settings ? `
                <div class="settings-grid" role="group" aria-label="Machine settings controls">
                    <div class="setting-item">
                        <label class="setting-label" for="fan">Fan Threshold (°C)</label>
                        <div class="setting-control">
                            <input type="number" id="fan" value="${de1Settings.fan !== undefined ? de1Settings.fan : ''}" step="1" min="0" max="100" aria-label="Fan threshold temperature in degrees Celsius">
                            <button class="btn btn-primary" onclick="updateDe1Setting('fan', parseInt(document.getElementById('fan').value))" aria-label="Save fan threshold setting">Save</button>
                        </div>
                    </div>
                    <div class="setting-item">
                        <label class="setting-label" for="usb">USB Charger Mode</label>
                        <div class="setting-control">
                            <select id="usb" aria-label="USB charger mode enabled or disabled">
                                <option value="enable" ${de1Settings.usb ? 'selected' : ''}>Enabled</option>
                                <option value="disable" ${!de1Settings.usb ? 'selected' : ''}>Disabled</option>
                            </select>
                            <button class="btn btn-primary" onclick="updateDe1Setting('usb', document.getElementById('usb').value)" aria-label="Save USB charger mode setting">Save</button>
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
                    <div class="setting-item">
                        <label class="setting-label" for="steamPurgeMode">Steam Purge Mode</label>
                        <div class="setting-control">
                            <select id="steamPurgeMode" aria-label="Steam purge mode - normal or two tap stop">
                                <option value="0" ${de1Settings.steamPurgeMode === 0 ? 'selected' : ''}>Normal</option>
                                <option value="1" ${de1Settings.steamPurgeMode === 1 ? 'selected' : ''}>Two Tap Stop</option>
                            </select>
                            <button class="btn btn-primary" onclick="updateDe1Setting('steamPurgeMode', parseInt(document.getElementById('steamPurgeMode').value))" aria-label="Save steam purge mode setting">Save</button>
                        </div>
                    </div>
                </div>
            ` : '<div class="error" role="alert">Failed to load machine settings (machine may not be connected)</div>'}
            </section>

            <!-- Machine Advanced Settings -->
            <section class="section" aria-labelledby="machine-advanced-settings-heading">
                <h2 id="machine-advanced-settings-heading">Machine Advanced Settings</h2>
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
            ` : '<div class="error" role="alert">Failed to load machine advanced settings (machine may not be connected)</div>'}
            </section>
        </main>
    </div>

    <!-- Screen reader announcements -->
    <div id="sr-announcements" role="status" aria-live="polite" aria-atomic="true" class="visually-hidden"></div>

    <script>
        // Announce messages to screen readers
        function announceToScreenReader(message) {
            const announcer = document.getElementById('sr-announcements');
            announcer.textContent = message;
            // Clear after announcement
            setTimeout(() => {
                announcer.textContent = '';
            }, 1000);
        }

        function showToast(message, isError = false) {
            const toast = document.createElement('div');
            toast.className = isError ? 'error-toast' : 'success-toast';
            toast.setAttribute('role', isError ? 'alert' : 'status');
            toast.setAttribute('aria-live', isError ? 'assertive' : 'polite');
            toast.textContent = message;
            document.body.appendChild(toast);
            
            // Also announce to screen readers
            announceToScreenReader(message);
            
            setTimeout(() => {
                toast.remove();
            }, 3000);
        }

        const baseUrl = window.location.protocol + '//' + window.location.host;

        async function updateReaSetting(key, value) {
            try {
                const payload = {};
                payload[key] = value;
                
                const response = await fetch(baseUrl + '/api/v1/settings', {
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
                
                const response = await fetch(baseUrl + '/api/v1/machine/settings', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok || response.status === 202) {
                    showToast('Machine setting updated successfully');
                    document.getElementById('timestamp').textContent = new Date().toLocaleString();
                } else {
                    const error = await response.text();
                    showToast('Failed to update machine setting: ' + error, true);
                }
            } catch (e) {
                showToast('Error updating machine setting: ' + e.message, true);
            }
        }

        async function updateDe1AdvancedSetting(key, value) {
            try {
                const payload = {};
                payload[key] = value;
                
                const response = await fetch(baseUrl + '/api/v1/machine/settings/advanced', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok || response.status === 202) {
                    showToast('Machine advanced setting updated successfully');
                    document.getElementById('timestamp').textContent = new Date().toLocaleString();
                } else {
                    const error = await response.text();
                    showToast('Failed to update machine advanced setting: ' + error, true);
                }
            } catch (e) {
                showToast('Error updating machine advanced setting: ' + e.message, true);
            }
        }

        // Keyboard shortcuts
        document.addEventListener('keydown', function(e) {
            // Alt+R to refresh
            if (e.altKey && e.key === 'r') {
                e.preventDefault();
                location.reload();
                announceToScreenReader('Refreshing settings');
            }
        });

        // Improve form submission on Enter key
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && (e.target.tagName === 'SELECT' || e.target.type === 'number')) {
                e.preventDefault();
                const settingItem = e.target.closest('.setting-item');
                if (settingItem) {
                    const saveButton = settingItem.querySelector('.btn-primary');
                    if (saveButton) {
                        saveButton.click();
                    }
                }
            }
        });
    </script>
</body>
</html>`;
  }

  // Return the plugin object
  return {
    id: "settings.reaplugin",
    version: "0.0.8",

    onLoad(settings) {
      state.refreshInterval = settings.RefreshInterval !== undefined ? settings.RefreshInterval : 5;
      log(`Loaded with refresh interval: ${state.refreshInterval}s`);
    },

    onUnload() {
      log("Unloaded");
    },

    // HTTP request handler for the 'ui' endpoint
    __httpRequestHandler(request) {
      log(`Received HTTP request for ${request.endpoint}: ${request.method}`);

      if (request.endpoint === "ui") {
        // Fetch all settings and generate HTML
        return Promise.all([
          fetchReaSettings(),
          fetchDe1Settings(),
          fetchDe1AdvancedSettings(),
          fetchWebUISkins()
        ]).then(([reaSettings, de1Settings, de1AdvancedSettings, webUISkins]) => {
          const html = generateSettingsHTML(reaSettings, de1Settings, de1AdvancedSettings, webUISkins);
          
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













