/* shot-upload.reaplugin
 *
 * Uploads finished espresso shots to the user's Decent account at
 * decentespresso.com (POST support/api/shot_upload). Authentication reuses the
 * Decent account the user is already logged into: the upload goes through
 * host.decentProxy, which attaches the account credentials in Dart and never
 * exposes them to plugin JS. The server verifies the account and that the
 * connected machine's serial belongs to it, then stores the shot.
 *
 * There is no "shot stored" plugin event, so (like the Visualizer plugin) we
 * watch machine state for espresso -> non-espresso, then pull the just-stored
 * shot from the local REST API, inject the machine serial (which the shot JSON
 * does not carry) from /api/v1/machine/info, and upload it.
 *
 * Contract: must define createPlugin(host) returning {id, version, onLoad,
 * onUnload, onEvent}.
 */

function createPlugin(host) {
  "use strict";

  const NS = "shot-upload.reaplugin";
  const LOCAL_API_URL = "http://localhost:8080/api/v1";
  const UPLOAD_PATH = "support/api/shot_upload"; // relative to the Decent proxy base
  const SHOT_FETCH_DELAY_MS = 5000; // let the app finish persisting the shot
  const RETRIES = 3;
  const RETRY_DELAY_MS = 2000;

  let shotTimeoutId = null;
  let isUploading = false;

  const state = {
    autoUpload: true,
    lengthThreshold: 5,
    lastMachineState: null,
    lastCheckedShotId: null,
    lastUploadedShot: null,
    lastResult: null,
  };

  function log(msg) { try { host.log(`[shot-upload] ${msg}`); } catch (e) {} }

  async function fetchLocal(path) {
    const res = await fetch(`${LOCAL_API_URL}${path}`);
    if (!res.ok) { log(`local ${path} -> ${res.status}`); return null; }
    return await res.json();
  }

  // seconds between first and last measurement
  function shotDuration(shot) {
    const m = shot && shot.measurements;
    if (!m || m.length < 2) return 0;
    const t0 = Date.parse(m[0].machine.timestamp);
    const t1 = Date.parse(m[m.length - 1].machine.timestamp);
    return isNaN(t0) || isNaN(t1) ? 0 : (t1 - t0) / 1000;
  }

  // Inject machine identity (serial not carried in the shot JSON) + provenance.
  async function withMachine(shot) {
    const info = await fetchLocal("/machine/info");
    const serial = info && (info.serialNumber || info.serial);
    if (!serial) return null;
    shot.machine = { serialNumber: String(serial) };
    if (info.id) shot.machine.bleId = String(info.id);
    if (info.firmwareVersion) shot.machine.firmwareVersion = String(info.firmwareVersion);
    if (info.model) shot.machine.model = String(info.model);
    shot.app = { name: "decaid", version: "0.1.0", sourceFormat: "decaid" };
    shot.schemaVersion = 1;
    return shot;
  }

  // POST the shot through the authenticated Decent proxy (reuses account login).
  async function postShot(shot) {
    const body = JSON.stringify(shot);
    let lastErr = null;
    for (let i = 0; i < RETRIES; i++) {
      try {
        const res = await host.decentProxy(UPLOAD_PATH, {
          method: "POST",
          body: body,
          contentType: "application/json",
        });
        const status = res && res.status;
        const text = (res && res.body) || "";
        if (status >= 200 && status < 300) {
          try { return JSON.parse(text); } catch (e) { return { ok: true }; }
        }
        // 4xx (not logged in / not your machine / bad shot) -> don't retry
        if (status >= 400 && status < 500) {
          throw new Error(`HTTP ${status}: ${text}`);
        }
        lastErr = new Error(`HTTP ${status}: ${text}`);
      } catch (e) {
        lastErr = e;
        if (String(e.message).indexOf("HTTP 4") === 0) throw e;
      }
      if (i < RETRIES - 1) await new Promise(r => setTimeout(r, RETRY_DELAY_MS));
    }
    throw lastErr || new Error("upload failed");
  }

  async function uploadShotById(shotId) {
    if (isUploading) return;
    isUploading = true;
    try {
      let meta = shotId ? { id: shotId } : await fetchLocal("/shots/latest");
      if (!meta || !meta.id) { log("no shot available"); return; }

      if (!shotId && meta.id === state.lastCheckedShotId) { log(`shot ${meta.id} already handled`); return; }
      state.lastCheckedShotId = meta.id;

      const full = await fetchLocal(`/shots/${meta.id}`);
      if (!full) { log(`could not fetch shot ${meta.id}`); return; }

      const dur = shotDuration(full);
      if (dur < state.lengthThreshold) { log(`shot ${meta.id} too short (${dur.toFixed(1)}s); skipping`); return; }

      const payload = await withMachine(full);
      if (!payload) { log("no machine serial available; skipping"); return; }

      const result = await postShot(payload);
      state.lastUploadedShot = full.id;
      state.lastResult = result;
      host.storage({ type: "write", key: "lastUploadedShot", namespace: NS, data: full.id });
      log(`uploaded ${full.id} -> ${result && result.profile_ref ? result.profile_ref : "ok"}`);
      host.emit("shotUploaded", { shotId: full.id, result: result, timestamp: Date.now() });
    } catch (e) {
      log(`error: ${e.message}`);
      host.emit("uploadError", { error: e.message, timestamp: Date.now() });
    } finally {
      isUploading = false;
    }
  }

  function applySettings(settings) {
    if (!settings) return;
    state.autoUpload = settings.AutoUpload !== undefined ? settings.AutoUpload : true;
    state.lengthThreshold = settings.LengthThreshold !== undefined ? settings.LengthThreshold : 5;
  }

  return {
    id: NS,
    version: "0.1.0",

    onLoad(settings) {
      applySettings(settings);
      try {
        const saved = host.storage({ type: "read", key: "lastUploadedShot", namespace: NS });
        if (saved) state.lastUploadedShot = saved;
      } catch (e) {}
      log(`loaded (auto ${state.autoUpload})`);
    },

    onUnload() {
      if (shotTimeoutId) { clearTimeout(shotTimeoutId); shotTimeoutId = null; }
    },

    onEvent(event) {
      switch (event.name) {
        case "stateUpdate": {
          const cur = event.payload && event.payload.state && event.payload.state.state;
          if (state.lastMachineState === "espresso" && cur !== "espresso") {
            if (state.autoUpload) {
              log(`shot ended (${state.lastMachineState} -> ${cur}); uploading in ${SHOT_FETCH_DELAY_MS / 1000}s`);
              if (shotTimeoutId) clearTimeout(shotTimeoutId);
              shotTimeoutId = setTimeout(() => uploadShotById(null), SHOT_FETCH_DELAY_MS);
            }
          }
          state.lastMachineState = cur;
          break;
        }
        case "settingsUpdated":
          applySettings(event.payload);
          break;
      }
    },

    // Optional control endpoints (POST upload {shotId}, GET status).
    async __httpRequestHandler(request) {
      const id = (request && request.id) || "";
      if (id === "upload") {
        const shotId = request.data && request.data.shotId;
        await uploadShotById(shotId || null);
        return { status: 200, body: { ok: true, lastUploaded: state.lastUploadedShot } };
      }
      if (id === "status") {
        return { status: 200, body: {
          autoUpload: state.autoUpload,
          lastUploaded: state.lastUploadedShot,
          lastResult: state.lastResult,
        } };
      }
      return { status: 404, body: { error: "unknown endpoint" } };
    },
  };
}
