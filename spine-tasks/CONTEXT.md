# reaprime — Context

**Last Updated:** 2026-07-01
**Status:** Active
**Next Task ID:** SP-019

---

## Current State

Combustion Inc Predictive Thermometer integration — spine tasks authored from `doc/plans/combustion-probe/`. Phase 0 spike (SP-001) blocks all implementation tasks.

### Resolved product decisions (OD-1–OD-6)

Defaults from [PRD §11](../doc/plans/combustion-probe/PRD.md#11-open-product-decisions) adopted for v1:

| ID | Decision | **Resolved default** |
|----|----------|----------------------|
| OD-1 | Steam `temperature` channel | **Virtual core** for milk pitcher |
| OD-2 | Brew cup `temperature` channel | **T1** (immersed tip / instant-read) |
| OD-3 | Preferred probe storage | **Settings keys** (`preferredSteamProbeId`, `preferredShotProbeId`); optional remember-device later |
| OD-4 | Connection mode for MVP | **Advertising-only** (no persistent GATT) |
| OD-5 | Shot UI placement | **Realtime shot overlay** + existing sensor WebSocket API for skins |
| OD-6 | Gateway mode steam stop | **Inert when `gatewayMode == full`** (matches hot-water-stop precedent) |

### Phase 0 — Spike

| Task | Summary | Status | Deps |
|------|---------|--------|------|
| SP-001 | BLE discovery spike + fixtures + go/no-go | Ready | — |

### Phase 1 — Driver + discovery + steam

| Task | Summary | Status | Deps |
|------|---------|--------|------|
| SP-002 | CombustionProtocol parser | Ready | SP-001 |
| SP-003 | DeviceMatcher scan metadata | Ready | SP-001 |
| SP-004 | Discovery service metadata path | Ready | SP-003 |
| SP-005 | CombustionProbe adv-only sensor | Ready | SP-002, SP-004 |
| SP-006 | MockCombustion simulate wiring | Ready | SP-005 |
| SP-007 | Preferred probe settings | Ready | SP-006 |
| SP-008 | SteamSequencer probe stop + probeLost | Ready | SP-007 |
| SP-009 | Steam integration test | Ready | SP-008 |
| SP-010 | E2E steam-stop scenario | Ready | SP-009 |
| SP-011 | DeviceManagement docs | Ready | SP-010 |

### Phase 2 — Live brew docs

| Task | Summary | Status | Deps |
|------|---------|--------|------|
| SP-012 | API sensor WS during shots docs | Ready | SP-011 |

### Phase 3 — Shot persistence + UI

| Task | Summary | Status | Deps |
|------|---------|--------|------|
| SP-013 | ShotSnapshot probeTemperature + Drift | Ready | SP-012 |
| SP-014 | ShotSequencer probe subscription | Ready | SP-013 |
| SP-015 | Shot REST + OpenAPI | Ready | SP-014 |
| SP-016 | Realtime shot UI probe display | Ready | SP-015 |
| SP-017 | Steam settings stopAtTemperature UI | Ready | SP-016 |
| SP-018 | Hardware validation protocol | Ready | SP-017 |

---

## Execution policy

**Operator runbook:** [pi-spine operator runbook](https://github.com/beettlle/pi-spine/blob/main/docs/adoption/operator-runbook.md) — install, preflight, start/monitor, land loop, gate races, resume/dismiss/complete, dashboard, troubleshooting.

1. **Preflight** before every batch: `spine preflight`.
2. **Land loop:** `spine batch start` → monitor `spine status --diagnose` → `spine gate approve` → `spine integrate` → `spine batch complete`.
3. **Never** hand-edit `.spine/batch-state.json`.
4. **Start development** with `spine batch start SP-001` (or `spine batch start pending` for full chain).

---
