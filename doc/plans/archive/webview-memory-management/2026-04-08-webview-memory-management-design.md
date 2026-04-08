# WebView Memory Management for SkinView

## Problem

On the m50mini (Teclast ACM-T01K, Android 14, ~2-3GB RAM), the InAppWebView in SkinView adds ~350MB RSS (from ~200MB to ~550MB). Android's Low Memory Killer terminates the entire app overnight because the combined memory footprint is too high for background survival.

Root cause: commit `9d3cbf4` (April 6) changed the WebView compatibility checker from hard-blocking all Teclast devices to a runtime test. The m50mini passes the runtime test, so now a full InAppWebView loads — previously it showed a static incompatibility message with no WebView.

## Approach

Three layers of defense, all in `lib/src/skin_feature/skin_view.dart`:

### 1. Renderer Priority Policy (passive)

Add `rendererPriorityPolicy` to `InAppWebViewSettings` with `waivedWhenNotVisible: true`. This tells Android it can kill the WebView renderer process (not the app) when memory is tight. The renderer runs in a separate sandboxed process on Android 8+.

Must pair with `useOnRenderProcessGone: true` and handle the callback.

### 2. Pause + blank on background (active)

Add `WidgetsBindingObserver` to `_SkinViewState`. When the app goes to background (`paused`):
- Call `controller.pause()` + `controller.pauseTimers()`
- Load `about:blank` to release DOM, JS heap, images, canvas buffers

When the app returns to foreground (`resumed`):
- Call `controller.resumeTimers()` + `controller.resume()`
- Reload the skin URL

Since the skin is served from localhost:3000, reload should be near-instant.

### 3. Graceful renderer death recovery

When `onRenderProcessGone` fires (Android killed the renderer to reclaim memory):
- Show a brief "Reloading skin..." UI state
- Trigger a full WebView rebuild via `setState`
- The app stays alive (BLE connections, REST API, foreground service all intact)

## What we're NOT doing

- Destroying the WebView when navigating to HomeScreen (user navigates back frequently)
- Adding platform channels for `onTrimMemory` (overkill for now)
- Changing the compatibility checker (that memory cost is already paid at startup)

## Files changed

- `lib/src/skin_feature/skin_view.dart` — all changes

## Testing

Deploy to the m50mini tablet, monitor RSS via the WebSocket log stream, verify the app survives overnight without being killed.

## Known risks

- flutter_inappwebview issue #1923: WebView may go invisible on resume after switching apps
- flutter_inappwebview issue #1215: Some devices freeze after resume
- Both need testing on the m50mini specifically
