/* visualizer.reaplugin
 *
 * Contract:
 * - This file must define a function named 'createPlugin'
 * - Factory function receives 'host' object as parameter
 * - Returns a plugin object with onLoad, onUnload, onEvent methods
 */

// Standard factory function - receives host object from PluginManager
function createPlugin(host) {
  "use strict";

  const CHECK_INTERVAL_MS = 10000;
  const VISUALIZER_API_URL = "https://visualizer.coffee/api";

  let timeoutId = null;
  let isChecking = false;
  let isRunning = false;

  const state = {
    lastUploadedShot: null,
    lastVisualizerId: null,
    lastCheckedShotId: null,
    username: null,
    password: null,
    ticks: 0,
  };

  function log(msg) {
    host.log(`[visualizer] ${msg}`);
  }

  async function fetchLatestShot() {
    try {
      const res = await fetch("http://localhost:8080/api/v1/shots/latest");
      if (!res.ok) {
        log(`Failed to fetch latest shot: ${res.status} ${res.statusText}`);
        return null;
      }
      return await res.json();
    } catch (e) {
      log(`Error fetching latest shot: ${e.message}`);
      return null;
    }
  }

  function getAuthHeader() {
    if (!state.username || !state.password) {
      throw new Error("Username or password not configured");
    }
    return "Basic " + btoa(state.username + ":" + state.password);
  }

  function buildMultipartBody({ fieldName, filename, contentType, data }) {
    const boundary = "----reaBoundary" + Math.random().toString(16).slice(2);

    const body =
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="${fieldName}"; filename="${filename}"\r\n` +
      `Content-Type: ${contentType}\r\n\r\n` +
      data + `\r\n` +
      `--${boundary}--\r\n`;

    return {
      body,
      boundary,
    };
  }
  /// FormData and Blob not available in Flutter_JS
  async function uploadShot(shotData, onRetry) {
    const retries = 3;
    const delay = 2000;
    const url = `${VISUALIZER_API_URL}/shots/upload`;

    const payload = buildMultipartBody({
      fieldName: "file",
      filename: "file.shot",
      contentType: "application/json",
      data: JSON.stringify(shotData),
    });

    for (let i = 0; i < retries; i++) {
      try {
        const authHeader = getAuthHeader();
        const response = await fetch(url, {
          method: "POST",
          headers: {
            "Authorization": authHeader,
            "Content-Type": `multipart/form-data; boundary=${payload.boundary}`,
          },
          body: payload.body,
        });

        if (response.ok) {
          return await response.json();
        }

        const errorText = await response.text();

        // 4xx → fail fast
        if (response.status >= 400 && response.status < 500) {
          throw new Error(`HTTP ${response.status}: ${errorText}`);
        }

        throw new Error(`HTTP ${response.status}: ${errorText}`);

      } catch (error) {
        console.error(`Upload attempt ${i + 1}/${retries} failed:`, error.message, error.stack);

        if (i === retries - 1) {
          throw error;
        }

        if (onRetry) {
          onRetry(i + 1, retries);
        }

        await new Promise(res => setTimeout(res, delay));
      }
    }
  }

  function convertReaToVisualizerFormat(reaShot) {
    if (!reaShot || !reaShot.measurements || reaShot.measurements.length === 0) {
      throw new Error("Invalid or empty REA shot data for conversion.");
    }

    const firstTimestamp = new Date(reaShot.measurements[0].machine.timestamp).getTime();
    const lastMeasurement = reaShot.measurements[reaShot.measurements.length - 1];
    const lastTimestamp = new Date(lastMeasurement.machine.timestamp).getTime();
    let totalWaterDispensed = 0;

    const visualizerShot = {
      // start_time: reaShot.measurements[0].machine.timestamp,
      timestamp: Math.floor(firstTimestamp / 1000),
      duration: (lastTimestamp - firstTimestamp) / 1000,
      elapsed: [],
      pressure: { pressure: [], goal: [] },
      flow: { flow: [], goal: [], by_weight: [] },
      temperature: { mix: [], basket: [], goal: [] },
      totals: {},
      state_change: [],
      profile: reaShot.workflow.profile,
      app: {
        data: {
          settings: {
            bean_weight: String(reaShot.workflow.doseData.doseIn),
            drink_weight: String(lastMeasurement.scale?.weight ?? 0),
            target_weight: String(reaShot.workflow.profile.target_weight),
            grinder_model: reaShot.workflow.grinderData?.model,
            grinder_setting: reaShot.workflow.grinderData?.setting,
            bean_brand: reaShot.workflow.coffeeData?.roaster,
            bean_type: reaShot.workflow.coffeeData?.name,
          }
        }
      },
    };

    for (let i = 0; i < reaShot.measurements.length; i++) {
      const m = reaShot.measurements[i];
      const machine = m.machine;
      const scale = m.scale;

      const currentTimestamp = new Date(machine.timestamp).getTime();
      const elapsed = (currentTimestamp - firstTimestamp) / 1000;
      visualizerShot.elapsed.push(elapsed);

      visualizerShot.pressure.pressure.push(machine.pressure);
      visualizerShot.pressure.goal.push(machine.targetPressure);
      visualizerShot.flow.flow.push(machine.flow);
      visualizerShot.flow.goal.push(machine.targetFlow);
      visualizerShot.flow.by_weight.push(scale?.weightFlow ?? 0);
      visualizerShot.temperature.mix.push(machine.mixTemperature);
      visualizerShot.temperature.basket.push(machine.groupTemperature);
      visualizerShot.temperature.goal.push(machine.targetMixTemperature);
      visualizerShot.state_change.push(machine.state.substate);

      if (i > 0) {
        const prevMachine = reaShot.measurements[i - 1].machine;
        const timeDelta = elapsed - visualizerShot.elapsed[i - 1];
        totalWaterDispensed += prevMachine.flow * timeDelta;
      }
    }

    visualizerShot.totals.water_dispensed = totalWaterDispensed;

    return visualizerShot;
  }

  async function checkForNewShots() {
    if (isChecking || !isRunning) return;
    isChecking = true;

    try {
      log("Checking for new shots...");
      const shot = await fetchLatestShot();
      if (!shot || !shot.id) {
        log("No shot data available");
        return;
      }

      if (shot.id === state.lastCheckedShotId) {
        log(`Shot ${shot.id} already checked`);
        return;
      }

      state.lastCheckedShotId = shot.id;

      // Check if credentials are configured
      if (!state.username || !state.password) {
        log("Username/password not configured. Skipping upload.");
        return;
      }

      const result = await uploadShot(convertReaToVisualizerFormat(shot), null);
      state.lastUploadedShot = shot.id;
      state.lastVisualizerId = result.id;

      // Save to storage using new API
      host.storage({
        type: "write",
        key: "lastUploadedShot",
        namespace: "visualizer.reaplugin",
        data: shot.id
      });

      host.storage({
        type: "write",
        key: "lastVisualizerId",
        namespace: "visualizer.reaplugin",
        data: result.id
      });

      log(`Uploaded ${shot.id} → ${result.id}`);

      // Emit success event
      host.emit("shotUploaded", {
        shotId: shot.id,
        visualizerId: result.id,
        timestamp: Date.now()
      });
    } catch (e) {
      log(`Error: ${e.message}`);
      host.emit("uploadError", {
        error: e.message,
        timestamp: Date.now()
      });
    } finally {
      isChecking = false;
      scheduleNextCheck();
    }
  }

  function scheduleNextCheck() {
    if (!isRunning) return;

    // Clear any existing timeout
    // if (timeoutId !== null) {
    //   clearTimeout(timeoutId);
    // }

    // Schedule next check
    timeoutId = setTimeout(() => {
      checkForNewShots();
    }, CHECK_INTERVAL_MS);

    log(`Next check scheduled in ${CHECK_INTERVAL_MS / 1000} seconds`);
  }

  function start() {
    if (isRunning) return;
    isRunning = true;
    log("Started periodic checking");
    scheduleNextCheck();
  }

  function stop() {
    isRunning = false;
    if (timeoutId !== null) {
      clearTimeout(timeoutId);
      timeoutId = null;
    }
    log("Stopped periodic checking");
  }

  function handleStorageRead(payload) {
    if (payload.key === "lastUploadedShot") {
      state.lastUploadedShot = payload.value;
      log(`Loaded lastUploadedShot from storage: ${payload.value}`);
    } else if (payload.key === "lastVisualizerId") {
      state.lastVisualizerId = payload.value;
      log(`Loaded lastVisualizerId from storage: ${payload.value}`);
    }
  }

  function handleStorageWrite(payload) {
    log(`Saved to storage: ${payload.key} = ${payload.value}`);
  }

  // Return the plugin object
  return {
    id: "visualizer.reaplugin",
    version: "1.0.0",

    onLoad(settings) {
      state.username = settings.Username;
      state.password = settings.Password;

      log(`Loaded with username: ${state.username ? 'configured' : 'not configured'}`);

      // Load saved state from storage
      host.storage({
        type: "read",
        key: "lastUploadedShot",
        namespace: "visualizer.reaplugin"
      });

      host.storage({
        type: "read",
        key: "lastVisualizerId",
        namespace: "visualizer.reaplugin"
      });

      start();
    },

    onUnload() {
      log("Unloaded");
      stop();

      // Save current state to storage
      if (state.lastUploadedShot) {
        host.storage({
          type: "write",
          key: "lastUploadedShot",
          namespace: "visualizer.reaplugin",
          data: state.lastUploadedShot
        });
      }

      if (state.lastVisualizerId) {
        host.storage({
          type: "write",
          key: "lastVisualizerId",
          namespace: "visualizer.reaplugin",
          data: state.lastVisualizerId
        });
      }
    },

    // HTTP request handler (optional - can also handle via onEvent)
    __httpRequestHandler(request) {
      host.log(`Received HTTP request for ${request.endpoint}: ${request.method}`);

      if (request.endpoint === "status") {
        return {
          requestId: request.requestId,
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            'X-Custom-Header': 'Plugin-Response'
          },
          body: JSON.stringify({
            status: "online",
            timestamp: Date.now(),
          })
        };
      }

      if (request.endpoint === "echo") {
        return {
          requestId: request.requestId,
          status: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: "Echo response",
            yourData: request.body,
            yourQuery: request.query
          })
        };
      }

      // Default 404 response
      return {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: "Endpoint not found" })
      };
    },


    onEvent(event) {
      if (!event || !event.name) return;

      switch (event.name) {
        case "stateUpdate":
          state.ticks++;
          // if (state.ticks % 50 === 0) {
          //   checkForNewShots();
          // }
          break;
        // case "httpRequest":
        //   const handled = this.__httpRequestHandler(event.password);
        //   host.emit("httpResponse", {
        //     requestId: event.requestId,
        //     ...handled,
        //   });
        //   break;

        case "shutdown":
          stop();
          break;

        case "storageRead":
          handleStorageRead(event.payload);
          break;

        case "storageWrite":
          handleStorageWrite(event.payload);
          break;
      }
    },
  };
}
