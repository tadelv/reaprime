# Streamline Bridge MCP Server — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a TypeScript MCP server that bridges Claude Code to a running Streamline Bridge instance for developer tooling and integration testing.

**Architecture:** Standalone TypeScript process in `packages/mcp-server/`. Thin proxy tools wrap REST endpoints 1:1, smart utility tools manage app lifecycle and WebSocket streaming. Static resources serve docs, live resources query running instance.

**Tech Stack:** TypeScript, `@modelcontextprotocol/sdk` v1.x, `express` (Streamable HTTP transport), `ws` (WebSocket client), `zod` (schema validation).

**Design doc:** `doc/plans/2026-03-03-mcp-server-design.md`

---

## Task 1: Project Scaffolding

**Files:**
- Create: `packages/mcp-server/package.json`
- Create: `packages/mcp-server/tsconfig.json`
- Create: `packages/mcp-server/src/index.ts` (minimal placeholder)

**Step 1: Create directory and package.json**

```bash
mkdir -p packages/mcp-server/src
```

`packages/mcp-server/package.json`:
```json
{
  "name": "@streamline-bridge/mcp-server",
  "version": "0.1.0",
  "description": "MCP server for Streamline Bridge developer tooling",
  "type": "module",
  "engines": { "node": ">=20" },
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "dev": "tsx src/index.ts",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.27.1",
    "express": "^4.21.2",
    "ws": "^8.18.0",
    "zod": "^3.25.0"
  },
  "devDependencies": {
    "@types/express": "^5.0.0",
    "@types/node": "^22.0.0",
    "@types/ws": "^8.5.0",
    "tsx": "^4.19.0",
    "typescript": "^5.8.0",
    "vitest": "^3.0.0"
  }
}
```

**Step 2: Create tsconfig.json**

`packages/mcp-server/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src/**/*"]
}
```

**Step 3: Create minimal index.ts**

`packages/mcp-server/src/index.ts`:
```typescript
#!/usr/bin/env node
console.error("Streamline Bridge MCP Server starting...");
```

**Step 4: Install dependencies**

```bash
cd packages/mcp-server && npm install
```

**Step 5: Verify**

```bash
cd packages/mcp-server && npx tsx src/index.ts
```

Expected: prints "Streamline Bridge MCP Server starting..." to stderr, then exits.

**Step 6: Commit**

```bash
git add packages/mcp-server/
git commit -m "feat(mcp): scaffold MCP server package"
```

---

## Task 2: REST Client Bridge

**Files:**
- Create: `packages/mcp-server/src/bridge/rest-client.ts`
- Create: `packages/mcp-server/src/bridge/__tests__/rest-client.test.ts`

The REST client wraps `fetch()` calls to Streamline Bridge. All tools will use this.

**Step 1: Write the failing test**

`packages/mcp-server/src/bridge/__tests__/rest-client.test.ts`:
```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { RestClient } from "../rest-client.js";

describe("RestClient", () => {
  let client: RestClient;

  beforeEach(() => {
    client = new RestClient("http://localhost:8080");
  });

  it("should construct with base URL", () => {
    expect(client).toBeDefined();
  });

  it("should make GET requests", async () => {
    const mockResponse = { state: "idle" };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve(mockResponse),
        text: () => Promise.resolve(JSON.stringify(mockResponse)),
      })
    );

    const result = await client.get("/api/v1/machine/state");
    expect(result).toEqual(mockResponse);
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/machine/state",
      expect.objectContaining({ method: "GET" })
    );

    vi.unstubAllGlobals();
  });

  it("should make POST requests with JSON body", async () => {
    const body = { key: "value" };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ success: true }),
        text: () => Promise.resolve(JSON.stringify({ success: true })),
      })
    );

    const result = await client.post("/api/v1/settings", body);
    expect(result).toEqual({ success: true });
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/settings",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({
          "Content-Type": "application/json",
        }),
        body: JSON.stringify(body),
      })
    );

    vi.unstubAllGlobals();
  });

  it("should make PUT requests with JSON body", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ success: true }),
        text: () => Promise.resolve(JSON.stringify({ success: true })),
      })
    );

    await client.put("/api/v1/devices/connect", { deviceId: "abc" });
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/devices/connect",
      expect.objectContaining({ method: "PUT" })
    );

    vi.unstubAllGlobals();
  });

  it("should make DELETE requests", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ success: true }),
        text: () => Promise.resolve(JSON.stringify({ success: true })),
      })
    );

    await client.delete("/api/v1/shots/123");
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/shots/123",
      expect.objectContaining({ method: "DELETE" })
    );

    vi.unstubAllGlobals();
  });

  it("should throw on non-OK responses", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 404,
        text: () => Promise.resolve("Not Found"),
      })
    );

    await expect(client.get("/api/v1/nonexistent")).rejects.toThrow();

    vi.unstubAllGlobals();
  });

  it("should check if the server is reachable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({}),
        text: () => Promise.resolve("{}"),
      })
    );

    const reachable = await client.isReachable();
    expect(reachable).toBe(true);

    vi.unstubAllGlobals();
  });

  it("should return false when server is unreachable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );

    const reachable = await client.isReachable();
    expect(reachable).toBe(false);

    vi.unstubAllGlobals();
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd packages/mcp-server && npx vitest run src/bridge/__tests__/rest-client.test.ts
```

Expected: FAIL — module not found.

**Step 3: Write implementation**

`packages/mcp-server/src/bridge/rest-client.ts`:
```typescript
export class RestClientError extends Error {
  constructor(
    public status: number,
    public body: string,
    public path: string
  ) {
    super(`HTTP ${status} on ${path}: ${body}`);
    this.name = "RestClientError";
  }
}

export class RestClient {
  constructor(private baseUrl: string) {}

  async get<T = unknown>(path: string, params?: Record<string, string>): Promise<T> {
    const url = this.buildUrl(path, params);
    return this.request<T>(url, { method: "GET" });
  }

  async post<T = unknown>(path: string, body?: unknown): Promise<T> {
    const url = this.buildUrl(path);
    return this.request<T>(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  }

  async put<T = unknown>(path: string, body?: unknown): Promise<T> {
    const url = this.buildUrl(path);
    return this.request<T>(url, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  }

  async delete<T = unknown>(path: string): Promise<T> {
    const url = this.buildUrl(path);
    return this.request<T>(url, { method: "DELETE" });
  }

  async isReachable(): Promise<boolean> {
    try {
      await this.get("/api/v1/machine/state");
      return true;
    } catch {
      return false;
    }
  }

  private buildUrl(path: string, params?: Record<string, string>): string {
    const url = new URL(path, this.baseUrl);
    if (params) {
      for (const [key, value] of Object.entries(params)) {
        url.searchParams.set(key, value);
      }
    }
    return url.toString();
  }

  private async request<T>(url: string, init: RequestInit): Promise<T> {
    const response = await fetch(url, init);
    if (!response.ok) {
      const body = await response.text();
      const path = new URL(url).pathname;
      throw new RestClientError(response.status, body, path);
    }
    const text = await response.text();
    try {
      return JSON.parse(text) as T;
    } catch {
      return text as T;
    }
  }
}
```

