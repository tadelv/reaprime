/* time-to-ready.reaplugin
 *
 * Contract:
 * - This file must define a function named 'createPlugin'
 * - Factory function receives 'host' object as parameter
 * - Returns a plugin object with onLoad, onUnload, onEvent methods
 */

// Standard factory function - receives host object from PluginManager
function createPlugin(host) {
  "use strict";

  // Internal state (private to this plugin instance)
  let state = {
    ticksSeen: 0,
    loadedAt: null,
    tempHistory: [], // Array of {timestamp, temperature}
    maxHistorySize: 20, // Keep last 20 readings for rate calculation
    lastEstimation: null,
  };

  function log(msg) {
    host.log(`[time-to-ready] ${msg}`);
  }

  function handleStateUpdate(payload) {
    state.ticksSeen++;

    if (payload['groupTemperature'] == undefined || payload['targetGroupTemperature'] == undefined) {
      log(`missing fields in ${JSON.stringify(payload)}`)
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
      {
        ...estimation,
        currentTemp: currentTemp,
        targetTemp: targetTemp,
        timestamp: now
      }
    );
  }

  function handleStorageRead(payload) {
    if (payload.key === "lastEstimation") {
      log(`Loaded last estimation from storage: ${JSON.stringify(payload.value)}`);
      // You could use this to restore state
      if (payload.value) {
        state.lastEstimation = payload.value;
      }
    }
  }

  function handleStorageWrite(payload) {
    log(`Saved to storage: ${JSON.stringify(payload)}`);
  }

  function handleShutdown() {
    log("Shutdown requested");
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

  // Return the plugin object
  return {
    id: "time-to-ready.reaplugin",
    version: "1.0.0",

    onLoad(settings) {
      state.loadedAt = Date.now();

      log(`Loaded with settings: ${JSON.stringify(settings)}`);

      host.emit("plugin.loaded", {
        plugin: this.id,
        version: this.version,
        settings: settings
      });

      // Example: Load saved state from storage
      host.storage({
        type: "read",
        key: "lastEstimation",
        namespace: "time-to-ready.reaplugin"
      });
    },

    onUnload() {
      log(`Unloaded after ${state.ticksSeen} ticks`);

      // Save last estimation to storage
      if (state.lastEstimation) {
        host.storage({
          type: "write",
          key: "lastEstimation",
          namespace: "time-to-ready.reaplugin",
          data: state.lastEstimation
        });
      }

      state = {
        ticksSeen: 0,
        loadedAt: null,
      };
    },

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

        case "storageRead":
          handleStorageRead(event.payload);
          break;

        case "storageWrite":
          handleStorageWrite(event.payload);
          break;

        default:
          // Ignore unknown events (important for forward compatibility)
          break;
      }
    },
  };
}
