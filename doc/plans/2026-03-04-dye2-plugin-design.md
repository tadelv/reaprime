# Streamline/DYE2 Plugin Design

**Date:** 2026-03-04
**Branch:** `feature/dye2-plugin-scaffold`
**Context:** Implements the plugin-side features deferred from the simplified schema proposal. DYE2 is a first-party JS plugin providing entity management UI via Web Components served through plugin HTTP endpoints.

---

## Overview

The core app owns Bean, BeanBatch, and Grinder as Drift tables with REST API. It provides no management UI for these entities. The DYE2 plugin fills that gap: bean/grinder CRUD screens, batch management, and workflow pickers — all served as HTML pages with Web Components.

**Two JS runtimes:**
1. **flutter_js** — runs `plugin.js`, handles plugin lifecycle, routes HTTP requests to page generators
2. **Browser** — renders the HTML pages served by the plugin, runs Web Components that call the core REST API directly

---

## Project Structure

```
packages/dye2-plugin/
├── package.json              # @streamline/dye2-plugin
├── tsconfig.json
├── vite.config.ts            # Library mode → single IIFE bundle
├── manifest.json             # Copied as-is to build output
├── src/
│   ├── plugin.ts             # Entry: createPlugin(host), lifecycle, HTTP router
│   ├── host.d.ts             # Type declarations for host API
│   ├── api/
│   │   ├── client.ts         # Base REST client wrapping fetch()
│   │   ├── beans.ts          # Bean + BeanBatch CRUD
│   │   ├── grinders.ts       # Grinder CRUD
│   │   └── workflow.ts       # Workflow GET/PUT (context field)
│   ├── components/           # Web Components (custom elements)
│   │   ├── bean-list.ts      # <dye2-bean-list>
│   │   ├── bean-form.ts      # <dye2-bean-form> (create/edit)
│   │   ├── bean-batch-list.ts
│   │   ├── bean-batch-form.ts
│   │   ├── grinder-list.ts   # <dye2-grinder-list>
│   │   ├── grinder-form.ts   # <dye2-grinder-form>
│   │   ├── bean-picker.ts    # <dye2-bean-picker> (select for workflow)
│   │   └── grinder-picker.ts # <dye2-grinder-picker>
│   ├── pages/                # Full HTML page compositions
│   │   ├── beans.ts          # Beans management page
│   │   ├── grinders.ts       # Grinders management page
│   │   └── layout.ts         # Shared page shell (nav, styles)
│   └── utils/
│       └── html.ts           # Tagged template literal for HTML, CSS helpers
```

**Build output** (gitignored):
```
assets/plugins/dye2.reaplugin/
├── manifest.json
└── plugin.js
```

---

## Build

**Tooling:** Vite in library mode, IIFE output format (flutter_js has no ES module support).

**Two-output build:** The single source tree produces one bundle that contains:
- Plugin logic (page generators, HTTP router) — executed in flutter_js
- Web Component class definitions — compiled to string constants, inlined into HTML `<script>` tags when pages are served

Component source is imported as compiled strings (via Vite `?raw` or custom plugin) so they can be embedded in HTML responses without executing in flutter_js.

**Build commands:**
```bash
cd packages/dye2-plugin
npm install
npm run build    # → assets/plugins/dye2.reaplugin/
```

**CI:** Add build step to GitHub Actions workflows before `flutter build`.

**Dev workflow:**
```bash
npm run dev      # Watch mode, rebuilds on source change
# Then reload plugin via API or app restart
```

---

## Manifest

```json
{
  "id": "dye2.reaplugin",
  "author": "Streamline",
  "name": "Streamline/DYE2",
  "description": "Bean, grinder, and equipment management for Decent Espresso",
  "version": "0.1.0",
  "apiVersion": 1,
  "permissions": ["log", "api", "emit", "pluginStorage"],
  "settings": {},
  "api": [
    { "id": "beans", "type": "http", "data": {} },
    { "id": "grinders", "type": "http", "data": {} },
    { "id": "bean-picker", "type": "http", "data": {} },
    { "id": "grinder-picker", "type": "http", "data": {} }
  ]
}
```

---

## HTTP Endpoints

| Endpoint | URL | Purpose |
|---|---|---|
| `beans` | `/api/v1/plugins/dye2.reaplugin/beans` | Full bean + batch management page |
| `grinders` | `/api/v1/plugins/dye2.reaplugin/grinders` | Full grinder management page |
| `bean-picker` | `/api/v1/plugins/dye2.reaplugin/bean-picker` | Workflow bean selection picker |
| `grinder-picker` | `/api/v1/plugins/dye2.reaplugin/grinder-picker` | Workflow grinder selection picker |

**Management pages** serve standalone HTML with full CRUD. Skins link to these or iframe them.

**Picker pages** are lightweight selection UIs. On selection, the picker writes entity ID + display strings to the workflow context via `PUT /api/v1/workflow`, then signals completion to the parent via `window.postMessage`.

---

## Plugin Logic (flutter_js)

