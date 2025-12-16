/* plugin.js
 *
 * Runtime expectations:
 * - global `host` object injected by Flutter
 * - host.log(message)
 * - host.emit(eventName, payload)
 *
 * This file must define a global `Plugin` object.
 */

(function () {
  "use strict";

  // Internal state (private to this plugin instance)
  let state = {
    ticksSeen: 0,
    loadedAt: null,
  };

  function assertHostApi() {
    if (
      typeof host !== "object" ||
      typeof host.log !== "function" ||
      typeof host.emit !== "function"
    ) {
      throw new Error("Host API not available");
    }
  }

  globalThis.Plugin = {
    id: "example.plugin",
    version: "1.0.0",

    /**
     * Called once when the plugin is loaded
     * @param {Object} ctx
     */
    onLoad(ctx) {
      assertHostApi();

      state.loadedAt = Date.now();

      host.log(
        `[example.plugin] Loaded (apiVersion=${ctx.apiVersion})`
      );

      host.emit("plugin.loaded", {
        plugin: this.id,
        version: this.version,
      });
    },

    /**
     * Called when the plugin is unloaded
     */
    onUnload() {
      host.log(
        `[example.plugin] Unloaded after ${state.ticksSeen} ticks`
      );

      state = {
        ticksSeen: 0,
        loadedAt: null,
      };
    },

    /**
     * Called for every event dispatched by the host
     * @param {Object} event
     * @param {string} event.name
     * @param {*} event.payload
     */
    onEvent(event) {
      if (!event || typeof event.name !== "string") {
        return;
      }

      switch (event.name) {
        case "tick":
          handleTick(event.payload);
          break;

        case "shutdown":
          handleShutdown();
          break;

        default:
          // Ignore unknown events (important for forward compatibility)
          break;
      }
    },
  };

  // ─────────────────────────────────────────────
  // Event handlers
  // ─────────────────────────────────────────────

  function handleTick(payload) {
    state.ticksSeen++;

    // Example: only emit every 5 ticks
    if (state.ticksSeen % 5 === 0) {
      host.emit("example.tick.report", {
        ticksSeen: state.ticksSeen,
        uptimeMs: Date.now() - state.loadedAt,
        payload,
      });
    }
  }

  function handleShutdown() {
    host.log("[example.plugin] Shutdown requested");
  }
})();