**Step 4: Add vitest config**

`packages/mcp-server/vitest.config.ts`:
```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["src/**/__tests__/**/*.test.ts"],
  },
});
```

**Step 5: Run tests to verify they pass**

```bash
cd packages/mcp-server && npx vitest run src/bridge/__tests__/rest-client.test.ts
```

Expected: all PASS.

**Step 6: Commit**

```bash
git add packages/mcp-server/src/bridge/ packages/mcp-server/vitest.config.ts
git commit -m "feat(mcp): add REST client bridge with tests"
```

---

## Task 3: Server Skeleton + stdio Transport

**Files:**
- Create: `packages/mcp-server/src/server.ts`
- Modify: `packages/mcp-server/src/index.ts`

**Step 1: Create server.ts**

`packages/mcp-server/src/server.ts`:
```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { RestClient } from "./bridge/rest-client.js";

export interface ServerConfig {
  host: string;
  port: number;
  projectRoot: string;
  flutterCmd: string;
}

export function createConfig(): ServerConfig {
  return {
    host: process.env.STREAMLINE_HOST ?? "localhost",
    port: parseInt(process.env.STREAMLINE_PORT ?? "8080", 10),
    projectRoot:
      process.env.STREAMLINE_PROJECT_ROOT ??
      findProjectRoot(),
    flutterCmd: process.env.STREAMLINE_FLUTTER_CMD ?? "flutter",
  };
}

export function createServer(config: ServerConfig) {
  const server = new McpServer({
    name: "streamline-bridge",
    version: "0.1.0",
  });

  const restClient = new RestClient(`http://${config.host}:${config.port}`);

  return { server, restClient, config };
}

function findProjectRoot(): string {
  // Walk up from this file to find the repo root (contains pubspec.yaml)
  let dir = new URL(".", import.meta.url).pathname;
  for (let i = 0; i < 10; i++) {
    try {
      const fs = await import("node:fs");
      if (fs.existsSync(`${dir}/pubspec.yaml`)) return dir;
    } catch { /* continue */ }
    dir = dir.replace(/\/[^/]+\/?$/, "");
  }
  return process.cwd();
}
```

Note: `findProjectRoot` is a best-effort helper. The `STREAMLINE_PROJECT_ROOT` env var is the reliable override.

**Step 2: Update index.ts with stdio transport**

`packages/mcp-server/src/index.ts`:
```typescript
#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer, createConfig } from "./server.js";

const config = createConfig();
const { server } = createServer(config);

