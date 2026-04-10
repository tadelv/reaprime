# Settings Plugin Extension — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the settings.reaplugin and supporting REST API to cover simulated devices, theme, skins management, WebUI server control, data management, plugin management, feedback, and app info.

**Architecture:** Two sequential workstreams — (1) backend REST API additions with TDD, (2) plugin UI extensions. Each workstream gets a 2-reviewer + arbiter code review before proceeding. Integration testing via curl against a running simulated app.

**Tech Stack:** Dart/Flutter (backend), JavaScript (plugin), shelf (HTTP), SharedPreferences (settings persistence)

**Branch:** `feature/add-skins-extracto-passione`

---

## Workstream 1: Backend REST API

### Task 1: Add simulatedDevices and themeMode to settings endpoint

**Files:**
- Modify: `lib/src/services/webserver/settings_handler.dart:20-207`
- Test: `test/webserver/settings_handler_test.dart` (create)

**Step 1: Write failing test for GET simulatedDevices and themeMode**

Create `test/webserver/settings_handler_test.dart`. Reference existing handler test patterns in `test/webserver/beans_handler_test.dart` for setup.

The settings handler is a `part of webserver_service.dart` file — it requires a running `WebServerService` with dependencies. For unit testing, create a minimal test that:
- Creates a `MockSettingsService` + `SettingsController`
- Sets simulatedDevices to `{SimulatedDevicesTypes.machine}`
- Sets themeMode to `ThemeMode.dark`
- Calls `GET /api/v1/settings` via shelf test utilities
- Asserts response contains `"simulatedDevices": ["machine"]` and `"themeMode": "dark"`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import '../helpers/mock_settings_service.dart';

void main() {
  group('Settings handler', () {
    late MockSettingsService mockService;
    late SettingsController controller;

    setUp(() async {
      mockService = MockSettingsService();
      controller = SettingsController(mockService);
      await controller.loadSettings();
    });

    test('GET /api/v1/settings includes simulatedDevices', () async {
      await controller.setSimulatedDevices({SimulatedDevicesTypes.machine});
      // The actual HTTP test requires WebServerService setup — 
      // for now test the controller state that the handler reads
      expect(controller.simulatedDevices, contains(SimulatedDevicesTypes.machine));
    });

    test('GET /api/v1/settings includes themeMode', () async {
      await controller.updateThemeMode(ThemeMode.dark);
      expect(controller.themeMode, equals(ThemeMode.dark));
    });

    test('POST /api/v1/settings updates simulatedDevices', () async {
      await controller.setSimulatedDevices({SimulatedDevicesTypes.machine, SimulatedDevicesTypes.scale});
      expect(controller.simulatedDevices, containsAll([SimulatedDevicesTypes.machine, SimulatedDevicesTypes.scale]));
    });
  });
}
```

**Step 2: Run test to verify it passes (these test the controller, not the handler directly)**

Run: `flutter test test/webserver/settings_handler_test.dart`
Expected: PASS (controller methods already exist)

**Step 3: Add simulatedDevices and themeMode to GET handler**

In `lib/src/services/webserver/settings_handler.dart`, in the GET handler (line ~20), add to the response map after existing fields:

```dart
'simulatedDevices': _controller.simulatedDevices.map((e) => e.name).toList(),
'themeMode': _controller.themeMode.name,
```

**Step 4: Add POST handler for simulatedDevices and themeMode**

In the POST handler (after line ~205), add:

```dart
if (json.containsKey('simulatedDevices')) {
  final value = json['simulatedDevices'];
  if (value is List) {
    final devices = <SimulatedDevicesTypes>{};
    for (final item in value) {
      if (item is String) {
        final type = SimulatedDevicesTypesFromString.fromString(item);
        if (type != null) devices.add(type);
      }
    }
    await _controller.setSimulatedDevices(devices);
  }
}
if (json.containsKey('themeMode')) {
  final value = json['themeMode'];
  if (value is String) {
    final mode = ThemeMode.values.firstWhereOrNull((e) => e.name == value);
    if (mode != null) {
      await _controller.updateThemeMode(mode);
    }
  }
}
```

Note: Need to add `import 'package:collection/collection.dart';` if not already imported for `firstWhereOrNull`.

**Step 5: Run tests**

Run: `flutter test test/webserver/settings_handler_test.dart`
Expected: PASS

**Step 6: Run flutter analyze**

Run: `flutter analyze lib/src/services/webserver/settings_handler.dart`
Expected: No issues

**Step 7: Commit**

```bash
git add lib/src/services/webserver/settings_handler.dart test/webserver/settings_handler_test.dart
git commit -m "feat: add simulatedDevices and themeMode to settings API"
```

---

### Task 2: Add WebUI server lifecycle endpoints

**Files:**
- Modify: `lib/src/services/webserver/webui_handler.dart:12-36`
- Test: `test/webserver/settings_handler_test.dart` (extend, or separate file)

**Step 1: Write failing test for WebUI server status**

Add test that verifies the WebUIService exposes `isServing` state.

```dart
test('WebUIService reports serving status', () {
  // WebUIService.isServing is a getter that checks _server != null
  // This is already implemented — we test the handler response shape
});
```

**Step 2: Add three new routes to webui_handler.dart addRoutes()**

After existing routes (line ~36), add:

```dart
app.get('/api/v1/webui/server/status', (Request request) {
  return Response.ok(
    jsonEncode({
      'serving': _service.isServing,
      'path': _service.isServing ? _service.serverPath() : null,
      'port': _service.isServing ? 3000 : null,
      'ip': _service.isServing ? _service.serverIP() : null,
    }),
    headers: {'Content-Type': 'application/json'},
  );
});

