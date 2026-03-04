# DYE2 Plugin Scaffold Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a buildable DYE2 plugin scaffold with Vite tooling, TypeScript types, and a working "hello world" HTTP endpoint that proves the full pipeline (build → bundle as asset → load in app → serve HTML).

**Architecture:** Monolithic Vite-bundled TypeScript plugin in `packages/dye2-plugin/`, IIFE output to `assets/plugins/dye2.reaplugin/`. Web Components compiled to strings, inlined into HTML served via plugin HTTP endpoints. All data operations go from browser directly to core REST API.

**Tech Stack:** TypeScript, Vite (library mode, IIFE), Web Components, Shelf (plugin HTTP handler)

**Design doc:** `doc/plans/2026-03-04-dye2-plugin-design.md`

---

## Task 1: Package Scaffold

Create the `packages/dye2-plugin/` directory with build tooling config.

**Files:**
- Create: `packages/dye2-plugin/package.json`
- Create: `packages/dye2-plugin/tsconfig.json`
- Create: `packages/dye2-plugin/vite.config.ts`

**Step 1: Create package.json**

```json
{
  "name": "@streamline/dye2-plugin",
  "version": "0.1.0",
  "private": true,
  "description": "Streamline/DYE2 plugin for bean and grinder management",
  "type": "module",
  "scripts": {
    "build": "vite build",
    "dev": "vite build --watch"
  },
  "devDependencies": {
    "typescript": "^5.8.0",
    "vite": "^6.0.0",
    "vite-plugin-dts": "^4.0.0"
  }
}
```

**Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": false,
    "sourceMap": false,
    "lib": ["ES2020"]
  },
  "include": ["src/**/*"]
}
```

Note: No DOM lib — the plugin entry runs in flutter_js. Components that need DOM types use inline `declare` statements or a separate tsconfig for the component sub-build (addressed in Task 4).

**Step 3: Create vite.config.ts**

```typescript
import { defineConfig } from "vite";
import { resolve } from "path";
import { readFileSync, mkdirSync, copyFileSync } from "fs";

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, "src/plugin.ts"),
      name: "createPlugin",
      formats: ["iife"],
      fileName: () => "plugin.js",
    },
    outDir: resolve(__dirname, "../../assets/plugins/dye2.reaplugin"),
    emptyOutDir: false,
    minify: false,
    rollupOptions: {
      output: {
        // Wrap in a function that flutter_js can call
        // The IIFE should expose createPlugin on globalThis
        footer: "",
      },
    },
  },
  plugins: [
    {
      name: "copy-manifest",
      closeBundle() {
        const outDir = resolve(
          __dirname,
          "../../assets/plugins/dye2.reaplugin"
        );
        mkdirSync(outDir, { recursive: true });
        copyFileSync(
          resolve(__dirname, "manifest.json"),
          resolve(outDir, "manifest.json")
        );
      },
    },
  ],
});
```

**Step 4: Install dependencies**

Run: `cd packages/dye2-plugin && npm install`
Expected: `node_modules/` created, `package-lock.json` generated

**Step 5: Commit**

```bash
git add packages/dye2-plugin/package.json packages/dye2-plugin/tsconfig.json packages/dye2-plugin/vite.config.ts packages/dye2-plugin/package-lock.json
git commit -m "feat(dye2): scaffold package with Vite build config"
```

---

## Task 2: Manifest & Plugin Entry Point

Create the manifest and a minimal plugin.ts that responds to HTTP requests.

**Files:**
- Create: `packages/dye2-plugin/manifest.json`
- Create: `packages/dye2-plugin/src/plugin.ts`
- Create: `packages/dye2-plugin/src/host.d.ts`

**Step 1: Create manifest.json**

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

**Step 2: Create host.d.ts**

Type declarations for the flutter_js host API. Not a real module — these types help during development.

```typescript
/** Host API provided by the flutter_js plugin runtime */
interface PluginHost {
  log(message: string): void;
  emit(eventName: string, payload: Record<string, unknown>): void;
  storage(command: StorageCommand): void;
}

interface StorageCommand {
  type: "read" | "write";
  key: string;
  namespace: string;
  data?: unknown;
}

interface PluginEvent {
  name: string;
  payload: Record<string, unknown>;
}

interface HttpRequest {
  requestId: string;
  endpoint: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
  query: Record<string, string>;
}

interface HttpResponse {
  requestId?: string;
  status: number;
  headers: Record<string, string>;
  body: string;
}

