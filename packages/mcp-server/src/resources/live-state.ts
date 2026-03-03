import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { RestClient } from "../bridge/rest-client.js";

interface LiveResource {
  name: string;
  uri: string;
  endpoint: string;
  description: string;
}

const LIVE_RESOURCES: LiveResource[] = [
  {
    name: "Machine State (Live)",
    uri: "streamline://live/machine/state",
    endpoint: "/api/v1/machine/state",
    description: "Current machine state snapshot (pressure, flow, temperatures, state/substate)",
  },
  {
    name: "Machine Info (Live)",
    uri: "streamline://live/machine/info",
    endpoint: "/api/v1/machine/info",
    description: "Connected machine hardware and firmware info",
  },
  {
    name: "Devices (Live)",
    uri: "streamline://live/devices",
    endpoint: "/api/v1/devices",
    description: "All known devices and their connection states",
  },
  {
    name: "Workflow (Live)",
    uri: "streamline://live/workflow",
    endpoint: "/api/v1/workflow",
    description: "Current workflow configuration (profile, dose, grinder, coffee metadata)",
  },
  {
    name: "Plugins (Live)",
    uri: "streamline://live/plugins",
    endpoint: "/api/v1/plugins",
    description: "Currently loaded plugins and their manifests",
  },
];

export function registerLiveResources(server: McpServer, rest: RestClient) {
  for (const resource of LIVE_RESOURCES) {
    server.registerResource(resource.name, resource.uri, {
      description: resource.description,
      mimeType: "application/json",
    }, async (uri) => {
      try {
        const data = await rest.get(resource.endpoint);
        return {
          contents: [{
            uri: uri.href,
            text: JSON.stringify(data, null, 2),
            mimeType: "application/json",
          }],
        };
      } catch {
        return {
          contents: [{
            uri: uri.href,
            text: JSON.stringify({
              error: "App is not running or not reachable.",
              hint: "Use the app_start tool to launch Streamline Bridge.",
            }, null, 2),
            mimeType: "application/json",
          }],
        };
      }
    });
  }
}