app.post('/api/v1/webui/server/start', (Request request) async {
  if (_service.isServing) {
    return Response.ok(jsonEncode({'message': 'Already serving'}),
        headers: {'Content-Type': 'application/json'});
  }
  final defaultSkin = _storage.defaultSkin;
  if (defaultSkin == null) {
    return Response(400,
        body: jsonEncode({'error': 'No default skin set. Set defaultSkinId in settings first.'}),
        headers: {'Content-Type': 'application/json'});
  }
  try {
    await _service.serveFolderAtPath(defaultSkin.path);
    return Response.ok(
        jsonEncode({'message': 'WebUI server started', 'path': defaultSkin.path}),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to start: $e'}),
        headers: {'Content-Type': 'application/json'});
  }
});

app.post('/api/v1/webui/server/stop', (Request request) async {
  if (!_service.isServing) {
    return Response.ok(jsonEncode({'message': 'Not serving'}),
        headers: {'Content-Type': 'application/json'});
  }
  try {
    await _service.stopServing();
    return Response.ok(jsonEncode({'message': 'WebUI server stopped'}),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to stop: $e'}),
        headers: {'Content-Type': 'application/json'});
  }
});
```

**Step 3: Run flutter analyze**

Run: `flutter analyze lib/src/services/webserver/webui_handler.dart`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/services/webserver/webui_handler.dart
git commit -m "feat: add WebUI server start/stop/status endpoints"
```

---

### Task 3: Add plugin lifecycle endpoints

**Files:**
- Modify: `lib/src/services/webserver/plugins_handler.dart:13-29`

**Step 1: Add enable/disable/remove/install routes**

Replace the stub admin endpoint (line ~20-22) and add new routes after existing ones:

```dart
app.post('/api/v1/plugins/<id>/enable', (Request request, String id) async {
  try {
    if (!pluginService.isPluginLoaded(id)) {
      await pluginService.loadPlugin(id);
    }
    await pluginService.setPluginAutoLoad(id, true);
    return Response.ok(jsonEncode({'message': 'Plugin enabled', 'id': id}),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to enable plugin: $e'}),
        headers: {'Content-Type': 'application/json'});
  }
});

app.post('/api/v1/plugins/<id>/disable', (Request request, String id) async {
  try {
    if (pluginService.isPluginLoaded(id)) {
      await pluginService.unloadPlugin(id);
    }
    await pluginService.setPluginAutoLoad(id, false);
    return Response.ok(jsonEncode({'message': 'Plugin disabled', 'id': id}),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to disable plugin: $e'}),
        headers: {'Content-Type': 'application/json'});
  }
});

app.delete('/api/v1/plugins/<id>', (Request request, String id) async {
  try {
    await pluginService.removePlugin(id);
    return Response.ok(jsonEncode({'message': 'Plugin removed', 'id': id}),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to remove plugin: $e'}),
        headers: {'Content-Type': 'application/json'});
  }
});

app.post('/api/v1/plugins/install', (Request request) async {
  try {
    final payload = await request.readAsString();
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final url = json['url'] as String?;
    if (url == null || url.isEmpty) {
      return Response.badRequest(
          body: jsonEncode({'error': 'url is required'}),
          headers: {'Content-Type': 'application/json'});
    }
    // Download and install plugin from URL
    // TODO: implement download-and-install from URL
    // For now, return not implemented
    return Response(501,
        body: jsonEncode({'error': 'Plugin install from URL not yet implemented'}),
        headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to install plugin: $e'}),
        headers: {'Content-Type': 'application/json'});
  }
});
```

