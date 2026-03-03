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
