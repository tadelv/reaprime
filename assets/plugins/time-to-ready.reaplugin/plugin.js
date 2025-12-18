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
    tempHistory: [], // Array of {timestamp, temperature}
    maxHistorySize: 20, // Keep last 20 readings for rate calculation
    lastEstimation: null,
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
    id: "time-to-ready.reaplugin",
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
        case "stateUpdate":
          handleStateUpdate(event.payload);
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

  function handleStateUpdate(payload) {
    state.ticksSeen++;

    if (payload['groupTemperature'] == undefined || payload['targetGroupTemperature'] == undefined) {
      host.log(`missing fields in ${payload}`)
      return
    }

    const currentTemp = payload['groupTemperature'];
    const targetTemp = payload['targetGroupTemperature'];
    const now = Date.now();

    // Add current reading to history
    state.tempHistory.push({
      timestamp: now,
      temperature: currentTemp
    });

    // Keep history size limited
    if (state.tempHistory.length > state.maxHistorySize) {
      state.tempHistory.shift(); // Remove oldest entry
    }

    // Calculate remaining time estimation
    const estimation = estimateRemainingTime(
      currentTemp,
      targetTemp,
      state.tempHistory
    );

    // Store last estimation for debugging/monitoring
    state.lastEstimation = estimation;

    // Emit the estimation along with other data
    host.emit(
      "timeToReady",
      estimation
    );
  }

  /**
   * Estimate remaining time to reach target temperature
   * @param {number} currentTemp - Current temperature
   * @param {number} targetTemp - Target temperature
   * @param {Array} history - Array of {timestamp, temperature} objects
   * @returns {Object|null} Estimation object or null if not enough data
   */
  function estimateRemainingTime(currentTemp, targetTemp, history) {
    // Edge cases
    if (currentTemp >= targetTemp) {
      return {
        remainingTimeMs: 0,
        heatingRate: 0,
        status: 'reached',
        message: 'Target temperature reached'
      };
    }

    // Need at least 2 data points to calculate rate
    if (history.length < 2) {
      return {
        remainingTimeMs: null,
        heatingRate: null,
        status: 'insufficient_data',
        message: 'Collecting temperature data...'
      };
    }

    // Calculate heating rate using linear regression on recent data
    const heatingRate = calculateHeatingRate(history);

    if (heatingRate <= 0) {
      return {
        remainingTimeMs: null,
        heatingRate: heatingRate,
        status: 'not_heating',
        message: 'Temperature is stable or decreasing'
      };
    }

    // Calculate remaining time in milliseconds
    const tempDifference = targetTemp - currentTemp;
    const remainingTimeMs = (tempDifference / heatingRate) * 1000; // Convert to ms

    return {
      remainingTimeMs: Math.round(remainingTimeMs),
      heatingRate: heatingRate,
      status: 'heating',
      message: `Estimated ${formatTime(remainingTimeMs)} remaining`,
      formattedTime: formatTime(remainingTimeMs)
    };
  }

  /**
   * Calculate current heating rate (temperature change per second)
   * Uses difference between current and recent past temperature over a fixed time window
   * @param {Array} history - Array of {timestamp, temperature} objects
   * @returns {number} Heating rate in °C per second
   */
  function calculateHeatingRate(history) {
    if (history.length < 2) return 0;

    // Look back 2-3 seconds worth of data
    const currentTime = history[history.length - 1].timestamp;
    const lookbackTime = 2000; // 2 seconds in milliseconds

    // Find a point approximately 2 seconds ago
    let pastIndex = history.length - 2;
    while (pastIndex >= 0 &&
      currentTime - history[pastIndex].timestamp < lookbackTime) {
      pastIndex--;
    }

    // If we found a suitable past point
    if (pastIndex >= 0) {
      const pastPoint = history[pastIndex];
      const currentPoint = history[history.length - 1];

      const timeDiffSec = (currentPoint.timestamp - pastPoint.timestamp) / 1000;

      // Ensure reasonable time difference (at least 0.5 seconds)
      if (timeDiffSec >= 0.5) {
        return (currentPoint.temperature - pastPoint.temperature) / timeDiffSec;
      }
    }

    // Fallback: use last two points
    const lastTwo = history.slice(-2);
    if (lastTwo.length === 2) {
      const timeDiffSec = (lastTwo[1].timestamp - lastTwo[0].timestamp) / 1000;
      if (timeDiffSec > 0) {
        return (lastTwo[1].temperature - lastTwo[0].temperature) / timeDiffSec;
      }
    }

    return 0;
  }

  /**
   * Format milliseconds into human-readable time string
   * @param {number} ms - Time in milliseconds
   * @returns {string} Formatted time string
   */
  function formatTime(ms) {
    if (ms === null || ms === undefined) return '--:--';

    const totalSeconds = Math.round(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;

    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  function handleShutdown() {
    host.log("[example.plugin] Shutdown requested");
  }
})();