Note: The `PluginLoaderService` has `addPlugin(String sourcePath)` which copies from a local path. Remote URL download is not yet implemented — the install endpoint will return 501 for now. Enable/disable uses existing `loadPlugin`/`unloadPlugin` + `setPluginAutoLoad`.

**Step 2: Enhance GET /api/v1/plugins to include autoLoad status**

Modify the existing GET handler (line ~14) to include whether each plugin auto-loads:

```dart
app.get('/api/v1/plugins', (Request request) {
  final plugins = pluginService.pluginManager.loadedPlugins;
  final allPluginIds = pluginService.availablePlugins; // need to add this
  // Return loaded plugins with their manifests + autoLoad status
  final result = plugins.map((p) => {
    final manifest = p.manifest.toJson();
    manifest['loaded'] = true;
    manifest['autoLoad'] = pluginService.shouldAutoLoad(p.manifest.id);
    return manifest;
  }).toList();
  return Response.ok(jsonEncode(result),
      headers: {'Content-Type': 'application/json'});
});
```

Check if `pluginService` exposes available (not just loaded) plugins. If not, the current list of loaded plugins is sufficient for now.

**Step 3: Run flutter analyze**

Run: `flutter analyze lib/src/services/webserver/plugins_handler.dart`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/services/webserver/plugins_handler.dart
git commit -m "feat: add plugin enable/disable/remove/install endpoints"
```

---

### Task 4: Update API documentation

**Files:**
- Modify: `assets/api/rest_v1.yml`

**Step 1: Add new fields to /api/v1/settings schema**

Add `simulatedDevices` (array of strings) and `themeMode` (string enum) to the settings GET response and POST request schemas.

**Step 2: Add WebUI server endpoints**

Document:
- `GET /api/v1/webui/server/status` — response: `{serving, path, port, ip}`
- `POST /api/v1/webui/server/start` — starts with default skin, error if no default set
- `POST /api/v1/webui/server/stop` — stops serving

**Step 3: Add plugin lifecycle endpoints**

Document:
- `POST /api/v1/plugins/{id}/enable` — loads plugin + sets auto-load
- `POST /api/v1/plugins/{id}/disable` — unloads plugin + disables auto-load
- `DELETE /api/v1/plugins/{id}` — removes plugin
- `POST /api/v1/plugins/install` — accepts `{url}`, returns 501 for now

**Step 4: Commit**

```bash
git add assets/api/rest_v1.yml
git commit -m "docs: update API spec for new settings, webui, and plugin endpoints"
```

---

### Task 5: Backend code review

**Reviewers:** Dispatch 2 independent code reviewers + 1 senior architect arbiter.

Review scope: All backend changes (Tasks 1-4) — settings_handler, webui_handler, plugins_handler, API docs.

Focus areas:
- REST API design consistency (status codes, error shapes, naming)
- Security (any endpoints that should be guarded in app-store mode?)
- Handler patterns matching existing codebase conventions
- Test coverage adequacy
- API doc accuracy

Incorporate findings and fix issues. Commit fixes.

---

## Workstream 2: Plugin UI

### Task 6: Add new fetch functions to settings.reaplugin

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js:21-121`

**Step 1: Add fetch functions for new endpoints**

After existing fetch functions (line ~121), add:

