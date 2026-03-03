import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { RestClient } from "./bridge/rest-client.js";
import { registerMachineTools } from "./tools/machine.js";
import { registerProfileTools } from "./tools/profiles.js";
import { registerShotTools } from "./tools/shots.js";
import { registerDeviceTools } from "./tools/devices.js";
import { registerScaleTools } from "./tools/scale.js";
import { registerWorkflowTools } from "./tools/workflow.js";
import { registerSettingsTools } from "./tools/settings.js";
import { registerPluginTools } from "./tools/plugins.js";
import { registerSensorTools } from "./tools/sensors.js";

export interface ServerConfig {
  host: string;
  port: number;
  projectRoot: string;
  flutterCmd: string;
}

export function createConfig(): ServerConfig {
  return {
    host: process.env.STREAMLINE_HOST ?? "localhost",
    port: parseInt(process.env.STREAMLINE_PORT ?? "8080", 10),
    projectRoot:
      process.env.STREAMLINE_PROJECT_ROOT ??
      findProjectRoot(),
    flutterCmd: process.env.STREAMLINE_FLUTTER_CMD ?? "flutter",
  };
}

export function createServer(config: ServerConfig) {
  const server = new McpServer({
    name: "streamline-bridge",
    version: "0.1.0",
  });

  const restClient = new RestClient(`http://${config.host}:${config.port}`);

  registerMachineTools(server, restClient);
  registerProfileTools(server, restClient);
  registerShotTools(server, restClient);
  registerDeviceTools(server, restClient);
  registerScaleTools(server, restClient);
  registerWorkflowTools(server, restClient);
  registerSettingsTools(server, restClient);
  registerPluginTools(server, restClient);
  registerSensorTools(server, restClient);

  return { server, restClient, config };
}

function findProjectRoot(): string {
  const __filename = fileURLToPath(import.meta.url);
  let dir = dirname(__filename);
  for (let i = 0; i < 10; i++) {
    if (existsSync(resolve(dir, "pubspec.yaml"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return process.cwd();
}
