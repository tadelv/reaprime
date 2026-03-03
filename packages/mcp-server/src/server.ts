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
import { registerBeanTools } from "./tools/beans.js";
import { registerGrinderTools } from "./tools/grinders.js";
import { AppManager } from "./lifecycle/app-manager.js";
import { registerLifecycleTools } from "./tools/lifecycle.js";
import { WsClient } from "./bridge/ws-client.js";
import { registerStreamingTools } from "./tools/streaming.js";
import { registerStaticResources } from "./resources/static-docs.js";
import { registerLiveResources } from "./resources/live-state.js";

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
    flutterCmd: process.env.STREAMLINE_FLUTTER_CMD ?? "./flutter_with_commit.sh",
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
  registerBeanTools(server, restClient);
  registerGrinderTools(server, restClient);

  const appManager = new AppManager({
    flutterCmd: config.flutterCmd,
    projectRoot: config.projectRoot,
    host: config.host,
    port: config.port,
  });
  registerLifecycleTools(server, appManager, restClient);

  const wsClient = new WsClient(`http://${config.host}:${config.port}`);
  registerStreamingTools(server, wsClient);

  // Resources
  registerStaticResources(server, config.projectRoot);
  registerLiveResources(server, restClient);

  // Cleanup on process exit
  process.on("exit", () => { appManager.stop().catch(() => {}); wsClient.unsubscribeAll(); });
  process.on("SIGINT", () => { wsClient.unsubscribeAll(); appManager.stop().then(() => process.exit(0)); });
  process.on("SIGTERM", () => { wsClient.unsubscribeAll(); appManager.stop().then(() => process.exit(0)); });

  return { server, restClient, appManager, wsClient, config };
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
