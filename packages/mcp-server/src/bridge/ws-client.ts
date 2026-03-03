import WebSocket from "ws";

export interface Subscription {
  id: string;
  endpoint: string;
  buffer: string[];
  ws: WebSocket;
}

const MAX_BUFFER_SIZE = 100;

export class WsClient {
  private subscriptions = new Map<string, Subscription>();
  private nextId = 1;

  constructor(private baseUrl: string) {}

  subscribe(endpoint: string): string {
    const id = `sub_${this.nextId++}`;
    const wsUrl = this.baseUrl.replace(/^http/, "ws") + endpoint;

    const ws = new WebSocket(wsUrl);
    const sub: Subscription = { id, endpoint, buffer: [], ws };

    ws.on("message", (data: Buffer) => {
      const msg = data.toString();
      sub.buffer.push(msg);
      if (sub.buffer.length > MAX_BUFFER_SIZE) {
        sub.buffer.shift();
      }
    });

    ws.on("error", (err) => {
      sub.buffer.push(JSON.stringify({ error: err.message }));
    });

    ws.on("close", () => {
      sub.buffer.push(JSON.stringify({ event: "connection_closed" }));
    });

    this.subscriptions.set(id, sub);
    return id;
  }

  read(subscriptionId: string, count: number = 10): string[] {
    const sub = this.subscriptions.get(subscriptionId);
    if (!sub) {
      throw new Error(`Subscription ${subscriptionId} not found`);
    }
    // Drain up to `count` messages from the buffer
    return sub.buffer.splice(0, count);
  }

  unsubscribe(subscriptionId: string): void {
    const sub = this.subscriptions.get(subscriptionId);
    if (sub) {
      sub.ws.close();
      this.subscriptions.delete(subscriptionId);
    }
  }

  unsubscribeAll(): void {
    for (const [id] of this.subscriptions) {
      this.unsubscribe(id);
    }
  }

  listSubscriptions(): Array<{ id: string; endpoint: string; buffered: number }> {
    return Array.from(this.subscriptions.values()).map((s) => ({
      id: s.id,
      endpoint: s.endpoint,
      buffered: s.buffer.length,
    }));
  }
}
