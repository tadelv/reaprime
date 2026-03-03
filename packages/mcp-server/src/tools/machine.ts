import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { RestClient } from "../bridge/rest-client.js";

export function registerMachineTools(server: McpServer, rest: RestClient) {
  server.registerTool("machine_get_state", {
    title: "Get Machine State",
    description:
      "Get the current machine state snapshot including state, substate, pressure, flow, temperatures, and profile frame.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/machine/state");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_set_state", {
    title: "Set Machine State",
    description:
      "Request a machine state change. Valid states: idle, espresso, steam, hotWater, hotWaterRinse, flush, descale, clean, transport, skipStep.",
    inputSchema: z.object({
      state: z.enum([
        "idle", "espresso", "steam", "hotWater", "hotWaterRinse",
        "flush", "descale", "clean", "transport", "skipStep",
      ]),
    }),
  }, async ({ state }) => {
    const data = await rest.put(`/api/v1/machine/state/${state}`);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_get_info", {
    title: "Get Machine Info",
    description: "Get device info including hardware version, firmware version, and serial number.",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/machine/info");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_get_settings", {
    title: "Get Machine Settings",
    description: "Get current machine settings (USB, fan threshold, flush temp/flow, hot water flow, steam flow, tank temp).",
    inputSchema: z.object({}),
  }, async () => {
    const data = await rest.get("/api/v1/machine/settings");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_update_settings", {
    title: "Update Machine Settings",
    description: "Update machine settings. Pass only the fields you want to change.",
    inputSchema: z.object({
      settings: z.record(z.unknown()).describe("Key-value pairs of settings to update"),
    }),
  }, async ({ settings }) => {
    const data = await rest.post("/api/v1/machine/settings", settings);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_load_profile", {
    title: "Load Profile to Machine",
    description: "Load an espresso profile to the machine. Pass the full profile JSON object.",
    inputSchema: z.object({
      profile: z.record(z.unknown()).describe("Full profile JSON object"),
    }),
  }, async ({ profile }) => {
    const data = await rest.post("/api/v1/machine/profile", profile);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });

  server.registerTool("machine_update_shot_settings", {
    title: "Update Shot Settings",
    description: "Update shot settings (temperatures, flow targets).",
    inputSchema: z.object({
      shotSettings: z.record(z.unknown()).describe("Shot settings to update"),
    }),
  }, async ({ shotSettings }) => {
    const data = await rest.post("/api/v1/machine/shotSettings", shotSettings);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  });
}
