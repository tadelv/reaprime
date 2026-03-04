# DYE2 Plugin

DYE2 (Describe Your Espresso 2) is a first-party plugin for [Streamline Bridge](../../README.md) that provides bean, grinder, and equipment management UI for Decent Espresso machines.

## Goal

The core Streamline Bridge app stores beans, grinders, and batches in its database and exposes them via REST API — but provides no management UI for these entities. DYE2 fills that gap: it serves HTML pages with Web Components for full CRUD operations, plus lightweight pickers that skins can embed to select beans/grinders for the current workflow.

Long-term, DYE2 will expand to cover shot annotations (TDS, extraction yield, tasting notes), equipment tracking (baskets, portafilters), water chemistry, and commercial blend management.

## Architecture

DYE2 runs across two JavaScript runtimes:

1. **flutter_js** (server-side) — executes `plugin.js`, handles the plugin lifecycle, and routes HTTP requests to page generators that return HTML strings.
2. **Browser** (client-side) — renders the HTML pages served by the plugin. Web Components in the page call the core Streamline Bridge REST API directly via `fetch()`.

The plugin itself is essentially an HTTP server: it receives requests from the Streamline Bridge plugin framework and returns HTML responses. All data persistence goes through the core REST API (`/api/v1/beans`, `/api/v1/grinders`, `/api/v1/workflow`), not through plugin-local storage.

```
Browser                          Streamline Bridge                flutter_js
──────                          ─────────────────                ──────────
  │ GET /api/v1/plugins/                │                            │
  │   dye2.reaplugin/beans              │                            │
  │────────────────────────────────────>│  route to plugin           │
  │                                     │───────────────────────────>│
  │                                     │    __httpRequestHandler()  │
  │                                     │<───────────────────────────│
  │              HTML with              │    returns HTML string     │
  │         Web Components              │                            │
  │<────────────────────────────────────│                            │
  │                                     │                            │
  │ fetch /api/v1/beans                 │                            │
  │────────────────────────────────────>│ core REST API (direct)     │
  │              JSON                   │                            │
  │<────────────────────────────────────│                            │
```

## Current State (MVP)

**What works:**
- Bean CRUD — create, edit, list, archive beans with all schema fields (roaster, name, species, country, region, producer, processing, variety, altitude, decaf)
- Bean batch management — create, edit, list batches per bean (roast date/level, weight, price, quality score, dates)
- Grinder CRUD — create, edit, list, archive grinders (model, burrs, setting type, step sizes, RPM)
- Bean picker — select a bean + batch for the current workflow, writes to workflow context
- Grinder picker — select a grinder for the current workflow, writes to workflow context
- Dark theme UI styled for the DE1 tablet

**What's not built yet:**
- Shot annotation UI (TDS, extraction yield, enjoyment rating, tasting notes)
- Equipment tracking (baskets, portafilters, tampers) — planned via plugin KV store + `context.extras`
- Water chemistry profiles — planned via plugin KV store + `context.extras`
- Tasting attribute breakdowns (acidity, sweetness, body) — planned via `annotations.extras`
- Shot prep technique tracking (RDT, WDT, distribution) — planned via `context.extras`
- Commercial blend management — planned via `Bean.extras.blendComponents`
- Beverage details (added milk/liquid) — planned via `annotations.extras`
- Auto weight decrement on shot completion (consume batch weight after a shot)
- `stateUpdate` event processing (react to machine state changes)
- Embeddable Web Components for direct skin integration (currently full-page only)

## Project Structure

```
packages/dye2-plugin/
├── manifest.json             # Plugin metadata, permissions, HTTP endpoint declarations
├── package.json              # @streamline/dye2-plugin, Vite + TypeScript
├── vite.config.ts            # Library mode build → single IIFE bundle
├── tsconfig.json
└── src/
    ├── plugin.ts             # Entry point: createPlugin(host), HTTP router
    ├── host.d.ts             # TypeScript declarations for the flutter_js host API
    ├── api/
    │   └── client.ts         # Browser-side REST client (inlined into HTML pages)
    ├── components/           # Web Components (compiled to strings, inlined in HTML)
    │   ├── bean-list.ts      # <dye2-bean-list> — list with archive toggle
    │   ├── bean-form.ts      # <dye2-bean-form> — create/edit form
    │   ├── bean-batch-list.ts    # <dye2-bean-batch-list> — batches for a bean
    │   ├── bean-batch-form.ts    # <dye2-bean-batch-form> — create/edit batch
    │   ├── grinder-list.ts       # <dye2-grinder-list> — list with archive toggle
    │   ├── grinder-form.ts       # <dye2-grinder-form> — create/edit form
    │   ├── bean-picker.ts        # <dye2-bean-picker> — workflow bean selection
    │   └── grinder-picker.ts     # <dye2-grinder-picker> — workflow grinder selection
    ├── pages/                # Page generators (return full HTML documents)
    │   ├── layout.ts         # Shared page shell, CSS, HTML wrapper
    │   ├── beans.ts          # Beans management page
    │   ├── grinders.ts       # Grinders management page
    │   ├── bean-picker.ts    # Bean selection picker page
    │   └── grinder-picker.ts # Grinder selection picker page
    └── utils/
        └── html.ts           # Tagged template literal helper, HTML escaping
```