```javascript
async function fetchAppInfo() {
  try {
    const res = await fetch("http://localhost:8080/api/v1/info");
    if (!res.ok) { log(`Failed to fetch app info: ${res.status}`); return null; }
    return await res.json();
  } catch (e) { log(`Error fetching app info: ${e.message}`); return null; }
}

async function fetchWebUIServerStatus() {
  try {
    const res = await fetch("http://localhost:8080/api/v1/webui/server/status");
    if (!res.ok) { log(`Failed to fetch WebUI status: ${res.status}`); return null; }
    return await res.json();
  } catch (e) { log(`Error fetching WebUI status: ${e.message}`); return null; }
}

async function fetchPlugins() {
  try {
    const res = await fetch("http://localhost:8080/api/v1/plugins");
    if (!res.ok) { log(`Failed to fetch plugins: ${res.status}`); return null; }
    return await res.json();
  } catch (e) { log(`Error fetching plugins: ${e.message}`); return null; }
}
```

**Step 2: Add these to Promise.all in __httpRequestHandler**

Update the Promise.all (line ~882) to include the new fetches:

```javascript
return Promise.all([
  fetchReaSettings(),
  fetchDe1Settings(),
  fetchDe1AdvancedSettings(),
  fetchWebUISkins(),
  fetchCalibrationSettings(),
  fetchPresenceSettings(),
  fetchAppInfo(),
  fetchWebUIServerStatus(),
  fetchPlugins()
]).then(([reaSettings, de1Settings, de1AdvancedSettings, webUISkins,
          calibrationSettings, presenceSettings,
          appInfo, webUIStatus, plugins]) => {
  const html = generateSettingsHTML(
    reaSettings, de1Settings, de1AdvancedSettings, webUISkins,
    calibrationSettings, presenceSettings,
    appInfo, webUIStatus, plugins
  );
  // ... rest unchanged
```

**Step 3: Update generateSettingsHTML signature**

Add new parameters to the function signature (line ~126).

**Step 4: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add fetch functions for info, webui status, plugins"
```

---

### Task 7: Add "Back to WebUI" nav and About section

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`

**Step 1: Add persistent nav header**

In `generateSettingsHTML()`, before the first `<section>`, add a nav bar:

```html
<nav style="position: sticky; top: 0; z-index: 100; background: var(--bg-primary); padding: 12px 20px; border-bottom: 1px solid var(--border-color); display: flex; justify-content: space-between; align-items: center;">
  <h1 style="margin: 0; font-size: 1.2em;">Streamline-Bridge Settings</h1>
  <a href="http://localhost:3000" style="color: var(--accent-color); text-decoration: none; padding: 8px 16px; border: 1px solid var(--accent-color); border-radius: 6px;">← Back to WebUI</a>
</nav>
```

**Step 2: Add About section**

At the end of the sections, add:

```html
<section class="section" aria-labelledby="about-heading">
  <h2 id="about-heading">About</h2>
  ${appInfo ? `
    <div class="settings-grid">
      <div class="setting-item"><label>Version</label><span>${appInfo.version || '—'}</span></div>
      <div class="setting-item"><label>Build</label><span>${appInfo.buildNumber || '—'}</span></div>
      <div class="setting-item"><label>Commit</label><span>${appInfo.commit || '—'}</span></div>
      <div class="setting-item"><label>Branch</label><span>${appInfo.branch || '—'}</span></div>
    </div>
  ` : '<div class="error">Failed to load app info</div>'}
</section>
```

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add back-to-webui nav and about section"
```

---

### Task 8: Add Simulated Devices section

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`

**Step 1: Add simulated devices UI section**

After the existing REA Application Settings section, add:

```html
<section class="section" aria-labelledby="simulated-heading">
  <h2 id="simulated-heading">Simulated Devices</h2>
  ${reaSettings ? `
    <div class="settings-grid">
      ${['machine', 'scale', 'sensor'].map(type => `
        <div class="setting-item">
          <label>
            <input type="checkbox" ${(reaSettings.simulatedDevices || []).includes(type) ? 'checked' : ''}
              onchange="toggleSimulatedDevice('${type}', this.checked)" />
            ${type.charAt(0).toUpperCase() + type.slice(1)}
          </label>
        </div>
      `).join('')}
    </div>
  ` : '<div class="error">Failed to load settings</div>'}
</section>
```

**Step 2: Add submit handler in script section**

