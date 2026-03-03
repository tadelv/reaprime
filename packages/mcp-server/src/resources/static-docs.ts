import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

interface DocResource {
  name: string;
  uri: string;
  filePath: string;
  description: string;
  mimeType: string;
}

const DOCS: DocResource[] = [
  {
    name: "REST API Spec",
    uri: "streamline://docs/api/rest",
    filePath: "assets/api/rest_v1.yml",
    description: "Streamline Bridge REST API OpenAPI specification",
    mimeType: "application/x-yaml",
  },
  {
    name: "WebSocket API Spec",
    uri: "streamline://docs/api/websocket",
    filePath: "assets/api/websocket_v1.yml",
    description: "Streamline Bridge WebSocket API specification",
    mimeType: "application/x-yaml",
  },
  {
    name: "Skin Development Guide",
    uri: "streamline://docs/skins",
    filePath: "doc/Skins.md",
    description: "Guide for developing WebUI skins for Streamline Bridge",
    mimeType: "text/markdown",
  },
  {
    name: "Plugin Development Guide",
    uri: "streamline://docs/plugins",
    filePath: "doc/Plugins.md",
    description: "Guide for developing JavaScript plugins for Streamline Bridge",
    mimeType: "text/markdown",
  },
  {
    name: "Profile API Docs",
    uri: "streamline://docs/profiles",
    filePath: "doc/Profiles.md",
    description: "Profile API documentation including content-based hashing and versioning",
    mimeType: "text/markdown",
  },
  {
    name: "Device Management Docs",
    uri: "streamline://docs/devices",
    filePath: "doc/DeviceManagement.md",
    description: "Device discovery and connection management documentation",
    mimeType: "text/markdown",
  },
];

export function registerStaticResources(server: McpServer, projectRoot: string) {
  for (const doc of DOCS) {
    const fullPath = join(projectRoot, doc.filePath);

    server.registerResource(doc.name, doc.uri, {
      description: doc.description,
      mimeType: doc.mimeType,
    }, async (uri) => {
      if (!existsSync(fullPath)) {
        return {
          contents: [{
            uri: uri.href,
            text: `File not found: ${doc.filePath}. Make sure STREAMLINE_PROJECT_ROOT is set correctly.`,
          }],
        };
      }
      const content = readFileSync(fullPath, "utf-8");
      return {
        contents: [{ uri: uri.href, text: content, mimeType: doc.mimeType }],
      };
    });
  }
}
