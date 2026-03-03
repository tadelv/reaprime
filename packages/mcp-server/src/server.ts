import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { RestClient } from "./bridge/rest-client.js";
import { registerMachineTools } from "./tools/machine.js";

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