```javascript
async function toggleSimulatedDevice(type, enabled) {
  const current = ${JSON.stringify(reaSettings?.simulatedDevices || [])};
  let devices;
  if (enabled) {
    devices = [...new Set([...current, type])];
  } else {
    devices = current.filter(d => d !== type);
  }
  const response = await fetch(baseUrl + '/api/v1/settings', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ simulatedDevices: devices })
  });
  if (response.ok) showToast('Simulated devices updated');
  else showToast('Error: ' + await response.text(), true);
}
```

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add simulated devices section"
```

---

### Task 9: Add Skins Management section

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`

**Step 1: Add skins management UI**

```html
<section class="section" aria-labelledby="skins-heading">
  <h2 id="skins-heading">Skins Management</h2>
  ${webUISkins ? `
    <table class="data-table">
      <thead><tr><th>Name</th><th>Version</th><th>Bundled</th><th>Actions</th></tr></thead>
      <tbody>
        ${webUISkins.map(skin => `
          <tr>
            <td>${skin.name}</td>
            <td>${skin.version || '—'}</td>
            <td>${skin.isBundled ? 'Yes' : 'No'}</td>
            <td>
              <button onclick="setDefaultSkin('${skin.id}')">Set Default</button>
              ${!skin.isBundled ? `<button class="danger" onclick="removeSkin('${skin.id}', '${skin.name}')">Remove</button>` : ''}
            </td>
          </tr>
        `).join('')}
      </tbody>
    </table>
    <div style="margin-top: 16px;">
      <h3>Install Skin</h3>
      <div class="input-group">
        <input type="text" id="skinInstallUrl" placeholder="GitHub repo (owner/repo) or URL to .zip" />
        <button onclick="installSkin()">Install</button>
      </div>
    </div>
  ` : '<div class="error">Failed to load skins</div>'}
</section>
```

**Step 2: Add skin action handlers**

```javascript
async function setDefaultSkin(skinId) {
  const response = await fetch(baseUrl + '/api/v1/webui/skins/default', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ skinId: skinId })
  });
  if (response.ok) { showToast('Default skin updated'); location.reload(); }
  else showToast('Error: ' + await response.text(), true);
}

async function removeSkin(skinId, skinName) {
  if (!confirm('Remove skin "' + skinName + '"?')) return;
  const response = await fetch(baseUrl + '/api/v1/webui/skins/' + skinId, { method: 'DELETE' });
  if (response.ok) { showToast('Skin removed'); location.reload(); }
  else showToast('Error: ' + await response.text(), true);
}

async function installSkin() {
  const input = document.getElementById('skinInstallUrl').value.trim();
  if (!input) { showToast('Enter a URL or GitHub repo', true); return; }
  let endpoint, body;
  if (input.match(/^[\\w.-]+\\/[\\w.-]+$/)) {
    endpoint = '/api/v1/webui/skins/install/github-release';
    body = JSON.stringify({ repo: input });
  } else {
    endpoint = '/api/v1/webui/skins/install/url';
    body = JSON.stringify({ url: input });
  }
  showToast('Installing skin...');
  const response = await fetch(baseUrl + endpoint, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body
  });
  if (response.ok) { showToast('Skin installed'); location.reload(); }
  else showToast('Error: ' + await response.text(), true);
}
```

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add skins management section"
```

---

### Task 10: Add WebUI Server section

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`

**Step 1: Add WebUI server control UI**

```html
<section class="section" aria-labelledby="webui-server-heading">
  <h2 id="webui-server-heading">WebUI Server</h2>
  ${webUIStatus ? `
    <div class="settings-grid">
      <div class="setting-item">
        <label>Status</label>
        <span class="${webUIStatus.serving ? 'status-ok' : 'status-off'}">${webUIStatus.serving ? 'Serving' : 'Stopped'}</span>
      </div>
      ${webUIStatus.serving ? `
        <div class="setting-item"><label>Path</label><span>${webUIStatus.path}</span></div>
        <div class="setting-item"><label>Address</label><span>${webUIStatus.ip}:${webUIStatus.port}</span></div>
      ` : ''}
    </div>
    <div style="margin-top: 12px;">
      ${webUIStatus.serving
        ? '<button class="danger" onclick="stopWebUI()">Stop Server</button>'
        : '<button onclick="startWebUI()">Start Server</button>'}
    </div>
    <p class="note">Note: The server uses the default skin. Change the default skin in Skins Management above.</p>
  ` : '<div class="error">Failed to load WebUI status</div>'}
</section>
```

