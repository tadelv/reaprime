import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerInfoTools(server: McpServer, rest: RestClient) {
  server.registerTool("info_get", {
    title: "Get Build Info",
    description: "Get build-time metadata (version, commit, branch, build time, etc.).",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/info");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