**Build output** (gitignored, generated into the Flutter assets directory):
```
assets/plugins/dye2.reaplugin/
├── manifest.json
└── plugin.js
```

## Build

Requires Node.js 20+.

```bash
cd packages/dye2-plugin
npm install
npm run build        # Production build → assets/plugins/dye2.reaplugin/
npm run dev          # Watch mode — rebuilds on source changes
```

The build uses Vite in library mode with IIFE output format. flutter_js does not support ES modules, so everything is bundled into a single self-executing function that exposes `createPlugin` on `globalThis`.

After building, the Flutter app picks up the plugin from `assets/plugins/dye2.reaplugin/` at startup. To test changes:
1. Run `npm run build` (or use `npm run dev` for watch mode)
2. Hot restart the Flutter app, or restart it fully

## Local Development

The normal workflow — build plugin, hot-restart Flutter app, navigate to the plugin page — is slow for UI iteration. The dev server shortcuts this: it loads the built `plugin.js` in a Node.js VM, serves pages directly in the browser, and proxies REST API calls to a running Streamline Bridge instance. Edit source, save, and the browser shows the result within seconds.

### Prerequisites

- Node.js 20+
- `npm install` (one time)
- A running Streamline Bridge instance (for API data). Start one with:
  ```bash
  # From the repo root
  flutter run --dart-define=simulate=1 -d macos   # or linux, chrome, etc.
  ```

### Quick start

Open three terminals in `packages/dye2-plugin/`:

```bash
# Terminal 1 — watch-build the plugin (rebuilds on source changes)
npm run dev

# Terminal 2 — start the dev server
npm run serve

# Terminal 3 — your editor
```

Then open `http://localhost:4444` in a browser. You'll see an index page listing all available plugin pages.

### Development loop

1. Edit a source file in `src/` (component, page, plugin router, etc.)
2. Vite rebuilds `plugin.js` automatically (`npm run dev` in terminal 1)
3. The dev server detects the file change and reloads the plugin
4. Refresh the browser to see your changes

The pages served by the dev server are functionally identical to what the Flutter plugin framework serves — same HTML, same Web Components, same REST API calls. The only difference is that API calls (`/api/v1/*`) are proxied to the bridge instead of being handled directly.

### How it works

```
Browser                    Dev Server (:4444)              Streamline Bridge (:8080)
──────                    ──────────────────              ─────────────────────────
  │ GET /beans                  │                                │
  │────────────────────────────>│                                │
  │                             │ vm.Script runs plugin.js       │
  │                             │ __httpRequestHandler("beans")  │
  │         HTML response       │                                │
  │<────────────────────────────│                                │
  │                             │                                │
  │ fetch /api/v1/beans         │                                │
  │────────────────────────────>│ proxy ────────────────────────>│
  │              JSON           │<──────────────────────────────│
  │<────────────────────────────│                                │
```

- Plugin pages (`/beans`, `/grinders`, `/bean-picker`, `/grinder-picker`) are served by running the plugin's `__httpRequestHandler` in a Node.js VM sandbox
- API requests (`/api/v1/*`) are proxied to the Streamline Bridge instance
- `plugin.js` is watched with `fs.watch()` and auto-reloaded on change (debounced)

### Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `PORT` | `4444` | Dev server port |
| `BRIDGE_URL` | `http://localhost:8080` | Streamline Bridge URL to proxy API calls to |

```bash
PORT=5000 BRIDGE_URL=http://192.168.1.5:8080 npm run serve
```

### Tips

