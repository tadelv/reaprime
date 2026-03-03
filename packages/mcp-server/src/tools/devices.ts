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
