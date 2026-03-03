import { describe, it, expect, vi, beforeEach } from "vitest";
import { RestClient } from "../rest-client.js";

describe("RestClient", () => {
  let client: RestClient;

  beforeEach(() => {
    client = new RestClient("http://localhost:8080");
  });

  it("should construct with base URL", () => {
    expect(client).toBeDefined();
  });

  it("should make GET requests", async () => {
    const mockResponse = { state: "idle" };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve(mockResponse),
        text: () => Promise.resolve(JSON.stringify(mockResponse)),
      })
    );

    const result = await client.get("/api/v1/machine/state");
    expect(result).toEqual(mockResponse);
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/machine/state",
      expect.objectContaining({ method: "GET" })
    );

    vi.unstubAllGlobals();
  });

  it("should make POST requests with JSON body", async () => {
    const body = { key: "value" };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ success: true }),
        text: () => Promise.resolve(JSON.stringify({ success: true })),
      })
    );

    const result = await client.post("/api/v1/settings", body);
    expect(result).toEqual({ success: true });
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/settings",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({
          "Content-Type": "application/json",
        }),
        body: JSON.stringify(body),
      })
    );

    vi.unstubAllGlobals();
  });

  it("should make PUT requests with JSON body", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ success: true }),
        text: () => Promise.resolve(JSON.stringify({ success: true })),
      })
    );

    await client.put("/api/v1/devices/connect", { deviceId: "abc" });
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/devices/connect",
      expect.objectContaining({ method: "PUT" })
    );

    vi.unstubAllGlobals();
  });

  it("should make DELETE requests", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ success: true }),
        text: () => Promise.resolve(JSON.stringify({ success: true })),
      })
    );

    await client.delete("/api/v1/shots/123");
    expect(fetch).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/shots/123",
      expect.objectContaining({ method: "DELETE" })
    );

    vi.unstubAllGlobals();
  });

  it("should throw on non-OK responses", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 404,
        text: () => Promise.resolve("Not Found"),
      })
    );

    await expect(client.get("/api/v1/nonexistent")).rejects.toThrow();

    vi.unstubAllGlobals();
  });

  it("should check if the server is reachable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: () => Promise.resolve({}),
        text: () => Promise.resolve("{}"),
      })
    );

    const reachable = await client.isReachable();
    expect(reachable).toBe(true);

    vi.unstubAllGlobals();
  });

  it("should return false when server is unreachable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );

    const reachable = await client.isReachable();
    expect(reachable).toBe(false);

    vi.unstubAllGlobals();
  });
});
