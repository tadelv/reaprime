import { spawn, type ChildProcess } from "node:child_process";

export enum AppState {
  Stopped = "stopped",
  Starting = "starting",
  Running = "running",
  Stopping = "stopping",
}

export interface AppManagerConfig {
  flutterCmd: string;
  projectRoot: string;
  host: string;
  port: number;
}

const MAX_LOG_LINES = 1000;
const READY_TIMEOUT_MS = 120_000;
const STOP_TIMEOUT_MS = 5_000;
const POLL_INTERVAL_MS = 1_000;

export class AppManager {
  private process: ChildProcess | null = null;
  private logBuffer: string[] = [];
  private _state: AppState = AppState.Stopped;
  private startParams: { connectDevice?: string; connectScale?: string; platform?: string; dartDefines?: string[] } = {};

  constructor(private config: AppManagerConfig) {}

  get state(): AppState {
    return this._state;
  }

  get isRunning(): boolean {
    return this._state === AppState.Running;
  }

  get pid(): number | undefined {
    return this.process?.pid;
  }

  async start(options?: {
    connectDevice?: string;
    connectScale?: string;
    platform?: string;
    dartDefines?: string[];
  }): Promise<{ pid: number; connectionStatus?: string }> {
    if (this._state !== AppState.Stopped) {
      throw new Error(`Cannot start: app is ${this._state}`);
    }

    this._state = AppState.Starting;
    this.logBuffer = [];
    this.startParams = options ?? {};

    // Build dart-define flags — inject preferred device IDs so the Flutter UI
    // bypasses the device selection screen via its direct-connect fast-path.
    const defines = ["simulate=1"];
    if (options?.connectDevice) {
      defines.push(`preferredMachineId=${options.connectDevice}`);
    }
    if (options?.connectScale) {
      defines.push(`preferredScaleId=${options.connectScale}`);
    }

    const args = [
      "run",
      ...(options?.platform ? ["-d", options.platform] : []),
      ...defines.map((d) => `--dart-define=${d}`),
      ...(options?.dartDefines?.map((d) => `--dart-define=${d}`) ?? []),
    ];

    this.process = spawn(this.config.flutterCmd, args, {
      cwd: this.config.projectRoot,
      stdio: ["pipe", "pipe", "pipe"],
    });

    // Capture stdout
    this.process.stdout?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString().split("\n").filter(Boolean);
      for (const line of lines) {
        this.pushLog(`[stdout] ${line}`);
      }
    });

    // Capture stderr
    this.process.stderr?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString().split("\n").filter(Boolean);
      for (const line of lines) {
        this.pushLog(`[stderr] ${line}`);
      }
    });

    // Handle unexpected exit
    this.process.on("exit", (code) => {
      this.pushLog(`[lifecycle] Process exited with code ${code}`);
      this._state = AppState.Stopped;
      this.process = null;
    });

    // Wait for HTTP server to be ready
    await this.waitForReady();
    this._state = AppState.Running;

    const result: { pid: number; connectionStatus?: string } = {
      pid: this.process?.pid ?? 0,
    };

    // Auto-connect if requested
    if (options?.connectDevice) {
      result.connectionStatus = await this.connectDevice(options.connectDevice);
    }

    return result;
  }

  async stop(): Promise<void> {
    if (!this.process || this._state === AppState.Stopped) {
      return;
    }

    this._state = AppState.Stopping;

    // Try graceful quit via stdin (flutter run accepts 'q')
    try {
      this.process.stdin?.write("q");
    } catch {
      // stdin may be closed
    }

    // Wait for graceful exit
    const exited = await this.waitForExit(STOP_TIMEOUT_MS);

    if (!exited && this.process) {
      // Force kill
      this.process.kill("SIGKILL");
      await this.waitForExit(2000);
    }

    this._state = AppState.Stopped;
    this.process = null;
  }

  async restart(): Promise<{ pid: number; connectionStatus?: string }> {
    await this.stop();
    return this.start(this.startParams);
  }

  async hotReload(): Promise<string> {
    if (!this.process || this._state !== AppState.Running) {
      throw new Error("App is not running");
    }

    const logLenBefore = this.logBuffer.length;
    this.process.stdin?.write("r");

    // Wait for reload confirmation in stdout
    return this.waitForLogPattern(/reloaded/i, 30_000, logLenBefore);
  }

  async hotRestart(): Promise<string> {
    if (!this.process || this._state !== AppState.Running) {
      throw new Error("App is not running");
    }

    const logLenBefore = this.logBuffer.length;
    this.process.stdin?.write("R");

    // Wait for restart confirmation in stdout
    return this.waitForLogPattern(/restarted/i, 30_000, logLenBefore);
  }

  getLogs(count: number, filter?: string): string[] {
    let logs = this.logBuffer.slice(-count);
    if (filter) {
      logs = logs.filter((line) =>
        line.toLowerCase().includes(filter.toLowerCase())
      );
    }
    return logs;
  }

  private pushLog(line: string) {
    this.logBuffer.push(line);
    if (this.logBuffer.length > MAX_LOG_LINES) {
      this.logBuffer.shift();
    }
  }

  private async waitForReady(): Promise<void> {
    const start = Date.now();
    // Use /api/v1/devices — it responds 200 even before a machine is connected,
    // unlike /api/v1/machine/state which returns 500 until a DE1 is connected.
    const url = `http://${this.config.host}:${this.config.port}/api/v1/devices`;

    while (Date.now() - start < READY_TIMEOUT_MS) {
      try {
        const res = await fetch(url);
        if (res.ok) {
          this.pushLog("[lifecycle] HTTP server is ready");
          return;
        }
      } catch {
        // Server not ready yet
      }

      // Check if process died
      if (this.process?.exitCode !== null && this.process?.exitCode !== undefined) {
        throw new Error(
          `App process exited with code ${this.process.exitCode} before becoming ready.\n` +
            `Last logs:\n${this.getLogs(20).join("\n")}`
        );
      }

      await sleep(POLL_INTERVAL_MS);
    }

    throw new Error(
      `App did not become ready within ${READY_TIMEOUT_MS / 1000}s.\n` +
        `Last logs:\n${this.getLogs(20).join("\n")}`
    );
  }

  private async connectDevice(deviceName: string): Promise<string> {
    const url = `http://${this.config.host}:${this.config.port}`;

    // Trigger scan with auto-connect
    const scanRes = await fetch(`${url}/api/v1/devices/scan?connect=true`);
    if (!scanRes.ok) {
      return `Scan failed: ${await scanRes.text()}`;
    }

    // Poll for connected device
    const start = Date.now();
    while (Date.now() - start < 15_000) {
      const devRes = await fetch(`${url}/api/v1/devices`);
      if (devRes.ok) {
        const devices = (await devRes.json()) as Array<{
          name: string;
          state: string;
        }>;
        const match = devices.find(
          (d) =>
            d.name.toLowerCase().includes(deviceName.toLowerCase()) &&
            d.state === "connected"
        );
        if (match) {
          return `Connected to ${match.name}`;
        }
      }
      await sleep(POLL_INTERVAL_MS);
    }

    return `Timed out waiting for ${deviceName} to connect`;
  }

  private async waitForExit(timeoutMs: number): Promise<boolean> {
    return new Promise((resolve) => {
      if (!this.process) {
        resolve(true);
        return;
      }

      const timer = setTimeout(() => resolve(false), timeoutMs);
      this.process.on("exit", () => {
        clearTimeout(timer);
        resolve(true);
      });
    });
  }

  private async waitForLogPattern(
    pattern: RegExp,
    timeoutMs: number,
    startIndex: number
  ): Promise<string> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      // Check new log entries since startIndex
      for (let i = startIndex; i < this.logBuffer.length; i++) {
        if (pattern.test(this.logBuffer[i])) {
          return this.logBuffer[i];
        }
      }
      await sleep(200);
    }
    throw new Error(`Timed out waiting for log pattern: ${pattern}`);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
