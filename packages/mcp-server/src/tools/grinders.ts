import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerGrinderTools(server: McpServer, rest: RestClient) {
  server.registerTool("grinders_list", {
    title: "List Grinders",
    description: "List all grinders. Set includeArchived=true to include archived grinders.",
    inputSchema: z.object({
      includeArchived: z.boolean().optional(),
    }),
  }, async (params) => {
    const query: Record<string, string> = {};
    if (params.includeArchived) query.includeArchived = "true";
    const data = await rest.get("/api/v1/grinders", query);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("grinders_get", {
    title: "Get Grinder",
    description: "Get a specific grinder by ID.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/grinders/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("grinders_create", {
    title: "Create Grinder",
    description: "Create a new grinder entry. Requires model name. Supports numeric settings (with step sizes) or preset settings (with named values).",
    inputSchema: z.object({
      model: z.string().describe("Grinder model name"),
      burrs: z.string().optional().describe("Burr set name"),
      burrSize: z.number().optional().describe("Burr diameter in mm"),
      burrType: z.string().optional().describe("e.g. flat, conical"),
      notes: z.string().optional(),
      settingType: z.enum(["numeric", "preset"]).optional().describe("numeric for continuous settings, preset for named positions"),
      settingValues: z.array(z.string()).optional().describe("Named setting positions (for preset type)"),
      settingSmallStep: z.number().optional().describe("Fine grind adjustment step (for numeric type)"),
      settingBigStep: z.number().optional().describe("Coarse grind adjustment step (for numeric type)"),
      rpmSmallStep: z.number().optional().describe("Fine RPM adjustment step"),
      rpmBigStep: z.number().optional().describe("Coarse RPM adjustment step"),
      extras: z.record(z.unknown()).optional(),
    }),
  }, async (params) => {
    const data = await rest.post("/api/v1/grinders", params);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("grinders_update", {
    title: "Update Grinder",
    description: "Update an existing grinder by ID. Pass only the fields to change.",
    inputSchema: z.object({
      id: z.string(),
      model: z.string().optional(),
      burrs: z.string().optional(),
      burrSize: z.number().optional(),
      burrType: z.string().optional(),
      notes: z.string().optional(),
      archived: z.boolean().optional(),
      settingType: z.enum(["numeric", "preset"]).optional(),
      settingValues: z.array(z.string()).optional(),
      settingSmallStep: z.number().optional(),
      settingBigStep: z.number().optional(),
      rpmSmallStep: z.number().optional(),
      rpmBigStep: z.number().optional(),
      extras: z.record(z.unknown()).optional(),
    }),
  }, async ({ id, ...updates }) => {
    const data = await rest.put(`/api/v1/grinders/${encodeURIComponent(id)}`, updates);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("grinders_delete", {
    title: "Delete Grinder",
    description: "Delete a grinder by ID.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.delete(`/api/v1/grinders/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
