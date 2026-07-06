# Derek relay route

## Problem

Browser skins (e.g. Streamline) want to use Derek, the Decent RAG assistant, in a
modal. Derek's endpoint is internet-reachable but auth-less, and its server does
not answer CORS preflight — so a browser `POST` with a JSON body fails the
`OPTIONS` preflight before it starts. Calling Derek directly from the skin can't
work.

## Approach

Add a thin Reaprime relay, matching the existing `/api/v1/account/proxy/` pattern
but **streaming** (the account proxy buffers, which would break SSE):

```
POST /api/v1/derek/answers/stream
  -> Reaprime forwards the body verbatim to
     https://derek.decentespresso.com/api/answers/stream
  -> upstream SSE stream piped straight back, unbuffered
```

Because the call now lands on the API, the existing `corsHeaders` middleware
answers the preflight — the thing Derek's server couldn't do.

## Why no auth

Derek serves public knowledge-base data, so the route stays on the API's
LAN-trust model (no bearer token, unlike the account proxy). Request validation,
rate limiting, and error shapes stay Derek's responsibility; the relay passes the
upstream status and body through verbatim.

## Changes

- `lib/src/services/webserver/derek_handler.dart` — new `DerekHandler`. Reads the
  small JSON request body, forwards it via the injected `http.Client`, and returns
  `Response(status, body: upstream.stream, …)` so each SSE event flushes live.
  Sets `Cache-Control: no-cache` and `X-Accel-Buffering: no`.
- `lib/src/services/webserver_service.dart` — `part` include, construct
  `DerekHandler()`, thread it through `_init`, register the route.
- `test/webserver/derek_handler_test.dart` — `MockClient`-based tests: verbatim
  body forwarding, SSE + unbuffered headers passthrough, upstream error
  passthrough, content-type default.
- `assets/api/rest_v1.yml` — OpenAPI entry for the new path.

## Out of scope

- Assembling shot/workflow context into the prompt — the skin builds the query.
- A user-facing toggle / configurable upstream — `DerekHandler.baseUrl` already
  takes an override; a settings knob can come later if wanted.