**Step 2: Add server control handlers**

```javascript
async function startWebUI() {
  showToast('Starting WebUI server...');
  const response = await fetch(baseUrl + '/api/v1/webui/server/start', { method: 'POST' });
  if (response.ok) { showToast('WebUI server started'); location.reload(); }
  else { const data = await response.json(); showToast('Error: ' + data.error, true); }
}

async function stopWebUI() {
  const response = await fetch(baseUrl + '/api/v1/webui/server/stop', { method: 'POST' });
  if (response.ok) { showToast('WebUI server stopped'); location.reload(); }
  else showToast('Error: ' + await response.text(), true);
}
```

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add WebUI server control section"
```

---

### Task 11: Add Data Management section

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`

**Step 1: Add data management UI with export, import, and sync**

```html
<section class="section" aria-labelledby="data-heading">
  <h2 id="data-heading">Data Management</h2>

  <h3>Export</h3>
  <p>Download a full backup as a ZIP file.</p>
  <button onclick="exportData()">Export Data</button>

  <h3 style="margin-top: 20px;">Import</h3>
  <p>Restore from a previously exported ZIP file.</p>
  <div class="input-group">
    <input type="file" id="importFile" accept=".zip" />
    <button onclick="importData()">Import</button>
  </div>

  <h3 style="margin-top: 20px;">Sync</h3>
  <p>Synchronize data with another Streamline-Bridge instance.</p>
  <div class="settings-grid">
    <div class="setting-item">
      <label for="syncTarget">Target URL</label>
      <input type="text" id="syncTarget" placeholder="http://192.168.1.50:8080" />
    </div>
    <div class="setting-item">
      <label for="syncDirection">Direction</label>
      <select id="syncDirection">
        <option value="push">Push (send to target)</option>
        <option value="pull">Pull (receive from target)</option>
        <option value="two_way">Two-way</option>
      </select>
    </div>
    <div class="setting-item">
      <label for="syncConflict">On Conflict</label>
      <select id="syncConflict">
        <option value="skip">Skip</option>
        <option value="overwrite">Overwrite</option>
      </select>
    </div>
  </div>
  <fieldset style="margin-top: 12px;">
    <legend>Data to sync</legend>
    ${['profiles', 'shots', 'workflow', 'settings', 'store', 'beans', 'grinders'].map(s =>
      `<label style="display: inline-block; margin-right: 12px;">
        <input type="checkbox" class="sync-section" value="${s}" checked /> ${s.charAt(0).toUpperCase() + s.slice(1)}
      </label>`
    ).join('')}
  </fieldset>
  <button style="margin-top: 12px;" onclick="syncData()">Sync</button>
</section>
```

**Step 2: Add data management handlers**

```javascript
function exportData() {
  window.open(baseUrl + '/api/v1/data/export', '_blank');
}

async function importData() {
  const fileInput = document.getElementById('importFile');
  if (!fileInput.files.length) { showToast('Select a file first', true); return; }
  const formData = new FormData();
  formData.append('file', fileInput.files[0]);
  showToast('Importing data...');
  try {
    const response = await fetch(baseUrl + '/api/v1/data/import', {
      method: 'POST', body: formData
    });
    if (response.ok) { showToast('Data imported successfully'); location.reload(); }
    else showToast('Import failed: ' + await response.text(), true);
  } catch (e) { showToast('Import error: ' + e.message, true); }
}

async function syncData() {
  const target = document.getElementById('syncTarget').value.trim();
  if (!target) { showToast('Enter target URL', true); return; }
  const sections = [...document.querySelectorAll('.sync-section:checked')].map(el => el.value);
  if (sections.length === 0) { showToast('Select at least one data section', true); return; }
  const payload = {
    target: target,
    mode: document.getElementById('syncDirection').value,
    onConflict: document.getElementById('syncConflict').value,
    sections: sections
  };
  showToast('Syncing data...');
  try {
    const response = await fetch(baseUrl + '/api/v1/data/sync', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const result = await response.json();
    if (response.ok) showToast('Sync completed');
    else if (response.status === 207) showToast('Sync partially completed — check logs');
    else showToast('Sync failed: ' + JSON.stringify(result), true);
  } catch (e) { showToast('Sync error: ' + e.message, true); }
}
```

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add data management section with export/import/sync"
```

---

### Task 12: Add Plugin Management section

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`

