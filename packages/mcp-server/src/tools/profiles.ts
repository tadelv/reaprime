import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerProfileTools(server: McpServer, rest: RestClient) {
  server.registerTool("profiles_list", {
    title: "List Profiles",
    description: "List espresso profiles. Supports filtering by visibility (visible/hidden/deleted) and parentId.",
    inputSchema: z.object({
      visibility: z.enum(["visible", "hidden", "deleted"]).optional(),
      includeHidden: z.boolean().optional(),
      parentId: z.string().optional(),
    }),
  }, async (params) => {
    const query: Record<string, string> = {};
    if (params.visibility) query.visibility = params.visibility;
    if (params.includeHidden) query.includeHidden = "true";
    if (params.parentId) query.parentId = params.parentId;
    const data = await rest.get("/api/v1/profiles", query);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_get", {
    title: "Get Profile",
    description: "Get a single espresso profile by its ID (format: profile:<20-char-hash>).",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/profiles/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_create", {
    title: "Create Profile",
    description: "Create a new espresso profile. Pass the full profile JSON.",
    inputSchema: z.object({
      profile: z.record(z.unknown()),
    }),
  }, async ({ profile }) => {
    const data = await rest.post("/api/v1/profiles", profile);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_update", {
    title: "Update Profile",
    description: "Update an existing profile by ID.",
    inputSchema: z.object({
      id: z.string(),
      profile: z.record(z.unknown()),
    }),
  }, async ({ id, profile }) => {
    const data = await rest.put(`/api/v1/profiles/${encodeURIComponent(id)}`, profile);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_delete", {
    title: "Delete Profile",
    description: "Delete a profile by ID (soft delete — sets visibility to deleted).",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.delete(`/api/v1/profiles/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_get_lineage", {
    title: "Get Profile Lineage",
    description: "Get the version history (parent-child chain) for a profile.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/profiles/${encodeURIComponent(id)}/lineage`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_import", {
    title: "Import Profiles",
    description: "Bulk import profiles from a JSON array.",
    inputSchema: z.object({
      profiles: z.array(z.record(z.unknown())),
    }),
  }, async ({ profiles }) => {
    const data = await rest.post("/api/v1/profiles/import", profiles);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("profiles_export", {
    title: "Export Profiles",
    description: "Export all profiles as JSON.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/profiles/export");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
