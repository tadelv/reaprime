import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { AppManager, AppState } from "../app-manager.js";

describe("AppManager", () => {
  let manager: AppManager;

  beforeEach(() => {
    manager = new AppManager({
      flutterCmd: "echo",
      projectRoot: "/tmp/test",
      host: "localhost",
      port: 8080,
    });
  });

  afterEach(async () => {
    await manager.stop().catch(() => {});
  });

  it("should start with 'stopped' state", () => {
    expect(manager.state).toBe(AppState.Stopped);
  });

  it("should report not running", () => {
    expect(manager.isRunning).toBe(false);
  });

  it("should return empty logs when not started", () => {
    expect(manager.getLogs(10)).toEqual([]);
  });

  it("should support log filtering", () => {
    // Manually push to the log buffer for testing
    manager["logBuffer"].push("line 1: hello");
    manager["logBuffer"].push("line 2: world");
    manager["logBuffer"].push("line 3: hello again");

    const filtered = manager.getLogs(10, "hello");
    expect(filtered).toHaveLength(2);
    expect(filtered[0]).toContain("hello");
    expect(filtered[1]).toContain("hello");
  });
});
