import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerDisplayTools(server: McpServer, rest: RestClient) {
  server.registerTool("display_get", {
    title: "Get Display State",
    description: "Get current display state including brightness, wake lock status, and low battery brightness cap.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/display");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("display_set_brightness", {
    title: "Set Display Brightness",
    description: "Set screen brightness (0-100). May be capped by low battery brightness limit if active.",
    inputSchema: z.object({
      brightness: z.number().int().min(0).max(100).describe("Brightness level (0-100)"),
    }),
  }, async ({ brightness }) => {
    const data = await rest.put("/api/v1/display/brightness", { brightness });
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("display_wakelock_request", {
    title: "Request Wake Lock",
    description: "Request a wake lock to keep the screen on.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.post("/api/v1/display/wakelock", {});
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("display_wakelock_release", {
    title: "Release Wake Lock",
    description: "Release the wake lock, allowing the screen to turn off normally.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.delete("/api/v1/display/wakelock");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
