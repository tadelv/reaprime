var createPlugin = (function() {
  "use strict";
  const API_BASE_URL = "http://localhost:8080/api/v1";
  const STORAGE_KEYS = {
    presenceActiveHours: "settingsPresenceActiveHours"
  };
  const DEFAULT_REFRESH_INTERVAL = 5;
  const DEFAULT_MAIN_CATEGORY_KEY = "quickadjustments";
  const DEFAULT_DEVICE_STATE_CACHE = {
    devices: [],
    scanning: false,
    initialized: false
  };
  const INITIAL_SETTINGS_CACHE = {
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
    machineInfoError: null
  };
  const settingsTree = {
    quickadjustments: {
      name: "1. Quick Adjustments",
      subcategories: [
        { id: "flowmultiplier", name: "Flow Multiplier", settingsCategory: "flowmultiplier" },
        { id: "steam", name: "Steam", settingsCategory: "steam" },
        { id: "hotwater", name: "Hot Water", settingsCategory: "hotwater" },
        { id: "watertank", name: "Water Tank", settingsCategory: "watertank" },
        { id: "flush", name: "Flush", settingsCategory: "flush" }
      ]
    },
    bluetooth: {
      name: "2. Bluetooth",
      subcategories: [
        { id: "ble_machine", name: "1. Machine", settingsCategory: "ble_machine" },
        { id: "ble_scale", name: "2. Scale", settingsCategory: "ble_scale" }
      ]
    },
    calibration: {
      name: "3. Calibration",
      subcategories: [
        { id: "defaultloadsettings", name: "Default load settings", settingsCategory: "calibration" },
        { id: "refillkit", name: "Refill Kit", settingsCategory: "refillkit" },
        { id: "voltage", name: "Voltage", settingsCategory: "voltage" },
        { id: "fan", name: "Fan", settingsCategory: "fan" },
        { id: "stopatweight", name: "Stop at weight", settingsCategory: "stopatweight" },
        { id: "slowstart", name: "Slow start", settingsCategory: "slowstart" },
        { id: "steam_cal", name: "Steam", settingsCategory: "steam" }
      ]
    },
    machine: {
      name: "4. Machine",
      subcategories: [
        { id: "fanthreshold", name: "Fan Threshold", settingsCategory: "fanthreshold" },
        { id: "usbchargermode", name: "USB Charger Mode", settingsCategory: "usbchargermode" }
      ]
    },
    maintenance: {
      name: "5. Maintenance",
      subcategories: [
        { id: "machinedescaling", name: "Machine Descaling", settingsCategory: "maintenance" },
        { id: "transportmode", name: "Transport mode", settingsCategory: "transportmode" }
      ]
    },
    skin: {
      name: "6. Skin",
      subcategories: [
        { id: "skin1", name: "Theme", settingsCategory: "appearance" }
      ]
    },
    language: {
      name: "7. Language",
      subcategories: [
        { id: "selectlanguage", name: "Select Language", settingsCategory: "language" }
      ]
    },
    extensions: {
      name: "8. Extensions",
      subcategories: [
        { id: "extention1", name: "Visualizer", settingsCategory: "extensions" },
        { id: "extention2", name: "Extention 2", settingsCategory: "extensions" }
      ]
    },
    miscellaneous: {
      name: "9. Miscellaneous",
      subcategories: [
        { id: "reasettings", name: "Rea settings", settingsCategory: "rea" },
        { id: "brightness", name: "Brightness", settingsCategory: "brightness" },
        { id: "wakelock", name: "Wake Lock", settingsCategory: "wakelock" },
        { id: "presence", name: "Presence Detection", settingsCategory: "presence" },
        { id: "appversion", name: "App Version", settingsCategory: "updates" },
        { id: "unitssettings", name: "Units Settings", settingsCategory: "language" },
        { id: "fontsize", name: "Font Size", settingsCategory: "appearance" },
        { id: "resolution", name: "Resolution", settingsCategory: "appearance" },
        { id: "smartcharging", name: "Smart Charging", settingsCategory: "de1" },
        { id: "screensaver", name: "Screen Saver", settingsCategory: "misc" },
        { id: "machineadvancedsettings", name: "Machine Advanced Settings", settingsCategory: "de1advanced" }
      ]
    },
    updates: {
      name: "10. Updates",
      subcategories: [
        { id: "firmwareupdate", name: "Firmware Update", settingsCategory: "updates" },
        { id: "appupdate", name: "App Update", settingsCategory: "updates" }
      ]
    },
    usermanual: {
      name: "11. User Manual",
      subcategories: [
        { id: "onlinehelp", name: "Online Help", settingsCategory: "help" },
        { id: "tutorials", name: "Tutorials", settingsCategory: "help" }
      ]
    }
  };
  function createInitialSettingsCache() {
    return { ...INITIAL_SETTINGS_CACHE };
  }
  function getBrowserBootstrapData({
    reaSettings,
    de1Settings,
    de1AdvancedSettings,
    webUISkins,
    calibrationSettings,
    presenceSettings,
    appInfo,
    machineInfo,
    activeSettingsCategory,
    activeMainCategoryKey
  }) {
    return {
      settingsTree,
      reaSettings: reaSettings || {},
      de1Settings: de1Settings || {},
      de1AdvancedSettings: de1AdvancedSettings || {},
      webUISkins: webUISkins || [],
      calibrationSettings: calibrationSettings || {},
      presenceSettings: presenceSettings || {},
      appInfo: appInfo || null,
      machineInfo: machineInfo || null,
      activeSettingsCategory,
      activeMainCategoryKey,
      apiBaseUrl: API_BASE_URL,
      storageKeys: {
        presenceActiveHours: STORAGE_KEYS.presenceActiveHours
      },
      settingsCache: createInitialSettingsCache(),
      defaultDeviceStateCache: { ...DEFAULT_DEVICE_STATE_CACHE }
    };
  }
  function renderSettingsPageStyles() {
    return `<style>
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
        .success-toast,
        .error-toast {
            position: fixed;
            top: 20px;
            right: 20px;
            color: white;
            padding: 15px 20px;
            border-radius: 6px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
            animation: slideIn 0.3s ease-out;
            z-index: 1000;
        }
        .success-toast { background: var(--status-green-color); }
        .error-toast { background: var(--status-red-color); }
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
        .status-ok { background: var(--status-green-color); }
        .status-error { background: var(--status-red-color); }
        .visually-hidden {
            position: absolute;
            left: -10000px;
            width: 1px;
            height: 1px;
            overflow: hidden;
        }
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
        .settings-divider {
            width: 100%;
        }
        .settings-divider hr {
            border-top: 1px solid var(--low-contrast-white);
            width: 100%;
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
        .setting-control-flex {
            display: flex;
            gap: 12px;
            align-items: center;
            flex-wrap: wrap;
        }
        .settings-input-primary,
        .settings-input-wide {
            border: 2px solid var(--low-contrast-white);
            border-radius: 12px;
            background: var(--profileselectorbg);
            color: var(--text-primary);
            font-family: 'Inter', sans-serif;
            font-size: 20px;
            padding: 12px 16px;
        }
        .settings-input-primary {
            min-width: 120px;
        }
        .settings-input-wide {
            min-width: 220px;
        }
        .settings-btn-primary,
        .settings-btn-secondary,
        .settings-btn-danger,
        .settings-btn-wide {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            border-radius: 22.5px;
            font-family: 'Inter', sans-serif;
            font-size: 20px;
            font-weight: 700;
            padding: 12px 24px;
            cursor: pointer;
            transition: background 0.2s, color 0.2s, transform 0.1s;
            border: 1px solid var(--mimoja-blue);
        }
        .settings-btn-primary {
            background: var(--mimoja-blue);
            color: var(--white);
        }
        .settings-btn-secondary,
        .settings-btn-wide {
            background: transparent;
            color: var(--mimoja-blue);
        }
        .settings-btn-danger {
            background: transparent;
            border-color: var(--status-red-color);
            color: var(--status-red-color);
        }
        .toggle-button-group {
            display: flex;
            gap: 12px;
            flex-wrap: wrap;
        }
        .toggle-btn {
            border-radius: 22.5px;
            padding: 12px 24px;
            border: 1px solid var(--mimoja-blue);
            font-size: 18px;
            font-weight: 700;
            cursor: pointer;
            background: transparent;
            color: var(--mimoja-blue);
        }
        .toggle-btn.active {
            background: var(--mimoja-blue);
            color: var(--white);
        }
        .toggle-btn.inactive {
            background: transparent;
            color: var(--mimoja-blue);
        }
        .device-card {
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: var(--profile-button-background-color);
            border: 1px solid var(--low-contrast-white);
            border-radius: 12px;
            padding: 16px;
            gap: 16px;
        }
        .device-info {
            display: flex;
            flex-direction: column;
            gap: 6px;
            flex: 1;
        }
        .device-header {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .device-name {
            font-size: 22px;
            font-weight: 700;
            color: var(--text-primary);
        }
        .device-detail {
            font-size: 16px;
            color: var(--text-secondary);
        }
        .btn-connect {
            border-radius: 18px;
            padding: 10px 18px;
            border: 1px solid var(--mimoja-blue);
            background: transparent;
            color: var(--mimoja-blue);
            font-weight: 700;
            cursor: pointer;
        }
        .toast-container {
            position: fixed;
            left: 50%;
            bottom: 80px;
            transform: translateX(-50%);
            z-index: 1000;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 10px;
            pointer-events: none;
        }
        .modal-box {
            border-radius: 16px;
            padding: 24px;
        }
        .navigation-container {
            display: flex;
            flex: 1;
            overflow: hidden;
        }
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
        .main-category-btn:hover,
        .main-category-btn.active {
            color: var(--white);
            background: #2c4a7a;
        }
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
        .panel-resizer {
            width: 4px;
            background: var(--low-contrast-white);
            cursor: col-resize;
            transition: background 0.2s;
        }
        .panel-resizer:hover { background: var(--mimoja-blue); }
        .right-panel {
            flex: 1;
            overflow-y: auto;
            padding: 30px;
            background: var(--profile-button-background-color);
        }
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
    </style>`;
  }
  function renderSettingsPageHead() {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="REA Prime Settings Dashboard - Configure application and DE1 machine settings">
    <title>Settings</title>

    <link href="https://fonts.cdnfonts.com/css/noto-sans" rel="stylesheet">
    <link href="https://fonts.cdnfonts.com/css/inter" rel="stylesheet">
    <script src="https://cdn.tailwindcss.com"><\/script>
    <link href="https://cdn.jsdelivr.net/npm/daisyui@5" rel="stylesheet" type="text/css" />

    ${renderSettingsPageStyles()}`;
  }
  function renderSettingsPageLayout(timestamp = (/* @__PURE__ */ new Date()).toLocaleString()) {
    return `</head>
<body class="max-w-[1920px] max-h-[1200px] mx-auto">
    <a href="#main-content" class="skip-link">Skip to main content</a>

    <div id="toast-container" class="toast-container"></div>

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

    <div class="timestamp flex items-center gap-2 px-6 py-4" role="status" aria-live="polite" aria-atomic="true">
        <span class="status-indicator status-ok" role="img" aria-label="Settings loaded successfully"></span>
        Last updated: <span id="timestamp">${timestamp}</span>
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
                <div id="main-categories-panel" class="h-full overflow-y-auto p-2" style="width: 405px;" aria-label="Settings Categories"></div>
                <div id="sub-categories-separator" class="cursor-col-resize w-2 bg-gray-400 hover:bg-blue-500 h-full" aria-hidden="true"></div>
                <div id="sub-categories-panel" class="h-full overflow-y-auto p-2" style="width: 270px; background-color: var(--box-color-alt);" aria-label="Subcategories"></div>
            </div>
        </div>

        <div id="separator" class="cursor-col-resize w-2 bg-gray-300 hover:bg-blue-500 transition-colors z-10 h-full" aria-hidden="true"></div>

        <div id="right-panel" class="w-[1124px] flex-grow h-full flex flex-col bg-[var(--profile-button-background-color)] p-6 overflow-y-auto" role="main" aria-label="Settings Content">
            <div id="settings-content-area" class="flex-grow">
                <div class="flex flex-col items-center justify-center h-full text-center p-8">
                    <p class="text-[var(--text-primary)] text-[28px]" aria-live="polite">Loading Settings...</p>
                </div>
            </div>
        </div>
    </div>`;
  }
  function renderVisualizerSettingsForm() {
    return '\n                        <div id="visualizer-form-container" class="w-full mt-6">\n                            <div class="grid grid-cols-4">\n                                <div class="col-span-3 flex flex-col gap-6">\n                                    <div class="flex flex-col gap-2">\n                                        <label for="visualizer-username" class="text-[var(--text-primary)] text-[24px]">Username:</label>\n                                        <input type="text" id="visualizer-username" class="w-full max-w-[500px] p-3 rounded-lg border border-[var(--border-color)] bg-[var(--profile-button-background-color)] text-[var(--text-primary)] text-[24px] focus:outline-none focus:ring-2 focus:ring-[var(--mimoja-blue)]" placeholder="Enter your Visualizer username">\n                                    </div>\n                                    <div class="flex flex-col gap-2">\n                                        <label for="visualizer-password" class="text-[var(--text-primary)] text-[24px]">Password:</label>\n                                        <input type="password" id="visualizer-password" class="w-full max-w-[500px] p-3 rounded-lg border border-[var(--border-color)] bg-[var(--profile-button-background-color)] text-[var(--text-primary)] text-[24px] focus:outline-none focus:ring-2 focus:ring-[var(--mimoja-blue)]" placeholder="Enter your Visualizer password">\n                                    </div>\n                                    <div class="flex items-center gap-4">\n                                        <label for="visualizer-auto-upload" class="text-[var(--text-primary)] text-[24px]">Auto-upload shots to Visualizer</label>\n                                        <input type="checkbox" id="visualizer-auto-upload" class="w-8 h-8">\n                                    </div>\n                                    <div class="flex items-center gap-4">\n                                        <label for="visualizer-min-duration" class="text-[var(--text-primary)] text-[24px]">Minimum Shot Duration (seconds):</label>\n                                        <input type="number" id="visualizer-min-duration" class="w-24 p-3 rounded-lg border border-[var(--border-color)] bg-[var(--profile-button-background-color)] text-[var(--text-primary)] text-[24px] focus:outline-none focus:ring-2 focus:ring-[var(--mimoja-blue)]" min="1" value="5">\n                                    </div>\n                                </div>\n                                <div class="col-span-1 col-end-5 flex justify-end">\n                                    <button id="save-visualizer-credentials" class=" w-[150px] h-[50px] pt-3 pb-[15px] border border-solid border-[var(--mimoja-blue)] text-[var(--mimoja-blue)] rounded-[22.5px]">\n                                        Save Credentials\n                                    </button>\n                                </div>\n                            </div>\n                        </div>\n';
  }
  function renderVisualizerSection() {
    return [
      '                <div class="flex flex-col gap-[60px] items-start relative w-full max-w-full overflow-x-hidden">',
      `                    <div class="flex flex-col font-['Inter:Semi_Bold',sans-serif] font-semibold justify-center leading-[0] not-italic relative text-[var(--text-primary)] text-[36px] text-center w-full">`,
      '                        <p class="leading-[1.2]">Extensions Settings</p>',
      "                    </div>",
      '                    <div class="flex flex-col items-start relative w-full max-w-full">',
      '                        <div class="flex flex-col gap-[30px] items-start relative w-full max-w-full">',
      '                            <div class="flex items-center justify-between relative w-full max-w-full">',
      `                                <div class="flex flex-col font-['Inter:Bold',sans-serif] font-bold justify-center leading-[0] not-italic relative text-[#385a92] text-[30px]">`,
      '                                    <p class="leading-[1.2]">Visualizer</p>',
      `                                    <p class="font-['Inter:Regular',sans-serif] font-normal leading-[1.4] not-italic relative text-[var(--text-primary)] text-[24px] w-full">`,
      "                        Enable or disable the Visualizer extension",
      "                    </p>",
      "                                </div>",
      '                                <select id="visualizer-enabled" class="bg-[#385a92] border-2 border-[#385a92] border-solid h-[62.88px] rounded-[2617.374px] w-[200px] text-white text-[24px] p-2">',
      '                                    <option value="true">Enabled</option>',
      '                                    <option value="false">Disabled</option>',
      "                                </select>",
      "                            </div>",
      '                             <div class="justify-between grid-cols-4 mt-2 w-full">',
      renderVisualizerSettingsForm(),
      "                    </div>",
      "                        </div>",
      "                    </div>",
      "                </div>"
    ].join("\n");
  }
  function formatDaysOfWeek(days) {
    if (!days || days.length === 0) {
      return "Every day";
    }
    const dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return days.map((day) => dayNames[day - 1]).join(", ");
  }
  function buildPresenceSchedulesHtml(schedules) {
    return schedules.map((schedule) => '<div class="bg-[var(--profile-button-background-color)] rounded-lg p-4 flex items-center justify-between" data-schedule-id="' + schedule.id + '"><div class="flex-grow"><div class="text-[22px] font-semibold text-[var(--text-primary)]">' + schedule.time + " - " + formatDaysOfWeek(schedule.daysOfWeek) + '</div></div><div class="flex items-center gap-4"><input type="checkbox" class="toggle toggle-md toggle-primary" ' + (schedule.enabled ? "checked" : "") + ` onchange="handleScheduleToggle('` + schedule.id + `', this.checked)"><button class="settings-btn-danger" onclick="handleDeleteSchedule('` + schedule.id + `')">Delete</button></div></div>`).join("");
  }
  function buildPresenceActiveHoursHtml(activeHours) {
    return activeHours.map((activeHour) => '<div class="bg-[var(--profile-button-background-color)] rounded-lg p-4 flex items-center justify-between" data-active-hour-id="' + activeHour.id + '"><div class="flex-grow"><div class="text-[22px] font-semibold text-[var(--text-primary)]">' + activeHour.startTime + " - " + activeHour.endTime + " " + formatDaysOfWeek(activeHour.daysOfWeek) + '</div></div><div class="flex items-center gap-4"><input type="checkbox" class="toggle toggle-md toggle-primary" ' + (activeHour.enabled ? "checked" : "") + ` onchange="handleActiveHourToggle('` + activeHour.id + `', this.checked)"><button class="settings-btn-danger" onclick="handleDeleteActiveHour('` + activeHour.id + `')">Delete</button></div></div>`).join("");
  }
  function renderPresenceScheduleModal() {
    return `<dialog id="add-schedule-modal" class="modal"><div class="modal-box bg-[var(--box-color)] max-w-2xl"><h3 class="font-bold text-[24px] text-[var(--text-primary)] mb-4">Add Schedule</h3><div class="space-y-4"><div><label class="text-[20px] text-[var(--text-primary)] block mb-2">Wake Time</label><input type="time" id="schedule-time-input" class="settings-input-primary"></div><div><label class="text-[20px] text-[var(--text-primary)] block mb-2">Days of Week</label><div class="flex gap-2 flex-wrap"><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="1" class="checkbox checkbox-primary mr-1"> Mon</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="2" class="checkbox checkbox-primary mr-1"> Tue</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="3" class="checkbox checkbox-primary mr-1"> Wed</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="4" class="checkbox checkbox-primary mr-1"> Thu</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="5" class="checkbox checkbox-primary mr-1"> Fri</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="6" class="checkbox checkbox-primary mr-1"> Sat</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="7" class="checkbox checkbox-primary mr-1"> Sun</label></div></div></div><div class="modal-action"><button class="settings-btn-secondary" onclick="document.getElementById('add-schedule-modal').close()">Cancel</button><button class="settings-btn-primary" onclick="handleSaveSchedule()">Save</button></div></div></dialog>`;
  }
  function renderPresenceActiveHourModal() {
    return `<dialog id="add-active-hour-modal" class="modal"><div class="modal-box bg-[var(--box-color)] max-w-2xl"><h3 class="font-bold text-[24px] text-[var(--text-primary)] mb-4">Add Active Hours</h3><div class="space-y-4"><div><label class="text-[20px] text-[var(--text-primary)] block mb-2">Start Time</label><input type="time" id="active-hour-start-input" class="settings-input-primary"></div><div><label class="text-[20px] text-[var(--text-primary)] block mb-2">End Time</label><input type="time" id="active-hour-end-input" class="settings-input-primary"></div><div><label class="text-[20px] text-[var(--text-primary)] block mb-2">Days of Week</label><div class="flex gap-2 flex-wrap"><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="1" class="checkbox checkbox-primary mr-1"> Mon</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="2" class="checkbox checkbox-primary mr-1"> Tue</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="3" class="checkbox checkbox-primary mr-1"> Wed</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="4" class="checkbox checkbox-primary mr-1"> Thu</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="5" class="checkbox checkbox-primary mr-1"> Fri</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="6" class="checkbox checkbox-primary mr-1"> Sat</label><label class="cursor-pointer text-[var(--text-primary)]"><input type="checkbox" value="7" class="checkbox checkbox-primary mr-1"> Sun</label></div></div></div><div class="modal-action"><button class="settings-btn-secondary" onclick="document.getElementById('add-active-hour-modal').close()">Cancel</button><button class="settings-btn-primary" onclick="handleSaveActiveHour()">Save</button></div></div></dialog>`;
  }
  function renderPresenceSection({ presenceSettings = {}, activeHours = [] }) {
    const schedules = Array.isArray(presenceSettings.schedules) ? presenceSettings.schedules : [];
    const schedulesHtml = buildPresenceSchedulesHtml(schedules);
    const activeHoursHtml = buildPresenceActiveHoursHtml(activeHours);
    return [
      '                <div class="space-y-6 px-[60px] py-[80px]">',
      "                    <div>",
      '                        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Presence Detection</h2>',
      '                        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">Automatically manage machine sleep/wake based on user presence and schedules.</p>',
      "                    </div>",
      '                    <div class="bg-[var(--box-color)] rounded-lg p-6">',
      '                        <div class="flex items-center justify-between mb-6">',
      "                            <div>",
      '                                <label class="text-[24px] font-semibold text-[var(--text-primary)]">Enable Presence Detection</label>',
      '                                <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-1">Track user presence to automatically sleep the machine</p>',
      "                            </div>",
      '                            <input type="checkbox" id="presence-enabled-toggle" class="toggle toggle-lg toggle-primary" ' + (presenceSettings.userPresenceEnabled ? "checked" : "") + ' onchange="handlePresenceToggle(this.checked)">',
      "                        </div>",
      '                        <div class="mt-6">',
      '                            <label class="text-[22px] font-semibold text-[var(--text-primary)] block mb-3">Sleep Timeout (minutes)</label>',
      '                            <input type="number" id="sleep-timeout-input" class="settings-input-primary" value="' + (presenceSettings.sleepTimeoutMinutes || 30) + '" min="1" max="120" onchange="handleSleepTimeoutChange(this.value)">',
      '                            <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-2">Minutes of inactivity before auto-sleep</p>',
      "                        </div>",
      "                    </div>",
      '                    <div class="bg-[var(--box-color)] rounded-lg p-6">',
      '                        <div class="flex items-center justify-between mb-4">',
      '                            <h3 class="text-[24px] font-semibold text-[var(--text-primary)]">Wake Schedules</h3>',
      '                            <button class="settings-btn-primary" onclick="handleAddSchedule()">Add Schedule</button>',
      "                        </div>",
      '                        <div class="space-y-3">',
      schedules.length > 0 ? schedulesHtml : '                            <p class="text-[var(--text-primary)] opacity-75 text-[18px]">No schedules configured</p>',
      "                        </div>",
      "                    </div>",
      '                    <div class="bg-[var(--box-color)] rounded-lg p-6">',
      '                        <div class="flex items-center justify-between mb-4">',
      "                            <div>",
      '                                <h3 class="text-[24px] font-semibold text-[var(--text-primary)]">Active Hours</h3>',
      '                                <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-1">Machine stays awake during these time windows</p>',
      "                            </div>",
      '                            <button class="settings-btn-primary" onclick="handleAddActiveHour()">Add Active Hours</button>',
      "                        </div>",
      '                        <div class="space-y-3">',
      activeHours.length > 0 ? activeHoursHtml : '                            <p class="text-[var(--text-primary)] opacity-75 text-[18px]">No active hours configured</p>',
      "                        </div>",
      "                    </div>",
      renderPresenceScheduleModal(),
      renderPresenceActiveHourModal(),
      "                </div>"
    ].join("\n");
  }
  function renderBrightnessSection(currentBrightness = 75) {
    return `
    <div class="space-y-6 px-[60px] py-[80px]">
      <div>
        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Screen Brightness</h2>
        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">Adjust screen brightness level.</p>
      </div>
      <div class="bg-[var(--box-color)] rounded-lg p-6">
        <input type="range" id="brightness-slider" min="0" max="100" value="${currentBrightness}" class="brightness-slider flex-grow w-full" onchange="handleBrightnessChange(this.value)">
      </div>
    </div>
  `;
  }
  function renderWakeLockSection(wakeLockEnabled = false) {
    return `
    <div class="space-y-6 px-[60px] py-[80px]">
      <div>
        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Wake Lock Settings</h2>
        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">Control screen wake-lock to prevent the display from sleeping during operation.</p>
      </div>
      <div class="bg-[var(--box-color)] rounded-lg p-6">
        <div class="flex items-center justify-between">
          <div>
            <label class="text-[24px] font-semibold text-[var(--text-primary)]">Enable Wake Lock</label>
            <p class="text-[18px] text-[var(--text-primary)] opacity-75 mt-1">Keep the screen on while the app is active</p>
          </div>
          <input type="checkbox" id="wake-lock-toggle" class="toggle toggle-lg toggle-primary" ${wakeLockEnabled ? "checked" : ""} onchange="handleWakeLockToggle(this.checked)">
        </div>
      </div>
      <div class="text-[18px] text-[var(--text-primary)] opacity-75 mt-4">
        <p><strong>Note:</strong> Wake-lock automatically releases when the display service disconnects.</p>
      </div>
    </div>
  `;
  }
  function renderFlowMultiplierSection(settings = {}) {
    return `
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
                   value="${settings.weightFlowMultiplier !== void 0 ? settings.weightFlowMultiplier : 1}"
                   step="0.1" min="0" max="5">
            <button class="settings-btn-primary"
                    onclick="handleReaSettingSave('weightFlowMultiplier', document.getElementById('weightFlowMultiplierInput').value)">
              Save
            </button>
          </div>
        </div>
        <p class="setting-description">Multiplier for projected weight calculation. Higher values stop shots earlier.</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold">
            <p id="volume-flow-multiplier-label">Volume Flow Multiplier (s)</p>
          </div>
          <div class="setting-control-flex">
            <input type="number" id="volumeFlowMultiplierInput" aria-labelledby="volume-flow-multiplier-label" class="settings-input-primary"
                   value="${settings.volumeFlowMultiplier !== void 0 ? settings.volumeFlowMultiplier : 0.3}"
                   step="0.05" min="0" max="2">
            <button class="settings-btn-primary"
                    onclick="handleReaSettingSave('volumeFlowMultiplier', document.getElementById('volumeFlowMultiplierInput').value)">
              Save
            </button>
          </div>
        </div>
        <p class="setting-description">Look-ahead time in seconds for projected volume calculation. Accounts for system lag.</p>
      </div>
    </div>
  `;
  }
  function renderReaSettingsSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title">
        <p>Bridge Application Settings</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex-column">
          <div class="setting-label-bold">
            <p id="gateway-mode-label">Gateway Mode</p>
          </div>
          <div class="toggle-button-group" role="group" aria-labelledby="gateway-mode-label">
            <button class="toggle-btn ${settings.gatewayMode === "disabled" ? "active" : "inactive"}" onclick="handleReaSettingSave('gatewayMode', 'disabled')">Disabled</button>
            <button class="toggle-btn ${settings.gatewayMode === "tracking" ? "active" : "inactive"}" onclick="handleReaSettingSave('gatewayMode', 'tracking')">Tracking</button>
            <button class="toggle-btn ${settings.gatewayMode === "full" ? "active" : "inactive"}" onclick="handleReaSettingSave('gatewayMode', 'full')">Full</button>
          </div>
        </div>
        <p class="setting-description">Controls how the gateway monitors and controls the espresso machine</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold">
            <p id="log-level-label">Log Level</p>
          </div>
          <div class="setting-control-flex">
            <select id="logLevelSelect" class="settings-input-wide" onchange="handleReaSettingSave('logLevel', this.value)">
              <option value="INFO" ${settings.logLevel === "INFO" ? "selected" : ""}>INFO</option>
              <option value="WARNING" ${settings.logLevel === "WARNING" ? "selected" : ""}>WARNING</option>
              <option value="SEVERE" ${settings.logLevel === "SEVERE" ? "selected" : ""}>SEVERE</option>
            </select>
          </div>
        </div>
        <p class="setting-description">Controls the verbosity of Bridge application logging</p>
      </div>
    </div>
  `;
  }
  function renderSteamSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Steam Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="steam-temperature-label">Steam Temperature</p></div>
          <div class="setting-control-flex">
            <input type="number" id="steamTemperatureInput" class="settings-input-primary" value="${settings.steamTemperature !== void 0 ? settings.steamTemperature : 145}" step="1" min="100" max="180">
            <button class="settings-btn-primary" onclick="handleMachineSettingSave('steamTemperature', document.getElementById('steamTemperatureInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Set the target steam temperature.</p>
      </div>
    </div>
  `;
  }
  function renderHotWaterSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Hot Water Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="hot-water-temp-label">Hot Water Temperature</p></div>
          <div class="setting-control-flex">
            <input type="number" id="hotWaterTemperatureInput" class="settings-input-primary" value="${settings.hotWaterTemperature !== void 0 ? settings.hotWaterTemperature : 90}" step="1" min="20" max="100">
            <button class="settings-btn-primary" onclick="handleMachineSettingSave('hotWaterTemperature', document.getElementById('hotWaterTemperatureInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Set the target hot water temperature.</p>
      </div>
    </div>
  `;
  }
  function renderWaterTankSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Water Tank Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="tank-threshold-label">Low Water Threshold</p></div>
          <div class="setting-control-flex">
            <input type="number" id="waterTankThresholdInput" class="settings-input-primary" value="${settings.waterTankThreshold !== void 0 ? settings.waterTankThreshold : 20}" step="1" min="0" max="100">
            <button class="settings-btn-primary" onclick="handleMachineSettingSave('waterTankThreshold', document.getElementById('waterTankThresholdInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Alert threshold for low water level.</p>
      </div>
    </div>
  `;
  }
  function renderFlushSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Flush Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="flush-time-label">Flush Time</p></div>
          <div class="setting-control-flex">
            <input type="number" id="flushTimeInput" class="settings-input-primary" value="${settings.flushTime !== void 0 ? settings.flushTime : 3}" step="0.5" min="0" max="20">
            <button class="settings-btn-primary" onclick="handleMachineSettingSave('flushTime', document.getElementById('flushTimeInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Duration of automatic flush cycle.</p>
      </div>
    </div>
  `;
  }
  function renderFanThresholdSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Fan Threshold Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="fan-threshold-label">Fan Threshold</p></div>
          <div class="setting-control-flex">
            <input type="number" id="fanThresholdInput" class="settings-input-primary" value="${settings.fanThreshold !== void 0 ? settings.fanThreshold : 60}" step="1" min="0" max="100">
            <button class="settings-btn-primary" onclick="handleMachineSettingSave('fanThreshold', document.getElementById('fanThresholdInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Threshold for activating the fan.</p>
      </div>
    </div>
  `;
  }
  function renderUsbChargerModeSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>USB Charger Mode Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="usb-charger-mode-label">USB Charger Mode</p></div>
          <div class="setting-control-flex">
            <select id="usbChargerModeSelect" class="settings-input-wide" onchange="handleMachineSettingSave('usbChargerMode', this.value)">
              <option value="off" ${settings.usbChargerMode === "off" ? "selected" : ""}>Off</option>
              <option value="auto" ${settings.usbChargerMode === "auto" ? "selected" : ""}>Auto</option>
              <option value="on" ${settings.usbChargerMode === "on" ? "selected" : ""}>On</option>
            </select>
          </div>
        </div>
        <p class="setting-description">Control USB charger behavior.</p>
      </div>
    </div>
  `;
  }
  function renderBluetoothMachineSection() {
    return `
    <div class="space-y-6 px-[60px] py-[80px]">
      <div>
        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Bluetooth Machine</h2>
        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">Scan and manage espresso machine Bluetooth devices.</p>
      </div>
      <div class="bg-[var(--box-color)] rounded-lg p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-[24px] font-semibold text-[var(--text-primary)]">Machines</h3>
          <button class="settings-btn-primary" onclick="handleScanDevices('Machine')">Scan</button>
        </div>
        <div id="bluetooth-machine-devices-container" class="space-y-3">
          <p class="text-[var(--text-primary)] opacity-75 text-[18px]">No device data yet. Press Scan to search for nearby devices.</p>
        </div>
      </div>
    </div>
  `;
  }
  function renderBluetoothScaleSection() {
    return `
    <div class="space-y-6 px-[60px] py-[80px]">
      <div>
        <h2 class="text-[28px] font-bold text-[var(--text-primary)] mb-4">Bluetooth Scale</h2>
        <p class="text-[var(--text-primary)] text-[20px] mb-6 opacity-75">Scan and manage scale Bluetooth devices.</p>
      </div>
      <div class="bg-[var(--box-color)] rounded-lg p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-[24px] font-semibold text-[var(--text-primary)]">Scales</h3>
          <button class="settings-btn-primary" onclick="handleScanDevices('Scale')">Scan</button>
        </div>
        <div id="bluetooth-scale-devices-container" class="space-y-3">
          <p class="text-[var(--text-primary)] opacity-75 text-[18px]">No device data yet. Press Scan to search for nearby devices.</p>
        </div>
      </div>
    </div>
  `;
  }
  function renderCalibrationSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Calibration Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="voltage-label">Voltage</p></div>
          <div class="setting-control-flex">
            <input type="number" id="voltageInput" class="settings-input-primary" value="${settings.voltage !== void 0 ? settings.voltage : 120}" step="0.1" min="0" max="240">
            <button class="settings-btn-primary" onclick="handleCalibrationSettingSave('voltage', document.getElementById('voltageInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Set voltage calibration.</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="stop-weight-label">Stop at Weight</p></div>
          <div class="setting-control-flex">
            <input type="number" id="stopAtWeightInput" class="settings-input-primary" value="${settings.stopAtWeight !== void 0 ? settings.stopAtWeight : 0}" step="0.1" min="0" max="1000">
            <button class="settings-btn-primary" onclick="handleCalibrationSettingSave('stopAtWeight', document.getElementById('stopAtWeightInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Configure stop-at-weight calibration.</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="slow-start-label">Slow Start</p></div>
          <div class="setting-control-flex">
            <input type="number" id="slowStartInput" class="settings-input-primary" value="${settings.slowStart !== void 0 ? settings.slowStart : 0}" step="0.1" min="0" max="20">
            <button class="settings-btn-primary" onclick="handleCalibrationSettingSave('slowStart', document.getElementById('slowStartInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Configure slow-start timing.</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="fan-cal-label">Fan Calibration</p></div>
          <div class="setting-control-flex">
            <input type="number" id="fanCalibrationInput" class="settings-input-primary" value="${settings.fanCalibration !== void 0 ? settings.fanCalibration : 0}" step="1" min="0" max="100">
            <button class="settings-btn-primary" onclick="handleCalibrationSettingSave('fanCalibration', document.getElementById('fanCalibrationInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Set fan calibration offset.</p>
      </div>
    </div>
  `;
  }
  function renderMaintenanceSection() {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Maintenance Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p>Machine Descaling</p></div>
          <button class="settings-btn-wide" onclick="handleMaintenanceAction('descale')">Start</button>
        </div>
        <p class="setting-description">Run the descaling workflow.</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p>Transport Mode</p></div>
          <button class="settings-btn-wide" onclick="handleMaintenanceAction('transport')">Enable</button>
        </div>
        <p class="setting-description">Prepare the machine for transport.</p>
      </div>
    </div>
  `;
  }
  function renderDe1AdvancedSection(settings = {}) {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Machine Advanced Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="heater-ph1-flow-label">Heater Phase 1 Flow</p></div>
          <div class="setting-control-flex">
            <input type="number" id="heaterPh1FlowInput" class="settings-input-primary" value="${settings.heaterPh1Flow !== void 0 ? settings.heaterPh1Flow : 0}" step="0.1" min="0" max="10">
            <button class="settings-btn-primary" onclick="handleAdvancedSettingSave('heaterPh1Flow', document.getElementById('heaterPh1FlowInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Flow rate during heater phase 1.</p>
      </div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p id="heater-ph2-flow-label">Heater Phase 2 Flow</p></div>
          <div class="setting-control-flex">
            <input type="number" id="heaterPh2FlowInput" class="settings-input-primary" value="${settings.heaterPh2Flow !== void 0 ? settings.heaterPh2Flow : 0}" step="0.1" min="0" max="10">
            <button class="settings-btn-primary" onclick="handleAdvancedSettingSave('heaterPh2Flow', document.getElementById('heaterPh2FlowInput').value)">Save</button>
          </div>
        </div>
        <p class="setting-description">Flow rate during heater phase 2.</p>
      </div>
    </div>
  `;
  }
  function renderUpdatesSection(appInfo = null, machineInfo = null) {
    const appInfoDetails = appInfo ? `
    <div class="grid gap-4 sm:grid-cols-2">
      <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
        <p class="text-[20px] font-bold text-[#385a92]">Version</p>
        <p class="text-[24px]">${appInfo.version || "Unknown"}${appInfo.buildNumber ? " (" + appInfo.buildNumber + ")" : ""}</p>
        <p class="text-[16px] text-[var(--text-secondary)]">Full: ${appInfo.fullVersion || "N/A"}</p>
        <p class="text-[16px] text-[var(--text-secondary)]">${appInfo.buildTime || "Build time unavailable"}</p>
      </div>
      <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
        <p class="text-[20px] font-bold text-[#385a92]">Source</p>
        <p class="text-[24px]">${appInfo.branch || "Unknown"}</p>
        <p class="text-[16px] text-[var(--text-secondary)]">Commit: ${appInfo.commitShort || "N/A"}</p>
        <p class="text-[16px] text-[var(--text-secondary)]">App Store: ${appInfo.appStore ? "Yes" : "No"}</p>
      </div>
    </div>
  ` : `
    <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
      <p class="text-[20px] font-bold text-[#385a92]">Update info</p>
      <p class="text-[24px]">Fetching build metadata...</p>
    </div>
  `;
    const machineDetails = machineInfo ? `
    <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
      <p class="text-[20px] font-bold text-[#385a92]">Machine</p>
      <p class="text-[24px]">${machineInfo.model || "Unknown"}</p>
      <p class="text-[16px] text-[var(--text-secondary)]">Version: ${machineInfo.version || "N/A"}</p>
      <p class="text-[16px] text-[var(--text-secondary)]">Serial: ${machineInfo.serialNumber || "N/A"}</p>
      <p class="text-[16px] text-[var(--text-secondary)]">GHC: ${machineInfo.GHC ? "Enabled" : "Disabled"}</p>
    </div>
  ` : `
    <div class="rounded-[10px] border border-[#c9c9c9] p-4 bg-[var(--box-color)]">
      <p class="text-[20px] font-bold text-[#385a92]">Machine Info</p>
      <p class="text-[24px]">Fetching machine info...</p>
    </div>
  `;
    return `
    <div class="content-stretch flex flex-col gap-[60px] items-start relative w-full">
      <div class="flex flex-col font-semibold justify-center text-[var(--text-primary)] text-[36px] text-center w-full">
        <p class="leading-[1.2]">Updates Settings</p>
      </div>
      <div class="content-stretch flex flex-col items-start relative w-full space-y-10">
        <div class="flex flex-col gap-[30px] w-full">
          <div class="flex flex-col gap-3">
            <div class="flex items-center justify-between">
              <div class="font-bold text-[#385a92] text-[30px]">Firmware Update</div>
              <button class="settings-btn-wide" onclick="handleStaticAction('firmware-update')">Check</button>
            </div>
            <p class="text-[24px] text-[var(--text-primary)]">Check for firmware updates</p>
          </div>
          <div class="flex flex-col gap-3">
            <div class="flex items-center justify-between">
              <div class="font-bold text-[#385a92] text-[30px]">App Update</div>
              <button class="settings-btn-wide" onclick="handleStaticAction('app-update')">Check</button>
            </div>
            <p class="text-[24px] text-[var(--text-primary)]">Check for application updates</p>
          </div>
        </div>
        <div class="w-full flex flex-col gap-4">
          <div class="flex flex-col gap-4">
            <p class="font-bold text-[#385a92] text-[30px]">Build Information</p>
            ${appInfoDetails}
          </div>
          <div class="flex flex-col gap-4">
            <p class="font-bold text-[#385a92] text-[30px]">Machine Details</p>
            ${machineDetails}
          </div>
        </div>
      </div>
    </div>
  `;
  }
  function renderHelpSection() {
    return `
    <div class="content-stretch flex flex-col gap-[60px] items-start relative w-full">
      <div class="flex flex-col font-['Inter:Semi_Bold',sans-serif] font-semibold justify-center leading-[0] min-w-full not-italic relative text-[var(--text-primary)] text-[36px] text-center w-[min-content]">
        <p class="leading-[1.2]">User Manual</p>
      </div>

      <div class="content-stretch flex flex-col items-start relative w-full">
        <div class="content-stretch flex flex-col gap-[30px] items-start relative w-full">
          <div class="content-stretch flex items-center justify-between relative w-full">
            <div class="flex flex-col font-['Inter:Bold',sans-serif] font-bold justify-center leading-[0] not-italic relative text-[#385a92] text-[30px]">
              <p class="leading-[1.2]">Online Help</p>
            </div>
            <a href="https://decentespresso.com/support/submit" target="_blank" class="bg-[#385a92] h-[62.88px] rounded-[10px] w-[200px] text-white text-[24px] font-bold flex items-center justify-center">
              Visit
            </a>
          </div>
          <p class="font-['Inter:Regular',sans-serif] font-normal leading-[1.4] not-italic relative text-[var(--text-primary)] text-[24px] w-full">
            Get support and submit tickets for assistance
          </p>
        </div>
      </div>

      <div class="h-0 relative w-full">
        <hr class="border-t border-[#c9c9c9] w-full" />
      </div>

      <div class="content-stretch flex flex-col items-start relative w-full">
        <div class="content-stretch flex flex-col gap-[30px] items-start relative w-full">
          <div class="content-stretch flex items-center justify-between relative w-full">
            <div class="flex flex-col font-['Inter:Bold',sans-serif] font-bold justify-center leading-[0] not-italic relative text-[#385a92] text-[30px]">
              <p class="leading-[1.2]">Tutorials</p>
            </div>
            <a href="https://decentespresso.com/doc/quickstart/" target="_blank" class="bg-[#385a92] h-[62.88px] rounded-[10px] w-[200px] text-white text-[24px] font-bold flex items-center justify-center">
              View
            </a>
          </div>
          <p class="font-['Inter:Regular',sans-serif] font-normal leading-[1.4] not-italic relative text-[var(--text-primary)] text-[24px] w-full">
            Learn how to get started with your espresso machine
          </p>
        </div>
      </div>

      <div class="content-stretch flex flex-col items-start relative w-full">
        <div class="content-stretch flex flex-col gap-[30px] items-start relative w-full">
          <div class="content-stretch flex items-center justify-between relative w-full">
            <div class="flex flex-col font-['Inter:Bold',sans-serif] font-bold justify-center leading-[0] not-italic relative text-[#385a92] text-[30px]">
              <p class="leading-[1.2]">Start writing your own skin.</p>
            </div>
            <a href="https://github.com/tadelv/reaprime/blob/main/doc/Skins.md#skinsmd" target="_blank" class="bg-[#385a92] h-[62.88px] rounded-[10px] w-[200px] text-white text-[24px] font-bold flex items-center justify-center">
              View
            </a>
          </div>
          <p class="font-['Inter:Regular',sans-serif] font-normal leading-[1.4] not-italic relative text-[var(--text-primary)] text-[24px] w-full">
            Learn how to use streamline-bridge to create custom skins and more.
          </p>
        </div>
      </div>
    </div>
  `;
  }
  function renderAppearanceSection() {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Appearance Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p>Theme</p></div>
          <button class="settings-btn-wide" onclick="handleStaticAction('theme')">Select</button>
        </div>
        <p class="setting-description">Choose theme, font size, and display appearance options.</p>
      </div>
    </div>
  `;
  }
  function renderLanguageSection() {
    return `
    <div class="settings-flex-container">
      <div class="settings-page-title"><p>Language Settings</p></div>
      <div class="settings-divider"><hr /></div>
      <div class="settings-section-flex">
        <div class="setting-row-flex">
          <div class="setting-label-bold"><p>Language</p></div>
          <button class="settings-btn-wide" onclick="handleStaticAction('language')">Select</button>
        </div>
        <p class="setting-description">Choose the language for the application interface.</p>
      </div>
    </div>
  `;
  }
  function getDefaultSubcategory(settingsTree2, categoryKey) {
    var _a, _b, _c;
    return ((_c = (_b = (_a = settingsTree2 == null ? void 0 : settingsTree2[categoryKey]) == null ? void 0 : _a.subcategories) == null ? void 0 : _b[0]) == null ? void 0 : _c.settingsCategory) || null;
  }
  const browserRuntimeSource = `
(function () {
  const browserBootstrap = window.__SETTINGS_BOOTSTRAP__ || {};
  const settingsTree = browserBootstrap.settingsTree || {};
  const apiBaseUrl = browserBootstrap.apiBaseUrl || 'http://localhost:8080/api/v1';
  const WS_PROTOCOL = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const REA_HOSTNAME = localStorage.getItem('reaHostname') || window.location.hostname;
  const REA_PORT = 8080;
  let deviceWebSocket = null;
  let deviceStateCache = { devices: [], scanning: false, initialized: false };

  function showToast(message, isError) {
    const toastContainer = document.getElementById('toast-container');
    if (!toastContainer) return;
    const toast = document.createElement('div');
    toast.className = isError ? 'error-toast' : 'success-toast';
    toast.textContent = message;
    toastContainer.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
  }

  function getCategoryTitleLocal(category) {
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
      case 'ble_machine': return 'Bluetooth Machine';
      case 'ble_scale': return 'Bluetooth Scale';
      case 'appearance': return 'Appearance Settings';
      case 'language': return 'Language Settings';
      case 'help': return 'User Manual';
      default: return 'Settings';
    }
  }

  function getDefaultSubcategoryLocal(categoryKey) {
    return settingsTree?.[categoryKey]?.subcategories?.[0]?.settingsCategory || null;
  }

  function activateButtons(selector, button) {
    document.querySelectorAll(selector).forEach((btn) => btn.classList.remove('active'));
    if (button) button.classList.add('active');
  }

  function renderMainCategories(selectedKey) {
    const panel = document.getElementById('main-categories-panel');
    if (!panel) return;
    browserBootstrap.activeMainCategoryKey = selectedKey;
    let html = '<nav><ul style="list-style: none; padding: 0; margin: 0;">';
    for (const [key, category] of Object.entries(settingsTree)) {
      html += '<li><button class="main-category-btn ' + (key === selectedKey ? 'active' : '') + '" data-category="' + key + '">' + category.name + '</button></li>';
    }
    html += '</ul></nav>';
    panel.innerHTML = html;
  }

  function renderSubcategories(categoryKey, selectedCategory) {
    const panel = document.getElementById('sub-categories-panel');
    const category = settingsTree[categoryKey];
    if (!panel || !category) return;
    const activeCategory = selectedCategory || getDefaultSubcategoryLocal(categoryKey);
    let html = '<ul style="list-style: none; padding: 0; margin: 0;">';
    category.subcategories.forEach((subcat) => {
      html += '<li><button class="subcategory-btn ' + (subcat.settingsCategory === activeCategory ? 'active' : '') + '" data-category="' + subcat.settingsCategory + '" data-label="' + subcat.name + '">' + subcat.name + '</button></li>';
    });
    html += '</ul>';
    panel.innerHTML = html;
    if (activeCategory) renderActiveCategory(activeCategory, panel.querySelector('.subcategory-btn.active')?.dataset?.label || getCategoryTitleLocal(activeCategory));
  }

  function initDeviceWebSocket() {
    if (deviceWebSocket && (deviceWebSocket.readyState === WebSocket.OPEN || deviceWebSocket.readyState === WebSocket.CONNECTING)) return;
    deviceWebSocket = new WebSocket(WS_PROTOCOL + '//' + REA_HOSTNAME + ':' + REA_PORT + '/ws/v1/devices');
    deviceWebSocket.addEventListener('message', (event) => {
      try {
        const data = JSON.parse(event.data);
        deviceStateCache.devices = Array.isArray(data.devices) ? data.devices : [];
        deviceStateCache.foundMachines = Array.isArray(data.foundMachines) ? data.foundMachines : null;
        deviceStateCache.foundScales = Array.isArray(data.foundScales) ? data.foundScales : null;
        deviceStateCache.scanning = !!data.scanning;
        deviceStateCache.initialized = true;
        renderBluetoothLists();
      } catch (error) {
        console.error('Error parsing Device WebSocket message:', error);
      }
    });
    deviceWebSocket.addEventListener('close', () => { deviceWebSocket = null; }, { once: true });
  }

  function sendDeviceCommand(command) {
    initDeviceWebSocket();
    if (!deviceWebSocket || deviceWebSocket.readyState !== WebSocket.OPEN) {
      if (deviceWebSocket && deviceWebSocket.readyState === WebSocket.CONNECTING) {
        deviceWebSocket.addEventListener('open', () => {
          try { deviceWebSocket.send(JSON.stringify(command)); } catch (error) { console.error('Error sending device command:', error); }
        }, { once: true });
        return;
      }
      throw new Error('Device WebSocket is not connected. Cannot send command.');
    }
    deviceWebSocket.send(JSON.stringify(command));
  }

  function getBluetoothDevicesByType() {
    const explicitMachines = Array.isArray(deviceStateCache.foundMachines) ? deviceStateCache.foundMachines : null;
    const explicitScales = Array.isArray(deviceStateCache.foundScales) ? deviceStateCache.foundScales : null;
    if (explicitMachines || explicitScales) return { machines: explicitMachines || [], scales: explicitScales || [] };
    const devices = Array.isArray(deviceStateCache.devices) ? deviceStateCache.devices : [];
    return {
      machines: devices.filter((device) => device && device.type === 'machine'),
      scales: devices.filter((device) => device && device.type === 'scale')
    };
  }

  function renderSingleDeviceList(devices) {
    if (!Array.isArray(devices) || devices.length === 0) return '';
    return devices.map((device) => {
      if (!device || !device.name) return '';
      const isConnected = device.state === 'connected';
      const buttonText = isConnected ? 'Disconnect' : 'Connect';
      const buttonAction = isConnected ? 'disconnect' : 'connect';
      return '<div class="device-card">' +
        '<div class="device-info">' +
          '<div class="device-header"><div class="device-name">' + device.name + '</div></div>' +
          '<div class="device-detail">ID: ' + (device.id || 'N/A') + '</div>' +
          '<div class="device-detail">Status: ' + (device.state || 'unknown') + '</div>' +
          '<div class="device-detail">Type: ' + (device.type || 'unknown') + '</div>' +
        '</div>' +
        '<button class="btn-connect" data-device-id="' + device.id + '" data-device-action="' + buttonAction + '">' + buttonText + '</button>' +
      '</div>';
    }).join('');
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
    container.innerHTML = '<p class="setting-description">No ' + type.toLowerCase() + ' devices found.</p>';
  }

  function renderBluetoothLists() {
    const { machines, scales } = getBluetoothDevicesByType();
    renderDeviceList('bluetooth-machine-devices-container', machines, 'Machine');
    renderDeviceList('bluetooth-scale-devices-container', scales, 'Scale');
  }

  function renderActiveCategory(category, displayName) {
    const contentArea = document.getElementById('settings-content-area');
    if (!contentArea) return;
    browserBootstrap.activeSettingsCategory = category;
    const templateMap = {
      presence: 'presence-template',
      brightness: 'brightness-template',
      wakelock: 'wakelock-template',
      flowmultiplier: 'flowmultiplier-template',
      rea: 'rea-template',
      steam: 'steam-template',
      hotwater: 'hotwater-template',
      watertank: 'watertank-template',
      flush: 'flush-template',
      fanthreshold: 'fanthreshold-template',
      usbchargermode: 'usbchargermode-template',
      ble_machine: 'ble_machine-template',
      ble_scale: 'ble_scale-template',
      calibration: 'calibration-template',
      refillkit: 'calibration-template',
      voltage: 'calibration-template',
      fan: 'calibration-template',
      stopatweight: 'calibration-template',
      slowstart: 'calibration-template',
      maintenance: 'maintenance-template',
      transportmode: 'maintenance-template',
      de1advanced: 'de1advanced-template',
      updates: 'updates-template',
      firmwareupdate: 'updates-template',
      appupdate: 'updates-template',
      help: 'help-template',
      onlinehelp: 'help-template',
      tutorials: 'help-template',
      appearance: 'appearance-template',
      language: 'language-template',
      extensions: 'visualizer-template'
    };
    const templateId = templateMap[category];
    if (templateId) {
      contentArea.innerHTML = document.getElementById(templateId)?.innerHTML || '';
      if (category === 'extensions') setupVisualizerEventListeners();
      if (category === 'ble_machine' || category === 'ble_scale') {
        initDeviceWebSocket();
        renderBluetoothLists();
      }
      return;
    }
    contentArea.innerHTML = '<div class="settings-flex-container"><div class="settings-page-title"><p>' + (displayName || getCategoryTitleLocal(category)) + '</p></div><div class="settings-divider"><hr /></div><div class="setting-description"><p>Source migration placeholder for ' + (displayName || getCategoryTitleLocal(category)) + '.</p></div></div>';
  }

  function handleMainCategoryClickImpl(categoryKey, button) {
    browserBootstrap.activeMainCategoryKey = categoryKey;
    activateButtons('.main-category-btn', button);
    renderSubcategories(categoryKey);
  }

  function handleSubcategoryClickImpl(settingsCategory, button) {
    browserBootstrap.activeSettingsCategory = settingsCategory;
    activateButtons('.subcategory-btn', button);
    renderActiveCategory(settingsCategory, button?.dataset?.label || getCategoryTitleLocal(settingsCategory));
  }

  function attachNavigationHandlers() {
    const mainPanel = document.getElementById('main-categories-panel');
    const subPanel = document.getElementById('sub-categories-panel');
    if (mainPanel) {
      mainPanel.addEventListener('click', (event) => {
        const button = event.target.closest('.main-category-btn');
        if (!button) return;
        handleMainCategoryClickImpl(button.dataset.category, button);
      });
    }
    if (subPanel) {
      subPanel.addEventListener('click', (event) => {
        const button = event.target.closest('.subcategory-btn');
        if (!button) return;
        handleSubcategoryClickImpl(button.dataset.category, button);
      });
    }
    document.addEventListener('click', (event) => {
      const button = event.target.closest('.btn-connect');
      if (!button) return;
      const { deviceId, deviceAction } = button.dataset;
      if (!deviceId || !deviceAction) return;
      window.handleDeviceConnection(deviceId, deviceAction);
    });
  }

  function handleSearchInput(value) {
    const searchTerm = value.toLowerCase().trim();
    if (!searchTerm) {
      renderMainCategories(browserBootstrap.activeMainCategoryKey || 'extensions');
      renderSubcategories(browserBootstrap.activeMainCategoryKey || 'extensions', browserBootstrap.activeSettingsCategory || null);
      return;
    }
    const results = findSettingsSearchResultsLocal(searchTerm);
    const categoryResults = buildSearchCategoryResultsLocal(results);
    const mainPanel = document.getElementById('main-categories-panel');
    const subPanel = document.getElementById('sub-categories-panel');
    if (!mainPanel || !subPanel) return;
    if (results.length === 0) {
      mainPanel.innerHTML = '<p style="padding: 20px; color: var(--text-secondary);">No results found</p>';
      subPanel.innerHTML = '';
      return;
    }
    let mainHtml = '<nav><ul style="list-style: none; padding: 0; margin: 0;">';
    for (const [key, data] of Object.entries(categoryResults)) {
      mainHtml += '<li><button class="main-category-btn active" data-category="' + key + '">' + data.name + '</button></li>';
    }
    mainHtml += '</ul></nav>';
    mainPanel.innerHTML = mainHtml;
    const firstCategory = Object.keys(categoryResults)[0];
    if (firstCategory) renderSubcategories(firstCategory);
  }

  function getVisualizerElements() {
    return {
      saveButton: document.getElementById('save-visualizer-credentials'),
      usernameInput: document.getElementById('visualizer-username'),
      passwordInput: document.getElementById('visualizer-password'),
      autoUploadCheckbox: document.getElementById('visualizer-auto-upload'),
      minDurationInput: document.getElementById('visualizer-min-duration'),
      enabledSelect: document.getElementById('visualizer-enabled'),
      formContainer: document.getElementById('visualizer-form-container')
    };
  }

  function setVisualizerFormVisibility(enabledSelect, formContainer) {
    if (!enabledSelect || !formContainer) return;
    formContainer.style.display = enabledSelect.value === 'false' ? 'none' : 'block';
  }

  async function verifyVisualizerCredentialsLocal(username, password) {
    const response = await fetch(apiBaseUrl + '/plugins/visualizer.reaplugin/verifyCredentials', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });
    try {
      return await response.json();
    } catch {
      const errorText = await response.text();
      throw new Error(errorText || 'Invalid response format');
    }
  }

  async function saveVisualizerSettingsLocal(settingsPayload) {
    const response = await fetch(apiBaseUrl + '/plugins/visualizer.reaplugin/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(settingsPayload)
    });
    if (response.ok) return {};
    const contentType = response.headers.get('content-type');
    let errorMessage = 'Failed to save visualizer settings';
    if (contentType && contentType.includes('application/json')) {
      try {
        const errorData = await response.json();
        errorMessage = errorData.message || errorData.error || errorMessage;
      } catch {
        const errorText = await response.text();
        if (errorText) errorMessage = errorText;
      }
    } else {
      const errorText = await response.text();
      if (errorText) errorMessage = errorText;
    }
    throw new Error(errorMessage);
  }

  async function fetchVisualizerSavedSettingsLocal() {
    const response = await fetch(apiBaseUrl + '/plugins/visualizer.reaplugin/settings');
    if (!response.ok) return null;
    try {
      return await response.json();
    } catch {
      const errorText = await response.text();
      throw new Error(errorText || 'Failed to load Visualizer settings: Invalid response format');
    }
  }

  function applyVisualizerSettingsToFormLocal(savedSettings, elements) {
    const { usernameInput, passwordInput, autoUploadCheckbox, minDurationInput, enabledSelect, formContainer } = elements;
    if (usernameInput) usernameInput.value = savedSettings && savedSettings.Username ? savedSettings.Username : '';
    if (passwordInput) passwordInput.value = '';
    if (autoUploadCheckbox && savedSettings && typeof savedSettings.AutoUpload !== 'undefined') autoUploadCheckbox.checked = !!savedSettings.AutoUpload;
    if (minDurationInput && savedSettings && typeof savedSettings.Length !== 'undefined') minDurationInput.value = parseInt(savedSettings.Length, 10) || 5;
    if (enabledSelect) {
      const storedEnabled = localStorage.getItem('visualizerEnabled');
      enabledSelect.value = storedEnabled !== null ? storedEnabled : 'true';
    }
    setVisualizerFormVisibility(enabledSelect, formContainer);
  }

  async function loadVisualizerSettings() {
    try {
      const savedSettings = await fetchVisualizerSavedSettingsLocal();
      applyVisualizerSettingsToFormLocal(savedSettings, getVisualizerElements());
    } catch (error) {
      console.error('Failed to load Visualizer settings:', error);
      showToast(error.message || 'Could not load Visualizer plugin settings', true);
    }
  }

  async function setupVisualizerEventListeners() {
    const elements = getVisualizerElements();
    const { saveButton, usernameInput, passwordInput, autoUploadCheckbox, minDurationInput, enabledSelect, formContainer } = elements;
    if (!saveButton) return;
    await loadVisualizerSettings();
    setVisualizerFormVisibility(enabledSelect, formContainer);
    if (enabledSelect) {
      enabledSelect.addEventListener('change', function() {
        localStorage.setItem('visualizerEnabled', this.value);
        setVisualizerFormVisibility(enabledSelect, formContainer);
      });
    }
    saveButton.addEventListener('click', async () => {
      const username = usernameInput.value.trim();
      const password = passwordInput.value;
      if (!username || !password) {
        showToast('Please enter both username and password', true);
        return;
      }
      try {
        const testResult = await verifyVisualizerCredentialsLocal(username, password);
        if (!testResult.valid) {
          showToast('Visualizer log-in failed, check credentials', true);
          return;
        }
        const settingsPayload = {
          Username: username,
          Password: password,
          AutoUpload: autoUploadCheckbox.checked,
          LengthThreshold: parseInt(minDurationInput.value, 10) || 5
        };
        await saveVisualizerSettingsLocal(settingsPayload);
        showToast('Visualizer settings saved successfully', false);
      } catch (error) {
        console.error('Error during credential validation:', error);
        showToast('Error: ' + error.message, true);
      }
    });
  }

  function getPresenceScheduleModalElements() {
    return {
      dialog: document.getElementById('add-schedule-modal'),
      timeInput: document.getElementById('schedule-time-input'),
      dayCheckboxes: document.querySelectorAll('#add-schedule-modal input[type="checkbox"]'),
      checkedDayCheckboxes: document.querySelectorAll('#add-schedule-modal input[type="checkbox"]:checked')
    };
  }

  function getPresenceActiveHourModalElements() {
    return {
      dialog: document.getElementById('add-active-hour-modal'),
      startInput: document.getElementById('active-hour-start-input'),
      endInput: document.getElementById('active-hour-end-input'),
      dayCheckboxes: document.querySelectorAll('#add-active-hour-modal input[type="checkbox"]'),
      checkedDayCheckboxes: document.querySelectorAll('#add-active-hour-modal input[type="checkbox"]:checked')
    };
  }

  function resetPresenceScheduleModal(elements) {
    elements.timeInput.value = '';
    elements.dayCheckboxes.forEach((checkbox) => { checkbox.checked = false; });
  }

  function resetPresenceActiveHourModal(elements) {
    elements.startInput.value = '';
    elements.endInput.value = '';
    elements.dayCheckboxes.forEach((checkbox) => { checkbox.checked = false; });
  }

  window.handlePresenceToggle = function(enabled) {
    browserBootstrap.presenceSettings.userPresenceEnabled = enabled;
    showToast('Presence detection ' + (enabled ? 'enabled' : 'disabled'));
  };

  window.handleSleepTimeoutChange = function(value) {
    browserBootstrap.presenceSettings.sleepTimeoutMinutes = parseInt(value, 10) || 30;
    showToast('Sleep timeout updated');
  };

  window.handleAddSchedule = function() {
    getPresenceScheduleModalElements().dialog?.showModal();
  };

  window.handleSaveSchedule = function() {
    try {
      const elements = getPresenceScheduleModalElements();
      const timeInput = elements.timeInput.value;
      if (!timeInput) throw new Error('Please select a time');
      showToast('Schedule created');
      resetPresenceScheduleModal(elements);
      elements.dialog.close();
    } catch (error) {
      console.error('Error creating schedule:', error);
      showToast(error.message || 'Failed to create schedule', true);
    }
  };

  window.handleScheduleToggle = function(scheduleId, enabled) {
    showToast('Schedule ' + (enabled ? 'enabled' : 'disabled'));
  };

  window.handleDeleteSchedule = function(scheduleId) {
    if (!confirm('Are you sure you want to delete this schedule?')) return;
    showToast('Schedule deleted');
  };

  window.handleAddActiveHour = function() {
    getPresenceActiveHourModalElements().dialog?.showModal();
  };

  window.handleSaveActiveHour = function() {
    try {
      const elements = getPresenceActiveHourModalElements();
      const startTime = elements.startInput.value;
      const endTime = elements.endInput.value;
      if (!startTime || !endTime) throw new Error('Please select start and end times');
      if (startTime === endTime) throw new Error('Start and end times must be different');
      showToast('Active hours created');
      resetPresenceActiveHourModal(elements);
      elements.dialog.close();
    } catch (error) {
      console.error('Error creating active hours:', error);
      showToast(error.message || 'Failed to create active hours', true);
    }
  };

  window.handleActiveHourToggle = function(id, enabled) {
    showToast('Active hours ' + (enabled ? 'enabled' : 'disabled'));
  };

  window.handleDeleteActiveHour = function(id) {
    if (!confirm('Are you sure you want to delete this active hour?')) return;
    showToast('Active hours deleted');
  };

  window.handleBrightnessChange = function(value) {
    const slider = document.getElementById('brightness-slider');
    if (slider) slider.value = value;
    showToast('Brightness updated to ' + value);
  };

  window.handleWakeLockToggle = function(enabled) {
    const toggle = document.getElementById('wake-lock-toggle');
    if (toggle) toggle.checked = enabled;
    showToast('Wake lock ' + (enabled ? 'enabled' : 'disabled'));
  };

  async function postJson(path, payload) {
    const response = await fetch(apiBaseUrl + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(errorText || ('Request failed: ' + response.status));
    }
    return response.json().catch(() => ({}));
  }

  window.handleReaSettingSave = async function(key, value) {
    try {
      const payload = {};
      payload[key] = value;
      await postJson('/settings', payload);
      browserBootstrap.reaSettings = browserBootstrap.reaSettings || {};
      browserBootstrap.reaSettings[key] = value;
      showToast('REA setting saved: ' + key);
    } catch (error) {
      console.error('Error saving REA setting:', error);
      showToast('Failed to save REA setting: ' + error.message, true);
    }
  };

  window.handleMachineSettingSave = async function(key, value) {
    try {
      const payload = {};
      payload[key] = value;
      await postJson('/machine/settings', payload);
      browserBootstrap.de1Settings = browserBootstrap.de1Settings || {};
      browserBootstrap.de1Settings[key] = value;
      showToast('Machine setting saved: ' + key);
    } catch (error) {
      console.error('Error saving machine setting:', error);
      showToast('Failed to save machine setting: ' + error.message, true);
    }
  };

  window.handleCalibrationSettingSave = async function(key, value) {
    try {
      const payload = {};
      payload[key] = value;
      await postJson('/machine/calibration', payload);
      browserBootstrap.calibrationSettings = browserBootstrap.calibrationSettings || {};
      browserBootstrap.calibrationSettings[key] = value;
      showToast('Calibration setting saved: ' + key);
    } catch (error) {
      console.error('Error saving calibration setting:', error);
      showToast('Failed to save calibration setting: ' + error.message, true);
    }
  };

  window.handleAdvancedSettingSave = async function(key, value) {
    try {
      const payload = {};
      payload[key] = value;
      await postJson('/machine/settings/advanced', payload);
      browserBootstrap.de1AdvancedSettings = browserBootstrap.de1AdvancedSettings || {};
      browserBootstrap.de1AdvancedSettings[key] = value;
      showToast('Advanced setting saved: ' + key);
    } catch (error) {
      console.error('Error saving advanced setting:', error);
      showToast('Failed to save advanced setting: ' + error.message, true);
    }
  };

  window.handleMaintenanceAction = function(action) {
    showToast('Maintenance action: ' + action);
  };

  window.handleStaticAction = function(action) {
    showToast('Action: ' + action);
  };

  window.handleScanDevices = function(label) {
    try {
      initDeviceWebSocket();
      deviceStateCache.scanning = true;
      renderBluetoothLists();
      showToast('Scanning for ' + label.toLowerCase() + '...');
      sendDeviceCommand({ command: 'scan' });
    } catch (error) {
      console.error('Error scanning devices:', error);
      deviceStateCache.scanning = false;
      renderBluetoothLists();
      showToast('Failed to start scan: ' + error.message, true);
    }
  };

  window.handleDeviceConnection = function(deviceId, action) {
    try {
      sendDeviceCommand({ command: action, deviceId });
      showToast((action === 'connect' ? 'Connecting to ' : 'Disconnecting from ') + deviceId);
    } catch (error) {
      console.error('Error handling device connection:', error);
      showToast('Failed to ' + action + ': ' + error.message, true);
    }
  };

  document.addEventListener('DOMContentLoaded', async function() {
    const searchInput = document.getElementById('settings-search');
    if (searchInput) searchInput.addEventListener('input', (e) => handleSearchInput(e.target.value));
    attachNavigationHandlers();
    renderMainCategories(browserBootstrap.activeMainCategoryKey || 'extensions');
    renderSubcategories(browserBootstrap.activeMainCategoryKey || 'extensions', browserBootstrap.activeSettingsCategory || null);
    await setupVisualizerEventListeners();
  });

  console.log('settings plugin source page loaded', browserBootstrap);
})();
`;
  function buildSourceBootstrapScript(browserBootstrapData) {
    return `window.__SETTINGS_BOOTSTRAP__ = ${JSON.stringify(browserBootstrapData)};
${browserRuntimeSource}`;
  }
  function renderSettingsPage({
    reaSettings = {},
    de1Settings = {},
    de1AdvancedSettings = {},
    webUISkins = [],
    calibrationSettings = {},
    presenceSettings = {},
    appInfo = null,
    machineInfo = null,
    activeSettingsCategory = null,
    activeMainCategoryKey,
    activeHours = []
  }) {
    const browserBootstrapData = getBrowserBootstrapData({
      reaSettings,
      de1Settings,
      de1AdvancedSettings,
      webUISkins,
      calibrationSettings,
      presenceSettings,
      appInfo,
      machineInfo,
      activeSettingsCategory,
      activeMainCategoryKey
    });
    const initialCategory = activeSettingsCategory || getDefaultSubcategory(settingsTree, activeMainCategoryKey) || "extensions";
    if (initialCategory === "presence") {
      renderPresenceSection({ presenceSettings, activeHours });
    } else if (initialCategory === "brightness") ;
    else if (initialCategory === "wakelock") ;
    else if (initialCategory === "flowmultiplier") {
      renderFlowMultiplierSection(reaSettings);
    } else if (initialCategory === "rea") {
      renderReaSettingsSection(reaSettings);
    } else if (initialCategory === "steam") {
      renderSteamSection(de1Settings);
    } else if (initialCategory === "hotwater") {
      renderHotWaterSection(de1Settings);
    } else if (initialCategory === "watertank") {
      renderWaterTankSection(de1Settings);
    } else if (initialCategory === "flush") {
      renderFlushSection(de1Settings);
    } else if (initialCategory === "fanthreshold") {
      renderFanThresholdSection(de1Settings);
    } else if (initialCategory === "usbchargermode") {
      renderUsbChargerModeSection(de1Settings);
    } else if (initialCategory === "ble_machine") ;
    else if (initialCategory === "ble_scale") ;
    else if (["calibration", "refillkit", "voltage", "fan", "stopatweight", "slowstart"].includes(initialCategory)) {
      renderCalibrationSection(calibrationSettings);
    } else if (["maintenance", "transportmode"].includes(initialCategory)) ;
    else if (initialCategory === "de1advanced") {
      renderDe1AdvancedSection(de1AdvancedSettings);
    } else if (initialCategory === "updates") {
      renderUpdatesSection(appInfo, machineInfo);
    } else ;
    return `${renderSettingsPageHead()}
${renderSettingsPageLayout((/* @__PURE__ */ new Date()).toLocaleString())}
<div id="source-templates" style="display:none"><div id="visualizer-template" style="display:none">${renderVisualizerSection()}</div>
<div id="presence-template" style="display:none">${renderPresenceSection({ presenceSettings, activeHours })}</div>
<div id="brightness-template" style="display:none">${renderBrightnessSection()}</div>
<div id="wakelock-template" style="display:none">${renderWakeLockSection()}</div>
<div id="flowmultiplier-template" style="display:none">${renderFlowMultiplierSection(reaSettings)}</div>
<div id="rea-template" style="display:none">${renderReaSettingsSection(reaSettings)}</div>
<div id="steam-template" style="display:none">${renderSteamSection(de1Settings)}</div>
<div id="hotwater-template" style="display:none">${renderHotWaterSection(de1Settings)}</div>
<div id="watertank-template" style="display:none">${renderWaterTankSection(de1Settings)}</div>
<div id="flush-template" style="display:none">${renderFlushSection(de1Settings)}</div>
<div id="fanthreshold-template" style="display:none">${renderFanThresholdSection(de1Settings)}</div>
<div id="usbchargermode-template" style="display:none">${renderUsbChargerModeSection(de1Settings)}</div>
<div id="ble_machine-template" style="display:none">${renderBluetoothMachineSection()}</div>
<div id="ble_scale-template" style="display:none">${renderBluetoothScaleSection()}</div>
<div id="calibration-template" style="display:none">${renderCalibrationSection(calibrationSettings)}</div>
<div id="maintenance-template" style="display:none">${renderMaintenanceSection()}</div>
<div id="de1advanced-template" style="display:none">${renderDe1AdvancedSection(de1AdvancedSettings)}</div>
<div id="updates-template" style="display:none">${renderUpdatesSection(appInfo, machineInfo)}</div>
<div id="help-template" style="display:none">${renderHelpSection()}</div>
<div id="appearance-template" style="display:none">${renderAppearanceSection()}</div>
<div id="language-template" style="display:none">${renderLanguageSection()}</div>
</div>
<script>
${buildSourceBootstrapScript(browserBootstrapData)}
<\/script>
</body>
</html>`;
  }
  function createPlugin2(host) {
    let activeSettingsCategory = null;
    let activeMainCategoryKey = DEFAULT_MAIN_CATEGORY_KEY;
    function log(msg) {
      host.log(`[settings] ${msg}`);
    }
    async function fetchJson(path, label) {
      const response = await fetch(`${API_BASE_URL}${path}`);
      if (!response.ok) {
        throw new Error(`Failed to fetch ${label}: ${response.status} ${response.statusText}`);
      }
      return response.json();
    }
    async function fetchReaSettings() {
      try {
        return await fetchJson("/settings", "REA settings");
      } catch (e) {
        log(e.message);
        return {};
      }
    }
    async function fetchDe1Settings() {
      try {
        return await fetchJson("/machine/settings", "machine settings");
      } catch (e) {
        log(e.message);
        return {};
      }
    }
    async function fetchDe1AdvancedSettings() {
      try {
        return await fetchJson("/machine/settings/advanced", "advanced machine settings");
      } catch (e) {
        log(e.message);
        return {};
      }
    }
    async function fetchCalibrationSettings() {
      try {
        return await fetchJson("/machine/calibration", "calibration settings");
      } catch (e) {
        log(e.message);
        return {};
      }
    }
    async function fetchPresenceSettings() {
      try {
        return await fetchJson("/presence/settings", "presence settings");
      } catch (e) {
        log(e.message);
        return {};
      }
    }
    async function fetchWebUISkins() {
      try {
        return await fetchJson("/webui/skins", "web ui skins");
      } catch (e) {
        log(e.message);
        return [];
      }
    }
    async function fetchAppInfo() {
      try {
        return await fetchJson("/info", "app info");
      } catch (e) {
        log(e.message);
        return null;
      }
    }
    async function fetchMachineInfo() {
      try {
        return await fetchJson("/machine/info", "machine info");
      } catch (e) {
        log(e.message);
        return null;
      }
    }
    function getStoredActiveHours() {
      return [];
    }
    async function renderSourcePage() {
      const [
        reaSettings,
        de1Settings,
        de1AdvancedSettings,
        webUISkins,
        calibrationSettings,
        presenceSettings,
        appInfo,
        machineInfo
      ] = await Promise.all([
        fetchReaSettings(),
        fetchDe1Settings(),
        fetchDe1AdvancedSettings(),
        fetchWebUISkins(),
        fetchCalibrationSettings(),
        fetchPresenceSettings(),
        fetchAppInfo(),
        fetchMachineInfo()
      ]);
      return renderSettingsPage({
        reaSettings,
        de1Settings,
        de1AdvancedSettings,
        webUISkins,
        calibrationSettings,
        presenceSettings,
        appInfo,
        machineInfo,
        activeSettingsCategory,
        activeMainCategoryKey,
        activeHours: getStoredActiveHours()
      });
    }
    return {
      id: "streamline-settings.reaplugin",
      version: "0.1.0",
      onLoad(settings) {
        log(`Loaded with refresh interval: ${(settings == null ? void 0 : settings.RefreshInterval) ?? DEFAULT_REFRESH_INTERVAL}s`);
      },
      onUnload() {
        log("Unloaded");
      },
      onEvent(_event) {
      },
      __httpRequestHandler(request) {
        if (request.endpoint === "ui") {
          return Promise.resolve(renderSourcePage()).then((body) => ({
            requestId: request.requestId,
            status: 200,
            headers: {
              "Content-Type": "text/html; charset=utf-8",
              "Cache-Control": "no-cache"
            },
            body
          }));
        }
        return {
          requestId: request.requestId,
          status: 404,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ error: "Endpoint not found" })
        };
      }
    };
  }
  return createPlugin2;
})();
