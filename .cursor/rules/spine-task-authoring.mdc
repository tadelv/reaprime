---
description: "Create pi-spine task packets (PROMPT.md, STATUS.md, dependencies.json) under the configured tasks root. Use when asked to create spine tasks, decompose PRDs for spine batch, or stage SP-* work—not when operating batches or implementing code."
globs: ["**/.spine/**", "**/spine-tasks/**", "**/dependencies.json"]
alwaysApply: false
---

# pi-spine task authoring

Author **spine-compatible task packets** for autonomous execution via [pi-spine](https://github.com/beettlle/pi-spine) (`spine batch start`, `/spine`). Packets are file contracts; pi-spine workers run in lane worktrees with journal, review, and integrate gates—the PROMPT defines **what** to build, not **how** the orchestrator runs.

**Related:** `@spine-operator-cursor.mdc` for batch operations; `@spine-worker-cursor.mdc` for manual in-Cursor implementation; `@taskplane-task-authoring.mdc` when no `.spine/spine-config.json` exists. Templates: `@.cursor/rules/taskplane/prompt-template.md`, `@.cursor/rules/taskplane/status-template.md`. Deep decomposition: pi-spine `create-spine-tasks` skill (`pi install npm:pi-spine`)—link only, do not vendor.

## When this rule applies

Apply when the user asks to:

- Create, stage, or decompose **spine** tasks (`SP-*`, `spine-tasks/`, spine batch)
- Write or update spine `PROMPT.md`, `STATUS.md`, `dependencies.json`, or tasks-root `CONTEXT.md`
- Migrate or extend Taskplane packets for pi-spine

**Do not apply for:**

- Batch control (`spine batch start`, gate, integrate) → `@spine-operator-cursor.mdc`
- Implementing product code → `@spine-worker-cursor.mdc`
- Generic Taskplane packets with no spine config → `@taskplane-task-authoring.mdc`

If intent is ambiguous (author vs operate vs implement), ask once.

## Orchestration artifacts vs repo docs

Spine task files under the configured tasks root are **orchestration artifacts**, not unsolicited documentation. Creating them when the user requests spine task work is allowed. See `documentation-policy.mdc` (pi-spine task packets exception).

Do not hand-edit `.spine/runtime/**`, `.spine/batch-state.json`, or create `.DONE` / `.reviews/` at author time.

## Prerequisites

1. **`.spine/spine-config.json`** exists (`spine init`). If missing, tell the user to run `spine init` before authoring.
2. Read config keys: `paths.tasksRoot`, `testing.build` / `testing.test` / `testing.testWithCoverage`, `referenceDocs`, `standards`, `neverLoad`, `contract.mode`, `contract.legacyTaskIdPrefixes`.

Default tasks root: `spine-tasks/`. Migrated repos may use `taskplane-tasks/`—always read `paths.tasksRoot` from config.

## Packet layout

```text
{tasksRoot}/
├── CONTEXT.md              # Next Task ID, domain state
├── dependencies.json       # Machine-readable DAG edges
├── _explore/               # Authoring-only (optional)
├── _authoring/             # Authoring-only (optional)
└── {SP-###-slug}/
    ├── PROMPT.md
    └── STATUS.md
```

Folder name must match PROMPT heading ID (FR-TASK-01): `# Task: SP-042 — slug name`.

## Authoring workflow

1. **Read** `.spine/spine-config.json` and `{tasksRoot}/CONTEXT.md` (`Next Task ID`).
2. **Assess size** — S (&lt;2h), M (2–4h), L (4–8h). **Never XL**; split into multiple `SP-*` tasks with dependencies.
3. **Assess review level** — Rubric below; do not default to Level 0 for M+ work.
4. **Create folder** `{tasksRoot}/{SP-###-slug}/`.
5. **Write `PROMPT.md`** — Spine requirements below + taskplane template structure.
6. **Write `STATUS.md`** — Mirror PROMPT steps; `⚠️ Hydrate` on discovery-dependent steps.
7. **Update `dependencies.json`** — Edges for every non-None dependency.
8. **Increment `Next Task ID`** in `CONTEXT.md`.
9. **Handoff** — Report path; suggest `spine tasks validate`, `spine plan pending`, `spine preflight` before batch.

## Review level rubric

Score each dimension **0–2** (blast radius, pattern novelty, security, reversibility). Sum → level:

| Sum | Review level |
|-----|----------------|
| 0–1 | 0 — None (trivial doc/config only) |
| 2–3 | 1 — Plan before code |
| 4–5 | 2 — Plan + code review |
| 6–8 | 3 — Plan + code + test review |

Document level and score in PROMPT under `## Review Level`.

## Spine-specific PROMPT requirements

- **Heading:** `# Task: SP-### — Title` (em dash U+2014).
- **## Contract** — After `## File Scope`, before `## Steps`. Required for new `SP-*` when `contract.mode` is `required` (pi-spine default). Legacy `TP-*` may skip when listed in `contract.legacyTaskIdPrefixes`.

```markdown
## Contract

| Field | Value |
|-------|-------|
| testCommand | `npm run coverage:check` |
| fileScopeMustChange | `src/batch/review.mjs` |
| fileScopeMustNotChange | `src/planner/**` |
| completionCriteria | Tests pass; coverage gate met |
```

- **Testing & Verification step** — Mandatory penultimate step before Completion Criteria (SP-075). Use `testing.testWithCoverage` from config when present; else `testing.test`.
- **Max 4 implementation steps** (excluding Testing and Completion Criteria).
- **File Scope** — Disjoint across tasks intended to run in the same wave; overlapping paths force serial lanes.
- **Environment** — Include project test command; stub CI: `SPINE_WORKER_STUB=1` when documenting CI-only runs.
- **Git Commit Convention** — `feat(SP-###): …` at step boundaries.

### PROMPT must NOT contain

❌ Bad: "Run in lane worktree", "call spine_review_step", "wait for gate", "open dashboard"
✅ Good: Mission, scoped steps, verification commands, Contract proof fields
⚠️ Why: pi-spine engine owns waves, lanes, worktrees, review spawn, gates
🔧 Fix: Remove orchestration prose; keep outcome-focused steps
📍 See: [pi-spine EXECUTION-FLOW](https://github.com/beettlle/pi-spine/blob/main/docs/EXECUTION-FLOW.md)
**Detect:** worktree, lane, gate, dashboard, journal, `/spine` in PROMPT body

## Dependencies (dual-write)

**In PROMPT `## Dependencies`:** `- **None**`, bare `SP-003`, or `- **Task:** SP-003`.

**In `dependencies.json`:**

```json
{ "edges": [{ "from": "SP-042", "to": "SP-041" }] }
```

`from` depends on `to`. Both must stay in sync.

## Definition of ready (before handoff)

- [ ] `Next Task ID` incremented in `CONTEXT.md`
- [ ] Folder matches `SP-###-slug`; heading matches folder ID
- [ ] Contract table present for `SP-*` (when required)
- [ ] Testing & Verification step with real command from config
- [ ] `dependencies.json` edges match PROMPT Dependencies
- [ ] Review level assigned; size S/M/L (XL split)
- [ ] File scopes disjoint for parallel wave mates
- [ ] No `.DONE`, `.reviews/`, runtime `.spine/` edits
- [ ] Handoff path to `PROMPT.md` reported

## Anti-patterns (CRIT)

### XL single task (CRIT)

**CRITICAL:** Never author one XL task; split into M-sized tasks with explicit deps.

❌ Bad: `**Size:** XL` with 8+ hours of work in one packet
✅ Good: `SP-041`, `SP-042`, `SP-043` chain with `dependencies.json` edges
⚠️ Why: Stall budget, review timeouts, lane merge risk
🔧 Fix: Split at natural boundaries; one concern per packet
**Detect:** Size XL, 5+ impl steps, multi-feature Mission

### Missing Testing step (CRIT)

**CRITICAL:** Every `SP-*` PROMPT must include Testing & Verification before Completion Criteria.

❌ Bad: Steps end at implementation with no dedicated test step
✅ Good: `### Step N: Testing & Verification` with exact `npm run …` from config
⚠️ Why: SP-075 gate; Contract `testCommand` verified at final review
🔧 Fix: Add penultimate Testing step with coverage gate when configured
**Detect:** No Testing step, test command only in Contract table

### Overlapping parallel scopes (CRIT)

**CRITICAL:** Tasks in the same planned wave must have disjoint File Scope.

❌ Bad: `SP-010` and `SP-011` both list `src/batch/engine.mjs` with no dependency edge
✅ Good: Serialize via dependency or narrow scopes to non-overlapping paths
⚠️ Why: Lane assignment merges overlapping tasks; defeats parallelism
🔧 Fix: `spine plan` to verify; add dep or split files
**Detect:** Same path in sibling tasks without `from`→`to` edge

### Orchestration in PROMPT (CRIT)

**CRITICAL:** PROMPT describes product outcomes only.

❌ Bad: "Commit STATUS after each step for spine heartbeat"
✅ Good: "Update STATUS checkboxes at step boundaries" (worker discipline, not engine ops)
⚠️ Why: Authoring confusion; duplicates `.spine/agents/worker.md`
🔧 Fix: Delete engine-specific instructions
**Detect:** spine batch, worktree, integrate, gate in PROMPT

## Launch checklist (report to user)

```bash
spine tasks validate
spine tasks analyze
spine plan pending    # or: spine plan all
spine preflight
spine batch start pending --attached   # first run: attached until trusted
```

## External references

- [pi-spine](https://github.com/beettlle/pi-spine) — engine, operator runbook, PRD
- [Taskplane task format](https://github.com/HenryLach/taskplane/blob/main/docs/reference/task-format.md) — compatible packet shape