interface PluginInstance {
  id: string;
  version: string;
  onLoad(settings: Record<string, unknown>): void;
  onUnload(): void;
  onEvent(event: PluginEvent): void;
  __httpRequestHandler(request: HttpRequest): HttpResponse | Promise<HttpResponse>;
}
```

**Step 3: Create plugin.ts**

Minimal entry point with a "hello world" beans endpoint.

```typescript
/// <reference path="./host.d.ts" />

function createPlugin(host: PluginHost): PluginInstance {
  function log(msg: string) {
    host.log(`[dye2] ${msg}`);
  }

  return {
    id: "dye2.reaplugin",
    version: "0.1.0",

    onLoad(_settings: Record<string, unknown>) {
      log("DYE2 plugin loaded");
    },

    onUnload() {
      log("DYE2 plugin unloaded");
    },

    onEvent(_event: PluginEvent) {
      // MVP: no event processing
    },

    __httpRequestHandler(request: HttpRequest): HttpResponse {
      log(`HTTP ${request.method} ${request.endpoint}`);

      switch (request.endpoint) {
        case "beans":
          return {
            requestId: request.requestId,
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
            body: `<!DOCTYPE html>
<html>
<head><title>DYE2 - Beans</title></head>
<body>
  <h1>Streamline/DYE2 - Beans Management</h1>
  <p>Plugin scaffold working. Components coming soon.</p>
</body>
</html>`,
          };

        case "grinders":
          return {
            requestId: request.requestId,
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
            body: `<!DOCTYPE html>
<html>
<head><title>DYE2 - Grinders</title></head>
<body>
  <h1>Streamline/DYE2 - Grinders Management</h1>
  <p>Plugin scaffold working. Components coming soon.</p>
</body>
</html>`,
          };

        case "bean-picker":
        case "grinder-picker":
          return {
            requestId: request.requestId,
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
            body: `<!DOCTYPE html>
<html>
<head><title>DYE2 - Picker</title></head>
<body>
  <h1>Streamline/DYE2 - ${request.endpoint}</h1>
  <p>Picker scaffold working.</p>
</body>
</html>`,
          };

        default:
          return {
            requestId: request.requestId,
            status: 404,
            headers: { "Content-Type": "text/plain" },
            body: "Not found",
          };
      }
    },
  };
}
```

**Step 4: Commit**

```bash
git add packages/dye2-plugin/manifest.json packages/dye2-plugin/src/plugin.ts packages/dye2-plugin/src/host.d.ts
git commit -m "feat(dye2): add manifest and minimal plugin entry point"
```

---

## Task 3: Build & Verify Bundle

Build the plugin and verify the output is a valid IIFE that exposes `createPlugin`.

**Step 1: Run the build**

Run: `cd packages/dye2-plugin && npm run build`
Expected: `assets/plugins/dye2.reaplugin/plugin.js` and `manifest.json` created

**Step 2: Verify the bundle format**

Run: `head -5 assets/plugins/dye2.reaplugin/plugin.js`

Expected: Should be an IIFE wrapping the plugin code. The `createPlugin` function must be accessible at the top level (not nested in a module scope). If Vite wraps it in `var createPlugin = (function() { ... })()`, the flutter_js wrapper in `plugin_manager.dart` may not find it.

Check how existing plugins are loaded — look at `plugin_manager.dart` for the JS wrapper:

```dart
// plugin_manager.dart wraps plugin code like:
// globalThis.__plugins__["pluginId"] = (function() { ${jsCode} return createPlugin(host); })();
```

So `createPlugin` must be a **function declaration** at the top level of the bundle output. Vite IIFE may need adjustment. If the output wraps `createPlugin` in `var createPlugin = ...`, it should still work since the wrapper calls `createPlugin(host)` within the same scope.

**Step 3: Verify the bundle is valid JS**

Run: `node -e "const fs = require('fs'); const code = fs.readFileSync('assets/plugins/dye2.reaplugin/plugin.js', 'utf8'); eval(code); console.log(typeof createPlugin);"`
Expected: `function`

If this fails, the Vite config needs adjustment. Common fixes:
- Ensure `build.lib.name` matches `createPlugin`
- Try `formats: ['iife']` with explicit `rollupOptions.output.name: 'createPlugin'`
- If all else fails, use a Rollup output banner/footer to manually expose the function

**Step 4: Commit (if build adjustments were needed)**

```bash
git add packages/dye2-plugin/vite.config.ts
git commit -m "fix(dye2): adjust Vite config for flutter_js compatible output"
```

---

## Task 4: Gitignore & Pubspec Registration

Register the plugin as a bundled asset and gitignore the build output.

**Files:**
- Modify: `.gitignore`
- Modify: `pubspec.yaml` (line ~115, after existing plugin assets)
- Modify: `lib/src/plugins/plugin_loader_service.dart` (line ~376, `_getBundledPluginPaths`)

**Step 1: Add build output to .gitignore**

Append to `.gitignore`:
```
# DYE2 plugin build output
assets/plugins/dye2.reaplugin/
```

**Step 2: Add to pubspec.yaml assets**

After the existing plugin asset declarations (around line 115), add:
```yaml
    - assets/plugins/dye2.reaplugin/