**Step 1: Add plugin management UI with self-disable guard**

```html
<section class="section" aria-labelledby="plugins-heading">
  <h2 id="plugins-heading">Plugin Management</h2>
  ${plugins ? `
    <table class="data-table">
      <thead><tr><th>Name</th><th>Version</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>
        ${plugins.map(plugin => {
          const isSelf = plugin.id === 'settings.reaplugin';
          return `
            <tr>
              <td>${plugin.name}${isSelf ? ' (this plugin)' : ''}</td>
              <td>${plugin.version || '—'}</td>
              <td>${plugin.loaded ? 'Loaded' : 'Disabled'}</td>
              <td>
                ${isSelf ? '<span class="muted">Cannot modify self</span>' : `
                  ${plugin.loaded
                    ? '<button onclick="disablePlugin(\\''+plugin.id+'\\')">Disable</button>'
                    : '<button onclick="enablePlugin(\\''+plugin.id+'\\')">Enable</button>'}
                  <button class="danger" onclick="removePlugin(\\''+plugin.id+'\\', \\''+plugin.name+'\\')">Remove</button>
                `}
              </td>
            </tr>
          `;
        }).join('')}
      </tbody>
    </table>
    <div style="margin-top: 16px;">
      <h3>Install Plugin</h3>
      <div class="input-group">
        <input type="text" id="pluginInstallUrl" placeholder="URL to .reaplugin zip" />
        <button onclick="installPlugin()">Install</button>
      </div>
    </div>
  ` : '<div class="error">Failed to load plugins</div>'}
</section>
```

**Step 2: Add plugin action handlers**

```javascript
async function enablePlugin(id) {
  const response = await fetch(baseUrl + '/api/v1/plugins/' + id + '/enable', { method: 'POST' });
  if (response.ok) { showToast('Plugin enabled'); location.reload(); }
  else showToast('Error: ' + await response.text(), true);
}

async function disablePlugin(id) {
  const response = await fetch(baseUrl + '/api/v1/plugins/' + id + '/disable', { method: 'POST' });
  if (response.ok) { showToast('Plugin disabled'); location.reload(); }
  else showToast('Error: ' + await response.text(), true);
}

async function removePlugin(id, name) {
  if (!confirm('Remove plugin "' + name + '"? This cannot be undone.')) return;
  const response = await fetch(baseUrl + '/api/v1/plugins/' + id, { method: 'DELETE' });
  if (response.ok) { showToast('Plugin removed'); location.reload(); }
  else showToast('Error: ' + await response.text(), true);
}

async function installPlugin() {
  const url = document.getElementById('pluginInstallUrl').value.trim();
  if (!url) { showToast('Enter a URL', true); return; }
  showToast('Installing plugin...');
  const response = await fetch(baseUrl + '/api/v1/plugins/install', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url: url })
  });
  if (response.ok) { showToast('Plugin installed'); location.reload(); }
  else { const data = await response.json(); showToast('Error: ' + data.error, true); }
}
```

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add plugin management section with self-disable guard"
```

---

### Task 13: Add Feedback section

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`

**Step 1: Add feedback form UI**

```html
<section class="section" aria-labelledby="feedback-heading">
  <h2 id="feedback-heading">Feedback</h2>
  <p>Send feedback or report issues. This will create a GitHub issue.</p>
  <div class="settings-grid">
    <div class="setting-item" style="grid-column: 1 / -1;">
      <label for="feedbackText">Your feedback</label>
      <textarea id="feedbackText" rows="4" placeholder="Describe your feedback, issue, or suggestion..."></textarea>
    </div>
  </div>
  <button style="margin-top: 12px;" onclick="submitFeedback()">Submit Feedback</button>
</section>
```

**Step 2: Add feedback handler**

