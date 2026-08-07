# GH-561: Plugin timers and pending async request ownership

Implemented on branch `feat/gh561-plugin-async-ownership` against commit
`25d24276`. Companion issue #562 owns the top-level `PluginManager` /
`PluginLoaderService` disposal and must call `cancelAllOperations()`.

## Decisions

### host.httpRequest() removed, not implemented

The per-plugin `host.httpRequest()` API was a never-completed duplicate of
`fetch()`: added in a WIP commit (`7dcadbf8`) five days after fetch
(`eb4017b7`), JS registered a resolver Dart never answered, so every call
returned a permanently pending promise. Zero bundled plugins or dye2 code
ever used it. Removing it (the issue allows removal) also removes
`__registerHttpRequest`, `__pendingHttpRequests`, and `__sendHttpResponse`
(dead). `fetch()` is the supported outbound-HTTP API and is documented in
doc/Plugins.md.

### Ownership boundary: JS closures, Dart timers

Timers and fetch are shadowed inside the per-plugin load wrapper with the
pluginId + generation bound in closure, calling `globalThis.__timerSet` /
`__fetchFor`. JS keeps only callback maps (so callbacks stay callable);
Dart owns the real `Timer` / `HttpClient` objects. This gives per-plugin
ownership without a global "current plugin" state, and it lets tests stub
the seam (`__timerSet`, `__fetchFor`) exactly like they used to stub
`globalThis.setTimeout` / `fetch`.

Test seam note: visualizer/shot-upload tests stubbed `globalThis.setTimeout`
and `globalThis.fetch` to run synchronously; those stubs were retargeted to
`__timerSet` / `__fetchFor`. Plugin-visible behavior is unchanged.

### Unified pending-op registry with one terminal path

`_pendingOps` (key `kind:requestId`) holds one `_PendingOp` per in-flight
operation: kind, pluginId, generation, requestId, timeout timer, and an
optional Completer (plugin HTTP) or HttpClientRequest (fetch abort). Every
terminal path (success, error, timeout, unload, dispose) funnels through
`_completeOp()`, which cancels the timeout and removes the entry BEFORE
settling, so late or duplicate completions are no-ops.

### Late-response protection is removal-based, not generation-checked

Unload and reload reject all of the old plugin's ops and delete their JS
pending entries; fetch ids (`__fetchFor` counter) and Decent proxy request
ids (per-runtime nonce) are globally unique, so a late response from an old
generation can never match a new generation's request. Generation is
recorded in the op for diagnostics. Timers need no generation: there is no
async gap between the JS `setTimeout` call and the `timerSet` message, and
ids are globally unique.

### Timeout/size bounds

- Shared `HttpClient` (one per manager, closed in `cancelAllOperations`)
  with a 10s connection timeout; fetch ops add a total-operation timer
  (`fetchTimeout`, default 30s) and a response-size cap
  (`maxFetchResponseBytes`, default 10 MiB).
- Plugin HTTP ops: `pluginHttpTimeout` (default 30s, replaces the hardcoded
  30s poll window).
- Decent proxy ops: `decentProxyTimeout` (default 30s).
- Invalid UTF-8 fetch bodies decode with `allowMalformed: true` (defined
  behavior, never throws).

### Incoming plugin HTTP: Completer instead of polling

`plugins_handler.dart` registered nothing; it polled
`_pendingHttpResponses` every 100ms for 30s. Now `registerPendingHttp()`
registers the op before `dispatchEvent()`, and the handler awaits the
Completer. The 100ms periodic timer is gone; late/unknown responses are
ignored in `_handlePluginApiResponse` (op absent).

### Fire-and-forget callbacks

`host` and `fetch` `onMessage` handlers are now sync. Async work
(storage, Decent proxy, fetch) launches via `unawaited(...)` through
`_handleMessageSafely` / `_handleFetchSafely`, so fire-and-forget messages
no longer hand a Dart `Future` to the bridge's promise machinery. Only the
explicit Decent proxy promise (and fetch/plugin-HTTP promises) are awaited
in JS.

### Diagnostics

`activeTimerCount` / `activeTimersByPlugin` and `activePendingOpCount` /
`activePendingOpsByType` back the resource-invariant assertions in every
test and the acceptance criterion.

## Files

- `lib/src/plugins/plugin_manager.dart` — the six bridges reworked.
- `lib/src/services/webserver/plugins_handler.dart` — direct completion.
- `test/plugins/plugin_manager_timers_test.dart` — 5 timer tests.
- `test/plugins/plugin_manager_fetch_test.dart` — 8 fetch tests (local
  HttpServer, no mock lib).
- `test/services/webserver/plugins_handler_test.dart` — 6 plugin-HTTP
  tests (sync, async, throw, timeout, late response, unload).
- `test/plugins/plugin_manager_decent_proxy_ownership_test.dart` — 6 proxy
  tests (success, transport error, timeout, unload, dispose, stale
  generation).
- `test/plugins/plugin_manager_workload_test.dart` — 10-round mixed
  workload, registries return to zero.
- `test/plugins/plugin_test_helpers.dart` — shared fakes for new tests.
- `test/plugins/{visualizer,shot_upload}_plugin_test.dart` — stub seams
  retargeted.

## Hand-off to #562

`cancelAllOperations()` rejects every pending op, cancels all timers, and
closes the shared `HttpClient`. #562's `dispose()` should call it (and
close the JS runtime).