```

**Step 3: Register in bundled plugins list**

In `lib/src/plugins/plugin_loader_service.dart`, add to the `_getBundledPluginPaths()` return list (around line 379):
```dart
      'assets/plugins/dye2.reaplugin',
```

**Step 4: Commit**

```bash
git add .gitignore pubspec.yaml lib/src/plugins/plugin_loader_service.dart
git commit -m "feat(dye2): register as bundled plugin asset"
```

---

## Task 5: End-to-End Smoke Test

Verify the full pipeline: build plugin → Flutter bundles it → plugin loads → HTTP endpoint serves HTML.

**Step 1: Build the plugin**

Run: `cd packages/dye2-plugin && npm run build`

**Step 2: Run the app in simulate mode**

Run: `flutter run --dart-define=simulate=1`

Or use the MCP tool:
```
app_start with connectDevice: "MockDe1"
```

**Step 3: Verify plugin loads**

Run: `curl http://localhost:8080/api/v1/plugins`
Expected: Response includes an entry with `"id": "dye2.reaplugin"`

**Step 4: Verify HTTP endpoint**

Run: `curl http://localhost:8080/api/v1/plugins/dye2.reaplugin/beans`
Expected: HTML response with "Streamline/DYE2 - Beans Management"

Run: `curl http://localhost:8080/api/v1/plugins/dye2.reaplugin/grinders`
Expected: HTML response with "Streamline/DYE2 - Grinders Management"

**Step 5: Commit success**

No code changes needed if everything works. If fixes were required, commit them:

```bash
git add -A
git commit -m "fix(dye2): end-to-end smoke test fixes"
```

---

## Task 6: Utility Modules

Create the shared utilities that all pages and components will use.

**Files:**
- Create: `packages/dye2-plugin/src/utils/html.ts`
- Create: `packages/dye2-plugin/src/api/client.ts`

**Step 1: Create html.ts — tagged template literal helper**

```typescript
/**
 * Tagged template literal for HTML strings.
 * Provides a visual marker for syntax highlighting in editors
 * and escapes interpolated values.
 */
export function html(
  strings: TemplateStringsArray,
  ...values: unknown[]
): string {
  return strings.reduce((result, str, i) => {
    const value = i < values.length ? String(values[i]) : "";
    return result + str + value;
  }, "");
}

/** Escape HTML special characters in user-provided strings */
export function escapeHtml(unsafe: string): string {
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
```

**Step 2: Create client.ts — REST API wrapper (browser-side)**

This is code that runs in the **browser**, not in flutter_js. It will be inlined into HTML pages as a `<script>` block.

