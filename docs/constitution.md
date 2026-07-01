# reaprime — Constitution

**Last Updated:** 2026-07-01

Upstream principles for Decent.app (`reaprime` package). Agents load this file via `referenceDocs` in `.spine/spine-config.json`.

---

## Mission

Decent.app is a Flutter gateway for Decent Espresso machines (DE1, Bengle), scales, and sensors. It connects over BLE/USB, exposes REST (port 8080) and WebSocket APIs, and supports a JavaScript plugin system. Primary deployment is the Android DE1 tablet; macOS, Linux, Windows, and iOS are also supported.

---

## Guiding principles

### Simplicity

Prefer the smallest change that satisfies the requirement. Delete before you abstract. Device code depends on injected transport interfaces — never import third-party BLE libraries outside `lib/src/services/ble/`.

### Testing

- Every behavior change includes a test or explicit verification step in the task contract.
- Run `flutter analyze && flutter test` before marking work complete.
- Do not claim tests pass without evidence.
- Follow outside-in TDD: failing test → implement → green → commit.

### User experience

- Optimize for the barista and operator path, not internal convenience.
- Failures must be visible, actionable, and safe by default.
- Graceful degradation when peripherals disconnect mid-session (no stale-data stops, no crashes).

### Performance

- Avoid I/O in loops; batch reads and writes.
- BLE operations use per-device queues — probes must not block DE1/scale.
- Prefer advertising-only sensor paths when connection slots are scarce.

### Security

- No secrets in source control.
- Validate untrusted input at system boundaries (REST handlers, plugin boundaries).

### API discipline

- Update `assets/api/rest_v1.yml` and `doc/Api.md` in the **same commit** as schema changes.
- Reuse existing sensor API surface; do not add parallel `/api/v1/probe/*` namespaces.

---

## Non-negotiable rules

1. **Scope discipline** — Task workers stay within PROMPT File Scope unless the operator amends the packet.
2. **No silent failures** — Errors propagate with context; do not swallow exceptions.
3. **Honest verification** — Build and test claims require output or "verification pending."
4. **Reversibility** — Prefer changes that can be reverted without data loss.
5. **Transport boundary** — Wrap library-specific BLE types in domain types at the transport layer.

---

## Active feature context

Combustion Inc Predictive Thermometer integration is the current spine batch. Authoritative product and engineering docs:

- `doc/plans/combustion-probe/PRD.md`
- `doc/plans/combustion-probe/IMPLEMENTATION.md`
- `doc/plans/combustion-probe/SPIKE-universal-ble-discovery.md`
- `spine-tasks/CONTEXT.md` (resolved product decisions and task DAG)

---

## How this file is used

| Consumer | Usage |
|----------|-------|
| Task authoring | Mission and "Context to Read First" in `PROMPT.md` |
| Workers | Injected when listed in `referenceDocs` (not in `neverLoad`) |
| Reviewers | Principles inform plan/code review; reviewers do not auto-load `referenceDocs` |
