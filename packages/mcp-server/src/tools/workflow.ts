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