```typescript
function createPlugin(host) {
  return {
    id: "dye2.reaplugin",
    version: "0.1.0",

    onLoad(settings) {
      // MVP: no initialization needed — entities live in core DB
    },

    onUnload() {
      // MVP: no cleanup needed
    },

    onEvent(event) {
      // MVP: no event processing
      // Future: stateUpdate for auto-select, shot completion for weight decrement
    },

    __httpRequestHandler(request) {
      switch (request.endpoint) {
        case "beans":          return renderBeansPage(request);
        case "grinders":       return renderGrindersPage(request);
        case "bean-picker":    return renderBeanPickerPage(request);
        case "grinder-picker": return renderGrinderPickerPage(request);
        default: return { status: 404, headers: {}, body: "Not found" };
      }
    }
  };
}
```

The plugin is essentially an HTTP server that generates HTML pages. All data operations go directly from browser Web Components to the core REST API.

---

## Web Components

### MVP Component Set

| Component | Purpose |
|---|---|
| `<dye2-bean-list>` | Lists beans with archive toggle, click to expand batches |
| `<dye2-bean-form>` | Create/edit bean (all fields from simplified schema) |
| `<dye2-bean-batch-list>` | Batches for a bean, weight remaining indicator |
| `<dye2-bean-batch-form>` | Create/edit batch |
| `<dye2-grinder-list>` | Lists grinders with archive toggle |
| `<dye2-grinder-form>` | Create/edit grinder (model + UI config fields) |
| `<dye2-bean-picker>` | Select bean+batch for workflow context |
| `<dye2-grinder-picker>` | Select grinder for workflow context |

### Component Pattern

Components are authored as TypeScript classes extending `HTMLElement`, compiled to strings, and inlined into HTML pages:

```typescript
// components/bean-list.ts
export class Dye2BeanList extends HTMLElement {
  connectedCallback() {
    this.innerHTML = `<div class="bean-list">Loading...</div>`;
    this.fetchBeans();
  }

  async fetchBeans() {
    const res = await fetch("/api/v1/beans");
    const beans = await res.json();
    this.render(beans);
  }

  render(beans) { /* ... */ }
}
customElements.define("dye2-bean-list", Dye2BeanList);
```

### Page Generation

```typescript
// pages/beans.ts
export function renderBeansPage(request): PluginResponse {
  return {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: `
      <!DOCTYPE html>
      <html>
      <head>
        <style>${sharedStyles()}</style>
        <script>${beanListComponent()}</script>
        <script>${beanFormComponent()}</script>
      </head>
      <body>
        <dye2-bean-list></dye2-bean-list>
      </body>
      </html>
    `
  };
}
```

---

## Data Flows

### Bean/Grinder Management

```
User opens beans page (skin link or direct URL)
  → Browser GETs /api/v1/plugins/dye2.reaplugin/beans
  → flutter_js plugin generates HTML with inlined Web Components
  → Browser renders <dye2-bean-list>
  → Component fetches GET /api/v1/beans (core REST API)
  → User creates/edits/archives via forms
  → Components POST/PUT/DELETE to /api/v1/beans (core REST API)
  → On success, list re-fetches and updates
```

### Workflow Selection (Picker)

```
Skin needs user to pick a bean for the next shot
  → Skin opens /api/v1/plugins/dye2.reaplugin/bean-picker (iframe/modal)
  → Browser renders <dye2-bean-picker>
  → Component fetches GET /api/v1/beans (active beans + batches)
  → User selects a bean batch
  → Component PUTs to /api/v1/workflow:
    {
      "context": {
        "beanBatchId": "uuid-def",
        "coffeeName": "La Esperanza",
        "coffeeRoaster": "Sey"
      }
    }
  → Component signals completion via window.postMessage
  → Skin closes picker, reads updated workflow
```

---

## Plugin KV Store Usage (MVP)

Minimal — entities live in core DB. Plugin storage holds only:
- User UI preferences (sort order, view state)
- Expanded/collapsed section state

---

## What's NOT in MVP

| Feature | When |
|---|---|
| Shot annotation UI (TDS, EY, enjoyment, notes) | Post-MVP |
| Equipment tracking (baskets, portafilters) | Post-MVP, via KV store + context.extras |
| Water chemistry profiles | Post-MVP, via KV store + context.extras |
| Tasting attribute breakdowns | Post-MVP, via annotations.extras |
| Shot prep techniques (RDT, distribution) | Post-MVP, via context.extras |
| Commercial blend management | Post-MVP, via Bean.extras.blendComponents |
| Beverage details (added liquid) | Post-MVP, via annotations.extras |
| stateUpdate event processing | Post-MVP |
| Auto weight decrement on shot completion | Post-MVP |
| Embeddable Web Components for skin integration | Post-MVP (progressive enhancement) |

---

## Future Path

1. **Shot annotations** — post-shot UI for dose/yield/TDS/EY/enjoyment/notes
2. **Equipment + Water** — plugin-local entities in KV store, written to context.extras
3. **Tasting breakdowns** — quality/intensity/notes per attribute in annotations.extras
4. **Embeddable components** — Web Components that skins can embed directly (not just full pages)
5. **Own repository** — DYE2 plugin moves to its own repo, published as a standalone artifact