```typescript
/**
 * REST API client for use in browser-side Web Components.
 * This code is compiled to a string and inlined in served HTML pages.
 */

const API_BASE = "/api/v1";

export const api = {
  async listBeans(includeArchived = false): Promise<unknown[]> {
    const params = includeArchived ? "?archived=true" : "";
    const res = await fetch(`${API_BASE}/beans${params}`);
    return res.json();
  },

  async getBean(id: string): Promise<unknown> {
    const res = await fetch(`${API_BASE}/beans/${id}`);
    return res.json();
  },

  async createBean(bean: Record<string, unknown>): Promise<unknown> {
    const res = await fetch(`${API_BASE}/beans`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(bean),
    });
    return res.json();
  },

  async updateBean(
    id: string,
    bean: Record<string, unknown>
  ): Promise<unknown> {
    const res = await fetch(`${API_BASE}/beans/${id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(bean),
    });
    return res.json();
  },

  async deleteBean(id: string): Promise<void> {
    await fetch(`${API_BASE}/beans/${id}`, { method: "DELETE" });
  },

  async listBatches(beanId: string): Promise<unknown[]> {
    const res = await fetch(`${API_BASE}/beans/${beanId}/batches`);
    return res.json();
  },

  async createBatch(
    beanId: string,
    batch: Record<string, unknown>
  ): Promise<unknown> {
    const res = await fetch(`${API_BASE}/beans/${beanId}/batches`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(batch),
    });
    return res.json();
  },

  async updateBatch(
    id: string,
    batch: Record<string, unknown>
  ): Promise<unknown> {
    const res = await fetch(`${API_BASE}/bean-batches/${id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(batch),
    });
    return res.json();
  },

  async deleteBatch(id: string): Promise<void> {
    await fetch(`${API_BASE}/bean-batches/${id}`, { method: "DELETE" });
  },

  async listGrinders(includeArchived = false): Promise<unknown[]> {
    const params = includeArchived ? "?archived=true" : "";
    const res = await fetch(`${API_BASE}/grinders${params}`);
    return res.json();
  },

  async getGrinder(id: string): Promise<unknown> {
    const res = await fetch(`${API_BASE}/grinders/${id}`);
    return res.json();
  },

  async createGrinder(grinder: Record<string, unknown>): Promise<unknown> {
    const res = await fetch(`${API_BASE}/grinders`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(grinder),
    });
    return res.json();
  },

  async updateGrinder(
    id: string,
    grinder: Record<string, unknown>
  ): Promise<unknown> {
    const res = await fetch(`${API_BASE}/grinders/${id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(grinder),
    });
    return res.json();
  },

  async deleteGrinder(id: string): Promise<void> {
    await fetch(`${API_BASE}/grinders/${id}`, { method: "DELETE" });
  },

  async getWorkflow(): Promise<unknown> {
    const res = await fetch(`${API_BASE}/workflow`);
    return res.json();
  },

  async updateWorkflow(
    workflow: Record<string, unknown>
  ): Promise<unknown> {
    const res = await fetch(`${API_BASE}/workflow`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(workflow),
    });
    return res.json();
  },
};
```

**Step 3: Commit**

```bash
git add packages/dye2-plugin/src/utils/html.ts packages/dye2-plugin/src/api/client.ts
git commit -m "feat(dye2): add HTML template helper and REST API client"
```

---

## Task 7: Page Layout & Shared Styles

Create the shared page shell that all pages use.

**Files:**
- Create: `packages/dye2-plugin/src/pages/layout.ts`

**Step 1: Create layout.ts**

```typescript
import { html } from "../utils/html";

/** Shared CSS for all DYE2 pages */
export function sharedStyles(): string {
  return `
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #1a1a2e;
      color: #e0e0e0;
      padding: 16px;
    }
    h1 { font-size: 1.4rem; margin-bottom: 16px; color: #fff; }
    h2 { font-size: 1.1rem; margin-bottom: 12px; color: #ccc; }
    button {
      background: #16213e;
      color: #e0e0e0;
      border: 1px solid #0f3460;
      padding: 8px 16px;
      border-radius: 4px;
      cursor: pointer;
      font-size: 0.9rem;
    }
    button:hover { background: #0f3460; }
    button.primary { background: #533483; border-color: #533483; }
    button.primary:hover { background: #6a42a0; }
    button.danger { background: #6b2737; border-color: #6b2737; }
    button.danger:hover { background: #8b3a4a; }
    input, select, textarea {
      background: #16213e;
      color: #e0e0e0;
      border: 1px solid #0f3460;
      padding: 8px;
      border-radius: 4px;
      font-size: 0.9rem;
      width: 100%;
    }
    input:focus, select:focus, textarea:focus {
      outline: none;
      border-color: #533483;
    }
    .card {
      background: #16213e;
      border: 1px solid #0f3460;
      border-radius: 8px;
      padding: 16px;
      margin-bottom: 12px;
    }
    .flex { display: flex; gap: 8px; align-items: center; }
    .flex-between { display: flex; justify-content: space-between; align-items: center; }
    .grid { display: grid; gap: 12px; }
    .grid-2 { grid-template-columns: 1fr 1fr; }
    .mt-8 { margin-top: 8px; }
    .mt-16 { margin-top: 16px; }
    .mb-8 { margin-bottom: 8px; }
    .text-muted { color: #888; }
    .text-small { font-size: 0.8rem; }
    .hidden { display: none; }
    .tag {
      display: inline-block;
      background: #0f3460;
      padding: 2px 8px;
      border-radius: 12px;
      font-size: 0.75rem;
      margin-right: 4px;
    }
  `;
}

