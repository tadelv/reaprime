# reaprime — Context

**Last Updated:** 2026-07-01
**Status:** Active
**Next Task ID:** SP-001

---

## Current State

Greenfield pi-spine project. Add phase tables and task rows as you decompose work from the PRD.

### Phase 0 — Bootstrap

| Task | Summary | Status | Deps |
|------|---------|--------|------|
| | | | |

---

## Execution policy

**Operator runbook:** [`docs/adoption/operator-runbook.md`](../docs/adoption/operator-runbook.md) — install, preflight, start/monitor, land loop, gate races, resume/dismiss/complete, dashboard, troubleshooting.

1. **Preflight** before every batch: `spine preflight`.
2. **Land loop:** `spine batch start` → monitor `spine status --diagnose` → `spine gate approve` → `spine integrate` → `spine batch complete`.
3. **Never** hand-edit `.spine/batch-state.json`.

---

