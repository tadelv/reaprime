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
      connectScale: z
        .string()
        .optional()
        .describe("Scale name to auto-connect (e.g. 'MockScale')"),
      platform: z
        .string()
        .optional()
        .describe("Target platform/device (-d flag, e.g. 'macos', 'linux', 'chrome', or a device ID)"),
      dartDefines: z
        .array(z.string())
        .optional()
        .describe("Additional --dart-define flags (simulate=1 is always included)"),
    }),
  }, async ({ connectDevice, connectScale, platform, dartDefines }) => {
    try {
      const result = await appManager.start({ connectDevice, connectScale, platform, dartDefines });
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