/**
 * Wrap page content in a full HTML document with shared styles
 * and the browser-side API client.
 */
export function pageShell(title: string, content: string, scripts: string[] = []): string {
  return html`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>DYE2 - ${title}</title>
  <style>${sharedStyles()}</style>
</head>
<body>
  ${content}
  ${scripts.map((s) => `<script>${s}</script>`).join("\n")}
</body>
</html>`;
}
```

**Step 2: Commit**

```bash
git add packages/dye2-plugin/src/pages/layout.ts
git commit -m "feat(dye2): add shared page layout and styles"
```

---

## Task 8: Bean List Component

Create the first real Web Component — a bean list that fetches from the core API.

**Files:**
- Create: `packages/dye2-plugin/src/components/bean-list.ts`
- Modify: `packages/dye2-plugin/src/pages/beans.ts` (create)
- Modify: `packages/dye2-plugin/src/plugin.ts` (wire up beans page)

**Step 1: Create bean-list.ts**

This is browser-side code. It will be compiled and inlined as a string in the HTML page.

```typescript
/**
 * <dye2-bean-list> Web Component
 * Fetches and displays beans from the core REST API.
 * Runs in the BROWSER (not flutter_js).
 */
export const beanListComponent = `
class Dye2BeanList extends HTMLElement {
  constructor() {
    super();
    this._beans = [];
    this._showArchived = false;
  }

  connectedCallback() {
    this.render();
    this.fetchBeans();
  }

  async fetchBeans() {
    try {
      const params = this._showArchived ? '?includeArchived=true' : '';
      const res = await fetch('/api/v1/beans' + params);
      this._beans = await res.json();
      this.render();
    } catch (err) {
      this.innerHTML = '<p style="color: #ff6b6b;">Failed to load beans: ' + err.message + '</p>';
    }
  }

  toggleArchived() {
    this._showArchived = !this._showArchived;
    this.fetchBeans();
  }

  render() {
    const beans = this._beans;
    this.innerHTML = \`
      <div class="flex-between mb-8">
        <h1>Beans</h1>
        <div class="flex">
          <label class="flex" style="cursor:pointer;">
            <input type="checkbox" \${this._showArchived ? 'checked' : ''} style="width:auto;" />
            <span class="text-small">Show archived</span>
          </label>
          <button class="primary" data-action="create">+ Add Bean</button>
        </div>
      </div>
      \${beans.length === 0
        ? '<p class="text-muted">No beans yet. Add your first coffee!</p>'
        : beans.map(bean => \`
          <div class="card" data-bean-id="\${bean.id}">
            <div class="flex-between">
              <div>
                <strong>\${bean.name || 'Unnamed'}</strong>
                <span class="text-muted"> by \${bean.roaster || 'Unknown roaster'}</span>
              </div>
              <div class="flex">
                \${bean.archived ? '<span class="tag">archived</span>' : ''}
                \${bean.country ? '<span class="tag">' + bean.country + '</span>' : ''}
                \${bean.processing ? '<span class="tag">' + bean.processing + '</span>' : ''}
              </div>
            </div>
            \${bean.variety && bean.variety.length ? '<div class="text-small text-muted mt-8">' + bean.variety.join(', ') + '</div>' : ''}
          </div>
        \`).join('')
      }
    \`;

    // Event listeners
    const checkbox = this.querySelector('input[type="checkbox"]');
    if (checkbox) checkbox.addEventListener('change', () => this.toggleArchived());

    const createBtn = this.querySelector('[data-action="create"]');
    if (createBtn) createBtn.addEventListener('click', () => {
      this.dispatchEvent(new CustomEvent('create-bean', { bubbles: true }));
    });

    this.querySelectorAll('[data-bean-id]').forEach(card => {
      card.style.cursor = 'pointer';
      card.addEventListener('click', () => {
        const id = card.getAttribute('data-bean-id');
        this.dispatchEvent(new CustomEvent('select-bean', { detail: { id }, bubbles: true }));
      });
    });
  }
}
customElements.define('dye2-bean-list', Dye2BeanList);
`;
```

**Step 2: Create pages/beans.ts**

```typescript
import { pageShell } from "./layout";
import { beanListComponent } from "../components/bean-list";
import type { HttpRequest, HttpResponse } from "../host";

