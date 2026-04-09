# Settings Plugin Extension — Design

## Goal

Extend the settings.reaplugin and supporting REST API to cover all native Flutter settings sections, plus data management, skin management, plugin management, feedback, and app info.

## Scope

### New plugin UI sections (7 new + 1 nav element)

1. **Simulated Devices** — toggle mock devices on/off
2. **Skins Management** — list, install (URL/GitHub), remove, select default
3. **WebUI Server** — start/stop, status
4. **Data Management** — export (download ZIP), import (upload ZIP), sync (target URL, direction, conflict strategy, section checkboxes)
5. **Plugin Management** — list with status, enable/disable (except self), remove (except self), install from URL or GitHub
6. **Feedback** — text area, submit
7. **About** — version, build, commit, branch (read-only)
8. **Back to WebUI** — persistent nav link to localhost:3000

### REST API changes

**Extend `GET/POST /api/v1/settings`:**
- Add `simulatedDevices` (list of strings)
- Add `themeMode` (string: system/light/dark)

**New endpoints:**
- `POST /api/v1/webui/server/start` — start serving the default skin
- `POST /api/v1/webui/server/stop` — stop serving
- `GET /api/v1/webui/server/status` — current serving status
- `POST /api/v1/plugins/:id/enable` — enable a plugin
- `POST /api/v1/plugins/:id/disable` — disable a plugin
- `DELETE /api/v1/plugins/:id` — remove/uninstall a plugin
- `POST /api/v1/plugins/install` — install from URL (accepts `{url: "..."}`)

**Existing endpoints consumed by plugin (no changes needed):**
- `GET /api/v1/info` — app info
- `GET /api/v1/webui/skins` — list skins
- `POST /api/v1/webui/skins/install/github-release` — install skin from GH release
- `POST /api/v1/webui/skins/install/url` — install skin from URL
- `DELETE /api/v1/webui/skins/:id` — remove skin
- `PUT /api/v1/webui/skins/default` — set default skin
- `GET /api/v1/data/export` — download ZIP
- `POST /api/v1/data/import` — upload ZIP
- `POST /api/v1/data/sync` — sync with target (supports: target, mode [pull/push/two_way], onConflict [skip/overwrite], sections [profiles/shots/workflow/settings/store/beans/grinders])
- `GET /api/v1/plugins` — list plugins
- `GET/POST /api/v1/plugins/:id/settings` — plugin settings
- `POST /api/v1/feedback` — submit feedback

### Documentation

Update `assets/api/rest_v1.yml` for every new/modified endpoint.

## Plugin UI notes

- "Back to WebUI" is a persistent header link, not a section
- Self-disable guard: hide disable/remove buttons for `settings.reaplugin` in the plugin list
- Data sync form: target URL field, direction dropdown (pull/push/two_way), conflict strategy dropdown (skip/overwrite), checkboxes for each data section
- WebUI start uses `defaultSkinId` — document that setting defaultSkinId is required to change which skin is served
- Plugin install supports URL to .reaplugin zip file and GitHub repo reference
- Plugin versioning/update mechanism deferred to a future iteration

## Implementation strategy

Two sequential workstreams, each following TDD:

### Workstream 1: Backend (REST API)
1. Write failing tests for new settings fields (simulatedDevices, themeMode)
2. Implement in settings_handler + settings_controller/service
3. Write failing tests for WebUI server lifecycle endpoints
4. Implement in webui_handler
5. Write failing tests for plugin lifecycle endpoints
6. Implement in plugins_handler
7. Update assets/api/rest_v1.yml
8. Code review (2 reviewers + arbiter), incorporate fixes

### Workstream 2: Plugin (settings.reaplugin)
1. Add new fetch functions for all endpoints
2. Add each UI section one at a time
3. Add submit handlers for actions
4. Add "Back to WebUI" nav link
5. Add self-disable guard
6. Bump manifest version
7. Code review (2 reviewers + arbiter), incorporate fixes

### Testing
- Unit tests for backend changes (TDD)
- Integration testing via curl against running app (launch with simulate=1)
- Verify each plugin section loads and submits correctly
- Issues found during testing reviewed with 2 reviewers + arbiter
