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

  const SHOT_FETCH_DELAY_MS = 5000;
  const VISUALIZER_API_URL = "https://visualizer.coffee/api";
  const VISUALIZER_SHARED_API = "https://visualizer.coffee/api/shots/shared?code=";
  const VISUALIZER_PROFILE_API = "https://visualizer.coffee/api/shots/%1/profile?format=json";

  let timeoutId = null;
  let shotFetchTimeoutId = null;
  let isChecking = false;
  let isUploading = false;
  let isRunning = false;

  const state = {
    lastUploadedShot: null,
    lastVisualizerId: null,
    lastCheckedShotId: null,
    username: null,
    password: null,
    ticks: 0,
    autoUpload: true,
    lengthThreshold: 5,
    enabled: true,
    lastMachineState: null,
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

  function getAuthHeader(authState) {
    if (authState == null) {
      authState = state;
    }

    if (!authState.username || !authState.password) {
      throw new Error("Username or password not configured");
    }
    return "Basic " + btoa(authState.username + ":" + authState.password);
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

    log(`shot duration: ${shotData.duration}`);
    if (shotData.duration < state.lengthThreshold) {
      log(`Not uploading shot because it's too short: ${shotData.duration}`);
      throw new Error(`Not uploading shot because it's too short: ${shotData.duration}`);
    }

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

    const firstEspressoIndex = reaShot.measurements.findIndex((element) => {
      return element.machine.state.substate == 'preinfusion' ||
        element.machine.state.substate == 'pouring';
    });

    const firstTimestamp = new Date(reaShot.measurements[firstEspressoIndex].machine.timestamp).getTime();
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
            bean_weight: String(reaShot.workflow.context?.targetDoseWeight ?? reaShot.workflow.doseData?.doseIn ?? 0),
            drink_weight: String(lastMeasurement.scale?.weight ?? 0),
            target_weight: String(reaShot.workflow.profile.target_weight),
            grinder_model: reaShot.workflow.context?.grinderModel ?? reaShot.workflow.grinderData?.model,
            grinder_setting: reaShot.workflow.context?.grinderSetting ?? reaShot.workflow.grinderData?.setting,
            bean_brand: reaShot.workflow.context?.coffeeRoaster ?? reaShot.workflow.coffeeData?.roaster,
            bean_type: reaShot.workflow.context?.coffeeName ?? reaShot.workflow.coffeeData?.name,
          }
        }
      },
    };

    for (let i = firstEspressoIndex; i < reaShot.measurements.length; i++) {
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
    if (!state.enabled) {
      log("Plugin is disabled, not checking for new shots");
      return;
    }
    if (isChecking || !isRunning) return;
    isChecking = true;

    try {
      log("Checking for new shots...");
      if (!state.autoUpload) {
        log("Auto upload disabled, not checking ...");
        return
      }
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
    }
  }

  function start() {
    if (isRunning) return;
    isRunning = true;
    log("Started - listening for state changes");
  }

  function stop() {
    isRunning = false;
    if (timeoutId !== null) {
      clearTimeout(timeoutId);
      timeoutId = null;
    }
    if (shotFetchTimeoutId !== null) {
      clearTimeout(shotFetchTimeoutId);
      shotFetchTimeoutId = null;
    }
    log("Stopped");
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

  async function checkCredentials(body) {
    log(`checking creds: ${JSON.stringify(body)}`)
    const url = `${VISUALIZER_API_URL}/me`;
    const headers = {
      'Authorization': getAuthHeader(body)
    };

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: headers
      });

      return response.ok;
    } catch (error) {
      log('Error checking Visualizer credentials:', error);
      return false;
    }
  }

  async function importFromShareCode(shareCode) {
    if (!state.enabled) {
      throw new Error("Visualizer plugin is disabled");
    }
    
    const code = shareCode.trim();

    if (!code) {
      throw new Error("No share code provided");
    }

    log(`Importing profile from share code: ${code}`);

    // Step 1: Fetch shot metadata from share code
    const sharedUrl = `${VISUALIZER_SHARED_API}${code}`;
    log(`Fetching from: ${sharedUrl}`);

    const sharedResponse = await fetch(sharedUrl, {
      method: 'GET',
      headers: {
        'Authorization': getAuthHeader(),
        'Content-Type': 'application/json'
      }
    });

    if (!sharedResponse.ok) {
      const statusCode = sharedResponse.status;
      if (statusCode === 401) {
        throw new Error("Invalid Visualizer credentials");
      }
      throw new Error(`Failed to fetch share code: HTTP ${statusCode} ${sharedResponse.statusText}`);
    }

    const sharedData = await sharedResponse.json();
    log(`Share code response: ${JSON.stringify(sharedData).slice(0, 200)}`);

    // Handle both array and object responses
    let shotId;
    if (Array.isArray(sharedData)) {
      if (sharedData.length === 0) {
        throw new Error("No shared shots found for this code");
      }
      shotId = sharedData[0]?.id;
    } else {
      shotId = sharedData?.id;
    }

    if (!shotId) {
      throw new Error("Share code response missing shot ID");
    }

    log(`Got shot ID: ${shotId}, fetching profile...`);

    // Step 2: Fetch profile data using shot ID
    const profileUrl = VISUALIZER_PROFILE_API.replace('%1', shotId);
    log(`Fetching profile from: ${profileUrl}`);

    const profileResponse = await fetch(profileUrl, {
      method: 'GET',
      headers: {
        'Authorization': getAuthHeader(),
        'Content-Type': 'application/json'
      }
    });

    if (!profileResponse.ok) {
      const statusCode = profileResponse.status;
      if (statusCode === 401) {
        throw new Error("Invalid Visualizer credentials");
      }
      throw new Error(`Failed to fetch profile: HTTP ${statusCode} ${profileResponse.statusText}`);
    }

    const profileData = await profileResponse.json();
    log(`Fetched profile: ${JSON.stringify(profileData).slice(0, 200)}`);

    // Step 3: POST profile to REA workflow endpoint
    log(`Posting profile to REA workflow endpoint...`);
    const workflowResponse = await fetch('http://localhost:8080/api/v1/profiles', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        profile: profileData,
        metadata: { 'comment': `imported from visualizer: ${profileData.id}` }
      })
    });

    if (!workflowResponse.ok) {
      throw new Error(`Failed to import profile to REA: HTTP ${workflowResponse.status} ${workflowResponse.statusText}`);
    }

    const workflowResult = await workflowResponse.json();
    log(`Profile imported successfully: ${JSON.stringify(workflowResult).slice(0, 100)}`);

    return {
      success: true,
      profileTitle: profileData.title || 'Imported Profile',
      profileId: workflowResult.id || workflowResult.profile?.id || null,
      shotId: shotId,
      workflowResult: workflowResult
    };
  }

  // Handle settings update event from REA host
  function handleSettingsUpdate(newSettings) {
    log(`Received settings update: ${JSON.stringify(newSettings)}`);
    
    if (newSettings.Username !== undefined) {
      state.username = newSettings.Username;
      log(`Username updated: ${state.username ? 'configured' : 'cleared'}`);
    }
    
    if (newSettings.Password !== undefined) {
      state.password = newSettings.Password;
      log(`Password updated`);
    }
    
    if (newSettings.Enabled !== undefined) {
      state.enabled = newSettings.Enabled;
      log(`Plugin enabled: ${state.enabled}`);
      if (!state.enabled) {
        stop();
      } else if (isRunning === false) {
        start();
      }
    }
    
    if (newSettings.AutoUpload !== undefined) {
      state.autoUpload = newSettings.AutoUpload;
      log(`AutoUpload updated: ${state.autoUpload}`);
    }
    
    if (newSettings.LengthThreshold !== undefined) {
      state.lengthThreshold = newSettings.LengthThreshold;
      log(`Length threshold updated: ${state.lengthThreshold}`);
    }
  }
  // Return the plugin object
  return {
    id: "visualizer.reaplugin",
    version: "1.0.0",

    onLoad(settings) {
      state.enabled = settings.Enabled != undefined ? settings.Enabled : true;
      state.username = settings.Username;
      state.password = settings.Password;
      state.autoUpload = settings.AutoUpload != undefined ? settings.AutoUpload : true;
      state.lengthThreshold = settings.Length != undefined ? settings.Length : 5;

      log(`Loaded with enabled: ${state.enabled}, username: ${state.username ? 'configured' : 'not configured'}`);

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

      if (request.endpoint === "upload") {
        const shotId = request.body.shotId;
        if (!shotId) {
          return {
            requestId: request.requestId,
            status: 400,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              message: 'shotId is required'
            })

          }
        }
        return fetch(`http://localhost:8080/api/v1/shots?ids=${shotId}`)
          .then((res) => {
            return res.json();
          }).then((json) => {
            return uploadShot(convertReaToVisualizerFormat(json[0]), null);
          }).then((shotResponse) => {
            return {
              status: 200,
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                'visualizer_id': shotResponse.id
              })
            };
          });
      }

      if (request.endpoint === "verifyCredentials") {
        log(`verifying ${JSON.stringify(request.body)}`)
        return checkCredentials(request.body).then((verified) => {
          return {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              'valid': verified
            })
          }

        });
      }

      if (request.endpoint === 'lastUpload') {

        return {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            reaId: state.lastUploadedShot,
            visId: state.lastVisualizerId,
          })
        };
      }

      if (request.endpoint === 'import') {
        if (request.method !== 'POST') {
          return {
            status: 405,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ error: 'Method not allowed' })
          };
        }

        const shareCode = request.body?.shareCode;
        if (!shareCode) {
          return {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ error: 'shareCode is required' })
          };
        }

        // Call importFromShareCode and handle the async result
        return importFromShareCode(shareCode)
          .then((result) => {
            // Emit event for UI listeners
            host.emit('profileImported', {
              success: true,
              profileTitle: result.profileTitle,
              shotId: result.shotId,
              timestamp: Date.now()
            });

            return {
              status: 200,
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(result)
            };
          })
          .catch((error) => {
            log(`Import failed: ${error.message}`);
            
            // Emit error event for UI listeners
            host.emit('importError', {
              success: false,
              error: error.message,
              timestamp: Date.now()
            });

            return {
              status: error.message.includes('credentials') ? 401 : 400,
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ 
                success: false,
                error: error.message 
              })
            };
          });
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
          const currentState = event.payload?.state?.state;
          if (state.lastMachineState === "espresso" && currentState !== "espresso") {
            log(`Shot ended (${state.lastMachineState} → ${currentState}), scheduling upload in ${SHOT_FETCH_DELAY_MS / 1000}s`);
            if (shotFetchTimeoutId !== null) {
              clearTimeout(shotFetchTimeoutId);
            }
            shotFetchTimeoutId = setTimeout(() => {
              shotFetchTimeoutId = null;
              checkForNewShots();
            }, SHOT_FETCH_DELAY_MS);
          }
          state.lastMachineState = currentState;
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
          if (shotFetchTimeoutId !== null) {
            clearTimeout(shotFetchTimeoutId);
            shotFetchTimeoutId = null;
          }
          break;

        case "storageRead":
          handleStorageRead(event.payload);
          break;

        case "storageWrite":
          handleStorageWrite(event.payload);
          break;

        case "settingsUpdated":
          handleSettingsUpdate(event.payload);
          break;
      }
    },
  };
}