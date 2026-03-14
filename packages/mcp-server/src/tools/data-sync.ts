import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerDataSyncTools(server: McpServer, rest: RestClient) {
  server.registerTool("data_sync", {
    title: "Sync Data",
    description:
      "Synchronize data (shots, profiles, beans, grinders, workflow, settings) between two Streamline Bridge instances. " +
      "Pull imports from the target, push exports to the target, two_way does both.",
    inputSchema: z.object({
      target: z
        .string()
        .describe("Base URL of the target Bridge instance (e.g. 'http://de1tablet.home:8080')"),
      mode: z
        .enum(["pull", "push", "two_way"])
        .describe("Sync direction: pull (import from target), push (export to target), two_way (both)"),
      onConflict: z
        .enum(["skip", "overwrite"])
        .optional()
        .default("skip")
        .describe("Conflict resolution strategy (default: skip)"),
      sections: z
        .array(z.string())
        .optional()
        .describe("Optional list of sections to sync (e.g. ['shots', 'profiles', 'beans'])"),
    }),
  }, async ({ target, mode, onConflict, sections }) => {
    const body: Record<string, unknown> = { target, mode, onConflict };
    if (sections) {
      body.sections = sections;
    }
    const data = await rest.post("/api/v1/data/sync", body);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
