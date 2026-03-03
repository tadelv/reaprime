#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";
import express from "express";
import { randomUUID } from "node:crypto";
import { createServer, createConfig } from "./server.js";

const args = process.argv.slice(2);
const useHttp = args.includes("--http") || args.includes("--sse");
const httpPort = parseInt(
  args.find((_, i, a) => a[i - 1] === "--http-port" || a[i - 1] === "--sse-port") ?? "3100",
  10
);

const config = createConfig();

if (useHttp) {
  // Streamable HTTP transport
  const app = express();
  app.use(express.json());

  const sessions = new Map<string, StreamableHTTPServerTransport>();

  app.post("/mcp", async (req, res) => {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;

    if (sessionId && sessions.has(sessionId)) {
      const transport = sessions.get(sessionId)!;
      await transport.handleRequest(req, res, req.body);
      return;
    }

    if (!isInitializeRequest(req.body)) {
      res.status(400).json({ error: "Expected initialize request" });
      return;
    }

    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => randomUUID(),
      onsessioninitialized: (id) => {
        sessions.set(id, transport);
      },
    });
    transport.onclose = () => {
      if (transport.sessionId) sessions.delete(transport.sessionId);
    };

    const { server } = createServer(config);
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });

  app.get("/mcp", async (req, res) => {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;
    if (!sessionId || !sessions.has(sessionId)) {
      res.status(400).json({ error: "Unknown session" });
      return;
    }
    await sessions.get(sessionId)!.handleRequest(req, res);
  });

  app.delete("/mcp", async (req, res) => {
    const sessionId = req.headers["mcp-session-id"] as string | undefined;
    if (sessionId && sessions.has(sessionId)) {
      await sessions.get(sessionId)!.close();
      sessions.delete(sessionId);
    }
    res.status(200).end();
  });

  app.listen(httpPort, () => {
    console.error(`Streamline Bridge MCP Server running on http://localhost:${httpPort}/mcp`);
  });
} else {
  // stdio transport (default — for Claude Code)
  const { server } = createServer(config);
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Streamline Bridge MCP Server running on stdio");
}