export function renderBeansPage(request: HttpRequest): HttpResponse {
  const content = `<dye2-bean-list></dye2-bean-list>`;

  return {
    requestId: request.requestId,
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: pageShell("Beans", content, [beanListComponent]),
  };
}
```

Note: the `HttpRequest`/`HttpResponse` types are referenced here. They need to be exportable from `host.d.ts`. Update `host.d.ts` to use `export interface` or make `plugin.ts` import from a types module. Since this is an IIFE build, the simplest approach is to keep types as ambient declarations (no export/import of types at runtime — TypeScript strips them).

**Step 3: Update plugin.ts to use the page**

Replace the inline HTML in the `beans` case with:

```typescript
import { renderBeansPage } from "./pages/beans";
import { renderGrindersPage } from "./pages/grinders";

// In __httpRequestHandler:
case "beans":
  return renderBeansPage(request);
case "grinders":
  return renderGrindersPage(request);
```

Create a placeholder `pages/grinders.ts` for now (same pattern, will be filled in Task 9).

**Step 4: Build and verify**

Run: `cd packages/dye2-plugin && npm run build`
Expected: No TypeScript errors. `plugin.js` updated.

**Step 5: Commit**

```bash
git add packages/dye2-plugin/src/components/bean-list.ts packages/dye2-plugin/src/pages/beans.ts packages/dye2-plugin/src/plugin.ts
git commit -m "feat(dye2): add bean list component and beans page"
```

---

## Task 9: Grinder List Component

Same pattern as Task 8 but for grinders.

**Files:**
- Create: `packages/dye2-plugin/src/components/grinder-list.ts`
- Create: `packages/dye2-plugin/src/pages/grinders.ts`

**Step 1: Create grinder-list.ts**

Follow the same pattern as `bean-list.ts`. Display grinder model, burrs, burrType, settingType, and archived status. Show DYE2 UI config fields (settingSmallStep, settingBigStep, etc.) as secondary info.

**Step 2: Create pages/grinders.ts**

Same pattern as `pages/beans.ts`, using `grinder-list` component.

**Step 3: Build and verify**

Run: `cd packages/dye2-plugin && npm run build`

**Step 4: Commit**

```bash
git add packages/dye2-plugin/src/components/grinder-list.ts packages/dye2-plugin/src/pages/grinders.ts
git commit -m "feat(dye2): add grinder list component and grinders page"
```

---

## Task 10: Bean & Grinder Form Components

Create form components for creating/editing beans and grinders.

**Files:**
- Create: `packages/dye2-plugin/src/components/bean-form.ts`
- Create: `packages/dye2-plugin/src/components/grinder-form.ts`
- Modify: `packages/dye2-plugin/src/pages/beans.ts` (include form)
- Modify: `packages/dye2-plugin/src/pages/grinders.ts` (include form)

**Step 1: Create bean-form.ts**

Component that handles create and edit. Fields from the simplified schema:
- `roaster` (required), `name` (required)
- `species`, `country`, `region`, `producer`, `processing` (optional text)
- `variety` (comma-separated text → array)
- `altitude` (text → array of ints)
- `decaf` (checkbox), `decafProcess` (text, shown when decaf is checked)
- `notes` (textarea)

On submit, POSTs to `/api/v1/beans` (create) or PUTs to `/api/v1/beans/{id}` (edit). Dispatches `bean-saved` event on success.

**Step 2: Create grinder-form.ts**

Fields:
- `model` (required)
- `burrs`, `burrSize`, `burrType` (optional)
- `settingType` (select: numeric/preset)
- `settingValues` (text, shown when settingType=preset)
- `settingSmallStep`, `settingBigStep` (number, shown when settingType=numeric)
- `rpmSmallStep`, `rpmBigStep` (number, optional)
- `notes` (textarea)

**Step 3: Wire forms into pages**

Pages listen for `create-bean`/`create-grinder` events from list components, show the form. Forms dispatch `bean-saved`/`grinder-saved` events, list re-fetches.

**Step 4: Build and verify**

Run: `cd packages/dye2-plugin && npm run build`

**Step 5: Commit**

```bash
git add packages/dye2-plugin/src/components/bean-form.ts packages/dye2-plugin/src/components/grinder-form.ts packages/dye2-plugin/src/pages/beans.ts packages/dye2-plugin/src/pages/grinders.ts
git commit -m "feat(dye2): add bean and grinder form components"
```

---

## Task 11: Bean Batch Components

Add batch list and form components, integrated into the beans page.

**Files:**
- Create: `packages/dye2-plugin/src/components/bean-batch-list.ts`
- Create: `packages/dye2-plugin/src/components/bean-batch-form.ts`
- Modify: `packages/dye2-plugin/src/pages/beans.ts` (include batch components)

**Step 1: Create bean-batch-list.ts**

Displayed when a bean card is expanded/selected. Shows batches for that bean with roast date, weight remaining, roast level, frozen status. Uses `GET /api/v1/beans/{beanId}/batches`.

**Step 2: Create bean-batch-form.ts**

Fields from schema: roastDate, roastLevel, harvestDate, qualityScore, price, currency, weight, buyDate, openDate, bestBeforeDate, notes.

Creates via `POST /api/v1/beans/{beanId}/batches`, edits via `PUT /api/v1/bean-batches/{id}`.

**Step 3: Wire into beans page**

Bean card click expands to show batch list. Batch list has "Add Batch" button.

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git add packages/dye2-plugin/src/components/bean-batch-list.ts packages/dye2-plugin/src/components/bean-batch-form.ts packages/dye2-plugin/src/pages/beans.ts
git commit -m "feat(dye2): add bean batch list and form components"
```