// TODO: register tools and resources here (Tasks 4-11)

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("Streamline Bridge MCP Server running on stdio");
```

**Step 3: Verify it starts**

```bash
cd packages/mcp-server && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}' | npx tsx src/index.ts
```

Expected: JSON-RPC response with server capabilities on stdout, "running on stdio" on stderr.

**Step 4: Commit**

```bash
git add packages/mcp-server/src/server.ts packages/mcp-server/src/index.ts
git commit -m "feat(mcp): add server skeleton with stdio transport"
```

---

## Task 4: First Proxy Tool — machine_get_state (proves the pattern)

**Files:**
- Create: `packages/mcp-server/src/tools/machine.ts`
- Modify: `packages/mcp-server/src/server.ts` (add tool registration)

This task establishes the proxy tool pattern. All other proxy tools follow the same structure.

**Step 1: Create machine tools**

`packages/mcp-server/src/tools/machine.ts`:
```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerMachineTools(server: McpServer, rest: RestClient) {
  server.registerTool("machine_get_state", {
    title: "Get Machine State",
    description:
      "Get the current machine state snapshot including state, substate, pressure, flow, temperatures, and profile frame.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/machine/state");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_set_state", {
    title: "Set Machine State",
    description:
      "Request a machine state change. Valid states: idle, espresso, steam, hotWater, hotWaterRinse, flush, descale, clean, transport, skipStep.",
    inputSchema: z.object({
      state: z.enum([
        "idle", "espresso", "steam", "hotWater", "hotWaterRinse",
        "flush", "descale", "clean", "transport", "skipStep",
      ]),
    }),
  }, async ({ state }) => {
    const data = await rest.put(`/api/v1/machine/state/${state}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_get_info", {
    title: "Get Machine Info",
    description: "Get device info including hardware version, firmware version, and serial number.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/machine/info");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_get_settings", {
    title: "Get Machine Settings",
    description: "Get current machine settings (USB, fan threshold, flush temp/flow, hot water flow, steam flow, tank temp).",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/machine/settings");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_update_settings", {
    title: "Update Machine Settings",
    description: "Update machine settings. Pass only the fields you want to change.",
    inputSchema: z.object({
      settings: z.record(z.unknown()).describe("Key-value pairs of settings to update"),
    }),
  }, async ({ settings }) => {
    const data = await rest.post("/api/v1/machine/settings", settings);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_load_profile", {
    title: "Load Profile to Machine",
    description: "Load an espresso profile to the machine. Pass the full profile JSON object.",
    inputSchema: z.object({
      profile: z.record(z.unknown()).describe("Full profile JSON object"),
    }),
  }, async ({ profile }) => {
    const data = await rest.post("/api/v1/machine/profile", profile);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_update_shot_settings", {
    title: "Update Shot Settings",
    description: "Update shot settings (temperatures, flow targets).",
    inputSchema: z.object({
      shotSettings: z.record(z.unknown()).describe("Shot settings to update"),
    }),
  }, async ({ shotSettings }) => {
    const data = await rest.post("/api/v1/machine/shotSettings", shotSettings);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 2: Wire up registration in server.ts**

Add to `createServer()` in `server.ts`, after creating `restClient`:

```typescript
import { registerMachineTools } from "./tools/machine.js";

// Inside createServer():
registerMachineTools(server, restClient);
```

**Step 3: Verify tool appears in server capabilities**

```bash
cd packages/mcp-server && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | npx tsx src/index.ts
```

Expected: `tools/list` response includes `machine_get_state` and other machine tools.

**Step 4: Commit**

```bash
git add packages/mcp-server/src/tools/machine.ts packages/mcp-server/src/server.ts
git commit -m "feat(mcp): add machine proxy tools"
```

---

## Task 5: Remaining Proxy Tools

**Files:**
- Create: `packages/mcp-server/src/tools/profiles.ts`
- Create: `packages/mcp-server/src/tools/shots.ts`
- Create: `packages/mcp-server/src/tools/devices.ts`
- Create: `packages/mcp-server/src/tools/scale.ts`
- Create: `packages/mcp-server/src/tools/workflow.ts`
- Create: `packages/mcp-server/src/tools/settings.ts`
- Create: `packages/mcp-server/src/tools/plugins.ts`
- Create: `packages/mcp-server/src/tools/sensors.ts`
- Modify: `packages/mcp-server/src/server.ts` (register all)

All follow the same pattern as Task 4. Each file exports a `register*Tools(server, rest)` function.

**Step 1: Create profiles.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerProfileTools(server: McpServer, rest: RestClient) {
  server.registerTool("profiles_list", {
    title: "List Profiles",
    description: "List espresso profiles. Supports filtering by visibility (visible/hidden/deleted) and parentId.",
    inputSchema: z.object({
      visibility: z.enum(["visible", "hidden", "deleted"]).optional(),
      includeHidden: z.boolean().optional(),
      parentId: z.string().optional(),
    }),
  }, async (params) => {
    const query: Record<string, string> = {};
    if (params.visibility) query.visibility = params.visibility;
    if (params.includeHidden) query.includeHidden = "true";
    if (params.parentId) query.parentId = params.parentId;
    const data = await rest.get("/api/v1/profiles", query);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_get", {
    title: "Get Profile",
    description: "Get a single espresso profile by its ID (format: profile:<20-char-hash>).",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/profiles/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_create", {
    title: "Create Profile",
    description: "Create a new espresso profile. Pass the full profile JSON.",
    inputSchema: z.object({
      profile: z.record(z.unknown()),
    }),
  }, async ({ profile }) => {
    const data = await rest.post("/api/v1/profiles", profile);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_update", {
    title: "Update Profile",
    description: "Update an existing profile by ID.",
    inputSchema: z.object({
      id: z.string(),
      profile: z.record(z.unknown()),
    }),
  }, async ({ id, profile }) => {
    const data = await rest.put(`/api/v1/profiles/${encodeURIComponent(id)}`, profile);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_delete", {
    title: "Delete Profile",
    description: "Delete a profile by ID (soft delete — sets visibility to deleted).",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.delete(`/api/v1/profiles/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_get_lineage", {
    title: "Get Profile Lineage",
    description: "Get the version history (parent-child chain) for a profile.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/profiles/${encodeURIComponent(id)}/lineage`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_import", {
    title: "Import Profiles",
    description: "Bulk import profiles from a JSON array.",
    inputSchema: z.object({
      profiles: z.array(z.record(z.unknown())),
    }),
  }, async ({ profiles }) => {
    const data = await rest.post("/api/v1/profiles/import", profiles);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_export", {
    title: "Export Profiles",
    description: "Export all profiles as JSON.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/profiles/export");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 2: Create shots.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerShotTools(server: McpServer, rest: RestClient) {
  server.registerTool("shots_list", {
    title: "List Shots",
    description: "List shot records. Supports ordering by timestamp (asc/desc) and filtering by IDs.",
    inputSchema: z.object({
      orderBy: z.string().optional(),
      order: z.enum(["asc", "desc"]).optional(),
      ids: z.array(z.string()).optional(),
    }),
  }, async (params) => {
    const query: Record<string, string> = {};
    if (params.orderBy) query.orderBy = params.orderBy;
    if (params.order) query.order = params.order;
    if (params.ids) query.ids = params.ids.join(",");
    const data = await rest.get("/api/v1/shots", query);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("shots_get", {
    title: "Get Shot",
    description: "Get a specific shot record by ID, including measurements and workflow.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/shots/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("shots_get_latest", {
    title: "Get Latest Shot",
    description: "Get the most recent shot record.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/shots/latest");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("shots_update", {
    title: "Update Shot",
    description: "Update a shot record (supports partial updates for metadata, notes, etc.).",
    inputSchema: z.object({
      id: z.string(),
      updates: z.record(z.unknown()),
    }),
  }, async ({ id, updates }) => {
    const data = await rest.put(`/api/v1/shots/${encodeURIComponent(id)}`, updates);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("shots_delete", {
    title: "Delete Shot",
    description: "Delete a shot record by ID.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.delete(`/api/v1/shots/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 3: Create devices.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerDeviceTools(server: McpServer, rest: RestClient) {
  server.registerTool("devices_list", {
    title: "List Devices",
    description: "List all known devices and their connection state.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/devices");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("devices_scan", {
    title: "Scan for Devices",
    description: "Trigger BLE/USB device scan. Set connect=true to auto-connect if one device found. Set quick=true for a short scan.",
    inputSchema: z.object({
      connect: z.boolean().optional(),
      quick: z.boolean().optional(),
    }),
  }, async (params) => {
    const query: Record<string, string> = {};
    if (params.connect) query.connect = "true";
    if (params.quick) query.quick = "true";
    const data = await rest.get("/api/v1/devices/scan", query);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("devices_connect", {
    title: "Connect to Device",
    description: "Connect to a specific device by its device ID.",
    inputSchema: z.object({
      deviceId: z.string(),
    }),
  }, async ({ deviceId }) => {
    const data = await rest.put("/api/v1/devices/connect", { deviceId });
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("devices_disconnect", {
    title: "Disconnect Device",
    description: "Disconnect from the currently connected device.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.put("/api/v1/devices/disconnect");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 4: Create scale.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerScaleTools(server: McpServer, rest: RestClient) {
  server.registerTool("scale_tare", {
    title: "Tare Scale",
    description: "Zero the connected scale.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.put("/api/v1/scale/tare");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("scale_timer_start", {
    title: "Start Scale Timer",
    description: "Start the scale timer.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.put("/api/v1/scale/timer/start");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("scale_timer_stop", {
    title: "Stop Scale Timer",
    description: "Stop the scale timer.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.put("/api/v1/scale/timer/stop");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("scale_timer_reset", {
    title: "Reset Scale Timer",
    description: "Reset the scale timer to zero.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.put("/api/v1/scale/timer/reset");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 5: Create workflow.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerWorkflowTools(server: McpServer, rest: RestClient) {
  server.registerTool("workflow_get", {
    title: "Get Workflow",
    description: "Get the current workflow (profile, dose, grinder, coffee metadata, steam/rinse settings).",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/workflow");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("workflow_update", {
    title: "Update Workflow",
    description: "Update the workflow. Uses deep merge — pass only the fields to change.",
    inputSchema: z.object({
      workflow: z.record(z.unknown()),
    }),
  }, async ({ workflow }) => {
    const data = await rest.put("/api/v1/workflow", workflow);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 6: Create settings.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerSettingsTools(server: McpServer, rest: RestClient) {
  server.registerTool("settings_get", {
    title: "Get Settings",
    description: "Get Streamline Bridge app settings.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/settings");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("settings_update", {
    title: "Update Settings",
    description: "Update app settings (gateway mode, log level, multipliers, etc.).",
    inputSchema: z.object({
      settings: z.record(z.unknown()),
    }),
  }, async ({ settings }) => {
    const data = await rest.post("/api/v1/settings", settings);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 7: Create plugins.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerPluginTools(server: McpServer, rest: RestClient) {
  server.registerTool("plugins_list", {
    title: "List Plugins",
    description: "List all loaded plugins with their manifest info.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/plugins");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("plugins_get_settings", {
    title: "Get Plugin Settings",
    description: "Get settings for a specific plugin by its ID.",
    inputSchema: z.object({ pluginId: z.string() }),
  }, async ({ pluginId }) => {
    const data = await rest.get(`/api/v1/plugins/${encodeURIComponent(pluginId)}/settings`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("plugins_update_settings", {
    title: "Update Plugin Settings",
    description: "Update settings for a specific plugin.",
    inputSchema: z.object({
      pluginId: z.string(),
      settings: z.record(z.unknown()),
    }),
  }, async ({ pluginId, settings }) => {
    const data = await rest.post(
      `/api/v1/plugins/${encodeURIComponent(pluginId)}/settings`,
      settings
    );
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 8: Create sensors.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerSensorTools(server: McpServer, rest: RestClient) {
  server.registerTool("sensors_list", {
    title: "List Sensors",
    description: "List all connected sensors.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/sensors");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("sensors_get", {
    title: "Get Sensor",
    description: "Get info for a specific sensor by ID.",
    inputSchema: z.object({ sensorId: z.string() }),
  }, async ({ sensorId }) => {
    const data = await rest.get(`/api/v1/sensors/${encodeURIComponent(sensorId)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("sensors_execute_command", {
    title: "Execute Sensor Command",
    description: "Execute a command on a specific sensor.",
    inputSchema: z.object({
      sensorId: z.string(),
      command: z.record(z.unknown()),
    }),
  }, async ({ sensorId, command }) => {
    const data = await rest.post(
      `/api/v1/sensors/${encodeURIComponent(sensorId)}/execute`,
      command
    );
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
```

**Step 9: Register all tools in server.ts**

Update `server.ts` imports and `createServer()`:

```typescript
import { registerMachineTools } from "./tools/machine.js";
import { registerProfileTools } from "./tools/profiles.js";
import { registerShotTools } from "./tools/shots.js";
import { registerDeviceTools } from "./tools/devices.js";
import { registerScaleTools } from "./tools/scale.js";
import { registerWorkflowTools } from "./tools/workflow.js";
import { registerSettingsTools } from "./tools/settings.js";
import { registerPluginTools } from "./tools/plugins.js";
import { registerSensorTools } from "./tools/sensors.js";

// Inside createServer(), after creating restClient:
registerMachineTools(server, restClient);
registerProfileTools(server, restClient);
registerShotTools(server, restClient);
registerDeviceTools(server, restClient);
registerScaleTools(server, restClient);
registerWorkflowTools(server, restClient);
registerSettingsTools(server, restClient);
registerPluginTools(server, restClient);
registerSensorTools(server, restClient);
```

**Step 10: Verify tools list**

```bash
cd packages/mcp-server && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | npx tsx src/index.ts
```

Expected: All ~35 tools listed.

**Step 11: Commit**

```bash
git add packages/mcp-server/src/tools/ packages/mcp-server/src/server.ts
git commit -m "feat(mcp): add all REST proxy tools"
```

---

## Task 6: App Lifecycle Manager

**Files:**
- Create: `packages/mcp-server/src/lifecycle/app-manager.ts`
- Create: `packages/mcp-server/src/lifecycle/__tests__/app-manager.test.ts`

**Step 1: Write the failing test**

`packages/mcp-server/src/lifecycle/__tests__/app-manager.test.ts`:
```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { AppManager, AppState } from "../app-manager.js";

describe("AppManager", () => {
  let manager: AppManager;

  beforeEach(() => {
    manager = new AppManager({
      flutterCmd: "echo",
      projectRoot: "/tmp/test",
      host: "localhost",
      port: 8080,
    });
  });

  afterEach(async () => {
    await manager.stop().catch(() => {});
  });

  it("should start with 'stopped' state", () => {
    expect(manager.state).toBe(AppState.Stopped);
  });

  it("should report not running", () => {
    expect(manager.isRunning).toBe(false);
  });

  it("should return empty logs when not started", () => {
    expect(manager.getLogs(10)).toEqual([]);
  });

  it("should support log filtering", () => {
    // Manually push to the log buffer for testing
    manager["logBuffer"].push("line 1: hello");
    manager["logBuffer"].push("line 2: world");
    manager["logBuffer"].push("line 3: hello again");

    const filtered = manager.getLogs(10, "hello");
    expect(filtered).toHaveLength(2);
    expect(filtered[0]).toContain("hello");
    expect(filtered[1]).toContain("hello");
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd packages/mcp-server && npx vitest run src/lifecycle/__tests__/app-manager.test.ts
```

Expected: FAIL — module not found.

**Step 3: Write implementation**

`packages/mcp-server/src/lifecycle/app-manager.ts`:
```typescript
import { spawn, type ChildProcess } from "node:child_process";

export enum AppState {
  Stopped = "stopped",
  Starting = "starting",
  Running = "running",
  Stopping = "stopping",
}

export interface AppManagerConfig {
  flutterCmd: string;
  projectRoot: string;
  host: string;
  port: number;
}

const MAX_LOG_LINES = 1000;
const READY_TIMEOUT_MS = 60_000;
const STOP_TIMEOUT_MS = 5_000;
const POLL_INTERVAL_MS = 1_000;

export class AppManager {
  private process: ChildProcess | null = null;
  private logBuffer: string[] = [];
  private _state: AppState = AppState.Stopped;
  private startParams: { connectDevice?: string; dartDefines?: string[] } = {};

  constructor(private config: AppManagerConfig) {}

  get state(): AppState {
    return this._state;
  }

  get isRunning(): boolean {
    return this._state === AppState.Running;
  }

  get pid(): number | undefined {
    return this.process?.pid;
  }

  async start(options?: {
    connectDevice?: string;
    dartDefines?: string[];
  }): Promise<{ pid: number; connectionStatus?: string }> {
    if (this._state !== AppState.Stopped) {
      throw new Error(`Cannot start: app is ${this._state}`);
    }

    this._state = AppState.Starting;
    this.logBuffer = [];
    this.startParams = options ?? {};

    const args = [
      "run",
      "--dart-define=simulate=1",
      ...(options?.dartDefines?.map((d) => `--dart-define=${d}`) ?? []),
    ];

    this.process = spawn(this.config.flutterCmd, args, {
      cwd: this.config.projectRoot,
      stdio: ["pipe", "pipe", "pipe"],
    });

    // Capture stdout
    this.process.stdout?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString().split("\n").filter(Boolean);
      for (const line of lines) {
        this.pushLog(`[stdout] ${line}`);
      }
    });

    // Capture stderr
    this.process.stderr?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString().split("\n").filter(Boolean);
      for (const line of lines) {
        this.pushLog(`[stderr] ${line}`);
      }
    });

    // Handle unexpected exit
    this.process.on("exit", (code) => {
      this.pushLog(`[lifecycle] Process exited with code ${code}`);
      this._state = AppState.Stopped;
      this.process = null;
    });

    // Wait for HTTP server to be ready
    await this.waitForReady();
    this._state = AppState.Running;

    const result: { pid: number; connectionStatus?: string } = {
      pid: this.process?.pid ?? 0,
    };

    // Auto-connect if requested
    if (options?.connectDevice) {
      result.connectionStatus = await this.connectDevice(options.connectDevice);
    }

    return result;
  }

  async stop(): Promise<void> {
    if (!this.process || this._state === AppState.Stopped) {
      return;
    }

    this._state = AppState.Stopping;

    // Try graceful quit via stdin (flutter run accepts 'q')
    try {
      this.process.stdin?.write("q");
    } catch {
      // stdin may be closed
    }

    // Wait for graceful exit
    const exited = await this.waitForExit(STOP_TIMEOUT_MS);

    if (!exited && this.process) {
      // Force kill
      this.process.kill("SIGKILL");
      await this.waitForExit(2000);
    }

    this._state = AppState.Stopped;
    this.process = null;
  }

  async restart(): Promise<{ pid: number; connectionStatus?: string }> {
    await this.stop();
    return this.start(this.startParams);
  }

  async hotReload(): Promise<string> {
    if (!this.process || this._state !== AppState.Running) {
      throw new Error("App is not running");
    }

    const logLenBefore = this.logBuffer.length;
    this.process.stdin?.write("r");

    // Wait for reload confirmation in stdout
    return this.waitForLogPattern(/reloaded/i, 10_000, logLenBefore);
  }

  async hotRestart(): Promise<string> {
    if (!this.process || this._state !== AppState.Running) {
      throw new Error("App is not running");
    }

    const logLenBefore = this.logBuffer.length;
    this.process.stdin?.write("R");

    // Wait for restart confirmation in stdout
    return this.waitForLogPattern(/restarted/i, 15_000, logLenBefore);
  }

  getLogs(count: number, filter?: string): string[] {
    let logs = this.logBuffer.slice(-count);
    if (filter) {
      logs = logs.filter((line) =>
        line.toLowerCase().includes(filter.toLowerCase())
      );
    }
    return logs;
  }

  private pushLog(line: string) {
    this.logBuffer.push(line);
    if (this.logBuffer.length > MAX_LOG_LINES) {
      this.logBuffer.shift();
    }
  }

  private async waitForReady(): Promise<void> {
    const start = Date.now();
    const url = `http://${this.config.host}:${this.config.port}/api/v1/machine/state`;

    while (Date.now() - start < READY_TIMEOUT_MS) {
      try {
        const res = await fetch(url);
        if (res.ok) {
          this.pushLog("[lifecycle] HTTP server is ready");
          return;
        }
      } catch {
        // Server not ready yet
      }

      // Check if process died
      if (this.process?.exitCode !== null && this.process?.exitCode !== undefined) {
        throw new Error(
          `App process exited with code ${this.process.exitCode} before becoming ready.\n` +
            `Last logs:\n${this.getLogs(20).join("\n")}`
        );
      }

      await sleep(POLL_INTERVAL_MS);
    }

    throw new Error(
      `App did not become ready within ${READY_TIMEOUT_MS / 1000}s.\n` +
        `Last logs:\n${this.getLogs(20).join("\n")}`
    );
  }

  private async connectDevice(deviceName: string): Promise<string> {
    const url = `http://${this.config.host}:${this.config.port}`;

    // Trigger scan with auto-connect
    const scanRes = await fetch(`${url}/api/v1/devices/scan?connect=true`);
    if (!scanRes.ok) {
      return `Scan failed: ${await scanRes.text()}`;
    }

    // Poll for connected device
    const start = Date.now();
    while (Date.now() - start < 15_000) {
      const devRes = await fetch(`${url}/api/v1/devices`);
      if (devRes.ok) {
        const devices = (await devRes.json()) as Array<{
          name: string;
          state: string;
        }>;
        const match = devices.find(
          (d) =>
            d.name.toLowerCase().includes(deviceName.toLowerCase()) &&
            d.state === "connected"
        );
        if (match) {
          return `Connected to ${match.name}`;
        }
      }
      await sleep(POLL_INTERVAL_MS);
    }

    return `Timed out waiting for ${deviceName} to connect`;
  }

  private async waitForExit(timeoutMs: number): Promise<boolean> {
    return new Promise((resolve) => {
      if (!this.process) {
        resolve(true);
        return;
      }

      const timer = setTimeout(() => resolve(false), timeoutMs);
      this.process.on("exit", () => {
        clearTimeout(timer);
        resolve(true);
      });
    });
  }

  private async waitForLogPattern(
    pattern: RegExp,
    timeoutMs: number,
    startIndex: number
  ): Promise<string> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      // Check new log entries since startIndex
      for (let i = startIndex; i < this.logBuffer.length; i++) {
        if (pattern.test(this.logBuffer[i])) {
          return this.logBuffer[i];
        }
      }
      await sleep(200);
    }
    throw new Error(`Timed out waiting for log pattern: ${pattern}`);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
```

**Step 4: Run tests**

```bash
cd packages/mcp-server && npx vitest run src/lifecycle/__tests__/app-manager.test.ts
```

Expected: all PASS.

**Step 5: Commit**

```bash
git add packages/mcp-server/src/lifecycle/
git commit -m "feat(mcp): add app lifecycle manager with log capture"
```

---

## Task 7: Lifecycle Tools

**Files:**
- Create: `packages/mcp-server/src/tools/lifecycle.ts`
- Modify: `packages/mcp-server/src/server.ts` (create AppManager, register lifecycle tools)

**Step 1: Create lifecycle.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { AppManager } from "../lifecycle/app-manager.js";
import { RestClient } from "../bridge/rest-client.js";

export function registerLifecycleTools(
  server: McpServer,
  appManager: AppManager,
  rest: RestClient
) {
  server.registerTool("app_start", {
    title: "Start App",
    description:
      "Start Streamline Bridge in simulate mode. Waits for HTTP server to be ready. " +
      "Optionally connects to a simulated device (e.g. 'MockDe1').",
    inputSchema: z.object({
      connectDevice: z
        .string()
        .optional()
        .describe("Device name to auto-connect (e.g. 'MockDe1')"),
      dartDefines: z
        .array(z.string())
        .optional()
        .describe("Additional --dart-define flags (simulate=1 is always included)"),
    }),
  }, async ({ connectDevice, dartDefines }) => {
    try {
      const result = await appManager.start({ connectDevice, dartDefines });
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            status: "running",
            pid: result.pid,
            connectionStatus: result.connectionStatus ?? "no auto-connect requested",
          }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Failed to start app: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });

  server.registerTool("app_stop", {
    title: "Stop App",
    description: "Stop the running Streamline Bridge instance.",
    inputSchema: z.object({}),
  }, async () => {
    try {
      await appManager.stop();
      return {
        content: [{ type: "text", text: JSON.stringify({ status: "stopped" }) }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Failed to stop app: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });

  server.registerTool("app_restart", {
    title: "Restart App",
    description: "Cold restart — stops and starts the app with the same parameters.",
    inputSchema: z.object({}),
  }, async () => {
    try {
      const result = await appManager.restart();
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            status: "running",
            pid: result.pid,
            connectionStatus: result.connectionStatus ?? "no auto-connect",
          }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Failed to restart app: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });

  server.registerTool("app_status", {
    title: "App Status",
    description: "Check if the app is running, reachable, and what devices are connected.",
    inputSchema: z.object({}),
  }, async () => {
    const reachable = await rest.isReachable();
    const status: Record<string, unknown> = {
      processState: appManager.state,
      pid: appManager.pid ?? null,
      httpReachable: reachable,
    };

    if (reachable) {
      try {
        status.devices = await rest.get("/api/v1/devices");
        status.machineState = await rest.get("/api/v1/machine/state");
      } catch {
        // App might be partially up
      }
    }

    return {
      content: [{ type: "text", text: JSON.stringify(status, null, 2) }],
    };
  });

  server.registerTool("app_logs", {
    title: "App Logs",
    description:
      "Read recent output from the flutter run process (stdout + stderr). " +
      "Useful for seeing build output, errors, print statements, hot reload status.",
    inputSchema: z.object({
      count: z.number().optional().default(50).describe("Number of lines to return (default 50)"),
      filter: z.string().optional().describe("Case-insensitive text filter"),
    }),
  }, async ({ count, filter }) => {
    const logs = appManager.getLogs(count, filter);
    if (logs.length === 0) {
      return {
        content: [{
          type: "text",
          text: appManager.isRunning
            ? "No log lines match the filter."
            : "App is not running. No logs available.",
        }],
      };
    }
    return {
      content: [{ type: "text", text: logs.join("\n") }],
    };
  });

  server.registerTool("app_hot_reload", {
    title: "Hot Reload",
    description:
      "Trigger a Flutter hot reload. Applies code changes without restarting the app (preserves state).",
    inputSchema: z.object({}),
  }, async () => {
    try {
      const result = await appManager.hotReload();
      return {
        content: [{ type: "text", text: `Hot reload successful: ${result}` }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Hot reload failed: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });

  server.registerTool("app_hot_restart", {
    title: "Hot Restart",
    description:
      "Trigger a Flutter hot restart. Applies code changes and resets app state.",
    inputSchema: z.object({}),
  }, async () => {
    try {
      const result = await appManager.hotRestart();
      return {
        content: [{ type: "text", text: `Hot restart successful: ${result}` }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Hot restart failed: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });
}
```

**Step 2: Update server.ts to create AppManager and register lifecycle tools**

Add to `server.ts`:

```typescript
import { AppManager } from "./lifecycle/app-manager.js";
import { registerLifecycleTools } from "./tools/lifecycle.js";

// Inside createServer():
const appManager = new AppManager({
  flutterCmd: config.flutterCmd,
  projectRoot: config.projectRoot,
  host: config.host,
  port: config.port,
});

registerLifecycleTools(server, appManager, restClient);

// Also set up cleanup on process exit
process.on("exit", () => { appManager.stop().catch(() => {}); });
process.on("SIGINT", () => { appManager.stop().then(() => process.exit(0)); });
process.on("SIGTERM", () => { appManager.stop().then(() => process.exit(0)); });

return { server, restClient, appManager, config };
```

**Step 3: Verify**

```bash
cd packages/mcp-server && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | npx tsx src/index.ts
```

Expected: lifecycle tools appear in tools list.

**Step 4: Commit**

```bash
git add packages/mcp-server/src/tools/lifecycle.ts packages/mcp-server/src/server.ts
git commit -m "feat(mcp): add lifecycle tools (start/stop/restart/hot-reload/logs)"
```

---

## Task 8: WebSocket Client Bridge

**Files:**
- Create: `packages/mcp-server/src/bridge/ws-client.ts`

**Step 1: Write implementation**

`packages/mcp-server/src/bridge/ws-client.ts`:
```typescript
import WebSocket from "ws";

export interface Subscription {
  id: string;
  endpoint: string;
  buffer: string[];
  ws: WebSocket;
}

const MAX_BUFFER_SIZE = 100;

export class WsClient {
  private subscriptions = new Map<string, Subscription>();
  private nextId = 1;

  constructor(private baseUrl: string) {}

  subscribe(endpoint: string): string {
    const id = `sub_${this.nextId++}`;
    const wsUrl = this.baseUrl.replace(/^http/, "ws") + endpoint;

    const ws = new WebSocket(wsUrl);
    const sub: Subscription = { id, endpoint, buffer: [], ws };

    ws.on("message", (data: Buffer) => {
      const msg = data.toString();
      sub.buffer.push(msg);
      if (sub.buffer.length > MAX_BUFFER_SIZE) {
        sub.buffer.shift();
      }
    });

    ws.on("error", (err) => {
      sub.buffer.push(JSON.stringify({ error: err.message }));
    });

    ws.on("close", () => {
      sub.buffer.push(JSON.stringify({ event: "connection_closed" }));
    });

    this.subscriptions.set(id, sub);
    return id;
  }

  read(subscriptionId: string, count: number = 10): string[] {
    const sub = this.subscriptions.get(subscriptionId);
    if (!sub) {
      throw new Error(`Subscription ${subscriptionId} not found`);
    }
    // Drain up to `count` messages from the buffer
    return sub.buffer.splice(0, count);
  }

  unsubscribe(subscriptionId: string): void {
    const sub = this.subscriptions.get(subscriptionId);
    if (sub) {
      sub.ws.close();
      this.subscriptions.delete(subscriptionId);
    }
  }

  unsubscribeAll(): void {
    for (const [id] of this.subscriptions) {
      this.unsubscribe(id);
    }
  }

  listSubscriptions(): Array<{ id: string; endpoint: string; buffered: number }> {
    return Array.from(this.subscriptions.values()).map((s) => ({
      id: s.id,
      endpoint: s.endpoint,
      buffered: s.buffer.length,
    }));
  }
}
```

**Step 2: Commit**

```bash
git add packages/mcp-server/src/bridge/ws-client.ts
git commit -m "feat(mcp): add WebSocket client bridge with buffered subscriptions"
```

---

## Task 9: Streaming Tools

**Files:**
- Create: `packages/mcp-server/src/tools/streaming.ts`
- Modify: `packages/mcp-server/src/server.ts` (create WsClient, register streaming tools)

**Step 1: Create streaming.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { WsClient } from "../bridge/ws-client.js";

export function registerStreamingTools(server: McpServer, wsClient: WsClient) {
  server.registerTool("stream_subscribe", {
    title: "Subscribe to Stream",
    description:
      "Open a WebSocket subscription to a real-time data stream. Returns a subscription ID " +
      "for use with stream_read. Available endpoints: " +
      "/ws/v1/machine/snapshot (machine state), " +
      "/ws/v1/scale/snapshot (scale weight/timer), " +
      "/ws/v1/devices (device list changes), " +
      "/ws/v1/sensors/<id>/snapshot (sensor data), " +
      "/ws/v1/display (display state).",
    inputSchema: z.object({
      endpoint: z.string().describe("WebSocket endpoint path, e.g. /ws/v1/machine/snapshot"),
    }),
  }, async ({ endpoint }) => {
    const id = wsClient.subscribe(endpoint);
    return {
      content: [{
        type: "text",
        text: JSON.stringify({ subscriptionId: id, endpoint, status: "subscribed" }, null, 2),
      }],
    };
  });

  server.registerTool("stream_read", {
    title: "Read Stream",
    description:
      "Read buffered messages from a WebSocket subscription. Messages are consumed (removed from buffer) when read.",
    inputSchema: z.object({
      subscriptionId: z.string(),
      count: z.number().optional().default(10).describe("Max messages to read (default 10)"),
    }),
  }, async ({ subscriptionId, count }) => {
    try {
      const messages = wsClient.read(subscriptionId, count);
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ count: messages.length, messages }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Error: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });

  server.registerTool("stream_unsubscribe", {
    title: "Unsubscribe from Stream",
    description: "Close a WebSocket subscription and discard its buffer.",
    inputSchema: z.object({
      subscriptionId: z.string(),
    }),
  }, async ({ subscriptionId }) => {
    wsClient.unsubscribe(subscriptionId);
    return {
      content: [{ type: "text", text: JSON.stringify({ status: "unsubscribed" }) }],
    };
  });
}
```

**Step 2: Update server.ts**

Add to imports and `createServer()`:

```typescript
import { WsClient } from "./bridge/ws-client.js";
import { registerStreamingTools } from "./tools/streaming.js";

// Inside createServer():
const wsClient = new WsClient(`http://${config.host}:${config.port}`);
registerStreamingTools(server, wsClient);

// Add to cleanup:
process.on("exit", () => { wsClient.unsubscribeAll(); });
```

**Step 3: Commit**

```bash
git add packages/mcp-server/src/tools/streaming.ts packages/mcp-server/src/bridge/ws-client.ts packages/mcp-server/src/server.ts
git commit -m "feat(mcp): add WebSocket streaming tools"
```

---

## Task 10: Static Resources

**Files:**
- Create: `packages/mcp-server/src/resources/static-docs.ts`
- Modify: `packages/mcp-server/src/server.ts`

**Step 1: Create static-docs.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

interface DocResource {
  name: string;
  uri: string;
  filePath: string;
  description: string;
  mimeType: string;
}

const DOCS: DocResource[] = [
  {
    name: "REST API Spec",
    uri: "streamline://docs/api/rest",
    filePath: "assets/api/rest_v1.yml",
    description: "Streamline Bridge REST API OpenAPI specification",
    mimeType: "application/x-yaml",
  },
  {
    name: "WebSocket API Spec",
    uri: "streamline://docs/api/websocket",
    filePath: "assets/api/websocket_v1.yml",
    description: "Streamline Bridge WebSocket API specification",
    mimeType: "application/x-yaml",
  },
  {
    name: "Skin Development Guide",
    uri: "streamline://docs/skins",
    filePath: "doc/Skins.md",
    description: "Guide for developing WebUI skins for Streamline Bridge",
    mimeType: "text/markdown",
  },
  {
    name: "Plugin Development Guide",
    uri: "streamline://docs/plugins",
    filePath: "doc/Plugins.md",
    description: "Guide for developing JavaScript plugins for Streamline Bridge",
    mimeType: "text/markdown",
  },
  {
    name: "Profile API Docs",
    uri: "streamline://docs/profiles",
    filePath: "doc/Profiles.md",
    description: "Profile API documentation including content-based hashing and versioning",
    mimeType: "text/markdown",
  },
  {
    name: "Device Management Docs",
    uri: "streamline://docs/devices",
    filePath: "doc/DeviceManagement.md",
    description: "Device discovery and connection management documentation",
    mimeType: "text/markdown",
  },
];

export function registerStaticResources(server: McpServer, projectRoot: string) {
  for (const doc of DOCS) {
    const fullPath = join(projectRoot, doc.filePath);

    server.registerResource(doc.name, doc.uri, {
      description: doc.description,
      mimeType: doc.mimeType,
    }, async (uri) => {
      if (!existsSync(fullPath)) {
        return {
          contents: [{
            uri: uri.href,
            text: `File not found: ${doc.filePath}. Make sure STREAMLINE_PROJECT_ROOT is set correctly.`,
          }],
        };
      }
      const content = readFileSync(fullPath, "utf-8");
      return {
        contents: [{ uri: uri.href, text: content, mimeType: doc.mimeType }],
      };
    });
  }
}
```

**Step 2: Register in server.ts**

```typescript
import { registerStaticResources } from "./resources/static-docs.js";

// Inside createServer():
registerStaticResources(server, config.projectRoot);
```

**Step 3: Verify resources appear**

```bash
cd packages/mcp-server && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}
{"jsonrpc":"2.0","id":2,"method":"resources/list","params":{}}' | npx tsx src/index.ts
```

Expected: all 6 static resources listed.

**Step 4: Commit**

```bash
git add packages/mcp-server/src/resources/static-docs.ts packages/mcp-server/src/server.ts
git commit -m "feat(mcp): add static doc resources (API specs, dev guides)"
```

---

## Task 11: Live Resources

**Files:**
- Create: `packages/mcp-server/src/resources/live-state.ts`
- Modify: `packages/mcp-server/src/server.ts`

**Step 1: Create live-state.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { RestClient } from "../bridge/rest-client.js";

interface LiveResource {
  name: string;
  uri: string;
  endpoint: string;
  description: string;
}

const LIVE_RESOURCES: LiveResource[] = [
  {
    name: "Machine State (Live)",
    uri: "streamline://live/machine/state",
    endpoint: "/api/v1/machine/state",
    description: "Current machine state snapshot (pressure, flow, temperatures, state/substate)",
  },
  {
    name: "Machine Info (Live)",
    uri: "streamline://live/machine/info",
    endpoint: "/api/v1/machine/info",
    description: "Connected machine hardware and firmware info",
  },
  {
    name: "Devices (Live)",
    uri: "streamline://live/devices",
    endpoint: "/api/v1/devices",
    description: "All known devices and their connection states",
  },
  {
    name: "Workflow (Live)",
    uri: "streamline://live/workflow",
    endpoint: "/api/v1/workflow",
    description: "Current workflow configuration (profile, dose, grinder, coffee metadata)",
  },
  {
    name: "Plugins (Live)",
    uri: "streamline://live/plugins",
    endpoint: "/api/v1/plugins",
    description: "Currently loaded plugins and their manifests",
  },
];

export function registerLiveResources(server: McpServer, rest: RestClient) {
  for (const resource of LIVE_RESOURCES) {
    server.registerResource(resource.name, resource.uri, {
      description: resource.description,
      mimeType: "application/json",
    }, async (uri) => {
      try {
        const data = await rest.get(resource.endpoint);
        return {
          contents: [{
            uri: uri.href,
            text: JSON.stringify(data, null, 2),
            mimeType: "application/json",
          }],
        };
      } catch {
        return {
          contents: [{
            uri: uri.href,
            text: JSON.stringify({
              error: "App is not running or not reachable.",
              hint: "Use the app_start tool to launch Streamline Bridge.",
            }, null, 2),
            mimeType: "application/json",
          }],
        };
      }
    });
  }
}
```

**Step 2: Register in server.ts**

```typescript
import { registerLiveResources } from "./resources/live-state.js";

// Inside createServer():
registerLiveResources(server, restClient);
```

**Step 3: Commit**

```bash
git add packages/mcp-server/src/resources/live-state.ts packages/mcp-server/src/server.ts
git commit -m "feat(mcp): add live state resources (machine, devices, workflow, plugins)"
```

---

## Task 12: Streamable HTTP Transport (SSE alternative)

**Files:**
- Modify: `packages/mcp-server/src/index.ts`

**Step 1: Update index.ts to support both transports**

```typescript
#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";
import express from "express";
import { randomUUID } from "node:crypto";
import { createServer, createConfig } from "./server.js";

const args = process.argv.slice(2);
const useHttp = args.includes("--http") || args.includes("--sse");
const httpPort = parseInt(
  args.find((_, i, a) => a[i - 1] === "--http-port" || a[i - 1] === "--sse-port") ?? "3100",
  10
);

const config = createConfig();

if (useHttp) {
  // Streamable HTTP transport
  const app = express();
  app.use(express.json());

  const sessions = new Map<string, StreamableHTTPServerTransport>();

  app.post("/mcp", async (req, res) => {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;

    if (sessionId && sessions.has(sessionId)) {
      const transport = sessions.get(sessionId)!;
      await transport.handleRequest(req, res, req.body);
      return;
    }

    if (!isInitializeRequest(req.body)) {
      res.status(400).json({ error: "Expected initialize request" });
      return;
    }

    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => randomUUID(),
      onsessioninitialized: (id) => {
        sessions.set(id, transport);
      },
    });
    transport.onclose = () => {
      if (transport.sessionId) sessions.delete(transport.sessionId);
    };

    const { server } = createServer(config);
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });

  app.get("/mcp", async (req, res) => {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;
    if (!sessionId || !sessions.has(sessionId)) {
      res.status(400).json({ error: "Unknown session" });
      return;
    }
    await sessions.get(sessionId)!.handleRequest(req, res);
  });

  app.delete("/mcp", async (req, res) => {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;
    if (sessionId && sessions.has(sessionId)) {
      await sessions.get(sessionId)!.close();
      sessions.delete(sessionId);
    }
    res.status(200).end();
  });

  app.listen(httpPort, () => {
    console.error(`Streamline Bridge MCP Server running on http://localhost:${httpPort}/mcp`);
  });
} else {
  // stdio transport (default — for Claude Code)
  const { server } = createServer(config);
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Streamline Bridge MCP Server running on stdio");
}
```

**Step 2: Verify HTTP mode starts**

```bash
cd packages/mcp-server && npx tsx src/index.ts --http --http-port 3100 &
sleep 1
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
kill %1
```

Expected: JSON-RPC response with server capabilities.

**Step 3: Commit**

```bash
git add packages/mcp-server/src/index.ts
git commit -m "feat(mcp): add Streamable HTTP transport (--http flag)"
```

---

## Task 13: MCP Configuration File

**Files:**
- Create: `.mcp.json` (project root)

**Step 1: Create .mcp.json**

`.mcp.json`:
```json
{
  "mcpServers": {
    "streamline-bridge": {
      "command": "npx",
      "args": ["tsx", "packages/mcp-server/src/index.ts"],
      "cwd": "packages/mcp-server",
      "env": {
        "STREAMLINE_HOST": "localhost",
        "STREAMLINE_PORT": "8080"
      }
    }
  }
}
```

**Step 2: Add packages/mcp-server/node_modules to .gitignore**

Check if `.gitignore` exists and add `packages/mcp-server/node_modules/` to it.

**Step 3: Commit**

```bash
git add .mcp.json
git commit -m "feat(mcp): add MCP server configuration for Claude Code"
```

---

## Task 14: Integration Smoke Test

Run the full stack manually to verify everything works end-to-end.

**Step 1: Start Streamline Bridge in simulate mode**

```bash
cd /Users/vid/development/repos/reaprime
flutter run --dart-define=simulate=1
```

**Step 2: In another terminal, test the MCP server against the running instance**

```bash
cd packages/mcp-server

# Test machine_get_state
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"machine_get_state","arguments":{}}}' | npx tsx src/index.ts
```

Expected: machine state JSON in the response.

**Step 3: Test resources**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}
{"jsonrpc":"2.0","id":2,"method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"streamline://docs/plugins"}}' | npx tsx src/index.ts
```

Expected: resource list + Plugins.md content.

**Step 4: Run all unit tests**

```bash
cd packages/mcp-server && npx vitest run
```

Expected: all PASS.

**Step 5: Final commit if any fixes were needed**

```bash
git add -A packages/mcp-server/
git commit -m "fix(mcp): integration test fixes"
```
