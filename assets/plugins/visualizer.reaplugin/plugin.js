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

  async function uploadShot(shot) {
    const res = await fetch(
      `${VISUALIZER_API_URL}/shots/upload`,
      {
        method: "POST",
        headers: {
          Authorization: getAuthHeader(),
          "Content-Type": "application/json",
        },
        body: JSON.stringify(shot),
      }
    );

    if (!res.ok) {
      const errorText = await res.text();
      throw new Error(`Upload failed: ${res.status} ${res.statusText} - ${errorText}`);
    }

    return await res.json();
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

      const result = await uploadShot(shot);
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

    onEvent(event) {
      if (!event || !event.name) return;

      switch (event.name) {
        case "stateUpdate":
          state.ticks++;
          // if (state.ticks % 50 === 0) {
          //   checkForNewShots();
          // }
          break;

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