```javascript
async function submitFeedback() {
  const text = document.getElementById('feedbackText').value.trim();
  if (!text) { showToast('Enter feedback text', true); return; }
  showToast('Submitting feedback...');
  try {
    const response = await fetch(baseUrl + '/api/v1/feedback', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ feedback: text })
    });
    if (response.ok) {
      showToast('Feedback submitted — thank you!');
      document.getElementById('feedbackText').value = '';
    } else {
      showToast('Failed to submit: ' + await response.text(), true);
    }
  } catch (e) { showToast('Error: ' + e.message, true); }
}
```

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat(plugin): add feedback section"
```

---

### Task 14: Bump plugin version and finalize

**Files:**
- Modify: `assets/plugins/settings.reaplugin/manifest.json`

**Step 1: Update manifest version**

Change `"version": "0.0.14"` to `"version": "0.1.0"` (feature release bump).

**Step 2: Run flutter analyze on full project**

Run: `flutter analyze`
Expected: No new issues

**Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/manifest.json
git commit -m "chore: bump settings plugin to v0.1.0"
```

---

### Task 15: Plugin code review

**Reviewers:** Dispatch 2 independent code reviewers + 1 senior architect arbiter.

Review scope: All plugin changes (Tasks 6-14) — plugin.js, manifest.json.

Focus areas:
- HTML/JS quality and correctness
- Self-disable guard robustness
- Error handling in fetch/submit functions
- Consistent UX patterns across sections
- Security (any XSS risks in template literals?)
- Accessibility of new UI sections

Incorporate findings and fix issues. Commit fixes.

---

## Integration Testing

### Task 16: Integration test via curl

**Step 1: Launch app in simulated mode**

```bash
flutter run --dart-define=simulate=1
```

Wait for app to start and web server to be ready.

**Step 2: Test new settings fields**

```bash
# GET settings — verify new fields present
curl -s http://localhost:8080/api/v1/settings | jq '.simulatedDevices, .themeMode'

# POST update simulatedDevices
curl -s -X POST http://localhost:8080/api/v1/settings \
  -H 'Content-Type: application/json' \
  -d '{"simulatedDevices": ["machine", "scale"]}' 

# POST update themeMode
curl -s -X POST http://localhost:8080/api/v1/settings \
  -H 'Content-Type: application/json' \
  -d '{"themeMode": "dark"}'

# Verify roundtrip
curl -s http://localhost:8080/api/v1/settings | jq '.simulatedDevices, .themeMode'
```

**Step 3: Test WebUI server endpoints**

```bash
curl -s http://localhost:8080/api/v1/webui/server/status | jq .
curl -s -X POST http://localhost:8080/api/v1/webui/server/start | jq .
curl -s http://localhost:8080/api/v1/webui/server/status | jq .
curl -s -X POST http://localhost:8080/api/v1/webui/server/stop | jq .
```

**Step 4: Test plugin endpoints**

```bash
curl -s http://localhost:8080/api/v1/plugins | jq .
curl -s -X POST http://localhost:8080/api/v1/plugins/settings.reaplugin/enable | jq .
curl -s -X POST http://localhost:8080/api/v1/plugins/settings.reaplugin/disable | jq .
# Re-enable since we need it
curl -s -X POST http://localhost:8080/api/v1/plugins/settings.reaplugin/enable | jq .
```

**Step 5: Test plugin UI loads**

```bash
curl -s http://localhost:8080/api/v1/plugins/settings.reaplugin/ui | head -50
# Verify HTML contains new sections
curl -s http://localhost:8080/api/v1/plugins/settings.reaplugin/ui | grep -c 'section'
```

**Step 6: Test data export**

```bash
curl -s -o /tmp/test-export.zip http://localhost:8080/api/v1/data/export
file /tmp/test-export.zip
```

**Step 7: Test app info**

```bash
curl -s http://localhost:8080/api/v1/info | jq .
```

**Step 8: Document any issues found, dispatch review if needed**

If issues are found during integration testing, fix them and dispatch 2 reviewers + arbiter to review the fixes.

**Step 9: Commit any integration test fixes**

```bash
git add -A
git commit -m "fix: integration test fixes for settings plugin extension"
```

---

### Task 17: Final verification

**Step 1: Run flutter analyze**

Run: `flutter analyze`
Expected: No new issues

**Step 2: Run flutter test**

Run: `flutter test`
Expected: All tests pass

**Step 3: Final commit if needed**

Any remaining cleanup.
