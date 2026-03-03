import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerBeanTools(server: McpServer, rest: RestClient) {
  // --- Beans ---

  server.registerTool("beans_list", {
    title: "List Beans",
    description: "List all coffee beans. Set includeArchived=true to include archived beans.",
    inputSchema: z.object({
      includeArchived: z.boolean().optional(),
    }),
  }, async (params) => {
    const query: Record<string, string> = {};
    if (params.includeArchived) query.includeArchived = "true";
    const data = await rest.get("/api/v1/beans", query);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_get", {
    title: "Get Bean",
    description: "Get a specific coffee bean by ID.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/beans/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_create", {
    title: "Create Bean",
    description: "Create a new coffee bean entry. Requires roaster and name.",
    inputSchema: z.object({
      roaster: z.string().describe("Coffee roaster name"),
      name: z.string().describe("Bean name"),
      species: z.string().optional().describe("e.g. arabica, robusta"),
      decaf: z.boolean().optional(),
      decafProcess: z.string().optional(),
      country: z.string().optional().describe("Country of origin"),
      region: z.string().optional(),
      producer: z.string().optional(),
      variety: z.array(z.string()).optional().describe("Bean varieties"),
      altitude: z.array(z.number()).optional().describe("Altitude range [min, max] in meters"),
      processing: z.string().optional().describe("e.g. washed, natural, honey"),
      notes: z.string().optional(),
      extras: z.record(z.unknown()).optional(),
    }),
  }, async (params) => {
    const data = await rest.post("/api/v1/beans", params);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_update", {
    title: "Update Bean",
    description: "Update an existing coffee bean by ID. Pass only the fields to change.",
    inputSchema: z.object({
      id: z.string(),
      roaster: z.string().optional(),
      name: z.string().optional(),
      species: z.string().optional(),
      decaf: z.boolean().optional(),
      decafProcess: z.string().optional(),
      country: z.string().optional(),
      region: z.string().optional(),
      producer: z.string().optional(),
      variety: z.array(z.string()).optional(),
      altitude: z.array(z.number()).optional(),
      processing: z.string().optional(),
      notes: z.string().optional(),
      archived: z.boolean().optional(),
      extras: z.record(z.unknown()).optional(),
    }),
  }, async ({ id, ...updates }) => {
    const data = await rest.put(`/api/v1/beans/${encodeURIComponent(id)}`, updates);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_delete", {
    title: "Delete Bean",
    description: "Delete a coffee bean by ID.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.delete(`/api/v1/beans/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  // --- Bean Batches ---

  server.registerTool("beans_list_batches", {
    title: "List Bean Batches",
    description: "List batches for a specific bean. A batch represents a specific purchase/roast of a bean.",
    inputSchema: z.object({
      beanId: z.string().describe("Parent bean ID"),
      includeArchived: z.boolean().optional(),
    }),
  }, async ({ beanId, includeArchived }) => {
    const query: Record<string, string> = {};
    if (includeArchived) query.includeArchived = "true";
    const data = await rest.get(`/api/v1/beans/${encodeURIComponent(beanId)}/batches`, query);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_get_batch", {
    title: "Get Bean Batch",
    description: "Get a specific bean batch by ID.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.get(`/api/v1/bean-batches/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_create_batch", {
    title: "Create Bean Batch",
    description: "Create a new batch for a bean. Tracks a specific purchase/roast with weight, dates, and pricing.",
    inputSchema: z.object({
      beanId: z.string().describe("Parent bean ID"),
      roastDate: z.string().optional().describe("ISO 8601 date string"),
      roastLevel: z.string().optional().describe("e.g. light, medium, dark"),
      harvestDate: z.string().optional(),
      qualityScore: z.number().optional().describe("Cupping score"),
      price: z.number().optional(),
      currency: z.string().optional().describe("e.g. USD, EUR"),
      weight: z.number().optional().describe("Total weight in grams"),
      buyDate: z.string().optional().describe("ISO 8601 date string"),
      openDate: z.string().optional().describe("ISO 8601 date string"),
      bestBeforeDate: z.string().optional().describe("ISO 8601 date string"),
      notes: z.string().optional(),
      extras: z.record(z.unknown()).optional(),
    }),
  }, async ({ beanId, ...batch }) => {
    const data = await rest.post(`/api/v1/beans/${encodeURIComponent(beanId)}/batches`, batch);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_update_batch", {
    title: "Update Bean Batch",
    description: "Update an existing bean batch by ID. Pass only the fields to change.",
    inputSchema: z.object({
      id: z.string(),
      roastDate: z.string().optional(),
      roastLevel: z.string().optional(),
      qualityScore: z.number().optional(),
      price: z.number().optional(),
      currency: z.string().optional(),
      weight: z.number().optional(),
      weightRemaining: z.number().optional().describe("Remaining weight in grams"),
      frozen: z.boolean().optional(),
      archived: z.boolean().optional(),
      notes: z.string().optional(),
      extras: z.record(z.unknown()).optional(),
    }),
  }, async ({ id, ...updates }) => {
    const data = await rest.put(`/api/v1/bean-batches/${encodeURIComponent(id)}`, updates);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("beans_delete_batch", {
    title: "Delete Bean Batch",
    description: "Delete a bean batch by ID.",
    inputSchema: z.object({ id: z.string() }),
  }, async ({ id }) => {
    const data = await rest.delete(`/api/v1/bean-batches/${encodeURIComponent(id)}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
