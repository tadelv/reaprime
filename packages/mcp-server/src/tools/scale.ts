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
