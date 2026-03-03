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
