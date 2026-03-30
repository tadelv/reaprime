/* Stremline-settings.reaplugin
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

  const API_BASE_URL = "http://localhost:8080/api/v1";
  const SEARCH_RESULTS_MAIN_KEY = '__search_results__';
  const STORAGE_KEYS = {
    wakeLockEnabled: 'wakeLockEnabled',
    presenceActiveHours: 'settingsPresenceActiveHours',
  };

  const settingsCache = {
    rea: null,
    de1: null,
    de1Advanced: null,
    appInfo: null,
    machineInfo: null,
    reaLoading: false,
    de1Loading: false,
    de1AdvancedLoading: false,
    appInfoLoading: false,
    machineInfoLoading: false,
    reaError: null,
    de1Error: null,
    de1AdvancedError: null,
    appInfoError: null,
    machineInfoError: null,
  };

  let settingsLoadingPromise = null;

  // Settings Tree Structure for Navigation
  const settingsTree = {
    'quickadjustments': {
        name: '1. Quick Adjustments',
        subcategories: [
            { id: 'flowmultiplier', name: 'Flow Multiplier', settingsCategory: 'flowmultiplier' },
            { id: 'steam', name: 'Steam', settingsCategory: 'steam' },
            { id: 'hotwater', name: 'Hot Water', settingsCategory: 'hotwater' },
            { id: 'watertank', name: 'Water Tank', settingsCategory: 'watertank' },
            { id: 'flush', name: 'Flush', settingsCategory: 'flush' }
        ]
    },
    'bluetooth': {
        name: '2. Bluetooth',
        subcategories: [
            { id: 'ble_machine', name: '1. Machine', settingsCategory: 'ble_machine' },
            { id: 'ble_scale', name: '2. Scale', settingsCategory: 'ble_scale' }
        ]
    },
    'calibration': {
        name: '3. Calibration',
        subcategories: [
            { id: 'defaultloadsettings', name: 'Default load settings', settingsCategory: 'calibration' },
            { id: 'refillkit', name: 'Refill Kit', settingsCategory: 'refillkit' },
            { id: 'voltage', name: 'Voltage', settingsCategory: 'voltage' },
            { id: 'fan', name: 'Fan', settingsCategory: 'fan' },
            { id: 'stopatweight', name: 'Stop at weight', settingsCategory: 'stopatweight' },
            { id: 'slowstart', name: 'Slow start', settingsCategory: 'slowstart' },
            { id: 'steam_cal', name: 'Steam', settingsCategory: 'steam' }
        ]
    },
    'machine': {
        name: '4. Machine',
        subcategories: [
            { id: 'fanthreshold', name: 'Fan Threshold', settingsCategory: 'fanthreshold' },
            { id: 'usbchargermode', name: 'USB Charger Mode', settingsCategory: 'usbchargermode' }
        ]
    },
    'maintenance': {
        name: '5. Maintenance',
        subcategories: [
            { id: 'machinedescaling', name: 'Machine Descaling', settingsCategory: 'maintenance' },
            { id: 'transportmode', name: 'Transport mode', settingsCategory: 'transportmode' }
        ]
    },
    'skin': {
        name: '6. Skin',
        subcategories: [
            { id: 'skin1', name: 'Theme', settingsCategory: 'appearance' }
        ]
    },
    'language': {
        name: '7. Language',
        subcategories: [
            { id: 'selectlanguage', name: 'Select Language', settingsCategory: 'language' }
        ]
    },
    'extensions': {
        name: '8. Extensions',
        subcategories: [
            { id: 'extention1', name: 'Visualizer', settingsCategory: 'extensions' },
            { id: 'extention2', name: 'Extention 2', settingsCategory: 'extensions' }
        ]
    },
    'miscellaneous': {
        name: '9. Miscellaneous',
        subcategories: [
            { id: 'reasettings', name: 'Rea settings', settingsCategory: 'rea' },
            { id: 'brightness', name: 'Brightness', settingsCategory: 'brightness' },
            { id: 'wakelock', name: 'Wake Lock', settingsCategory: 'wakelock' },
            { id: 'presence', name: 'Presence Detection', settingsCategory: 'presence' },
            { id: 'appversion', name: 'App Version', settingsCategory: 'updates' },
            { id: 'unitssettings', name: 'Units Settings', settingsCategory: 'language' },
            { id: 'fontsize', name: 'Font Size', settingsCategory: 'appearance' },
            { id: 'resolution', name: 'Resolution', settingsCategory: 'appearance' },
            { id: 'smartcharging', name: 'Smart Charging', settingsCategory: 'de1' },
            { id: 'screensaver', name: 'Screen Saver', settingsCategory: 'misc' },
            { id: 'machineadvancedsettings', name: 'Machine Advanced Settings', settingsCategory: 'de1advanced' }
        ]
    },
    'updates': {
        name: '10. Updates',
        subcategories: [
            { id: 'firmwareupdate', name: 'Firmware Update', settingsCategory: 'updates' },
            { id: 'appupdate', name: 'App Update', settingsCategory: 'updates' }
        ]
    },
    'usermanual': {
        name: '11. User Manual',
        subcategories: [
            { id: 'onlinehelp', name: 'Online Help', settingsCategory: 'help' },
            { id: 'tutorials', name: 'Tutorials', settingsCategory: 'help' }
        ]
    }
  };

  let activeSettingsCategory = null;
  let activeMainCategoryKey = 'quickadjustments';

  function log(msg) {
    host.log(`[settings] ${msg}`);
  }

  function formatMachineExtra(extra) {
    if (!extra || typeof extra !== 'object') {
      return 'N/A';
    }

    const entries = Object.entries(extra);
    if (entries.length === 0) {
      return 'N/A';
    }

    return entries
      .map(([key, value]) => {
        const readableKey = key
          .replace(/([A-Z])/g, ' $1')
          .replace(/^./, (char) => char.toUpperCase());
        const readableValue = typeof value === 'boolean' ? (value ? 'on' : 'off') : String(value);
        return `${readableKey} : ${readableValue}`;
      })
      .join(', ');
  }

  function formatBuildTimestamp(timestamp) {
    if (!timestamp) {
      return 'Unavailable';
    }

    const parsed = new Date(timestamp);
    if (Number.isNaN(parsed.getTime())) {
      return timestamp;
    }

    return parsed.toLocaleString();
  }

  function readStoredActiveHours() {
    try {
      const stored = localStorage.getItem(STORAGE_KEYS.presenceActiveHours);
      return stored ? JSON.parse(stored) : [];
    } catch (error) {
      log(`Failed to read stored active hours: ${error.message}`);
      return [];
    }
  }

  function writeStoredActiveHours(activeHours) {
    localStorage.setItem(STORAGE_KEYS.presenceActiveHours, JSON.stringify(activeHours));
  }

  function getActiveHours() {
    const activeHours = readStoredActiveHours();
    return Array.isArray(activeHours) ? activeHours : [];
  }

  function addActiveHour(activeHour) {
    const activeHours = getActiveHours();
    activeHours.push({
      id: `active-hour-${Date.now()}`,
      ...activeHour,
    });
    writeStoredActiveHours(activeHours);
  }

  function updateActiveHour(id, updates) {
    const activeHours = getActiveHours();
    const nextHours = activeHours.map((activeHour) => (
      activeHour.id === id ? { ...activeHour, ...updates } : activeHour
    ));
    writeStoredActiveHours(nextHours);
  }

  function deleteActiveHour(id) {
    const activeHours = getActiveHours();
    writeStoredActiveHours(activeHours.filter((activeHour) => activeHour.id !== id));
  }

  async function fetchJson(endpoint, errorLabel) {
    const response = await fetch(`${API_BASE_URL}${endpoint}`);
    if (!response.ok) {
      const error = new Error(`Failed to fetch ${errorLabel}: ${response.status} ${response.statusText}`);
      error.status = response.status;
      throw error;
    }
    return response.json();
  }

  async function fetchReaSettings() {
    try {
      return await fetchJson('/settings', 'REA settings');
    } catch (e) {
      log(`Error fetching REA settings: ${e.message}`);
      return null;
    }
  }

  async function fetchWebUISkins() {
    try {
      return await fetchJson('/webui/skins', 'WebUI skins');
    } catch (e) {
      log(`Error fetching WebUI skins: ${e.message}`);
      return null;
    }
  }

  async function fetchDe1Settings() {
    try {
      return await fetchJson('/machine/settings', 'machine settings');
    } catch (e) {
      log(`Error fetching machine settings: ${e.message}`);
      return null;
    }
  }

  async function fetchCalibrationSettings() {
    try {
      return await fetchJson('/machine/calibration', 'calibration settings');
    } catch (e) {
      log(`Error fetching calibration settings: ${e.message}`);
      return null;
    }
  }

  async function fetchPresenceSettings() {
    try {
      return await fetchJson('/presence/settings', 'presence settings');
    } catch (e) {
      log(`Error fetching presence settings: ${e.message}`);
      return null;
    }
  }

  async function fetchDe1AdvancedSettings() {
    try {
      return await fetchJson('/machine/settings/advanced', 'advanced machine settings');
    } catch (e) {
      log(`Error fetching machine advanced settings: ${e.message}`);
      return null;
    }
  }

  async function fetchAppInfo() {
    try {
      return await fetchJson('/info', 'app info');
    } catch (e) {
      log(`Error fetching app info: ${e.message}`);
      return null;
    }
  }

  async function fetchMachineInfo() {
    try {
      return await fetchJson('/machine/info', 'machine info');
    } catch (e) {
      log(`Error fetching machine info: ${e.message}`);
      return null;
    }
  }

  async function preloadSettings() {
    if (settingsLoadingPromise) {
      return settingsLoadingPromise;
    }

    settingsLoadingPromise = (async () => {
      settingsCache.reaLoading = true;
      settingsCache.de1Loading = true;
      settingsCache.de1AdvancedLoading = true;
      settingsCache.appInfoLoading = true;
      settingsCache.machineInfoLoading = true;

      settingsCache.reaError = null;
      settingsCache.de1Error = null;
      settingsCache.de1AdvancedError = null;
      settingsCache.appInfoError = null;
      settingsCache.machineInfoError = null;

      try {
        const [reaResult, de1Result, de1AdvancedResult, appInfoResult, machineInfoResult] = await Promise.allSettled([
          fetchReaSettings(),
          fetchDe1Settings(),
          fetchDe1AdvancedSettings(),
          fetchAppInfo(),
          fetchMachineInfo(),
        ]);

        settingsCache.rea = reaResult.status === 'fulfilled' ? reaResult.value : null;
        settingsCache.de1 = de1Result.status === 'fulfilled' ? de1Result.value : null;
        settingsCache.de1Advanced = de1AdvancedResult.status === 'fulfilled' ? de1AdvancedResult.value : null;
        settingsCache.appInfo = appInfoResult.status === 'fulfilled' ? appInfoResult.value : null;
        settingsCache.machineInfo = machineInfoResult.status === 'fulfilled' ? machineInfoResult.value : null;

        settingsCache.reaError = reaResult.status === 'rejected' ? reaResult.reason?.message || 'Failed to load REA settings' : null;
        settingsCache.de1Error = de1Result.status === 'rejected' ? de1Result.reason?.message || 'Failed to load machine settings' : null;
        settingsCache.de1AdvancedError = de1AdvancedResult.status === 'rejected' ? de1AdvancedResult.reason?.message || 'Failed to load advanced settings' : null;
        settingsCache.appInfoError = appInfoResult.status === 'rejected' ? appInfoResult.reason?.message || 'Failed to load app info' : null;
        settingsCache.machineInfoError = machineInfoResult.status === 'rejected' ? machineInfoResult.reason?.message || 'Failed to load machine info' : null;

        return settingsCache;
      } finally {
        settingsCache.reaLoading = false;
        settingsCache.de1Loading = false;
        settingsCache.de1AdvancedLoading = false;
        settingsCache.appInfoLoading = false;
        settingsCache.machineInfoLoading = false;
        settingsLoadingPromise = null;
      }
    })();

    return settingsLoadingPromise;
  }

  function updateTimestamp() {
    const timestamp = document.getElementById('timestamp');
    if (timestamp) {
      timestamp.textContent = new Date().toLocaleString();
    }
  }

  /**
   * Generate HTML page with all settings (with editable controls)
   */
  function generateSettingsHTML(reaSettings, de1Settings, de1AdvancedSettings, webUISkins, calibrationSettings, presenceSettings, appInfo, machineInfo) {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="REA Prime Settings Dashboard - Configure application and DE1 machine settings">
    <title>Settings</title>
    
    <!-- Google Fonts CDN -->
    <link href="https://fonts.cdnfonts.com/css/noto-sans" rel="stylesheet">
    <link href="https://fonts.cdnfonts.com/css/inter" rel="stylesheet">
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://cdn.jsdelivr.net/npm/daisyui@5" rel="stylesheet" type="text/css" />

    <style>
        /* ============================================
           Base Styles - Viewport Setup
           ============================================ */
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
        }

        /* ============================================
           Design System Variables
           ============================================ */
        :root {
            /* Core colors from Design System */
            --mimoja-blue: #385A92;
            --mimoja-blue-v2: #415996;
            --white: #FFFFFF;
            --button-grey: #EDEDED;
            --low-contrast-white: #959595;
            --success-green: #0CA581;
            --error-red: #e74c3c;
            --status-red-color: #DA515E;

            /* Theme-aware colors (light mode default) */
            --profile-button-outline-color: #c5cdda;
            --profile-button-background-color: #FFFFFF;
            --box-color: #f8f9fb;
            --profileselectorbg: #FFFFFF;
            --text-primary: #121212;
            --text-secondary: #51639c;
            --preset-label-selected-color: #777777;
            --status-green-color: #0CA581;

            /* Typography */
            --font-family-primary: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            --font-family-mono: 'NotoSansMono', monospace;
        }
        
        /* Settings page specific layout styles */
        body {
            background: var(--bgmain-color);
            padding: 20px;
            line-height: 1.6;
            max-width: 1920px;
            max-height: 1200px;
            margin: 0 auto;
            /* overflow removed - was creating containing block for fixed elements */
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            color: var(--text-primary);
            margin-bottom: 10px;
            font-size: 2em;
            font-weight: 600;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        .timestamp {
            color: var(--text-primary);
            font-size: 0.9em;
        }
        .section {
            background: var(--profile-button-background-color);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .section h2 {
            color: var(--text-primary);
            margin-bottom: 15px;
            font-size: 1.5em;
            font-weight: 600;
            border-bottom: 2px solid var(--mimoja-blue);
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
            background: var(--box-color);
            border-radius: 6px;
            border-left: 3px solid var(--mimoja-blue);
        }
        .setting-label {
            font-weight: 600;
            color: var(--text-primary);
            flex: 1;
        }
        .setting-control {
            display: flex;
            gap: 8px;
            align-items: center;
        }
        input[type="number"], input[type="text"], select {
            
            border: 2px solid var(--low-contrast-white);
            border-radius: 4px;
            font-family: 'NotoSansMono', monospace;
            font-size: 14px;
            
            background: var(--profileselectorbg);
            color: var(--text-primary);
        }
        input[type="number"]:focus, input[type="text"]:focus, select:focus {
            outline: 3px solid var(--mimoja-blue);
            outline-offset: 2px;
            border-color: var(--mimoja-blue);
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
            font-family: 'Inter', sans-serif;
        }
        .btn:focus {
            outline: 3px solid var(--text-primary);
            outline-offset: 2px;
        }
        .btn:active {
            transform: translateY(1px);
        }
        .btn-primary {
            background: var(--mimoja-blue);
            color: var(--white);
        }
        .btn-primary:hover, .btn-primary:focus {
            background: var(--mimoja-blue-v2);
        }
        .btn-refresh {
            background: var(--status-green-color);
            color: white;
        }
        .btn-refresh:hover, .btn-refresh:focus {
            background: #0a8a6c;
        }
        .skip-link {
            position: absolute;
            top: -40px;
            left: 0;
            background: var(--text-primary);
            color: var(--white);
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
            border-left-color: var(--status-red-color);
            color: #c0392b;
            padding: 12px;
            border-radius: 6px;
        }
        .readonly {
            color: var(--preset-label-selected-color);
            font-family: 'NotoSansMono', monospace;
        }
        
        /* Toast notifications */
        .success-toast {
            position: fixed;
            top: 20px;
            right: 20px;
            background: var(--status-green-color);
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
            background: var(--status-red-color);
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
        
        /* Status indicator */
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        
        .status-ok {
            background: var(--status-green-color);
        }
        
        .status-error {
            background: var(--status-red-color);
        }
        
        /* Accessibility */
        .visually-hidden {
            position: absolute;
            left: -10000px;
            width: 1px;
            height: 1px;
            overflow: hidden;
        }
        
        /* New flexbox layout classes (matching settings.js design) */
        .settings-container {
            display: flex;
            flex-direction: column;
            gap: 60px;
            align-items: flex-start;
            position: relative;
            width: 100%;
            max-width: 100%;
            overflow-x: hidden;
        }
        
        .settings-section {
            display: flex;
            flex-direction: column;
            gap: 30px;
            align-items: flex-start;
            position: relative;
            width: 100%;
            max-width: 100%;
        }
        
        .setting-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            position: relative;
            width: 100%;
            max-width: 885px;
        }
        
        .setting-label-bold {
            display: flex;
            flex-direction: column;
            font-family: 'Inter', sans-serif;
            font-weight: 700;
            justify-content: center;
            line-height: 0;
            not-italic: true;
            position: relative;
            color: var(--mimoja-blue);
            font-size: 30px;
        }
        
        .setting-label-bold p {
            line-height: 1.2;
        }
        
        .setting-description {
            font-family: 'Inter', sans-serif;
            font-weight: 400;
            line-height: 1.4;
            position: relative;
            color: var(--text-primary);
            font-size: 24px;
            width: 100%;
            max-width: 100%;
            word-break: break-word;
        }
        
        .divider {
            height: 0;
            position: relative;
            width: 100%;
        }
        
        .divider hr {
            border-top: 1px solid var(--low-contrast-white);
            width: 100%;
        }
        
        .settings-title {
            display: flex;
            flex-direction: column;
            font-family: 'Inter', sans-serif;
            font-weight: 600;
            justify-content: center;
            line-height: 0;
            not-italic: true;
            position: relative;
            color: var(--text-primary);
            font-size: 36px;
            text-align: center;
            width: 100%;
        }
        
        .settings-title p {
            line-height: 1.2;
        }
        
        /* ============================================
           NEW FLEXBOX LAYOUT (settings.js parity)
           ============================================ */
        
        .settings-flex-container {
            display: flex;
            flex-direction: column;
            gap: 60px;
            align-items: flex-start;
            position: relative;
            width: 100%;
            max-width: 100%;
            overflow-x: hidden;
            padding: 20px;
        }
        
        .settings-section-flex {
            display: flex;
            flex-direction: column;
            gap: 30px;
            align-items: flex-start;
            position: relative;
            width: 100%;
            max-width: 100%;
        }
        
        .settings-page-title {
            font-family: 'Inter', sans-serif;
            font-weight: 600;
            color: var(--text-primary);
            font-size: 36px;
            text-align: center;
            width: 100%;
            line-height: 1.2;
        }
        
        .setting-row-flex {
            display: flex;
            align-items: center;
            justify-content: space-between;
            position: relative;
            width: 100%;
            max-width: 885px;
        }
        
        .setting-row-flex-column {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            gap: 20px;
            position: relative;
            width: 100%;
            max-width: 885px;
        }
        
        .setting-label-bold {
            font-family: 'Inter', sans-serif;
            font-weight: 700;
            color: var(--mimoja-blue);
            font-size: 30px;
            line-height: 1.2;
        }
        
        .setting-label-bold p {
            line-height: 1.2;
        }
        
        .setting-description {
            font-family: 'Inter', sans-serif;
            font-weight: 400;
            line-height: 1.4;
            color: var(--text-primary);
            font-size: 24px;
            width: 100%;
            max-width: 100%;
            word-break: break-word;
        }
        
        .settings-divider {
            height: 0;
            position: relative;
            width: 100%;
        }
        
        .settings-divider hr {
            border-top: 1px solid #c9c9c9;
            width: 100%;
        }
        
        .settings-input-primary {
            background: var(--mimoja-blue);
            border: 2px solid var(--mimoja-blue);
            border-style: solid;
            height: 62.88px;
            border-radius: 10px;
            width: 150px;
            color: var(--white);
            font-size: 24px;
            padding: 8px;
            text-align: center;
            font-family: 'Inter', sans-serif;
            max-width: 150px;
        }
        
        .settings-input-primary:focus {
            outline: 3px solid var(--white);
            outline-offset: 2px;
        }
        
        .settings-input-wide {
            background: var(--mimoja-blue);
            border: 2px solid var(--mimoja-blue);
            border-style: solid;
            height: 62.88px;
            border-radius: 2617.374px;
            width: 250px;
            color: var(--white);
            font-size: 24px;
            padding: 8px;
            font-family: 'Inter', sans-serif;
            max-width: 250px;
        }
        
        .settings-input-wide:focus {
            outline: 3px solid var(--white);
            outline-offset: 2px;
        }
        
        .settings-input-text {
            background: var(--mimoja-blue);
            border: 2px solid var(--mimoja-blue);
            border-style: solid;
            height: 62.88px;
            border-radius: 10px;
            width: 200px;
            color: var(--white);
            font-size: 24px;
            padding: 8px;
            font-family: 'Inter', sans-serif;
        }
        
        .settings-input-text:focus {
            outline: 3px solid var(--white);
            outline-offset: 2px;
        }
        
        .settings-btn-primary {
            background: var(--mimoja-blue);
            height: 62.88px;
            border-radius: 10px;
            width: 100px;
            color: var(--white);
            font-size: 24px;
            font-weight: 700;
            border: none;
            cursor: pointer;
            transition: background 0.2s, transform 0.1s;
            font-family: 'Inter', sans-serif;
            max-width: 100px;
        }
        
        .settings-btn-primary:hover {
            background: var(--mimoja-blue-v2);
        }
        
        .settings-btn-primary:active {
            transform: translateY(1px);
        }
        
        .settings-btn-primary:focus {
            outline: 3px solid var(--white);
            outline-offset: 2px;
        }
        
        .settings-btn-wide {
            background: var(--mimoja-blue);
            height: 62.88px;
            border-radius: 10px;
            width: 200px;
            color: var(--white);
            font-size: 24px;
            font-weight: 700;
            border: none;
            cursor: pointer;
            transition: background 0.2s, transform 0.1s;
            font-family: 'Inter', sans-serif;
        }
        
        .settings-btn-wide:hover {
            background: var(--mimoja-blue-v2);
        }
        
        .settings-btn-secondary {
            background: transparent;
            border: 2px solid var(--mimoja-blue);
            color: var(--mimoja-blue);
            height: 62.88px;
            border-radius: 10px;
            width: 100px;
            font-size: 24px;
            font-weight: 700;
            cursor: pointer;
            transition: all 0.2s;
            font-family: 'Inter', sans-serif;
            max-width: 100px;
        }
        
        .settings-btn-secondary:hover {
            background: var(--mimoja-blue);
            color: var(--white);
        }
        
        .settings-btn-secondary:active {
            transform: translateY(1px);
        }
        
        .settings-btn-secondary:focus {
            outline: 3px solid var(--white);
            outline-offset: 2px;
        }
        
        .setting-control-flex {
            display: flex;
            align-items: center;
            gap: 16px;
        }
        
        .toggle-button-group {
            display: flex;
            align-items: center;
            justify-content: space-between;
            width: 100%;
            max-width: 885px;
            gap: 16px;
        }
        
        .toggle-btn {
            height: 120px;
            width: 295px;
            border-radius: 10px;
            font-family: 'Inter', sans-serif;
            font-weight: 700;
            font-size: 30px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: background 0.2s, color 0.2s;
            border: 2px solid transparent;
        }
        
        .toggle-btn.active {
            background: var(--mimoja-blue);
            color: var(--white);
        }
        
        .toggle-btn.inactive {
            background: var(--box-color);
            border-color: var(--profile-button-outline-color);
            color: #b6c3d7;
        }
        
        .settings-loading-state,
        .settings-error-state {
            display: flex;
            flex-direction: column;
            gap: 60px;
            align-items: flex-start;
            position: relative;
            width: 100%;
            max-width: 100%;
            overflow-x: hidden;
        }
        
        .settings-error-text {
            color: var(--error-red);
            padding: 16px;
            font-size: 24px;
            text-align: center;
            width: 100%;
        }

        /* ============================================
           Toast Notifications
           ============================================ */
        .toast-container {
            position: fixed !important;
            bottom: 100px !important;
            left: 40% !important;
            right: auto !important;
            transform: translateX(-50%) !important;
            z-index: 99999 !important;
            display: flex !important;
            flex-direction: column-reverse !important;
            align-items: center !important;
            justify-content: flex-start !important;
            gap: 8px;
            width: 90%;
            max-width: 900px;
            pointer-events: none;
        }

        .toast {
            padding: 16px 32px !important;
            border-radius: 12px;
            box-shadow: 0 8px 24px rgba(0,0,0,0.2);
            animation: slideIn 0.4s ease-out;
            width: auto !important;
            min-width: 600px !important;
            max-width: 100% !important;
            text-align: center !important;
            font-size: 20px !important;
            font-weight: 400 !important;
            font-family: 'Inter', sans-serif !important;
            letter-spacing: 0.5px;
            word-wrap: break-word;
            white-space: normal !important;
            display: block !important;
            pointer-events: auto;
            opacity: 1;
            transition: opacity 0.3s ease-out;
        }

        .toast-success {
            background: var(--success-green);
            color: var(--white);
        }

        .toast-error {
            background: var(--status-red-color);
            color: var(--white);
        }

        .toast-info {
            background: var(--mimoja-blue);
            color: var(--white);
        }

        .toast.fade-out {
            opacity: 0;
        }

        @keyframes slideIn {
            from {
                transform: translateY(100px);
                opacity: 0;
            }
            to {
                transform: translateY(0);
                opacity: 1;
            }
        }

        /* ============================================
           Header (Settings.js Pattern)
           ============================================ */
        .settings-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 20px;
            border-bottom: 2px solid var(--low-contrast-white);
            background: var(--box-color);
            margin-bottom: 20px;
        }

        .settings-header h1 {
            font-size: 28px;
            font-weight: 700;
            color: var(--text-primary);
            margin: 0;
        }

        .header-actions {
            display: flex;
            gap: 22px;
            align-items: center;
        }

        .btn-cancel {
            background: transparent;
            border: 2px solid var(--mimoja-blue);
            color: var(--mimoja-blue);
            height: 82.5px;
            width: 240px;
            border-radius: 67.5px;
            font-size: 24px;
            font-weight: 700;
            cursor: pointer;
            transition: all 0.2s;
            font-family: 'Inter', sans-serif;
        }

        .btn-cancel:hover {
            background: var(--mimoja-blue);
            color: var(--white);
        }

        .btn-save {
            background: var(--mimoja-blue);
            color: var(--white);
            height: 82.5px;
            width: 240px;
            border-radius: 67.5px;
            font-size: 24px;
            font-weight: 700;
            border: none;
            cursor: pointer;
            transition: all 0.2s;
            font-family: 'Inter', sans-serif;
        }

        .btn-save:hover {
            background: var(--mimoja-blue-v2);
        }

        /* ============================================
           Device Card (Bluetooth)
           ============================================ */
        .device-card {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: var(--profile-button-background-color);
            border-radius: 10px;
            margin-bottom: 12px;
            padding: 16px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .device-info {
            flex: 1;
            min-width: 0;
        }

        .device-header {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 8px;
        }

        .device-status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
        }

        .device-status-dot.connected {
            background-color: #22c55e;
        }

        .device-status-dot.disconnected {
            background-color: #ef4444;
        }

        .device-name {
            font-size: 24px;
            color: var(--text-primary);
            font-weight: 600;
        }

        .device-detail {
            font-size: 18px;
            color: var(--text-secondary);
            margin: 4px 0;
        }

        .device-status-text {
            font-size: 18px;
            font-weight: 600;
        }

        .device-status-text.connected {
            color: #22c55e;
        }

        .device-status-text.disconnected {
            color: #ef4444;
        }

        .btn-connect {
            background: var(--mimoja-blue);
            color: var(--white);
            height: 60px;
            border-radius: 67.5px;
            width: 120px;
            font-size: 18px;
            font-weight: 600;
            border: none;
            cursor: pointer;
            transition: all 0.2s;
            font-family: 'Inter', sans-serif;
            margin-left: 16px;
        }

        .btn-connect:hover {
            background: var(--mimoja-blue-v2);
        }

        /* ============================================
           Stepper (Plus/Minus)
           ============================================ */
        .stepper-container {
            border: 2px solid #c9c9c9;
            border-radius: 10px;
            padding: 30px 60px;
            display: flex;
            flex-direction: column;
            gap: 30px;
            align-items: center;
            width: 590px;
        }

        .stepper-controls {
            display: flex;
            gap: 20px;
            height: 72px;
            align-items: center;
            justify-content: center;
            width: 100%;
        }

        .stepper-button {
            width: 72px;
            height: 72px;
            background: var(--button-grey);
            border-radius: 20px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: background 0.2s;
            border: none;
        }

        .stepper-button:hover {
            background: var(--low-contrast-white);
        }

        .stepper-button svg {
            stroke: var(--text-primary);
        }

        .stepper-input-container {
            text-align: center;
            font-size: 24px;
            font-weight: 700;
            color: var(--text-primary);
            width: 130px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: transparent;
            border: none;
        }

        .stepper-input {
            background: transparent;
            border: none;
            text-align: center;
            font-size: 24px;
            font-weight: 700;
            color: var(--text-primary);
            width: 100%;
            padding: 0;
            font-family: 'Inter', sans-serif;
        }

        .stepper-input:focus {
            outline: none;
        }

        .stepper-unit {
            margin-left: 8px;
            white-space: nowrap;
            font-size: 24px;
            color: var(--text-primary);
        }

        /* ============================================
           Toggle Switch (Checkbox)
           ============================================ */
        .toggle-switch {
            position: relative;
            display: inline-flex;
            align-items: center;
            cursor: pointer;
        }

        .toggle-switch input {
            opacity: 0;
            width: 0;
            height: 0;
            position: absolute;
        }

        .toggle-slider {
            width: 44px;
            height: 24px;
            background-color: var(--text-secondary);
            border-radius: 24px;
            position: relative;
            transition: 0.2s;
        }

        .toggle-slider:before {
            position: absolute;
            content: "";
            height: 20px;
            width: 20px;
            left: 2px;
            bottom: 2px;
            background-color: white;
            border-radius: 50%;
            transition: 0.2s;
        }

        .toggle-switch input:checked + .toggle-slider {
            background-color: var(--mimoja-blue);
        }

        .toggle-switch input:checked + .toggle-slider:before {
            transform: translateX(20px);
        }

        /* ============================================
           Scan Button
           ============================================ */
        .btn-scan {
            border: 2px solid var(--mimoja-blue);
            color: var(--mimoja-blue);
            height: 62px;
            border-radius: 67.5px;
            width: 139px;
            font-size: 24px;
            font-weight: 600;
            background: transparent;
            cursor: pointer;
            transition: all 0.2s;
            font-family: 'Inter', sans-serif;
        }

        .btn-scan:hover {
            background: var(--mimoja-blue);
            color: var(--white);
        }

        /* ============================================
           Read-only Value
           ============================================ */
        .readonly-value {
            color: var(--preset-label-selected-color);
            font-family: var(--font-family-mono);
            font-size: 24px;
        }

        /* Override generic input styles for Visualizer form */
        .visualizer-input {
            border: 1px solid var(--border-color) !important;
            border-radius: 8px !important;
            font-family: 'Inter', sans-serif !important;
            font-size: 24px !important;
            background: var(--profile-button-background-color) !important;
            color: var(--text-primary) !important;
        }

        /* ============================================
           Two-Panel Navigation Layout
           ============================================ */
        .settings-layout {
            display: flex;
            height: calc(100vh - 200px);
            overflow: hidden;
        }

        /* Left Panel */
        .left-panel {
            width: 400px;
            min-width: 300px;
            max-width: 600px;
            display: flex;
            flex-direction: column;
            border-right: 2px solid var(--low-contrast-white);
            background: var(--box-color);
            overflow: hidden;
        }

        /* Search Bar */
        .search-container {
            padding: 20px;
            border-bottom: 2px solid var(--low-contrast-white);
        }

        .settings-search-input {
            width: 100%;
            padding: 12px 12px 12px 48px;
            border-radius: 8px;
            border: 2px solid var(--low-contrast-white);
            background: var(--profileselectorbg);
            color: var(--text-primary);
            font-size: 16px;
            font-family: 'Inter', sans-serif;
        }

        .settings-search-input:focus {
            outline: none;
            border-color: var(--mimoja-blue);
            box-shadow: 0 0 0 2px var(--mimoja-blue);
        }

        /* Navigation Container */
        .navigation-container {
            display: flex;
            flex: 1;
            overflow: hidden;
        }

        /* Main Categories Panel */
        .main-categories-panel {
            width: 250px;
            min-width: 200px;
            overflow-y: auto;
            padding: 10px;
            background: var(--box-color);
        }

        .main-category-btn {
            width: 100%;
            text-align: left;
            padding: 12px 16px;
            margin-bottom: 4px;
            border-radius: 8px;
            font-size: 20px;
            font-weight: 600;
            font-family: 'Inter', sans-serif;
            color: var(--text-secondary);
            background: transparent;
            border: none;
            cursor: pointer;
            transition: all 0.2s;
        }

        .main-category-btn:hover {
            color: var(--white);
            background: #2c4a7a;
        }

        .main-category-btn.active {
            color: var(--white);
            background: #2c4a7a;
        }

        /* Subcategories Panel */
        .subcategories-panel {
            width: 200px;
            min-width: 150px;
            overflow-y: auto;
            padding: 10px;
            background: var(--box-color);
            border-left: 1px solid var(--low-contrast-white);
        }

        .subcategory-btn {
            width: 100%;
            text-align: left;
            padding: 10px 14px;
            margin-bottom: 4px;
            border-radius: 6px;
            font-size: 16px;
            font-family: 'Inter', sans-serif;
            color: var(--text-secondary);
            background: transparent;
            border: none;
            cursor: pointer;
            transition: all 0.2s;
        }

        .subcategory-btn:hover {
            color: var(--white);
            background: #2c4a7a;
        }

        .subcategory-btn.active {
            background: var(--mimoja-blue);
            color: var(--white);
        }

        /* Panel Resizer */
        .panel-resizer {
            width: 4px;
            background: var(--low-contrast-white);
            cursor: col-resize;
            transition: background 0.2s;
        }

        .panel-resizer:hover {
            background: var(--mimoja-blue);
        }

        /* Right Panel - Content Area */
        .right-panel {
            flex: 1;
            overflow-y: auto;
            padding: 30px;
            background: var(--profile-button-background-color);
        }

        /* Scrollbar Styling */
        .main-categories-panel::-webkit-scrollbar,
        .subcategories-panel::-webkit-scrollbar,
        .right-panel::-webkit-scrollbar {
            width: 8px;
        }

        .main-categories-panel::-webkit-scrollbar-track,
        .subcategories-panel::-webkit-scrollbar-track,
        .right-panel::-webkit-scrollbar-track {
            background: var(--box-color);
        }

        .main-categories-panel::-webkit-scrollbar-thumb,
        .subcategories-panel::-webkit-scrollbar-thumb,
        .right-panel::-webkit-scrollbar-thumb {
            background: var(--low-contrast-white);
            border-radius: 4px;
        }

        .main-categories-panel::-webkit-scrollbar-thumb:hover,
        .subcategories-panel::-webkit-scrollbar-thumb:hover,
        .right-panel::-webkit-scrollbar-thumb:hover {
            background: var(--mimoja-blue);
        }
    </style>
</head>
<body class="max-w-[1920px] max-h-[1200px] mx-auto">
    <a href="#main-content" class="skip-link">Skip to main content</a>
    
    <!-- Toast Container -->
    <div id="toast-container" class="toast-container"></div>

    <!-- Header -->
    <header class="relative flex justify-between items-center p-6 border-b border-base-300 bg-[var(--box-color)] h-[112px]">
        <h1 id="page-title" class="text-[28px] font-bold text-[var(--text-primary)] no-select" data-i18n-key="Settings">Settings</h1>
        <div class="flex items-center gap-[22px]">
            <button id="cancel-settings-btn" class="flex justify-center items-center min-h-0 w-[240px] h-[82.5px] px-[67.5px] py-[27px] border border-solid border-[var(--mimoja-blue)] text-[var(--mimoja-blue)] rounded-[67.5px] font-bold text-[24px]" data-i18n-key="Cancel" onclick="window.closeSettings()">CANCEL</button>
            <button id="save-settings-btn" class="bg-[var(--mimoja-blue)] text-white min-h-0 w-[240px] h-[82.5px] px-[67.5px] py-[27px] font-bold text-[24px] rounded-[67.5px]" data-i18n-key="Save" onclick="saveAllSettings()">SAVE</button>
        </div>
        <button id="fullscreen-toggle-btn" title="Toggle fullscreen" class="absolute -top-1 -right-1 w-12 h-12 flex items-center justify-center text-[var(--mimoja-blue)]" aria-label="Toggle Fullscreen" onclick="window.toggleFullscreen()">
            <svg class="enter-fullscreen-icon" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/></svg>
            <svg class="exit-fullscreen-icon" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor" style="display: none;"><path d="M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z"/></svg>
        </button>
    </header>

    <!-- Timestamp -->
    <div class="timestamp flex items-center gap-2 px-6 py-4" role="status" aria-live="polite" aria-atomic="true">
        <span class="status-indicator status-ok" role="img" aria-label="Settings loaded successfully"></span>
        Last updated: <span id="timestamp">${new Date().toLocaleString()}</span>
    </div>

    <div class="flex h-[1088px]">
        <div id="left-panel" class="w-[796px] h-full flex flex-col border-r border-base-300 bg-[var(--box-color)]">
            <div class="p-6 border-b border-base-300">
                <div class="relative">
                    <input type="text" id="settings-search" placeholder="Search settings..." class="w-full p-3 pl-12 rounded-lg border border-[var(--border-color)] bg-[var(--profile-button-background-color)] text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--mimoja-blue)]" aria-label="Search settings">
                    <svg class="absolute left-4 top-1/2 transform -translate-y-1/2 w-5 h-5 text-[var(--text-primary)]" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                    </svg>
                </div>
            </div>

            <div class="flex flex-grow overflow-hidden" id="settings-navigation-container">
                <div id="main-categories-panel" class="h-full overflow-y-auto p-2" style="width: 405px;" aria-label="Settings Categories">
                    <!-- Main categories will be dynamically loaded here -->
                </div>
                <div id="sub-categories-separator" class="cursor-col-resize w-2 bg-gray-400 hover:bg-blue-500 h-full" aria-hidden="true"></div>
                <div id="sub-categories-panel" class="h-full overflow-y-auto p-2" style="width: 270px; background-color: var(--box-color-alt);" aria-label="Subcategories">
                    <!-- Subcategories will be dynamically loaded here -->
                </div>
            </div>
        </div>

        <div id="separator" class="cursor-col-resize w-2 bg-gray-300 hover:bg-blue-500 transition-colors z-10 h-full" aria-hidden="true"></div>

        <div id="right-panel" class="w-[1124px] flex-grow h-full flex flex-col bg-[var(--profile-button-background-color)] p-6 overflow-y-auto" role="main" aria-label="Settings Content">
            <div id="settings-content-area" class="flex-grow">
                <!-- Settings content will be dynamically loaded here -->
                <div class="flex flex-col items-center justify-center h-full text-center p-8">
                    <p class="text-[var(--text-primary)] text-[28px]" aria-live="polite">Loading Settings...</p>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Settings Tree Structure for Navigation (embedded for template scope)
        const settingsTree = ${JSON.stringify(settingsTree)};

        // Embedded settings data for browser runtime access
        const reaSettings = ${JSON.stringify(reaSettings || {})};
        const de1Settings = ${JSON.stringify(de1Settings || {})};
        const de1AdvancedSettings = ${JSON.stringify(de1AdvancedSettings || {})};
        const webUISkins = ${JSON.stringify(webUISkins || [])};
        const calibrationSettings = ${JSON.stringify(calibrationSettings || {})};
        const presenceSettings = ${JSON.stringify(presenceSettings || {})};
        const appInfo = ${JSON.stringify(appInfo || null)};
        const machineInfo = ${JSON.stringify(machineInfo || null)};

        // Navigation state - embedded from outer scope
        let activeSettingsCategory = ${JSON.stringify(activeSettingsCategory)};
        let activeMainCategoryKey = ${JSON.stringify(activeMainCategoryKey)};

        // API and storage constants
        const API_BASE_URL = "http://localhost:8080/api/v1";
        const STORAGE_KEYS = {
            presenceActiveHours: 'settingsPresenceActiveHours',
        };

        // Settings cache
        const settingsCache = {
            rea: null,
            de1: null,
            de1Advanced: null,
            appInfo: null,
            machineInfo: null,
            reaError: null,
            de1Error: null,
            de1AdvancedError: null,
            appInfoError: null,
            machineInfoError: null,
        };
        const WS_PROTOCOL = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const REA_HOSTNAME = localStorage.getItem('reaHostname') || window.location.hostname;
        const REA_PORT = 8080;
        let deviceWebSocket = null;
        let deviceStateCache = {
            devices: [],
            scanning: false,
            initialized: false,
        };

        // Active hours functions
        function getActiveHours() {
            try {
                const stored = localStorage.getItem(STORAGE_KEYS.presenceActiveHours);
                return stored ? JSON.parse(stored) : [];
            } catch (error) {
                console.error('Failed to read stored active hours:', error);
                return [];
            }
        }

        function writeStoredActiveHours(activeHours) {
            localStorage.setItem(STORAGE_KEYS.presenceActiveHours, JSON.stringify(activeHours));
        }

        function addActiveHour(activeHour) {
            const activeHours = getActiveHours();
            activeHours.push({
                id: 'active-hour-' + Date.now(),
                ...activeHour,
            });
            writeStoredActiveHours(activeHours);
        }

        function updateActiveHour(id, updates) {
            const activeHours = getActiveHours();
            const nextHours = activeHours.map((activeHour) => (
                activeHour.id === id ? { ...activeHour, ...updates } : activeHour
            ));
            writeStoredActiveHours(nextHours);
        }

        function deleteActiveHour(id) {
            const activeHours = getActiveHours();
            writeStoredActiveHours(activeHours.filter((activeHour) => activeHour.id !== id));
        }

        // Fetch functions
        async function fetchReaSettings() {
            try {
                const response = await fetch(API_BASE_URL + '/settings');
                if (!response.ok) throw new Error('Failed to fetch REA settings');
                return await response.json();
            } catch (e) {
                console.error('Error fetching REA settings:', e);
                return null;
            }
        }

        async function fetchDe1Settings() {
            try {
                const response = await fetch(API_BASE_URL + '/machine/settings');
                if (!response.ok) throw new Error('Failed to fetch DE1 settings');
                return await response.json();
            } catch (e) {
                console.error('Error fetching DE1 settings:', e);
                return null;
            }
        }

        async function fetchDe1AdvancedSettings() {
            try {
                const response = await fetch(API_BASE_URL + '/machine/settings/advanced');
                if (!response.ok) throw new Error('Failed to fetch DE1 advanced settings');
                return await response.json();
            } catch (e) {
                console.error('Error fetching DE1 advanced settings:', e);
                return null;
            }
        }

        async function fetchAppInfo() {
            try {
                const response = await fetch(API_BASE_URL + '/info');
                if (!response.ok) throw new Error('Failed to fetch app info');
                return await response.json();
            } catch (e) {
                console.error('Error fetching app info:', e);
                return null;
            }
        }

        async function fetchMachineInfo() {
            try {
                const response = await fetch(API_BASE_URL + '/machine/info');
                if (!response.ok) throw new Error('Failed to fetch machine info');
                return await response.json();
            } catch (e) {
                console.error('Error fetching machine info:', e);
                return null;
            }
        }

        async function fetchPresenceSettings() {
            try {
                const response = await fetch(API_BASE_URL + '/presence/settings');
                if (!response.ok) throw new Error('Failed to fetch presence settings');
                return await response.json();
            } catch (e) {
                console.error('Error fetching presence settings:', e);
                return null;
            }
        }

        function updateCacheEntry(cacheKey, value) {
            settingsCache[cacheKey] = value;
        }

        // Update calibration setting function
        async function updateCalibrationSetting(key, value) {
            try {
                const payload = {};
                payload[key] = value;

                const response = await fetch('http://localhost:8080/api/v1/machine/calibration', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok || response.status === 202) {
                    showToast('Calibration setting updated successfully', false);
                    updateTimestamp();
                } else {
                    const error = await response.text();
                    showToast('Failed to update calibration setting: ' + error, true);
                }
            } catch (e) {
                showToast('Error updating calibration setting: ' + e.message, true);
            }
        }

        // Update REA setting function
        async function updateReaSetting(key, value, event) {
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
                    updateCacheEntry('rea', { ...settingsCache.rea, ...payload });
                    showToast('REA setting updated successfully', false);
                    updateTimestamp();

                    // Update button states for gateway mode
                    if (key === 'gatewayMode' && event) {
                        // Update all gateway mode buttons
                        const gatewayButtons = document.querySelectorAll('[onclick*="gatewayMode"]');
                        gatewayButtons.forEach(btn => {
                            const btnValue = btn.getAttribute('onclick').match(/'([^']+)'/)[1];
                            if (btnValue === value) {
                                btn.classList.remove('inactive');
                                btn.classList.add('active');
                                btn.setAttribute('aria-pressed', 'true');
                            } else {
                                btn.classList.remove('active');
                                btn.classList.add('inactive');
                                btn.setAttribute('aria-pressed', 'false');
                            }
                        });
                    }
                } else {
                    const error = await response.text();
                    console.error('Failed to update REA setting:', error);
                    showToast('Failed to update REA setting: ' + error, true);
                }
            } catch (e) {
                console.error('Error updating REA setting:', e);
                showToast('Error updating REA setting: ' + e.message, true);
            }
        }

        // Update DE1 machine setting function
        async function updateDe1Setting(key, value) {
            try {
                const payload = {};
                payload[key] = value;

                const response = await fetch('http://localhost:8080/api/v1/machine/settings', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (response.ok || response.status === 202) {
                    updateCacheEntry('de1', { ...settingsCache.de1, ...payload });
                    showToast('Machine setting updated successfully', false);
                    updateTimestamp();
                } else {
                    const error = await response.text();
                    showToast('Failed to update machine setting: ' + error, true);
                }
            } catch (e) {
                showToast('Error updating machine setting: ' + e.message, true);
            }
        }

        function updateCacheEntry(cacheKey, value) {
            settingsCache[cacheKey] = value;
            switch (cacheKey) {
                case 'rea':
                    Object.assign(reaSettings, value || {});
                    break;
                case 'de1':
                    Object.assign(de1Settings, value || {});
                    break;
                case 'de1Advanced':
                    Object.assign(de1AdvancedSettings, value || {});
                    break;
                default:
                    break;
            }
        }

        async function updatePresenceSettings(payload) {
            const response = await fetch(\`${API_BASE_URL}/presence/settings\`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(payload)
            });

            if (!response.ok) {
                const errorText = await response.text();
                throw new Error(errorText || \`Failed to update presence settings: \${response.status}\`);
            }

            const updated = await response.json();
            Object.assign(presenceSettings, updated || payload);
            return updated;
        }

        async function updatePresenceSchedule(scheduleId, payload) {
            const response = await fetch(\`${API_BASE_URL}/presence/schedules/\${scheduleId}\`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(payload)
            });

            if (!response.ok) {
                const errorText = await response.text();
                throw new Error(errorText || \`Failed to update schedule \${scheduleId}: \${response.status}\`);
            }

            const updated = await response.json();
            if (Array.isArray(presenceSettings.schedules)) {
                presenceSettings.schedules = presenceSettings.schedules.map((schedule) => (
                    String(schedule.id) === String(scheduleId) ? { ...schedule, ...updated } : schedule
                ));
            }
            return updated;
        }

        async function createPresenceSchedule(payload) {
            const response = await fetch(\`${API_BASE_URL}/presence/schedules\`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(payload)
            });

            if (!response.ok) {
                const errorText = await response.text();
                throw new Error(errorText || \`Failed to create schedule: \${response.status}\`);
            }

            const created = await response.json();
            if (!Array.isArray(presenceSettings.schedules)) {
                presenceSettings.schedules = [];
            }
            presenceSettings.schedules.push(created);
            return created;
        }

        async function deletePresenceSchedule(scheduleId) {
            const response = await fetch(\`${API_BASE_URL}/presence/schedules/\${scheduleId}\`, {
                method: 'DELETE'
            });

            if (!response.ok) {
                const errorText = await response.text();
                throw new Error(errorText || \`Failed to delete schedule \${scheduleId}: \${response.status}\`);
            }

            if (Array.isArray(presenceSettings.schedules)) {
                presenceSettings.schedules = presenceSettings.schedules.filter((schedule) => String(schedule.id) !== String(scheduleId));
            }

            return response.json().catch(() => ({}));
        }

        async function enableWakeLock() {
            const response = await fetch(\`${API_BASE_URL}/display/wakelock\`, { method: 'POST' });
            if (!response.ok) {
                throw new Error(\`Failed to enable wake lock: \${response.status}\`);
            }
            return response.json().catch(() => ({}));
        }

        async function disableWakeLock() {
            const response = await fetch(\`${API_BASE_URL}/display/wakelock\`, { method: 'DELETE' });
            if (!response.ok) {
                throw new Error(\`Failed to disable wake lock: \${response.status}\`);
            }
            return response.json().catch(() => ({}));
        }

        function sendDisplayCommand(command) {
            return fetch(\`${API_BASE_URL}/display/command\`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(command)
            }).catch((error) => {
                console.error('Failed to send display command:', error);
                throw error;
            });
        }

        async function updateDe1AdvancedSetting(key, value) {
            try {
                const payload = {};
                payload[key] = value;

                const response = await fetch(\`${API_BASE_URL}/machine/settings/advanced\`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (!response.ok) {
                    const error = await response.text();
                    throw new Error(error || \`Failed to update advanced setting: \${response.status}\`);
                }

                updateCacheEntry('de1Advanced', { ...settingsCache.de1Advanced, ...payload });
                showToast('DE1 advanced setting updated successfully');
                updateTimestamp();
                if (activeSettingsCategory) {
                    updateSettingsContentArea(activeSettingsCategory);
                }
            } catch (error) {
                console.error('Error updating DE1 advanced setting:', error);
                showToast(\`Failed to update DE1 advanced setting: \${error.message}\`, true);
            }
        }

        function showToast(message, isError = false) {
            const toastContainer = document.getElementById('toast-container');
            if (!toastContainer) return;

            const toast = document.createElement('div');
            toast.className = isError ? 'toast toast-error' : 'toast toast-success';
            toast.textContent = message;
            toast.id = 'toast-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
            toastContainer.appendChild(toast);

            setTimeout(() => {
                toast.classList.add('fade-out');
                setTimeout(() => {
                    if (toast.parentNode === toastContainer) {
                        toast.remove();
                    }
                }, 300);
            }, 3000);
        }

        function initDeviceWebSocket() {
            if (deviceWebSocket && (deviceWebSocket.readyState === WebSocket.OPEN || deviceWebSocket.readyState === WebSocket.CONNECTING)) {
                return;
            }

            deviceWebSocket = new WebSocket(WS_PROTOCOL + '//' + REA_HOSTNAME + ':' + REA_PORT + '/ws/v1/devices');

            deviceWebSocket.addEventListener('open', () => {
                console.log('Device WebSocket connected');
            });

            deviceWebSocket.addEventListener('message', (event) => {
                try {
                    const data = JSON.parse(event.data);
                    deviceStateCache.devices = Array.isArray(data.devices) ? data.devices : [];
                    deviceStateCache.scanning = !!data.scanning;
                    deviceStateCache.initialized = true;
                    renderDeviceListFromCache();
                } catch (error) {
                    console.error('Error parsing Device WebSocket message:', error);
                }
            });

            deviceWebSocket.addEventListener('close', () => {
                deviceWebSocket = null;
            }, { once: true });

            deviceWebSocket.addEventListener('error', (error) => {
                console.error('Device WebSocket error:', error);
            });
        }

        function sendDeviceCommand(command) {
            initDeviceWebSocket();

            if (!deviceWebSocket || deviceWebSocket.readyState !== WebSocket.OPEN) {
                if (deviceWebSocket && deviceWebSocket.readyState === WebSocket.CONNECTING) {
                    deviceWebSocket.addEventListener('open', () => {
                        try {
                            deviceWebSocket.send(JSON.stringify(command));
                        } catch (error) {
                            console.error('Error sending device command:', error);
                        }
                    }, { once: true });
                    return;
                }

                throw new Error('Device WebSocket is not connected. Cannot send command.');
            }

            deviceWebSocket.send(JSON.stringify(command));
        }

        function getBluetoothDevicesByType() {
            const devices = Array.isArray(deviceStateCache.devices) ? deviceStateCache.devices : [];

            const machines = devices.filter((device) => device && device.name && (
                device.name.toLowerCase().includes('decent') ||
                device.name.toLowerCase().includes('espresso') ||
                device.type === 'espresso'
            ));

            const scales = devices.filter((device) => device && device.name && (
                device.name.toLowerCase().includes('scale') ||
                device.name.toLowerCase().includes('weight') ||
                device.type === 'scale'
            ));

            return { machines, scales };
        }

        function renderDeviceListFromCache() {
            const { machines, scales } = getBluetoothDevicesByType();
            renderDeviceList('bluetooth-machine-devices-container', machines, 'Machine');
            renderDeviceList('bluetooth-scale-devices-container', scales, 'Scale');
        }

        function renderDeviceList(containerId, devices, type) {
            const container = document.getElementById(containerId);
            if (!container) return;

            if (deviceStateCache.scanning) {
                container.innerHTML = '<p class="setting-description">Scanning for ' + type.toLowerCase() + ' devices...</p>';
                return;
            }

            if (devices.length > 0) {
                container.innerHTML = renderSingleDeviceList(devices);
                return;
            }

            if (!deviceStateCache.initialized) {
                container.innerHTML = '<p class="setting-description">No device data yet. Press Scan to search for nearby devices.</p>';
                return;
            }

            container.innerHTML = '<p class="setting-description">No ' + type.toLowerCase() + ' devices found. Make sure your ' + type.toLowerCase() + ' is powered on and in pairing mode.</p>';
        }

        function renderSingleDeviceList(devices) {
            if (!Array.isArray(devices) || devices.length === 0) {
                return '';
            }

            return devices.map((device) => {
                if (!device || !device.name) {
                    return '';
                }

                const isConnected = device.state === 'connected';
                const statusClass = isConnected ? 'connected' : 'disconnected';
                const buttonText = isConnected ? 'Disconnect' : 'Connect';
                const buttonAction = isConnected ? 'disconnect' : 'connect';

                return '<div class="device-card">' +
                    '<div class="device-info">' +
                        '<div class="device-header">' +
                            '<div class="device-status-dot ' + statusClass + '"></div>' +
                            '<div class="device-name">' + device.name + '</div>' +
                        '</div>' +
                        '<div class="device-detail">ID: ' + (device.id || 'N/A') + '</div>' +
                        '<div class="device-detail device-status-text ' + statusClass + '">Status: ' + (device.state || 'unknown') + '</div>' +
                        '<div class="device-detail">Type: ' + (device.type || 'unknown') + '</div>' +
                    '</div>' +
                    '<button class="btn-connect" onclick="window.handleDeviceConnection(&quot;' + device.id + '&quot;, &quot;' + buttonAction + '&quot;)">' + buttonText + '</button>' +
                '</div>';
            }).join('');
        }

        window.handleDeviceConnection = async function(deviceId, action) {
            try {
                sendDeviceCommand({ command: action, deviceId });
                showToast((action === 'connect' ? 'Connecting to ' : 'Disconnecting from ') + deviceId);
            } catch (error) {
                console.error('Error handling device connection:', error);
                showToast('Failed to ' + action + ': ' + error.message, true);
            }
        };

        function updateTimestamp() {
            const timestamp = document.getElementById('timestamp');
            if (timestamp) {
                timestamp.textContent = new Date().toLocaleString();
            }
        }

        function getCategoryTitle(category) {
            switch (category) {
                case 'rea': return 'REA Application Settings';
                case 'flowmultiplier': return 'Flow Multiplier Settings';
                case 'steam': return 'Steam Settings';
                case 'hotwater': return 'Hot Water Settings';
                case 'watertank': return 'Water Tank Settings';
                case 'flush': return 'Flush Settings';
                case 'fanthreshold': return 'Fan Threshold Settings';
                case 'usbchargermode': return 'USB Charger Mode Settings';
                case 'de1advanced': return 'Machine Advanced Settings';
                case 'brightness': return 'Screen Brightness';
                case 'wakelock': return 'Wake Lock Settings';
                case 'presence': return 'Presence Detection';
                case 'updates': return 'Updates Settings';
                default: return 'Settings';
            }
        }

        function renderLoadingState(title) {
            return \`
                <div class="settings-loading-state">
                    <div class="settings-page-title"><p>\${title}</p></div>
                    <div style="color: var(--text-primary); padding: 16px; font-size: 24px; text-align: center; width: 100%;">Loading settings...</div>
                </div>
            \`;
        }

        function renderErrorState(title, message) {
            return \`
                <div class="settings-loading-state" role="alert">
                    <div class="settings-page-title"><p>\${title}</p></div>
                    <div class="settings-error-text">Failed to load settings: \${message}</div>
                    <button class="settings-btn-primary" style="margin: 0 auto;" onclick="window.retryLoadSettings()">Retry</button>
                </div>
            \`;
        }

        function renderMainCategories(selectedKey = activeMainCategoryKey) {
            const panel = document.getElementById('main-categories-panel');
            if (!panel) return;

            activeMainCategoryKey = selectedKey;
            let html = '<nav><ul style="list-style: none; padding: 0; margin: 0;">';

            for (const [key, category] of Object.entries(settingsTree)) {
                html += \`
                    <li>
                        <button class="main-category-btn \${key === selectedKey ? 'active' : ''}"
                                data-category="\${key}"
                                onclick="handleMainCategoryClick('\${key}', this)">
                            \${category.name}
                        </button>
                    </li>
                \`;
            }

            html += '</ul></nav>';
            panel.innerHTML = html;
        }

        function renderSubcategories(categoryKey, selectedCategory = null) {
            const panel = document.getElementById('sub-categories-panel');
            const category = settingsTree[categoryKey];

            if (!panel || !category) return;

            const activeCategory = selectedCategory || category.subcategories[0]?.settingsCategory || null;
            let html = '<ul style="list-style: none; padding: 0; margin: 0;">';

            category.subcategories.forEach((subcat) => {
                html += \`
                    <li>
                        <button class="subcategory-btn \${subcat.settingsCategory === activeCategory ? 'active' : ''}"
                                data-category="\${subcat.settingsCategory}"
                                data-label="\${subcat.name}"
                                onclick="handleSubcategoryClick('\${subcat.settingsCategory}', this)">
                            \${subcat.name}
                        </button>
                    </li>
                \`;
            });

            html += '</ul>';
            panel.innerHTML = html;

            if (activeCategory) {
                activeSettingsCategory = activeCategory;
                const activeName = category.subcategories.find((subcat) => subcat.settingsCategory === activeCategory)?.name || getCategoryTitle(activeCategory);
                renderSettingsContent(activeCategory, activeName);
            }
        }

        function handleMainCategoryClick(categoryKey, button) {
            activeMainCategoryKey = categoryKey;
            document.querySelectorAll('.main-category-btn').forEach((btn) => btn.classList.remove('active'));
            if (button) {
                button.classList.add('active');
            }
            renderSubcategories(categoryKey);
        }

        function handleSubcategoryClick(settingsCategory, button) {
            activeSettingsCategory = settingsCategory;
            document.querySelectorAll('.subcategory-btn').forEach((btn) => btn.classList.remove('active'));
            if (button) {
                button.classList.add('active');
            }
            const displayName = button?.dataset?.label || getCategoryTitle(settingsCategory);
            renderSettingsContent(settingsCategory, displayName);
        }

        function updateSettingsContentArea(category) {
            renderSettingsContent(category, getCategoryTitle(category));
        }

        function renderSettingsContent(category, displayName) {
            const contentArea = document.getElementById('settings-content-area');
            if (!contentArea) return;

            activeSettingsCategory = category;
            contentArea.innerHTML = renderLoadingState(displayName || getCategoryTitle(category));

            requestAnimationFrame(() => {
                let content = '';

                switch (category) {
                    case 'flowmultiplier':
                        content = settingsCache.rea ? renderFlowMultiplierSettings(settingsCache.rea) : renderErrorState(getCategoryTitle(category), settingsCache.reaError || 'Failed to load REA settings');
                        break;
                    case 'rea':
                        content = settingsCache.rea ? renderReaSettingsForm(settingsCache.rea) : renderErrorState(getCategoryTitle(category), settingsCache.reaError || 'Failed to load REA settings');
                        break;
                    case 'steam':
                        content = settingsCache.de1 ? renderSteamSettings(settingsCache.de1) : renderErrorState(getCategoryTitle(category), settingsCache.de1Error || 'Failed to load machine settings');
                        break;
                    case 'hotwater':
                        content = settingsCache.de1 ? renderHotWaterSettings(settingsCache.de1) : renderErrorState(getCategoryTitle(category), settingsCache.de1Error || 'Failed to load machine settings');
                        break;
                    case 'watertank':
                        content = settingsCache.de1 ? renderWaterTankSettings(settingsCache.de1) : renderErrorState(getCategoryTitle(category), settingsCache.de1Error || 'Failed to load machine settings');
                        break;
                    case 'flush':
                        content = settingsCache.de1 ? renderFlushSettingsForm(settingsCache.de1) : renderErrorState(getCategoryTitle(category), settingsCache.de1Error || 'Failed to load machine settings');
                        break;
                    case 'fanthreshold':
                        content = settingsCache.de1 ? renderFanThresholdSettings(settingsCache.de1) : renderErrorState(getCategoryTitle(category), settingsCache.de1Error || 'Failed to load machine settings');
                        break;
                    case 'usbchargermode':
                        content = settingsCache.de1 ? renderUsbChargerModeSettings(settingsCache.de1) : renderErrorState(getCategoryTitle(category), settingsCache.de1Error || 'Failed to load machine settings');
                        break;
                    case 'de1advanced':
                        content = settingsCache.de1Advanced ? renderDe1AdvancedSettingsForm(settingsCache.de1Advanced) : renderErrorState(getCategoryTitle(category), settingsCache.de1AdvancedError || 'Failed to load advanced settings');
                        break;
                    case 'brightness':
                        content = renderBrightnessSettings();
                        break;
                    case 'wakelock':
                        content = renderWakeLockSettings();
                        break;
                    case 'presence':
                        content = renderPresenceSettings();
                        break;
                    case 'updates':
                        content = renderUpdatesSettings();
                        break;
                    case 'ble_machine':
                        content = renderBluetoothMachineSettings();
                        break;
                    case 'ble_scale':
                        content = renderBluetoothScaleSettings();
                        break;
                    case 'appearance':
                        content = renderSkinSettings();
                        break;
                    case 'language':
                        content = renderLanguageSettings();
                        break;
                    case 'extensions':
                        content = renderExtensionsSettings();
                        break;
                    case 'help':
                        content = renderUserManualSettings();
                        break;
                    case 'calibration':
                    case 'refillkit':
                    case 'voltage':
                    case 'stopatweight':
                    case 'slowstart':
                        content = renderCalibrationSettings();
                        break;
                    case 'fan':
                        content = renderFanThresholdSettings(settingsCache.de1 || de1Settings);
                        break;
                    case 'maintenance':
                    case 'transportmode':
                        content = renderMaintenanceSettings();
                        break;
                    case 'misc':
                    case 'de1':
                        content = renderMiscellaneousSettings();
                        break;
                    default:
                        content = \`
                            <div class="settings-flex-container">
                                <div class="settings-page-title"><p>\${displayName}</p></div>
                                <div class="settings-divider"><hr /></div>
                                <div class="setting-description"><p>Settings content for \${displayName} coming soon.</p></div>
                            </div>
                        \`;
                }

                contentArea.innerHTML = content;
                updateBrightnessSliderState();
                updateWakeLockToggleState();
            });
        }

        // Render Flow Multiplier settings
        function renderFlowMultiplierSettings(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Flow Multiplier Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load flow multiplier settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Flow Multiplier Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p id="weight-flow-multiplier-label">Weight Flow Multiplier</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="weightFlowMultiplierInput" aria-labelledby="weight-flow-multiplier-label" class="settings-input-primary"
                                       value="\${settings.weightFlowMultiplier !== undefined ? settings.weightFlowMultiplier : 1.0}"
                                       step="0.1" min="0" max="5">
                                <button class="settings-btn-primary" aria-label="Save weight flow multiplier setting"
                                        onclick="updateReaSetting('weightFlowMultiplier', parseFloat(document.getElementById('weightFlowMultiplierInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Multiplier for projected weight calculation. Higher values stop shots earlier.
                        </p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p id="volume-flow-multiplier-label">Volume Flow Multiplier (s)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="volumeFlowMultiplierInput" aria-labelledby="volume-flow-multiplier-label" class="settings-input-primary"
                                       value="\${settings.volumeFlowMultiplier !== undefined ? settings.volumeFlowMultiplier : 0.3}"
                                       step="0.05" min="0" max="2">
                                <button class="settings-btn-primary"
                                        onclick="updateReaSetting('volumeFlowMultiplier', parseFloat(document.getElementById('volumeFlowMultiplierInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Look-ahead time in seconds for projected volume calculation. Accounts for system lag.
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render REA settings form
        function renderReaSettingsForm(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Bridge Application Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load REA settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Bridge Application Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Gateway Mode -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex-column">
                            <div class="setting-label-bold">
                                <p id="gateway-mode-label">Gateway Mode</p>
                            </div>
                            <div class="toggle-button-group" role="group" aria-labelledby="gateway-mode-label">
                                <button class="toggle-btn \${settings.gatewayMode === 'disabled' ? 'active' : 'inactive'}"
                                        aria-pressed="\${settings.gatewayMode === 'disabled'}"
                                        onclick="updateReaSetting('gatewayMode', 'disabled')">
                                    Disabled
                                </button>
                                <button class="toggle-btn \${settings.gatewayMode === 'tracking' ? 'active' : 'inactive'}"
                                        aria-pressed="\${settings.gatewayMode === 'tracking'}"
                                        onclick="updateReaSetting('gatewayMode', 'tracking')">
                                    Tracking
                                </button>
                                <button class="toggle-btn \${settings.gatewayMode === 'full' ? 'active' : 'inactive'}"
                                        aria-pressed="\${settings.gatewayMode === 'full'}"
                                        onclick="updateReaSetting('gatewayMode', 'full')">
                                    Full
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Controls how the gateway monitors and controls the espresso machine
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Log Level -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p id="log-level-label">Log Level</p>
                            </div>
                            <div class="setting-control-flex">
                                <select id="logLevelSelect" class="settings-input-wide"
                                        aria-labelledby="log-level-label"
                                        onchange="updateReaSetting('logLevel', this.value)">
                                    <option value="ALL" \${settings.logLevel === 'ALL' ? 'selected' : ''}>ALL</option>
                                    <option value="FINEST" \${settings.logLevel === 'FINEST' ? 'selected' : ''}>FINEST</option>
                                    <option value="FINER" \${settings.logLevel === 'FINER' ? 'selected' : ''}>FINER</option>
                                    <option value="FINE" \${settings.logLevel === 'FINE' ? 'selected' : ''}>FINE</option>
                                    <option value="CONFIG" \${settings.logLevel === 'CONFIG' ? 'selected' : ''}>CONFIG</option>
                                    <option value="INFO" \${settings.logLevel === 'INFO' ? 'selected' : ''}>INFO</option>
                                    <option value="WARNING" \${settings.logLevel === 'WARNING' ? 'selected' : ''}>WARNING</option>
                                    <option value="SEVERE" \${settings.logLevel === 'SEVERE' ? 'selected' : ''}>SEVERE</option>
                                    <option value="SHOUT" \${settings.logLevel === 'SHOUT' ? 'selected' : ''}>SHOUT</option>
                                    <option value="OFF" \${settings.logLevel === 'OFF' ? 'selected' : ''}>OFF</option>
                                </select>
                            </div>
                        </div>
                        <p class="setting-description">
                            Controls the verbosity of Bridge application logging
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Scale Power Mode -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Scale Power Mode</p>
                            </div>
                            <div class="setting-control-flex">
                                <select class="settings-input-wide"
                                        onchange="updateReaSetting('scalePowerMode', this.value)">
                                    <option value="disabled" \${settings.scalePowerMode === 'disabled' ? 'selected' : ''}>Disabled</option>
                                    <option value="displayOff" \${settings.scalePowerMode === 'displayOff' ? 'selected' : ''}>Display Off</option>
                                    <option value="disconnect" \${settings.scalePowerMode === 'disconnect' ? 'selected' : ''}>Disconnect</option>
                                </select>
                            </div>
                        </div>
                        <p class="setting-description">
                            Automatic scale power management when machine sleeps
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Steam settings
        function renderSteamSettings(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Steam Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load DE1 settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Steam Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Steam Purge Mode</p>
                            </div>
                            <div class="setting-control-flex">
                                <select class="settings-input-wide"
                                        onchange="updateDe1Setting('steamPurgeMode', parseInt(this.value))">
                                    <option value="0" \${settings.steamPurgeMode === 0 ? 'selected' : ''}>Normal</option>
                                    <option value="1" \${settings.steamPurgeMode === 1 ? 'selected' : ''}>Two Tap Stop</option>
                                </select>
                            </div>
                        </div>
                        <p class="setting-description">
                            Steam purge mode - normal or two tap stop
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Hot Water settings
        function renderHotWaterSettings(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Hot Water Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load DE1 settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Hot Water Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Hot Water Flow (ml/s)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="hotWaterFlowInput" class="settings-input-primary"
                                       value="\${settings.hotWaterFlow !== undefined ? settings.hotWaterFlow : 2.5}"
                                       step="0.1" min="0" max="10">
                                <button class="settings-btn-primary"
                                        onclick="updateDe1Setting('hotWaterFlow', parseFloat(document.getElementById('hotWaterFlowInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Flow rate for hot water dispensing
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Water Tank settings
        function renderWaterTankSettings(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Water Tank Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load DE1 settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Water Tank Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Tank Temperature (°C)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="tankTempInput" class="settings-input-primary"
                                       value="\${settings.tankTemp !== undefined ? settings.tankTemp : 80}"
                                       step="1" min="0" max="100">
                                <button class="settings-btn-primary"
                                        onclick="updateDe1Setting('tankTemp', parseInt(document.getElementById('tankTempInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Set the water tank temperature in degrees Celsius
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Flush settings form
        function renderFlushSettingsForm(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Flush Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load DE1 settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Flush Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Flush Temperature (°C)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="flushTempInput" class="settings-input-primary"
                                       value="\${settings.flushTemp !== undefined ? settings.flushTemp : ''}"
                                       step="0.1" min="0" max="100">
                                <button class="settings-btn-primary"
                                        onclick="updateDe1Setting('flushTemp', parseFloat(document.getElementById('flushTempInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Target temperature for automatic flush cycles
                        </p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Flush Flow (ml/s)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="flushFlowInput" class="settings-input-primary"
                                       value="\${settings.flushFlow !== undefined ? settings.flushFlow : ''}"
                                       step="0.1" min="0" max="10">
                                <button class="settings-btn-primary"
                                        onclick="updateDe1Setting('flushFlow', parseFloat(document.getElementById('flushFlowInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Flow rate for automatic flush cycles
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Fan Threshold settings
        function renderFanThresholdSettings(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Fan Threshold Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load DE1 settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Fan Threshold Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p id="fan-threshold-label">Fan Threshold (°C)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="fanThresholdInput" aria-labelledby="fan-threshold-label" class="settings-input-primary"
                                       value="\${settings.fan !== undefined ? settings.fan : ''}"
                                       step="1" min="0" max="100">
                                <button class="settings-btn-primary" aria-label="Save fan threshold setting"
                                        onclick="updateDe1Setting('fan', parseInt(document.getElementById('fanThresholdInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Temperature threshold at which the cooling fan turns on
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render USB Charger Mode settings
        function renderUsbChargerModeSettings(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>USB Charger Mode Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load DE1 settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>USB Charger Mode Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>USB Charger Mode</p>
                            </div>
                            <div class="setting-control-flex">
                                <select class="settings-input-wide"
                                        onchange="updateDe1Setting('usb', this.value)">
                                    <option value="enable" \${settings.usb ? 'selected' : ''}>Enabled</option>
                                    <option value="disable" \${!settings.usb ? 'selected' : ''}>Disabled</option>
                                </select>
                            </div>
                        </div>
                        <p class="setting-description">
                            Controls whether the USB port provides power for charging devices
                        </p>
                    </div>
                </div>
            \`;
        }

        function renderBrightnessSettings() {
            const currentBrightness = previousBrightnessState ?? 75;
            return \`
                <div class="space-y-6 px-[60px] py-[80px]">
                    <div>
                        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Screen Brightness</h2>
                        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">
                            Adjust screen brightness level.
                        </p>
                    </div>
                    <div class="bg-[var(--box-color)] rounded-lg p-6">
                        <input type="range" id="brightness-slider" min="0" max="100" value="\${currentBrightness}" class="brightness-slider flex-grow w-full" onchange="handleBrightnessChange(this.value)">
                    </div>
                </div>
            \`;
        }

        function renderWakeLockSettings() {
            const wakeLockEnabled = localStorage.getItem(STORAGE_KEYS.wakeLockEnabled) === 'true';
            return \`
                <div class="space-y-6 px-[60px] py-[80px]">
                    <div>
                        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Wake Lock Settings</h2>
                        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">
                            Control screen wake-lock to prevent the display from sleeping during operation.
                        </p>
                    </div>
                    <div class="bg-[var(--box-color)] rounded-lg p-6">
                        <div class="flex items-center justify-between">
                            <div>
                                <label class="text-[24px] font-semibold text-[var(--text-primary)]">Enable Wake Lock</label>
                                <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-1">Keep the screen on while the app is active</p>
                            </div>
                            <input type="checkbox" id="wake-lock-toggle" class="toggle toggle-lg toggle-primary" \${wakeLockEnabled ? 'checked' : ''} onchange="handleWakeLockToggle(this.checked)">
                        </div>
                    </div>
                    <div class="text-[18px] text-[var(--text-primary)] opacity-75 mt-4">
                        <p><strong>Note:</strong> Wake-lock automatically releases when the display service disconnects.</p>
                    </div>
                </div>
            \`;
        }

        function formatDaysOfWeek(days) {
            if (!days || days.length === 0) {
                return 'Every day';
            }
            const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            return days.map((day) => dayNames[day - 1]).join(', ');
        }

        function renderPresenceSettings() {
            const settings = presenceSettings || {};
            const schedules = Array.isArray(settings.schedules) ? settings.schedules : [];
            const activeHours = getActiveHours();

            const schedulesHtml = schedules.map((schedule) => \`
                <div class="bg-[var(--profile-button-background-color)] rounded-lg p-4 flex items-center justify-between" data-schedule-id="\${schedule.id}">
                    <div class="flex-grow">
                        <div class="text-[22px] font-semibold text-[var(--text-primary)]">\${schedule.time} - \${formatDaysOfWeek(schedule.daysOfWeek)}</div>
                    </div>
                    <div class="flex items-center gap-4">
                        <input type="checkbox" class="toggle toggle-md toggle-primary" \${schedule.enabled ? 'checked' : ''} onchange="handleScheduleToggle('\${schedule.id}', this.checked)">
                        <button class="settings-btn-danger" onclick="handleDeleteSchedule('\${schedule.id}')">Delete</button>
                    </div>
                </div>
            \`).join('');

            const activeHoursHtml = activeHours.map((activeHour) => \`
                <div class="bg-[var(--profile-button-background-color)] rounded-lg p-4 flex items-center justify-between" data-active-hour-id="\${activeHour.id}">
                    <div class="flex-grow">
                        <div class="text-[22px] font-semibold text-[var(--text-primary)]">\${activeHour.startTime} - \${activeHour.endTime} \${formatDaysOfWeek(activeHour.daysOfWeek)}</div>
                    </div>
                    <div class="flex items-center gap-4">
                        <input type="checkbox" class="toggle toggle-md toggle-primary" \${activeHour.enabled ? 'checked' : ''} onchange="handleActiveHourToggle('\${activeHour.id}', this.checked)">
                        <button class="settings-btn-danger" onclick="handleDeleteActiveHour('\${activeHour.id}')">Delete</button>
                    </div>
                </div>
            \`).join('');

            return \`
                <div class="space-y-6 px-[60px] py-[80px]">
                    <div>
                        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Presence Detection</h2>
                        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">Automatically manage machine sleep/wake based on user presence and schedules.</p>
                    </div>
                    <div class="bg-[var(--box-color)] rounded-lg p-6">
                        <div class="flex items-center justify-between mb-6">
                            <div>
                                <label class="text-[24px] font-semibold text-[var(--text-primary)]">Enable Presence Detection</label>
                                <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-1">Track user presence to automatically sleep the machine</p>
                            </div>
                            <input type="checkbox" id="presence-enabled-toggle" class="toggle toggle-lg toggle-primary" \${settings.userPresenceEnabled ? 'checked' : ''} onchange="handlePresenceToggle(this.checked)">
                        </div>
                        <div class="mt-6">
                            <label class="text-[22px] font-semibold text-[var(--text-primary)] block mb-3">Sleep Timeout (minutes)</label>
                            <input type="number" id="sleep-timeout-input" class="settings-input-primary" value="\${settings.sleepTimeoutMinutes || 30}" min="1" max="120" onchange="handleSleepTimeoutChange(this.value)">
                            <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-2">Minutes of inactivity before auto-sleep</p>
                        </div>
                    </div>
                    <div class="bg-[var(--box-color)] rounded-lg p-6">
                        <div class="flex items-center justify-between mb-4">
                            <h3 class="text-[24px] font-semibold text-[var(--text-primary)]">Wake Schedules</h3>
                            <button class="settings-btn-primary" onclick="handleAddSchedule()">Add Schedule</button>
                        </div>
                        <div class="space-y-3">
                            \${schedules.length > 0 ? schedulesHtml : '<p class="text-[var(--text-primary)] opacity-75 text-[18px]">No schedules configured</p>'}
                        </div>
                    </div>
                    <div class="bg-[var(--box-color)] rounded-lg p-6">
                        <div class="flex items-center justify-between mb-4">
                            <div>
                                <h3 class="text-[24px] font-semibold text-[var(--text-primary)]">Active Hours</h3>
                                <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-1">Machine stays awake during these time windows</p>
                            </div>
                            <button class="settings-btn-primary" onclick="handleAddActiveHour()">Add Active Hours</button>
                        </div>
                        <div class="space-y-3">
                            \${activeHours.length > 0 ? activeHoursHtml : '<p class="text-[var(--text-primary)] opacity-75 text-[18px]">No active hours configured</p>'}
                        </div>
                    </div>
                    <dialog id="add-schedule-modal" class="modal">
                        <div class="modal-box bg-[var(--box-color)] max-w-2xl">
                            <h3 class="font-bold text-[24px] text-[var(--text-primary)] mb-4">Add Schedule</h3>
                            <div class="space-y-4">
                                <div>
                                    <label class="text-[20px] text-[var(--text-primary)] block mb-2">Wake Time</label>
                                    <input type="time" id="schedule-time-input" class="settings-input-primary">
                                </div>
                                <div>
                                    <label class="text-[20px] text-[var(--text-primary)] block mb-2">Days of Week</label>
                                    <div class="flex gap-2 flex-wrap">
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="1" class="checkbox checkbox-primary mr-1"> Mon</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="2" class="checkbox checkbox-primary mr-1"> Tue</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="3" class="checkbox checkbox-primary mr-1"> Wed</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="4" class="checkbox checkbox-primary mr-1"> Thu</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="5" class="checkbox checkbox-primary mr-1"> Fri</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="6" class="checkbox checkbox-primary mr-1"> Sat</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="7" class="checkbox checkbox-primary mr-1"> Sun</label>
                                    </div>
                                </div>
                            </div>
                            <div class="modal-action">
                                <button class="settings-btn-secondary" onclick="document.getElementById('add-schedule-modal').close()">Cancel</button>
                                <button class="settings-btn-primary" onclick="handleSaveSchedule()">Save</button>
                            </div>
                        </div>
                    </dialog>
                    <dialog id="add-active-hour-modal" class="modal">
                        <div class="modal-box bg-[var(--box-color)] max-w-2xl">
                            <h3 class="font-bold text-[24px] text-[var(--text-primary)] mb-4">Add Active Hours</h3>
                            <div class="space-y-4">
                                <div>
                                    <label class="text-[20px] text-[var(--text-primary)] block mb-2">Start Time</label>
                                    <input type="time" id="active-hour-start-input" class="settings-input-primary">
                                </div>
                                <div>
                                    <label class="text-[20px] text-[var(--text-primary)] block mb-2">End Time</label>
                                    <input type="time" id="active-hour-end-input" class="settings-input-primary">
                                </div>
                                <div>
                                    <label class="text-[20px] text-[var(--text-primary)] block mb-2">Days of Week</label>
                                    <div class="flex gap-2 flex-wrap">
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="1" class="checkbox checkbox-primary mr-1"> Mon</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="2" class="checkbox checkbox-primary mr-1"> Tue</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="3" class="checkbox checkbox-primary mr-1"> Wed</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="4" class="checkbox checkbox-primary mr-1"> Thu</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="5" class="checkbox checkbox-primary mr-1"> Fri</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="6" class="checkbox checkbox-primary mr-1"> Sat</label>
                                        <label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="7" class="checkbox checkbox-primary mr-1"> Sun</label>
                                    </div>
                                </div>
                            </div>
                            <div class="modal-action">
                                <button class="settings-btn-secondary" onclick="document.getElementById('add-active-hour-modal').close()">Cancel</button>
                                <button class="settings-btn-primary" onclick="handleSaveActiveHour()">Save</button>
                            </div>
                        </div>
                    </dialog>
                </div>
            \`;
        }

        // Render DE1 Advanced settings form
        function renderDe1AdvancedSettingsForm(settings) {
            if (!settings) {
                return \`
                    <div class="settings-flex-container">
                        <div class="settings-page-title">
                            <p>Machine Advanced Settings</p>
                        </div>
                        <div class="settings-error-text">Failed to load machine advanced settings</div>
                    </div>
                \`;
            }

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Machine Advanced Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Heater Phase 1 Flow (ml/s)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="heaterPh1FlowInput" class="settings-input-primary"
                                       value="\${settings.heaterPh1Flow !== undefined ? settings.heaterPh1Flow : ''}"
                                       step="0.1" min="0" max="10">
                                <button class="settings-btn-primary"
                                        onclick="updateDe1AdvancedSetting('heaterPh1Flow', parseFloat(document.getElementById('heaterPh1FlowInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Flow rate during heater phase 1
                        </p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Heater Phase 2 Flow (ml/s)</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="heaterPh2FlowInput" class="settings-input-primary"
                                       value="\${settings.heaterPh2Flow !== undefined ? settings.heaterPh2Flow : ''}"
                                       step="0.1" min="0" max="10">
                                <button class="settings-btn-primary"
                                        onclick="updateDe1AdvancedSetting('heaterPh2Flow', parseFloat(document.getElementById('heaterPh2FlowInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Flow rate during heater phase 2
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Skin settings
        function renderSkinSettings() {
            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Skin Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                   
                        <p class="setting-description">
                            Customer your own skin specific settings.
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Language settings
        function renderLanguageSettings() {
            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Language Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Display Language</p>
                            </div>
                            <select id="language-switcher" class="settings-input-wide">
                                <option>English</option>
                                <option>Spanish</option>
                                <option>French</option>
                            </select>
                        </div>
                        <p class="setting-description">
                            Choose the language for the application interface
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Extensions settings
        function renderExtensionsSettings() {
            // After returning the template, set up the event listeners
            setTimeout(setupVisualizerEventListeners, 0);
            
            return \`
                <div class="flex flex-col gap-[60px] items-start relative w-full max-w-full overflow-x-hidden">
                    <div class="flex flex-col font-['Inter:Semi_Bold',sans-serif] font-semibold justify-center leading-[0] not-italic relative text-[var(--text-primary)] text-[36px] text-center w-full">
                        <p class="leading-[1.2]">Extensions Settings</p>
                    </div>

                    <div class="flex flex-col items-start relative w-full max-w-full">
                        <div class="flex flex-col gap-[30px] items-start relative w-full max-w-full">
                            <div class="flex items-center justify-between relative w-full max-w-full">
                                <div class="flex flex-col font-['Inter:Bold',sans-serif] font-bold justify-center leading-[0] not-italic relative text-[#385a92] text-[30px]">
                                    <p class="leading-[1.2]">Visualizer</p>
                                    <p class="font-['Inter:Regular',sans-serif] font-normal leading-[1.4] not-italic relative text-[var(--text-primary)] text-[24px] w-full">
                        Enable or disable the Visualizer extension
                    </p>
                                </div>
                                <select id="visualizer-enabled" class="bg-[#385a92] border-2 border-[#385a92] border-solid h-[62.88px] rounded-[2617.374px] w-[200px] text-white text-[24px] p-2">
                                    <option value="true">Enabled</option>
                                    <option value="false">Disabled</option>
                                </select>
                            </div>

                             <div class="justify-between grid-cols-4 mt-2 w-full">
                        <div id="visualizer-form-container" class="w-full mt-6">
                            <div class="grid grid-cols-4">
                                <div class="col-span-3 flex flex-col gap-6">
                                    <div class="flex flex-col gap-2">
                                        <label for="visualizer-username" class="text-[var(--text-primary)] text-[24px]">Username:</label>
                                        <input type="text" id="visualizer-username" class="w-full max-w-[500px] p-3 rounded-lg border border-[var(--border-color)] bg-[var(--profile-button-background-color)] text-[var(--text-primary)] text-[24px] focus:outline-none focus:ring-2 focus:ring-[var(--mimoja-blue)]" placeholder="Enter your Visualizer username">
                                    </div>
                                    <div class="flex flex-col gap-2">
                                        <label for="visualizer-password" class="text-[var(--text-primary)] text-[24px]">Password:</label>
                                        <input type="password" id="visualizer-password" class="w-full max-w-[500px] p-3 rounded-lg border border-[var(--border-color)] bg-[var(--profile-button-background-color)] text-[var(--text-primary)] text-[24px] focus:outline-none focus:ring-2 focus:ring-[var(--mimoja-blue)]" placeholder="Enter your Visualizer password">
                                    </div>
                                    <div class="flex items-center gap-4">
                                        <label for="visualizer-auto-upload" class="text-[var(--text-primary)] text-[24px]">Auto-upload shots to Visualizer</label>
                                        <input type="checkbox" id="visualizer-auto-upload" class="w-8 h-8">
                                    </div>
                                    <div class="flex items-center gap-4">
                                        <label for="visualizer-min-duration" class="text-[var(--text-primary)] text-[24px]">Minimum Shot Duration (seconds):</label>
                                        <input type="number" id="visualizer-min-duration" class="w-24 p-3 rounded-lg border border-[var(--border-color)] bg-[var(--profile-button-background-color)] text-[var(--text-primary)] text-[24px] focus:outline-none focus:ring-2 focus:ring-[var(--mimoja-blue)]" min="1" value="5">
                                    </div>
                                </div>
                                <div class="col-span-1 col-end-5 flex justify-end">
                                    <button id="save-visualizer-credentials" class=" w-[150px] h-[50px] pt-3 pb-[15px] border border-solid border-[var(--mimoja-blue)] text-[var(--mimoja-blue)] rounded-[22.5px]">
                                        Save Credentials
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                        </div>
                    </div>

                    

                    
                </div>
            \`;
        }

        // Render Updates settings
        function renderUpdatesSettings() {
            const infoAvailable = !!appInfo;
            const appInfoDetails = infoAvailable ? \`
                <div class="grid gap-4 sm:grid-cols-2">
                    <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
                        <p class="text-[20px] font-bold text-[#385a92]">Version</p>
                        <p class="text-[24px]">\${appInfo.version} (\${appInfo.buildNumber})</p>
                        <p class="text-[16px] text-[var(--text-secondary)]">Full: \${appInfo.fullVersion}</p>
                        <p class="text-[16px] text-[var(--text-secondary)]">\${formatBuildTimestamp(appInfo.buildTime)}</p>
                    </div>
                    <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
                        <p class="text-[20px] font-bold text-[#385a92]">Source</p>
                        <p class="text-[24px]">\${appInfo.branch}</p>
                        <p class="text-[16px] text-[var(--text-secondary)]">Commit: \${appInfo.commitShort}</p>
                        <p class="text-[16px] text-[var(--text-secondary)]">App Store: \${appInfo.appStore ? 'Yes' : 'No'}</p>
                    </div>
                </div>
            \` : \`
                <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
                    <p class="text-[20px] font-bold text-[#385a92]">Update info</p>
                    <p class="text-[24px]">Fetching build metadata...</p>
                </div>
            \`;

            const machineExtra = formatMachineExtra(machineInfo?.extra);
            const machineDetails = machineInfo ? \`
                <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
                    <p class="text-[20px] font-bold text-[#385a92]">Machine</p>
                    <p class="text-[24px]">\${machineInfo.model}</p>
                    <p class="text-[16px] text-[var(--text-secondary)]">Version: \${machineInfo.version}</p>
                    <p class="text-[16px] text-[var(--text-secondary)]">Serial: \${machineInfo.serialNumber}</p>
                    <p class="text-[16px] text-[var(--text-secondary)]">GHC: \${machineInfo.GHC ? 'Enabled' : 'Disabled'}</p>
                    <p class="text-[16px] text-[var(--text-secondary)] break-words">\${machineExtra}</p>
                </div>
            \` : \`
                <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
                    <p class="text-[20px] font-bold text-[#385a92]">Machine Info</p>
                    <p class="text-[24px]">Fetching machine info...</p>
                </div>
            \`;

            return \`
                <div class="content-stretch flex flex-col gap-[60px] items-start relative w-full">
                    <div class="flex flex-col font-semibold justify-center text-[var(--text-primary)] text-[36px] text-center w-full">
                        <p class="leading-[1.2]">Updates Settings</p>
                    </div>
                    <div class="content-stretch flex flex-col items-start relative w-full space-y-10">
                        <div class="flex flex-col gap-[30px] w-full">
                            <div class="flex flex-col gap-3">
                                <div class="flex items-center justify-between">
                                    <div class="font-bold text-[#385a92] text-[30px]">Firmware Update</div>
                                    <button class="settings-btn-wide">Check</button>
                                </div>
                                <p class="text-[24px] text-[var(--text-primary)]">Check for firmware updates</p>
                            </div>
                            <div class="flex flex-col gap-3">
                                <div class="flex items-center justify-between">
                                    <div class="font-bold text-[#385a92] text-[30px]">App Update</div>
                                    <button class="settings-btn-wide">Check</button>
                                </div>
                                <p class="text-[24px] text-[var(--text-primary)]">Check for application updates</p>
                            </div>
                        </div>
                        <div class="w-full flex flex-col gap-4">
                            <div class="flex flex-col gap-4">
                                <p class="font-bold text-[#385a92] text-[30px]">Build Information</p>
                                \${appInfoDetails}
                            </div>
                            <div class="flex flex-col gap-4">
                                <p class="font-bold text-[#385a92] text-[30px]">Machine Details</p>
                                \${machineDetails}
                            </div>
                        </div>
                    </div>
                </div>
            \`;
        }

        // Render User Manual settings
        function renderUserManualSettings() {
            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>User Manual</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Online Help</p>
                            </div>
                            <a href="https://decentespresso.com/support/submit" target="_blank" class="settings-btn-wide" style="text-decoration: none; display: flex; align-items: center; justify-content: center;">
                                Visit
                            </a>
                        </div>
                        <p class="setting-description">
                            Get support and submit tickets for assistance
                        </p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Tutorials</p>
                            </div>
                            <a href="https://decentespresso.com/doc/quickstart/" target="_blank" class="settings-btn-wide" style="text-decoration: none; display: flex; align-items: center; justify-content: center;">
                                View
                            </a>
                        </div>
                        <p class="setting-description">
                            Learn how to get started with your espresso machine
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Calibration settings
        function renderCalibrationSettings() {
            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Calibration Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Default Load Settings -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Default Load Settings</p>
                            </div>
                            <button class="settings-btn-wide" onclick="updateCalibrationSetting('defaultLoad', 0)">Reset</button>
                        </div>
                        <p class="setting-description">
                            Reset to default calibration values
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Refill Kit -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Refill Kit</p>
                            </div>
                            <button class="settings-btn-wide" onclick="window.calibrateRefillKit()">Calibrate</button>
                        </div>
                        <p class="setting-description">
                            Calibrate refill kit settings
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Voltage -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Voltage</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="voltageInput" class="settings-input-primary"
                                       value="\${calibrationSettings.voltage !== undefined ? calibrationSettings.voltage : 120}"
                                       step="0.1" min="0" max="240">
                                <button class="settings-btn-primary"
                                        onclick="updateCalibrationSetting('voltage', parseFloat(document.getElementById('voltageInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Set voltage calibration
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Flow Estimation Multiplier -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Flow Estimation Multiplier</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="flowEstimationMultiplierInput" class="settings-input-primary"
                                       value="\${calibrationSettings.flowEstimationMultiplier !== undefined ? calibrationSettings.flowEstimationMultiplier : 1.0}"
                                       step="0.1" min="0" max="5">
                                <button class="settings-btn-primary"
                                        onclick="updateCalibrationSetting('flowEstimationMultiplier', parseFloat(document.getElementById('flowEstimationMultiplierInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Multiplier for flow estimation calibration
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Stop at Weight -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Stop at Weight</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="stopAtWeightInput" class="settings-input-primary"
                                       value="\${calibrationSettings.stopAtWeight !== undefined ? calibrationSettings.stopAtWeight : 36}"
                                       step="0.1" min="0" max="100">
                                <button class="settings-btn-primary"
                                        onclick="updateCalibrationSetting('stopAtWeight', parseFloat(document.getElementById('stopAtWeightInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Set weight target for stopping shots
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Slow Start -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Slow Start</p>
                            </div>
                            <div class="setting-control-flex">
                                <select class="settings-input-wide"
                                        onchange="updateCalibrationSetting('slowStart', this.value === 'Enabled')">
                                    <option value="Enabled" \${calibrationSettings.slowStart === true ? 'selected' : ''}>Enabled</option>
                                    <option value="Disabled" \${calibrationSettings.slowStart === false ? 'selected' : ''}>Disabled</option>
                                </select>
                            </div>
                        </div>
                        <p class="setting-description">
                            Enable slow start for smoother extraction
                        </p>
                    </div>
                    
                    <div class="settings-divider"><hr /></div>
                    
                    <!-- Steam Calibration -->
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Steam</p>
                            </div>
                            <div class="setting-control-flex">
                                <input type="number" id="steamCalibrationInput" class="settings-input-primary"
                                       value="\${calibrationSettings.steam !== undefined ? calibrationSettings.steam : 120}"
                                       step="1" min="0" max="200">
                                <button class="settings-btn-primary"
                                        onclick="updateCalibrationSetting('steam', parseInt(document.getElementById('steamCalibrationInput').value))">
                                    Save
                                </button>
                            </div>
                        </div>
                        <p class="setting-description">
                            Set steam calibration
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Maintenance settings
        function renderMaintenanceSettings() {
            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Maintenance Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Machine Descaling</p>
                            </div>
                            <button class="settings-btn-wide">Start</button>
                        </div>
                        <p class="setting-description">
                            Run a descaling cycle to remove mineral buildup
                        </p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Transport Mode</p>
                            </div>
                            <select class="settings-input-wide">
                                <option>Disabled</option>
                                <option>Enabled</option>
                            </select>
                        </div>
                        <p class="setting-description">
                            Enable transport mode for safe transportation
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Miscellaneous settings
        function renderMiscellaneousSettings() {
            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Miscellaneous Settings</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Screen Saver</p>
                            </div>
                            <select class="settings-input-wide">
                                <option>Enabled</option>
                                <option>Disabled</option>
                            </select>
                        </div>
                        <p class="setting-description">
                            Enable or disable screen saver functionality
                        </p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Brightness</p>
                            </div>
                            <input type="range" min="0" max="100" value="75" style="width: 200px; height: 30px;">
                        </div>
                        <p class="setting-description">
                            Adjust screen brightness level
                        </p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>App Version</p>
                            </div>
                            <div class="settings-btn-wide" style="display: flex; align-items: center; justify-content: center;">
                                1.0.0
                            </div>
                        </div>
                        <p class="setting-description">
                            Current application version
                        </p>
                    </div>
                </div>
            \`;
        }

        // Render Bluetooth Machine settings
        function renderBluetoothMachineSettings() {
            setTimeout(() => {
                initDeviceWebSocket();
                renderDeviceListFromCache();
            }, 0);

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Bluetooth Machine</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Espresso Machine</p>
                            </div>
                            <button class="btn-scan" onclick="window.scanForMachines()">Scan</button>
                        </div>
                        <p class="setting-description">
                            Scan and connect to espresso machines
                        </p>
                        <div id="bluetooth-machine-devices-container"></div>
                    </div>
                </div>
            \`;
        }

        async function scanForDeviceType(label) {
            try {
                initDeviceWebSocket();
                deviceStateCache.scanning = true;
                renderDeviceListFromCache();
                showToast('Scanning for ' + label.toLowerCase() + '...');
                sendDeviceCommand({ command: 'scan' });
                showToast('Scanning started, results will appear shortly');
            } catch (error) {
                deviceStateCache.scanning = false;
                renderDeviceListFromCache();
                console.error('Error scanning for ' + label.toLowerCase() + ':', error);
                showToast('Error scanning for ' + label.toLowerCase() + ': ' + error.message, true);
            }
        }

        window.scanForMachines = async function() {
            await scanForDeviceType('machines');
        };

        window.scanForScales = async function() {
            await scanForDeviceType('scales');
        };

        // Render Bluetooth Scale settings
        function renderBluetoothScaleSettings() {
            setTimeout(() => {
                initDeviceWebSocket();
                renderDeviceListFromCache();
            }, 0);

            return \`
                <div class="settings-flex-container">
                    <div class="settings-page-title">
                        <p>Bluetooth Scale</p>
                    </div>
                    <div class="settings-divider"><hr /></div>
                    <div class="settings-section-flex">
                        <div class="setting-row-flex">
                            <div class="setting-label-bold">
                                <p>Scale</p>
                            </div>
                            <button class="btn-scan" onclick="window.scanForScales()">Scan</button>
                        </div>
                        <p class="setting-description">
                            Scan and connect to weighing scales
                        </p>
                        <div id="bluetooth-scale-devices-container"></div>
                    </div>
                </div>
            \`;
        }

        // Initialize resizable panels
        function initResizablePanels() {
            const subCategoriesSeparator = document.getElementById('sub-categories-separator');
            const separator = document.getElementById('separator');
            const mainCategoriesPanel = document.getElementById('main-categories-panel');
            const subcategoriesPanel = document.getElementById('sub-categories-panel');
            const leftPanel = document.getElementById('left-panel');
            const rightPanel = document.getElementById('right-panel');

            // Main categories / Subcategories resizer (sub-categories-separator)
            if (subCategoriesSeparator && mainCategoriesPanel && subcategoriesPanel) {
                let isDragging = false;

                subCategoriesSeparator.addEventListener('mousedown', (e) => {
                    isDragging = true;
                    document.body.style.cursor = 'col-resize';
                    document.body.style.userSelect = 'none';

                    const startX = e.clientX;
                    const startMainWidth = mainCategoriesPanel.offsetWidth;
                    const startSubWidth = subcategoriesPanel.offsetWidth;

                    function doDrag(e) {
                        if (!isDragging) return;
                        const dx = e.clientX - startX;
                        const newMainWidth = startMainWidth + dx;
                        const newSubWidth = startSubWidth - dx;

                        if (newMainWidth > 150 && newSubWidth > 100) {
                            mainCategoriesPanel.style.width = \`\${newMainWidth}px\`;
                            subcategoriesPanel.style.width = \`\${newSubWidth}px\`;
                        }
                    }

                    function stopDrag() {
                        isDragging = false;
                        document.body.style.cursor = '';
                        document.body.style.userSelect = '';
                        document.removeEventListener('mousemove', doDrag);
                        document.removeEventListener('mouseup', stopDrag);
                    }

                    document.addEventListener('mousemove', doDrag);
                    document.addEventListener('mouseup', stopDrag);
                });
            }

            // Left panel / Right panel resizer (separator)
            if (separator && leftPanel && rightPanel) {
                let isDragging = false;

                separator.addEventListener('mousedown', (e) => {
                    isDragging = true;
                    document.body.style.cursor = 'col-resize';
                    document.body.style.userSelect = 'none';

                    const startX = e.clientX;
                    const startLeftWidth = leftPanel.offsetWidth;

                    function doDrag(e) {
                        if (!isDragging) return;
                        const dx = e.clientX - startX;
                        const newLeftWidth = startLeftWidth + dx;

                        if (newLeftWidth > 300 && newLeftWidth < 800) {
                            leftPanel.style.width = \`\${newLeftWidth}px\`;
                        }
                    }

                    function stopDrag() {
                        isDragging = false;
                        document.body.style.cursor = '';
                        document.body.style.userSelect = '';
                        document.removeEventListener('mousemove', doDrag);
                        document.removeEventListener('mouseup', stopDrag);
                    }

                    document.addEventListener('mousemove', doDrag);
                    document.addEventListener('mouseup', stopDrag);
                });
            }
        }

        // Initialize search functionality
        function initSettingsSearch() {
            const searchInput = document.getElementById('settings-search');
            if (!searchInput) return;

            searchInput.addEventListener('input', (e) => {
                const searchTerm = e.target.value.toLowerCase().trim();

                if (searchTerm === '') {
                    // Restore original navigation
                    renderMainCategories();
                    // Auto-click first category to populate subcategories
                    setTimeout(() => {
                        const firstCategoryBtn = document.querySelector('.main-category-btn');
                        if (firstCategoryBtn) {
                            firstCategoryBtn.click();
                        }
                    }, 50);
                    return;
                }

                // Filter and search
                const results = [];

                for (const [key, category] of Object.entries(settingsTree)) {
                    // Check if main category matches
                    if (category.name.toLowerCase().includes(searchTerm)) {
                        results.push({ type: 'category', key, name: category.name });
                    }

                    // Check subcategories
                    category.subcategories.forEach(subcat => {
                        if (subcat.name.toLowerCase().includes(searchTerm)) {
                            results.push({
                                type: 'subcategory',
                                categoryKey: key,
                                subcatKey: subcat.id,
                                settingsCategory: subcat.settingsCategory,
                                name: subcat.name
                            });
                        }
                    });
                }

                // Display search results
                displaySearchResults(results, searchTerm);
            });
        }

        function displaySearchResults(results, searchTerm) {
            const mainPanel = document.getElementById('main-categories-panel');
            const subPanel = document.getElementById('sub-categories-panel');

            if (!mainPanel || !subPanel) return;

            if (results.length === 0) {
                mainPanel.innerHTML = '<p style="padding: 20px; color: var(--text-secondary);">No results found</p>';
                subPanel.innerHTML = '';
                return;
            }

            const categoryResults = {};
            results.forEach((result) => {
                if (result.type === 'category') {
                    if (!categoryResults[result.key]) {
                        categoryResults[result.key] = {
                            name: result.name,
                            subcategories: [],
                            isSearchMatch: true,
                        };
                    }
                } else if (result.type === 'subcategory') {
                    if (!categoryResults[result.categoryKey]) {
                        categoryResults[result.categoryKey] = {
                            name: settingsTree[result.categoryKey].name,
                            subcategories: [],
                            isSearchMatch: false,
                        };
                    }
                    categoryResults[result.categoryKey].subcategories.push(result);
                }
            });

            let mainHtml = '<nav><ul style="list-style: none; padding: 0; margin: 0;">';
            for (const [key, data] of Object.entries(categoryResults)) {
                const highlightedName = highlightMatch(data.name, searchTerm);
                mainHtml += \`
                    <li>
                        <button class="main-category-btn active"
                                data-category="\${key}"
                                onclick="handleSearchCategoryClick('\${key}', this)">
                            \${highlightedName}
                        </button>
                    </li>
                \`;
            }
            mainHtml += '</ul></nav>';
            mainPanel.innerHTML = mainHtml;

            const firstCategory = Object.keys(categoryResults)[0];
            if (firstCategory && categoryResults[firstCategory].subcategories.length > 0) {
                handleSearchCategoryClick(firstCategory, mainPanel.querySelector('.main-category-btn'));
            } else if (firstCategory) {
                renderSubcategories(firstCategory);
            }
        }

        function handleSearchCategoryClick(categoryKey, button) {
            document.querySelectorAll('.main-category-btn').forEach((btn) => btn.classList.remove('active'));
            if (button) {
                button.classList.add('active');
            }

            const searchInput = document.getElementById('settings-search');
            const searchTerm = searchInput ? searchInput.value.toLowerCase().trim() : '';
            const category = settingsTree[categoryKey];
            const subPanel = document.getElementById('sub-categories-panel');

            if (!category || !subPanel) return;

            const matchingSubcats = category.subcategories.filter((subcat) => subcat.name.toLowerCase().includes(searchTerm));

            if (matchingSubcats.length === 0) {
                subPanel.innerHTML = '';
                return;
            }

            let subHtml = '<ul style="list-style: none; padding: 0; margin: 0;">';
            matchingSubcats.forEach((subcat, index) => {
                const highlightedName = highlightMatch(subcat.name, searchTerm);
                subHtml += \`
                    <li>
                        <button class="subcategory-btn \${index === 0 ? 'active' : ''}"
                                data-category="\${subcat.settingsCategory}"
                                onclick="handleSubcategoryClick('\${subcat.settingsCategory}', this, '\${subcat.name.replace(/'/g, "\\'")}')">
                            \${highlightedName}
                        </button>
                    </li>
                \`;
            });
            subHtml += '</ul>';
            subPanel.innerHTML = subHtml;

            const first = matchingSubcats[0];
            if (first) {
                handleSubcategoryClick(first.settingsCategory, subPanel.querySelector('.subcategory-btn'), first.name);
            }
        }

        function highlightMatch(text, searchTerm) {
            if (!searchTerm) return text;
            const escaped = searchTerm.replace(/[.*+?^\${}()|[\]\\]/g, '\\$&');
            const regex = new RegExp(\`(\${escaped})\`, 'gi');
            return text.replace(regex, '<mark style="background: #fef08a; color: #000; padding: 0 4px; border-radius: 2px;">$1</mark>');
        }

        function updateBrightnessSliderState(value = previousBrightnessState) {
            const slider = document.getElementById('brightness-slider');
            if (!slider) return;

            const currentValue = Number.isFinite(value) ? value : parseInt(slider.value || '75', 10);
            slider.value = currentValue;
            const percentage = Math.max(0, Math.min(100, currentValue));
            slider.style.background = \`linear-gradient(to right, #385a92 0%, #385a92 \${percentage}%, #e8e8e8 \${percentage}%, #e8e8e8 100%)\`;
        }

        function updateWakeLockToggleState() {
            const toggle = document.getElementById('wake-lock-toggle');
            if (toggle) {
                toggle.checked = localStorage.getItem(STORAGE_KEYS.wakeLockEnabled) === 'true';
            }
        }

        let previousBrightnessState = 75;

        window.handleBrightnessChange = async function(value) {
            try {
                const brightnessValue = parseInt(value, 10);
                previousBrightnessState = brightnessValue;
                updateBrightnessSliderState(brightnessValue);
                await sendDisplayCommand({ command: 'setBrightness', brightness: brightnessValue });
            } catch (error) {
                console.error('Error adjusting brightness:', error);
                showToast('Failed to update brightness', true);
            }
        };

        window.handleWakeLockToggle = async function(enabled) {
            const toggle = document.getElementById('wake-lock-toggle');
            try {
                if (enabled) {
                    await enableWakeLock();
                } else {
                    await disableWakeLock();
                }
                localStorage.setItem(STORAGE_KEYS.wakeLockEnabled, String(enabled));
                updateWakeLockToggleState();
                showToast(\`Wake lock \${enabled ? 'enabled' : 'disabled'}\`);
            } catch (error) {
                console.error('Error toggling wake lock:', error);
                if (toggle) {
                    toggle.checked = !enabled;
                }
                showToast('Failed to toggle wake lock', true);
            }
        };

        window.handlePresenceToggle = async function(enabled) {
            const toggle = document.getElementById('presence-enabled-toggle');
            try {
                await updatePresenceSettings({ userPresenceEnabled: enabled });
                presenceSettings.userPresenceEnabled = enabled;
                showToast(\`Presence detection \${enabled ? 'enabled' : 'disabled'}\`);
            } catch (error) {
                console.error('Error toggling presence detection:', error);
                if (toggle) {
                    toggle.checked = !enabled;
                }
                showToast('Failed to update presence detection', true);
            }
        };

        window.handleSleepTimeoutChange = async function(minutes) {
            const input = document.getElementById('sleep-timeout-input');
            try {
                const value = parseInt(minutes, 10);
                if (value < 1 || value > 120) {
                    throw new Error('Sleep timeout must be between 1 and 120 minutes');
                }
                await updatePresenceSettings({ sleepTimeoutMinutes: value });
                presenceSettings.sleepTimeoutMinutes = value;
                showToast('Sleep timeout updated');
            } catch (error) {
                console.error('Error updating sleep timeout:', error);
                if (input) {
                    input.value = presenceSettings.sleepTimeoutMinutes || 30;
                }
                showToast(error.message || 'Failed to update sleep timeout', true);
            }
        };

        window.handleAddSchedule = function() {
            document.getElementById('add-schedule-modal')?.showModal();
        };

        window.handleSaveSchedule = async function() {
            try {
                const timeInput = document.getElementById('schedule-time-input').value;
                if (!timeInput) {
                    throw new Error('Please select a time');
                }
                const checkboxes = document.querySelectorAll('#add-schedule-modal input[type="checkbox"]:checked');
                const daysOfWeek = Array.from(checkboxes).map((checkbox) => parseInt(checkbox.value, 10));
                await createPresenceSchedule({ time: timeInput, daysOfWeek, enabled: true });
                showToast('Schedule created');
                document.getElementById('schedule-time-input').value = '';
                document.querySelectorAll('#add-schedule-modal input[type="checkbox"]').forEach((checkbox) => { checkbox.checked = false; });
                document.getElementById('add-schedule-modal').close();
                updateSettingsContentArea('presence');
            } catch (error) {
                console.error('Error creating schedule:', error);
                showToast(error.message || 'Failed to create schedule', true);
            }
        };

        window.handleScheduleToggle = async function(scheduleId, enabled) {
            try {
                await updatePresenceSchedule(scheduleId, { enabled });
                showToast(\`Schedule \${enabled ? 'enabled' : 'disabled'}\`);
            } catch (error) {
                console.error('Error toggling schedule:', error);
                const toggle = document.querySelector(\`input[onchange*="\${scheduleId}"]\`);
                if (toggle) {
                    toggle.checked = !enabled;
                }
                showToast('Failed to update schedule', true);
            }
        };

        window.handleDeleteSchedule = async function(scheduleId) {
            if (!confirm('Are you sure you want to delete this schedule?')) return;
            try {
                await deletePresenceSchedule(scheduleId);
                showToast('Schedule deleted');
                updateSettingsContentArea('presence');
            } catch (error) {
                console.error('Error deleting schedule:', error);
                showToast('Failed to delete schedule', true);
            }
        };

        window.handleAddActiveHour = function() {
            document.getElementById('add-active-hour-modal')?.showModal();
        };

        window.handleSaveActiveHour = function() {
            try {
                const startTime = document.getElementById('active-hour-start-input').value;
                const endTime = document.getElementById('active-hour-end-input').value;
                if (!startTime || !endTime) {
                    throw new Error('Please select start and end times');
                }
                if (startTime === endTime) {
                    throw new Error('Start and end times must be different');
                }
                const checkboxes = document.querySelectorAll('#add-active-hour-modal input[type="checkbox"]:checked');
                const daysOfWeek = Array.from(checkboxes).map((checkbox) => parseInt(checkbox.value, 10));
                addActiveHour({ startTime, endTime, daysOfWeek, enabled: true });
                showToast('Active hours created');
                document.getElementById('active-hour-start-input').value = '';
                document.getElementById('active-hour-end-input').value = '';
                document.querySelectorAll('#add-active-hour-modal input[type="checkbox"]').forEach((checkbox) => { checkbox.checked = false; });
                document.getElementById('add-active-hour-modal').close();
                updateSettingsContentArea('presence');
            } catch (error) {
                console.error('Error creating active hours:', error);
                showToast(error.message || 'Failed to create active hours', true);
            }
        };

        window.handleActiveHourToggle = function(id, enabled) {
            try {
                updateActiveHour(id, { enabled });
                showToast(\`Active hours \${enabled ? 'enabled' : 'disabled'}\`);
            } catch (error) {
                console.error('Error toggling active hours:', error);
                showToast('Failed to update active hours', true);
            }
        };

        window.handleDeleteActiveHour = function(id) {
            if (!confirm('Are you sure you want to delete this active hour?')) return;
            try {
                deleteActiveHour(id);
                showToast('Active hours deleted');
                updateSettingsContentArea('presence');
            } catch (error) {
                console.error('Error deleting active hours:', error);
                showToast('Failed to delete active hours', true);
            }
        };

        window.retryLoadSettings = async function() {
            await fetchLatestSettings();
        };

        async function fetchLatestSettings() {
            const contentArea = document.getElementById('settings-content-area');
            if (contentArea) {
                contentArea.innerHTML = renderLoadingState(getCategoryTitle(activeSettingsCategory || 'rea'));
            }
            try {
                const [rea, de1, de1Advanced, nextAppInfo, nextMachineInfo, nextPresence] = await Promise.all([
                    fetchReaSettings(),
                    fetchDe1Settings(),
                    fetchDe1AdvancedSettings(),
                    fetchAppInfo(),
                    fetchMachineInfo(),
                    fetchPresenceSettings(),
                ]);
                if (rea) updateCacheEntry('rea', rea);
                if (de1) updateCacheEntry('de1', de1);
                if (de1Advanced) updateCacheEntry('de1Advanced', de1Advanced);
                if (nextAppInfo) settingsCache.appInfo = nextAppInfo;
                if (nextMachineInfo) settingsCache.machineInfo = nextMachineInfo;
                if (nextPresence) Object.assign(presenceSettings, nextPresence);
                renderSettingsContent(activeSettingsCategory || 'flowmultiplier', getCategoryTitle(activeSettingsCategory || 'flowmultiplier'));
                updateTimestamp();
            } catch (error) {
                console.error('Error refreshing settings:', error);
                showToast('Failed to refresh settings', true);
            }
        }

        // Function to set up event listeners for the Visualizer settings
        async function setupVisualizerEventListeners() {
            const saveButton = document.getElementById('save-visualizer-credentials');
            const usernameInput = document.getElementById('visualizer-username');
            const passwordInput = document.getElementById('visualizer-password');
            const autoUploadCheckbox = document.getElementById('visualizer-auto-upload');
            const minDurationInput = document.getElementById('visualizer-min-duration');
            const enabledSelect = document.getElementById('visualizer-enabled');
            const formContainer = document.getElementById('visualizer-form-container');

            if (!saveButton) {
                console.warn('Save button for Visualizer credentials not found');
                return;
            }

            // Load existing settings when the form loads
            await loadVisualizerSettings();

            // Initially hide the form if disabled
            if (enabledSelect && formContainer) {
                if (enabledSelect.value === 'false') {
                    formContainer.style.display = 'none';
                } else {
                    formContainer.style.display = 'block';
                }
            }

            // Add event listener to toggle form visibility based on selection
            if (enabledSelect) {
                enabledSelect.addEventListener('change', function() {
                    if (this.value === 'true') {
                        formContainer.style.display = 'block';
                    } else {
                        formContainer.style.display = 'none';
                    }
                });
            }

            // Add click handler for the save button
            saveButton.addEventListener('click', async () => {
                const username = usernameInput.value.trim();
                const password = passwordInput.value;

                if (!username || !password) {
                    showToast('Please enter both username and password', true);
                    return;
                }

                try {
                    // Test credentials via Visualizer plugin API - CORRECT ENDPOINT
                    const testResponse = await fetch('http://localhost:8080/api/v1/plugins/visualizer.reaplugin/verifyCredentials', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify({
                            username: username,
                            password: password
                        })
                    });

                    // Handle response - try to parse as JSON regardless of Content-Type header
                    let testResult;
                    const contentType = testResponse.headers.get('content-type');
                    
                    try {
                        testResult = await testResponse.json();
                    } catch (jsonError) {
                        // If JSON parsing fails, get raw text
                        const errorText = await testResponse.text();
                        console.error('Failed to parse response as JSON:', errorText);
                        showToast('Visualizer log-in failed: ' + errorText, true);
                        return;
                    }

                    if (!testResult.valid) {
                        showToast('Visualizer log-in failed, check credentials', true);
                        return;
                    }

                    showToast('Visualizer log-in success', false);

                    // Get form values
                    const autoUpload = autoUploadCheckbox.checked;
                    const minDuration = parseInt(minDurationInput.value, 10) || 5;
                    const isEnabled = enabledSelect.value === 'true';

                    // Save to plugin settings - use correct field names expected by visualizer plugin
                    const pluginId = 'visualizer.reaplugin';
                    const settingsPayload = {
                        Username: username,
                        Password: password,
                        AutoUpload: autoUpload,
                        LengthThreshold: minDuration  // Visualizer plugin uses 'Length' not 'LengthThreshold'
                    };

                    const saveResponse = await fetch('http://localhost:8080/api/v1/plugins/' + pluginId + '/settings', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify(settingsPayload)
                    });

                    // Handle save response
                    const saveContentType = saveResponse.headers.get('content-type');
                    if (saveResponse.ok) {
                        showToast('Visualizer settings saved successfully', false);
                    } else {
                        let errorMessage = 'Failed to save visualizer settings';
                        if (saveContentType && saveContentType.includes('application/json')) {
                            try {
                                const errorData = await saveResponse.json();
                                errorMessage = errorData.message || errorData.error || errorMessage;
                            } catch (jsonError) {
                                console.error('Error parsing JSON response:', jsonError);
                                const errorText = await saveResponse.text();
                                if (errorText) {
                                    errorMessage = errorText;
                                }
                            }
                        } else {
                            const errorText = await saveResponse.text();
                            if (errorText) {
                                errorMessage = errorText;
                            }
                        }
                        showToast(errorMessage, true);
                    }
                } catch (error) {
                    console.error('Error during credential validation:', error);
                    if (error instanceof SyntaxError) {
                        showToast('Invalid response from server, check API endpoint', true);
                    } else {
                        showToast('Error: ' + error.message, true);
                    }
                }
            });
        }

        // Function to load existing Visualizer settings
        async function loadVisualizerSettings() {
            try {
                const pluginId = 'visualizer.reaplugin';

                const response = await fetch('http://localhost:8080/api/v1/plugins/' + pluginId + '/settings');

                let savedSettings = null;
                if (response.ok) {
                    // Try to parse response as JSON directly - don't check Content-Type header
                    // as the response may be valid JSON without the proper header
                    try {
                        savedSettings = await response.json();
                    } catch (parseError) {
                        const errorText = await response.text();
                        console.error('Non-JSON response when loading settings:', errorText);
                        showToast('Failed to load Visualizer settings: Invalid response format', true);
                        return;
                    }
                }

                const usernameInput = document.getElementById('visualizer-username');
                const passwordInput = document.getElementById('visualizer-password');
                const autoUploadCheckbox = document.getElementById('visualizer-auto-upload');
                const minDurationInput = document.getElementById('visualizer-min-duration');
                const enabledSelect = document.getElementById('visualizer-enabled');
                const formContainer = document.getElementById('visualizer-form-container');

                if (savedSettings && savedSettings.Username) {
                    usernameInput.value = savedSettings.Username;
                } else {
                    usernameInput.value = '';
                }

                // Always clear the password field for security
                passwordInput.value = '';

                if (typeof savedSettings.AutoUpload !== 'undefined') {
                    autoUploadCheckbox.checked = !!savedSettings.AutoUpload;
                }

                // Visualizer plugin uses 'Length' not 'LengthThreshold'
                if (typeof savedSettings.Length !== 'undefined') {
                    minDurationInput.value = parseInt(savedSettings.Length, 10) || 5;
                }

                // Enabled state is not stored in plugin, use localStorage as fallback
                const storedEnabled = localStorage.getItem('visualizerEnabled');
                if (storedEnabled !== null) {
                    enabledSelect.value = storedEnabled;
                } else {
                    // Default to enabled if not set
                    enabledSelect.value = 'true';
                }

                // Set form visibility based on the enabled state
                if (formContainer) {
                    if (enabledSelect && enabledSelect.value === 'false') {
                        formContainer.style.display = 'none';
                    } else {
                        formContainer.style.display = 'block';
                    }
                }
            } catch (error) {
                console.error('Failed to load Visualizer settings:', error);
                if (error instanceof SyntaxError) {
                    showToast('Invalid response from server when loading settings', true);
                } else {
                    showToast('Could not load Visualizer plugin settings', true);
                }
            }
        }

        // Toggle fullscreen functionality
        function toggleFullscreen() {
            if (!document.fullscreenElement) {
                document.documentElement.requestFullscreen().catch((e) => {
                    console.log(\`Error attempting to enable fullscreen: \${e.message}\`);
                });
            } else {
                document.exitFullscreen();
            }
        }

        // Initialize navigation when DOM is ready
        document.addEventListener('DOMContentLoaded', async function() {
            await fetchLatestSettings();
            initDeviceWebSocket();
            renderMainCategories(activeMainCategoryKey);
            initResizablePanels();
            initSettingsSearch();
            renderSubcategories(activeMainCategoryKey);
        });
    </script>
</body>
</html>`;
  }

  // Return the plugin object
  return {
    id: "settings.reaplugin",
    version: "0.0.13",

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
          fetchWebUISkins(),
          fetchCalibrationSettings(),
          fetchPresenceSettings(),
          fetchAppInfo(),
          fetchMachineInfo()
        ]).then(([reaSettings, de1Settings, de1AdvancedSettings, webUISkins, calibrationSettings, presenceSettings, appInfo, machineInfo]) => {
          const html = generateSettingsHTML(reaSettings, de1Settings, de1AdvancedSettings, webUISkins, calibrationSettings, presenceSettings, appInfo, machineInfo);
          
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
