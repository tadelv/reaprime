---
description: "Operate pi-spine batches in Cursor: spine CLI commands, diagnosis, recovery, gates, integrate, and report upstream engine bugs. Use when user asks to start/pause/resume spine batch, run spine doctor/preflight/plan, check batch status, approve gate, recover from orphans, or report spine bugs—not when authoring packets or implementing task code."
alwaysApply: false
---

# pi-spine operator (Cursor)

Operate **pi-spine** batches from Cursor: validate, plan, start, monitor, recover, gate, and integrate. Cursor is the **operator console**—batch workers are **pi** sessions in lane worktrees, not Cursor Agent.

**Related:** `@spine-task-authoring.mdc` for packets; `@spine-worker-cursor.mdc` for manual implementation when no batch runs. Verification: `general-llm-anti-patterns.mdc` §3.8–3.9. Normative spec: [pi-spine PRD](https://github.com/beettlle/pi-spine/blob/main/docs/PRD.md).

Manual activation: `@spine-operator-cursor` when the agent does not auto-select this rule.

## When this rule applies

Apply when the user:

- Runs or asks about `spine` CLI (batch, gate, integrate, doctor, dashboard)
- Needs batch diagnosis, recovery, or orphan handling
- Wants to land work on `main` via gate + integrate

**Do not apply** when authoring packets or implementing task code in the same folders an active batch owns.

## Prerequisites

- Node.js ≥ 22, git, `pi` on PATH
- `.spine/spine-config.json` (`spine init`)
- Install: `pi install npm:pi-spine` or `npm install -g pi-spine`

## Command reference

| Phase | Commands |
|-------|----------|
| Setup | `spine init`, `spine doctor`, `spine migrate-from-taskplane` |
| Validate | `spine preflight`, `spine tasks validate`, `spine tasks analyze` |
| Plan | `spine plan all`, `spine plan pending`, `spine deps` |
| Batch | `spine batch start <scope>`, `pause`, `resume`, `abort`, `retry <id>`, `skip <id>` |
| Review | `spine review step`, `spine gate status`, `spine gate approve`, `spine gate reject` |
| Land | `spine integrate` |
| Observe | `spine status`, `spine status --diagnose`, `spine journal`, `spine dashboard`, `spine next` |

**Attached vs detached:** Prefer `spine batch start <scope> --attached` until the operator trusts detached recovery. After detached start, always run `spine status --diagnose`.

**Stub workers (CI / no pi):** `SPINE_WORKER_STUB=1 spine batch start <id>`.

## Operator workflow

```text
spine doctor → preflight → plan → batch start
    → monitor (status --diagnose, dashboard)
    → gate approve → integrate → main
```

Recovery entry point: **`spine status --diagnose`** — read headline + `suggestedCommand`; do not guess.

## Recovery tree (compact)

| Diagnosis | Action |
|-----------|--------|
| `state_drift` | `spine status --diagnose`; follow `suggestedCommand`; journal rebuild only via spine CLI |
| `engine_orphaned` | `spine batch resume` or `spine batch abort` per diagnose output |
| `worker_orphaned` | `spine batch resume`; may need `retry` on specific task |
| `gate_open` / `needs_approval` | `spine gate status`; collect evidence; `gate approve` before integrate |
| `post_merge_limbo` | Follow diagnose; do not hand-edit batch state |

Full procedures: [pi-spine operator runbook](https://github.com/beettlle/pi-spine/blob/main/docs/adoption/operator-runbook.md).

## Upstream bug reports

When recovery fails or the same diagnosis repeats after following `suggestedCommand`, triage before filing at [pi-spine issues](https://github.com/beettlle/pi-spine/issues). Search existing issues first.

| Situation | Action |
|-----------|--------|
| `suggestedCommand` fixes it | Follow diagnose; not upstream |
| Misconfig, preflight, task packet, or consumer code | Fix locally; not upstream |
| Documented v1 limit (no supervisor mail, pi-only workers) | Expected; not upstream |
| Repeatable fault after correct operator steps | Report upstream |

**Issue checklist** (sanitize secrets; minimal consumer repro):

| Field | Source |
|-------|--------|
| pi-spine version | `spine --version` or `npm list -g pi-spine` |
| Environment | `spine doctor` output |
| Commands run | Exact sequence |
| Diagnosis | `spine status --diagnose` full output |
| Journal excerpt | `spine journal` or relevant runtime journal lines |
| Expected vs actual | One line each |

If triage is ambiguous, ask the user once before filing. See `general-llm-anti-patterns.mdc` §7.3.

## v1 boundaries

- **Workers:** pi only—Cursor does not replace `spine batch start` workers
- **No concurrent orchestrators:** Do not run Taskplane batches and spine batches on the same repo
- **Human gates:** Integrate requires explicit `spine gate approve` + evidence
- **Runtime files:** Never hand-edit `.spine/batch-state.json` or `.spine/runtime/**/journal/*`

## Critical anti-patterns

### Hand-edit runtime state (CRIT)

**CRITICAL:** Batch state and journal are spine-owned.

❌ Bad: Edit `.spine/batch-state.json` to mark tasks done
✅ Good: `spine status --diagnose` → run `suggestedCommand`
⚠️ Why: Drift breaks reconcile, orphan detection, gate evidence
🔧 Fix: Use `spine batch resume`, `retry`, `abort` per diagnose
**Detect:** manual JSON edit, "fix state" without spine CLI

### False batch claims (CRIT)

**CRITICAL:** Never claim batch status without CLI output.

❌ Bad: "Batch completed successfully" without `spine status` output
✅ Good: Show command + output or state **verification pending**
⚠️ Why: False confidence; violates trust
🔧 Fix: Run `spine status --diagnose`; cite output
📍 See: `general-llm-anti-patterns.mdc` §3.8–3.9
**Detect:** batch done/running/failed without evidence

### Skip diagnose after detached ops (CRIT)

**CRITICAL:** After detached `batch start` or `resume`, run diagnose.

❌ Bad: Assume batch healthy after background start
✅ Good: `spine status --diagnose` before leaving session
⚠️ Why: Orphan workers and limbo states are common
🔧 Fix: Diagnose → follow `suggestedCommand`
**Detect:** detached start with no follow-up status check

### Integrate without gate (CRIT)

**CRITICAL:** Do not integrate before gate approval.

❌ Bad: `spine integrate` while gate pending
✅ Good: `spine gate status` → `gate approve` → `integrate`
⚠️ Why: Premature merge bypasses evidence and human approval
🔧 Fix: Complete gate FSM first
**Detect:** integrate before approve, missing test evidence

### Cursor coding during active batch (CRIT)

**CRITICAL:** Do not implement task packets in Cursor while spine batch owns them.

❌ Bad: Edit `spine-tasks/SP-014/` while batch running same scope
✅ Good: Pause batch or use manual worker only when batch inactive
⚠️ Why: Worktree/lane collisions, STATUS drift, merge conflicts
🔧 Fix: `spine batch pause` or wait; use `@spine-worker-cursor.mdc` only when batch idle
**Detect:** code edits in active task folders during running batch

### Workaround spine engine bugs locally (CRIT)

**CRITICAL:** Suspected pi-spine engine defects go upstream—not patched in consumer repos.

❌ Bad: Work around unexplained `engine_orphaned`, gate FSM bugs, or contract verifier false positives in task PROMPT or local hacks
✅ Good: Triage → search [pi-spine issues](https://github.com/beettlle/pi-spine/issues) → file with `spine doctor` + `spine status --diagnose` + journal excerpt
⚠️ Why: Engine bugs need upstream fixes; workarounds drift and hide root cause
🔧 Fix: Collect checklist from **Upstream bug reports**; ask user if triage unclear
📍 See: **Upstream bug reports** above; `general-llm-anti-patterns.mdc` §7.3
**Detect:** repeated recovery loop, same diagnosis after `suggestedCommand`, unexplained spine CLI crash

## Taskplane coexistence

Migrating from Taskplane: `spine migrate-from-taskplane`; keep `taskplane-tasks/` via config. **Never** run both orchestrators on the same repo concurrently. See [pi-spine bootstrap checklist](https://github.com/beettlle/pi-spine/blob/main/docs/adoption/bootstrap-checklist.md).

## Slash commands (in pi session)

When user works inside `pi`: `/spine`, `/spine-plan`, `/spine-status`, `/spine-gate`, `/spine-integrate`, `/spine-dashboard` mirror CLI—still prefer `spine status --diagnose` for recovery.
