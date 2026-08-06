/* shot-upload.reaplugin
 *
 * Uploads finished espresso shots to the user's Decent account at
 * decentespresso.com (POST support/api/shot_upload) through the authenticated
 * Decent proxy, reusing the account the user is already logged into. The proxy
 * attaches the account credentials in Dart and never exposes them to plugin JS;
 * the server verifies the account and that the connected machine's serial
 * belongs to it, then stores the shot.
 *
 * Opt-in: AutoUpload defaults to FALSE, so nothing is uploaded until the user
 * turns it on. (Beta stance. Post-beta, logging into the Decent account will
 * itself serve as opt-in consent and AutoUpload will default to true.)
 *
 * The upload binds to the exact persisted shot via the `shotStored` event (fired
 * with the shot id after persistence), so there is no timer/`/shots/latest`
 * race, and machine identity is captured at completion time.
 *
 * Contract: must define createPlugin(host) returning {id, version, onLoad,
 * onUnload, onEvent}.
 */

function createPlugin(host) {
  "use strict";

  const NS = "shot-upload.reaplugin";
  const VERSION = "0.1.0";
  const LOCAL_API_URL = "http://localhost:8080/api/v1";
  const UPLOAD_PATH = "support/api/shot_upload"; // exact allowlisted proxy write path
  const RETRIES = 3;
  const RETRY_DELAY_MS = 2000;

  let isUploading = false;
  let decaidVersion = null;

  const state = {
    autoUpload: false, // opt-in; see header
    lengthThreshold: 5,
    lastUploadedShot: null,
    lastResult: null,
  };

  function log(msg) { try { host.log(`[shot-upload] ${msg}`); } catch (e) {} }

  async function fetchLocal(path) {
    const res = await fetch(`${LOCAL_API_URL}${path}`);
    if (!res.ok) { log(`local ${path} -> ${res.status}`); return null; }
    return await res.json();
  }

  // Decaid app version (for provenance), cached.
  async function getDecaidVersion() {
    if (decaidVersion) return decaidVersion;
    const info = await fetchLocal("/info");
    decaidVersion = (info && (info.version || info.fullVersion)) || "unknown";
    return decaidVersion;
  }

  // seconds between first and last measurement
  function shotDuration(shot) {
    const m = shot && shot.measurements;
    if (!m || m.length < 2) return 0;
    const t0 = Date.parse(m[0].machine.timestamp);
    const t1 = Date.parse(m[m.length - 1].machine.timestamp);
    return isNaN(t0) || isNaN(t1) ? 0 : (t1 - t0) / 1000;
  }

  // Inject machine identity (serial not carried in the shot JSON) + provenance,
  // populated from the actual /machine/info fields (firmware = `version`).
  async function withMachine(shot) {
    const info = await fetchLocal("/machine/info");
    const serial = info && info.serialNumber;
    if (!serial) return null;
    shot.machine = { serialNumber: String(serial) };
    if (info.version) shot.machine.firmwareVersion = String(info.version);
    if (info.model) shot.machine.model = String(info.model);
    shot.app = { name: "decaid", version: await getDecaidVersion(), sourceFormat: "decaid" };
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

  // Upload one stored shot by id. Throws on failure (so callers can report
  // status); marks e.skipped=true for a too-short shot. Returns the server result.
  async function uploadShot(shotId) {
    const full = await fetchLocal(`/shots/${shotId}`);
    if (!full || !full.id) throw new Error(`shot ${shotId} not found`);

    const dur = shotDuration(full);
    if (dur < state.lengthThreshold) {
      const e = new Error(`shot too short (${dur.toFixed(1)}s < ${state.lengthThreshold}s)`);
      e.skipped = true;
      throw e;
    }

    const payload = await withMachine(full);
    if (!payload) throw new Error("no machine serial available");

    const result = await postShot(payload);
    state.lastUploadedShot = full.id;
    state.lastResult = result;
    host.storage({ type: "write", key: "lastUploadedShot", data: full.id });
    host.emit("shotUploaded", { shotId: full.id, result: result, timestamp: Date.now() });
    return result;
  }

  // Auto path: fire-and-forget with dedup + error handling (never throws).
  async function autoUpload(shotId) {
    if (isUploading) return;
    if (shotId && shotId === state.lastUploadedShot) { log(`shot ${shotId} already uploaded`); return; }
    isUploading = true;
    try {
      const r = await uploadShot(shotId);
      log(`uploaded ${shotId} -> ${r && r.profile_ref ? r.profile_ref : "ok"}`);
    } catch (e) {
      if (e.skipped) { log(`skipped ${shotId}: ${e.message}`); }
      else { log(`error uploading ${shotId}: ${e.message}`); host.emit("uploadError", { shotId: shotId, error: e.message, timestamp: Date.now() }); }
    } finally {
      isUploading = false;
    }
  }

  function applySettings(settings) {
    if (!settings) return;
    // Opt-in: default OFF unless the user explicitly enabled it.
    state.autoUpload = settings.AutoUpload === true;
    state.lengthThreshold = settings.LengthThreshold !== undefined ? settings.LengthThreshold : 5;
  }

  function jsonResponse(status, obj) {
    return { status: status, headers: { "Content-Type": "application/json" }, body: JSON.stringify(obj) };
  }

  return {
    id: NS,
    version: VERSION,

    onLoad(settings) {
      applySettings(settings);
      // Storage reads are event-based: this triggers a `storageRead` event,
      // handled in onEvent, that restores lastUploadedShot.
      try { host.storage({ type: "read", key: "lastUploadedShot" }); } catch (e) {}
      log(`loaded (autoUpload ${state.autoUpload})`);
    },

    onUnload() {},

    onEvent(event) {
      switch (event.name) {
        case "shotStored": {
          const id = event.payload && event.payload.id;
          if (id && state.autoUpload) autoUpload(id);
          break;
        }
        case "storageRead":
          if (event.payload && event.payload.key === "lastUploadedShot") {
            state.lastUploadedShot = event.payload.value || null;
          }
          break;
        case "settingsUpdated":
          applySettings(event.payload);
          break;
      }
    },

    // Control endpoints. GET status; POST upload (uploads the latest shot, which
    // belongs to the currently-connected machine — avoids misattributing an
    // arbitrary historical id to the wrong machine).
    async __httpRequestHandler(request) {
      const endpoint = request && request.endpoint;
      if (endpoint === "status") {
        return jsonResponse(200, {
          autoUpload: state.autoUpload,
          lastUploaded: state.lastUploadedShot,
          lastResult: state.lastResult,
        });
      }
      if (endpoint === "upload") {
        try {
          const latest = await fetchLocal("/shots/latest");
          if (!latest || !latest.id) return jsonResponse(404, { ok: false, error: "no shot available" });
          const result = await uploadShot(latest.id);
          return jsonResponse(200, { ok: true, id: latest.id, result: result });
        } catch (e) {
          if (e.skipped) return jsonResponse(200, { ok: false, skipped: true, error: e.message });
          return jsonResponse(502, { ok: false, error: e.message });
        }
      }
      return jsonResponse(404, { error: "unknown endpoint" });
    },
  };
}
