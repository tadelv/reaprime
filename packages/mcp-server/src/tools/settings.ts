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
    description: "Update app settings (gateway mode, log level, multipliers, scale power mode, charging mode, night mode, lowBatteryBrightnessLimit, etc.).",
    inputSchema: z.object({
      settings: z.record(z.unknown()),
    }),
  }, async ({ settings }) => {
    const data = await rest.post("/api/v1/settings", settings);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