---

## Task 12: Picker Components

Create workflow selection pickers for beans and grinders.

**Files:**
- Create: `packages/dye2-plugin/src/components/bean-picker.ts`
- Create: `packages/dye2-plugin/src/components/grinder-picker.ts`
- Create: `packages/dye2-plugin/src/pages/bean-picker.ts`
- Create: `packages/dye2-plugin/src/pages/grinder-picker.ts`
- Modify: `packages/dye2-plugin/src/plugin.ts` (wire picker pages)

**Step 1: Create bean-picker.ts**

Lightweight list of active beans → expand to batches → select a batch. On selection:
1. `PUT /api/v1/workflow` with `{ "context": { "beanBatchId": id, "coffeeName": name, "coffeeRoaster": roaster } }`
2. Dispatch `CustomEvent('picker-done', { detail: { beanBatchId, coffeeName, coffeeRoaster } })`
3. Call `window.parent.postMessage({ type: 'dye2-picker-done', ... }, '*')` for iframe integration

**Step 2: Create grinder-picker.ts**

List of active grinders → select one. On selection:
1. `PUT /api/v1/workflow` with `{ "context": { "grinderId": id, "grinderModel": model } }`
2. Same event dispatching pattern

**Step 3: Create picker pages**

Minimal pages using `pageShell()` with just the picker component.

**Step 4: Wire into plugin.ts**

**Step 5: Build and verify**

**Step 6: Commit**

```bash
git add packages/dye2-plugin/src/components/bean-picker.ts packages/dye2-plugin/src/components/grinder-picker.ts packages/dye2-plugin/src/pages/bean-picker.ts packages/dye2-plugin/src/pages/grinder-picker.ts packages/dye2-plugin/src/plugin.ts
git commit -m "feat(dye2): add bean and grinder picker components"
```

---

## Task 13: CI Workflow Updates

Add DYE2 plugin build step to both GitHub Actions workflows.

**Files:**
- Modify: `.github/workflows/develop-builds.yml`
- Modify: `.github/workflows/release.yml`

**Step 1: Add build step to develop-builds.yml**

In **every build job** (build-android, build-macos, build-linux, build-raspberrypi, build-windows), add after "Install dependencies" and before the Flutter build step:

```yaml
      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Build DYE2 plugin
        run: |
          cd packages/dye2-plugin
          npm ci
          npm run build
```

**Step 2: Add same steps to release.yml**

Same pattern in all build jobs.

**Step 3: Commit**

```bash
git add .github/workflows/develop-builds.yml .github/workflows/release.yml
git commit -m "ci: add DYE2 plugin build step to CI workflows"
```

---

## Task 14: End-to-End Verification

Full pipeline test with the complete plugin.

**Step 1: Build plugin**

Run: `cd packages/dye2-plugin && npm run build`

**Step 2: Run app**

Run: `flutter run --dart-define=simulate=1`

**Step 3: Verify all endpoints**

```bash
curl http://localhost:8080/api/v1/plugins/dye2.reaplugin/beans
curl http://localhost:8080/api/v1/plugins/dye2.reaplugin/grinders
curl http://localhost:8080/api/v1/plugins/dye2.reaplugin/bean-picker
curl http://localhost:8080/api/v1/plugins/dye2.reaplugin/grinder-picker
```