- **Use with browser DevTools** — since pages load in a real browser, you get full access to the Elements inspector, Console, Network tab, and CSS editing. This is much faster than debugging inside the Flutter WebView.
- **No need to restart the dev server** when source changes — Vite rebuilds and the server reloads automatically. Just refresh the browser.
- **API data comes from the bridge** — create test beans/grinders via the bridge's REST API or the Flutter app UI, and they'll appear in the dev server pages.

## HTTP Endpoints

The plugin registers four HTTP endpoints, accessible at:

| Endpoint | URL | Purpose |
|----------|-----|---------|
| `beans` | `/api/v1/plugins/dye2.reaplugin/beans` | Bean + batch management (full page) |
| `grinders` | `/api/v1/plugins/dye2.reaplugin/grinders` | Grinder management (full page) |
| `bean-picker` | `/api/v1/plugins/dye2.reaplugin/bean-picker` | Bean/batch selection for workflow |
| `grinder-picker` | `/api/v1/plugins/dye2.reaplugin/grinder-picker` | Grinder selection for workflow |

Management pages are standalone — open them directly or link to them from a skin. Picker pages are designed to be embedded in iframes; on selection they `PUT /api/v1/workflow` and signal completion via `window.parent.postMessage`.

## Extending DYE2

### Adding a new page

1. Create a Web Component in `src/components/my-thing.ts` — export a string constant containing the component class definition (this runs in the browser, not flutter_js).
2. Create a page generator in `src/pages/my-thing.ts` — import the component string and use `pageShell()` from `layout.ts` to wrap it in a full HTML document.
3. Add a route in `src/plugin.ts` — add a `case` to the `__httpRequestHandler` switch.
4. Declare the endpoint in `manifest.json` — add an entry to the `api` array with `"type": "http"`.
5. Build and test.

### Adding fields to an existing form

Forms are defined as string constants in `src/components/*-form.ts`. Each form generates its HTML in a `render()` method and collects values in a `getFormData()` method. Add the new field to both, plus the corresponding REST API call in the submit handler.

### Component pattern

Components are vanilla Web Components (no framework). They follow this pattern:

```typescript
// src/components/example.ts
export const exampleComponent = `
class Dye2Example extends HTMLElement {
  connectedCallback() {
    this.render();
    this.loadData();
  }

  async loadData() {
    const res = await fetch('/api/v1/some-endpoint');
    if (!res.ok) { /* handle error */ return; }
    this._data = await res.json();
    this.render();
  }

  render() {
    this.innerHTML = \`<div>...</div>\`;
    // Attach event listeners after setting innerHTML
  }
}
customElements.define('dye2-example', Dye2Example);
`;
```

Key constraints:
- Components are compiled to **string constants** and inlined into HTML `<script>` tags — they do not execute in flutter_js.
- No framework dependencies — vanilla `HTMLElement`, `innerHTML`, `addEventListener`.
- All data operations use `fetch()` against the core Streamline Bridge REST API.
- Use `escapeHtml()` from `utils/html.ts` for any user-provided data rendered into HTML.

### Core REST API endpoints used by DYE2

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/v1/beans` | List beans (`?includeArchived=true` for all) |
| POST | `/api/v1/beans` | Create bean |
| GET | `/api/v1/beans/:id` | Get bean |
| PUT | `/api/v1/beans/:id` | Update bean |
| DELETE | `/api/v1/beans/:id` | Delete bean |
| GET | `/api/v1/beans/:id/batches` | List batches for a bean |
| POST | `/api/v1/beans/:id/batches` | Create batch |
| GET | `/api/v1/bean-batches/:id` | Get batch |
| PUT | `/api/v1/bean-batches/:id` | Update batch |
| DELETE | `/api/v1/bean-batches/:id` | Delete batch |
| GET | `/api/v1/grinders` | List grinders (`?includeArchived=true` for all) |
| POST | `/api/v1/grinders` | Create grinder |
| GET | `/api/v1/grinders/:id` | Get grinder |
| PUT | `/api/v1/grinders/:id` | Update grinder |
| DELETE | `/api/v1/grinders/:id` | Delete grinder |
| GET | `/api/v1/workflow` | Get current workflow |
| PUT | `/api/v1/workflow` | Update workflow (deep merge) |

### Related documentation

- [Plugin Development Guide](../../doc/Plugins.md) — general plugin system docs (lifecycle, host API, events, storage)
- [Design document](../../doc/plans/archive/dye2-plugin/2026-03-04-dye2-plugin-design.md) — architectural decisions and data flow diagrams
- [Implementation plan](../../doc/plans/archive/dye2-plugin/2026-03-04-dye2-plugin-implementation.md) — task breakdown used to build the MVP
