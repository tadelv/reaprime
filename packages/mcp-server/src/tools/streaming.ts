import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { WsClient } from "../bridge/ws-client.js";

export function registerStreamingTools(server: McpServer, wsClient: WsClient) {
  server.registerTool("stream_subscribe", {
    title: "Subscribe to Stream",
    description:
      "Open a WebSocket subscription to a real-time data stream. Returns a subscription ID " +
      "for use with stream_read. Available endpoints: " +
      "/ws/v1/machine/snapshot (machine state), " +
      "/ws/v1/scale/snapshot (scale weight/timer), " +
      "/ws/v1/devices (device list changes), " +
      "/ws/v1/sensors/<id>/snapshot (sensor data), " +
      "/ws/v1/display (display state).",
    inputSchema: z.object({
      endpoint: z.string().describe("WebSocket endpoint path, e.g. /ws/v1/machine/snapshot"),
    }),
  }, async ({ endpoint }) => {
    const id = wsClient.subscribe(endpoint);
    return {
      content: [{
        type: "text",
        text: JSON.stringify({ subscriptionId: id, endpoint, status: "subscribed" }, null, 2),
      }],
    };
  });

  server.registerTool("stream_read", {
    title: "Read Stream",
    description:
      "Read buffered messages from a WebSocket subscription. Messages are consumed (removed from buffer) when read.",
    inputSchema: z.object({
      subscriptionId: z.string(),
      count: z.number().optional().default(10).describe("Max messages to read (default 10)"),
    }),
  }, async ({ subscriptionId, count }) => {
    try {
      const messages = wsClient.read(subscriptionId, count);
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ count: messages.length, messages }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Error: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });

  server.registerTool("stream_send", {
    title: "Send to Stream",
    description:
      "Send a JSON message through an existing WebSocket subscription. " +
      "Useful for bidirectional WebSocket endpoints like /ws/v1/devices which accepts commands: " +
      '{"command": "scan", "connect": true} to scan and auto-connect, ' +
      '{"command": "connect", "deviceId": "..."} to connect a specific device, ' +
      '{"command": "disconnect", "deviceId": "..."} to disconnect a device.',
    inputSchema: z.object({
      subscriptionId: z.string().describe("Subscription ID from stream_subscribe"),
      message: z.record(z.unknown()).describe("JSON message to send"),
    }),
  }, async ({ subscriptionId, message }) => {
    try {
      wsClient.send(subscriptionId, JSON.stringify(message));
      return {
        content: [{
          type: "text",
          text: JSON.stringify({ status: "sent", subscriptionId }, null, 2),
        }],
      };
    } catch (err) {
      return {
        content: [{
          type: "text",
          text: `Error: ${err instanceof Error ? err.message : String(err)}`,
        }],
        isError: true,
      };
    }
  });

  server.registerTool("stream_unsubscribe", {
    title: "Unsubscribe from Stream",
    description: "Close a WebSocket subscription and discard its buffer.",
    inputSchema: z.object({
      subscriptionId: z.string(),
    }),
  }, async ({ subscriptionId }) => {
    wsClient.unsubscribe(subscriptionId);
    return {
      content: [{ type: "text", text: JSON.stringify({ status: "unsubscribed" }) }],
    };
  });
}