All should return valid HTML with Web Components.

**Step 4: Test in browser**

Open `http://localhost:8080/api/v1/plugins/dye2.reaplugin/beans` in a browser. The page should render, fetch beans from the API (empty list initially), and show "No beans yet" message.

Create a bean via curl to verify the list updates:
```bash
curl -X POST http://localhost:8080/api/v1/beans \
  -H "Content-Type: application/json" \
  -d '{"roaster": "Sey", "name": "La Esperanza"}'
```

Refresh the beans page — should show the new bean.

**Step 5: Test picker workflow**

Open `http://localhost:8080/api/v1/plugins/dye2.reaplugin/bean-picker` in browser. Select the bean/batch. Check workflow was updated:

```bash
curl http://localhost:8080/api/v1/workflow
```

Should show `context.coffeeName: "La Esperanza"`, `context.coffeeRoaster: "Sey"`.

**Step 6: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues related to plugin changes.

---

## Task Summary

| Task | Description | Risk |
|------|-------------|------|
| 1 | Package scaffold (package.json, tsconfig, vite.config) | Low |
| 2 | Manifest & plugin entry point | Low |
| 3 | Build & verify bundle format | **Medium** — IIFE output must match flutter_js expectations |
| 4 | Gitignore & pubspec registration | Low |
| 5 | End-to-end smoke test (hello world) | **Medium** — first full pipeline test |
| 6 | Utility modules (HTML helper, API client) | Low |
| 7 | Page layout & shared styles | Low |
| 8 | Bean list component | Low |
| 9 | Grinder list component | Low |
| 10 | Bean & grinder form components | Medium |
| 11 | Bean batch components | Medium |
| 12 | Picker components | Medium |
| 13 | CI workflow updates | Low |
| 14 | End-to-end verification | Low |
| 15 | Update native UI (home_feature) for new schema | **High** — depends on schema migration |

**Critical path:** Tasks 1-5 must be done sequentially (build pipeline). Tasks 6-12 can be done in any order after Task 5. Task 13 is independent. Task 14 is second to last. Task 15 is last.

---

## Task 15: Update Native UI (home_feature) for New Schema

Update the Flutter home_feature to support the new bean/grinder schema fields on WorkflowContext. This ensures the native app UI displays entity data from the new schema correctly alongside the DYE2 plugin.

**Files:**
- Modify: `lib/src/home_feature/tiles/profile_tile.dart` — update grinder/coffee display to read from `WorkflowContext` fields (`grinderModel`, `grinderSetting`, `coffeeName`, `coffeeRoaster`, `grinderId`, `beanBatchId`)
- Modify: `lib/src/history_feature/history_feature.dart` — update shot history display to read from `workflow.context` and `annotations` instead of legacy `grinderData`/`coffeeData`/`doseData`
- Modify: other home_feature widgets that reference `DoseData`, `GrinderData`, or `CoffeeData`

**Note:** This task depends on the simplified schema implementation (Phase 1 of `simplified-schema-implementation-plan.md`). If WorkflowContext migration has not yet been done in the core app, this task should be deferred until after that migration. The DYE2 plugin scaffold (Tasks 1-14) does NOT depend on this task — it works with the current API surface.

**Step 1: Audit home_feature for old field references**

Search for `doseData`, `grinderData`, `coffeeData`, `DoseData`, `GrinderData`, `CoffeeData` in `lib/src/home_feature/` and `lib/src/history_feature/`.

**Step 2: Update profile_tile.dart**

Replace all reads of `workflow.doseData.doseIn`/`doseOut` with `workflow.context?.targetDoseWeight`/`targetYield`. Replace `grinderData?.model` with `context?.grinderModel`, `coffeeData?.name` with `context?.coffeeName`, etc. Replace mutable `doseData.doseIn = x` pattern with immutable `updateWorkflow(context: context.copyWith(...))`.

**Step 3: Update history_feature.dart**

Replace old field reads for shot display with `workflow.context` and `annotations` equivalents.

**Step 4: Run tests**

```bash
flutter test test/
flutter analyze
```

**Step 5: Visual verification**

Run with `flutter run --dart-define=simulate=1`. Verify profile tile displays dose/grinder/coffee correctly. Verify history shows shot data correctly.

**Step 6: Commit**

```bash
git add lib/src/home_feature/ lib/src/history_feature/
git commit -m "feat: update native UI to use WorkflowContext schema fields"
```
