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
