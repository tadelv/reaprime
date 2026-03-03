#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer, createConfig } from "./server.js";

const config = createConfig();
const { server } = createServer(config);

// TODO: register tools and resources here (Tasks 4-11)

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("Streamline Bridge MCP Server running on stdio");
