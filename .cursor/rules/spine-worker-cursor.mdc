---
description: "Manually execute a pi-spine task packet in Cursor when no spine batch is active: honor Contract, Testing step, File Scope, STATUS discipline. Use when user @PROMPT.md under spine tasks root and asks to implement—not when spine batch is running or user wants packet authoring."
alwaysApply: false
---

# pi-spine worker (Cursor, manual)

Manually execute a **spine task packet** in Cursor when **no spine batch** is active on the same tasks. Inherits the Taskplane worker loop; adds spine **Contract** and Testing-step requirements.

**Related:** `@taskplane-worker-cursor.mdc` (execution loop—follow it); `@spine-task-authoring.mdc` (authoring); `@spine-operator-cursor.mdc` (batch ops). Verification: `general-llm-anti-patterns.mdc` §3.8–3.9.

Manual activation: `@spine-worker-cursor`.

## When this rule applies

Apply when the user:

- `@PROMPT.md` under the spine tasks root and asks to implement
- References `SP-###` for in-Cursor work

**Do not apply when:**

- User wants new packets → `@spine-task-authoring.mdc`
- User wants batch/gate/integrate → `@spine-operator-cursor.mdc`
- `spine status` shows an **active batch** on the same task scope → stop; use operator rule or wait

## Startup (every session)

1. Read `.spine/spine-config.json` — `paths.tasksRoot`, `testing.*`, `contract.*`.
2. Read **full `PROMPT.md`** — Mission, Dependencies, File Scope, **## Contract**, Do NOT, Testing step, Completion Criteria.
3. Read **`STATUS.md`** — current step, first unchecked checkbox.
4. Load only docs in **Context to Read First**.
5. Confirm dependencies satisfied (`dependencies.json` + prior tasks merged).

If a spine batch is running on overlapping tasks, report conflict and defer to `@spine-operator-cursor.mdc`.

## Execution loop

Follow `@taskplane-worker-cursor.mdc`:

1. One checkbox at a time within current step.
2. Implement only within **File Scope**.
3. Update **STATUS** honestly at step boundaries.
4. Run tests per PROMPT; on Testing step run **exact** command(s).
5. Commits: `feat(SP-###): …` per Git Commit Convention.
6. Show test/build output or state **verification pending**.

## Spine additions (beyond Taskplane worker)

### Contract table

Satisfy every field in **## Contract** before claiming done:

| Field | Worker action |
|-------|----------------|
| `testCommand` | Run on Testing step; show output |
| `fileScopeMustChange` | Ensure each path has intended changes |
| `fileScopeMustNotChange` | Do not edit; if required, escalate |
| `completionCriteria` | Map to Completion Criteria checkboxes |

Legacy `TP-*` tasks may omit Contract when `contract.legacyTaskIdPrefixes` includes `TP-`.

### Testing & Verification step

Mandatory penultimate step (SP-075). Use `testing.testWithCoverage` from config when Contract references coverage gate.

### Completion artifacts

- Create **`.DONE`** only when PROMPT assigns it to the worker and no batch runner creates it.
- Do **not** call `spine_review_step`—that is a **pi extension tool** for batch workers. In Cursor, honor Review Level with self-review; user may run batch review separately.

### Batch conflict guard (CRIT)

**CRITICAL:** Do not edit packets under an active spine batch.

❌ Bad: Implement `SP-014` while `spine status` shows it `running` in a batch
✅ Good: Pause batch, wait for completion, or let pi worker finish
⚠️ Why: Lane worktree is source of truth during batch
🔧 Fix: `spine batch pause` or operator diagnose first
**Detect:** concurrent Cursor edits + running batch on same task ID

## End state

Report: changed paths, Contract fields satisfied, test evidence or verification pending, remaining checkboxes. Not a generic "done." See `general-llm-anti-patterns.mdc` §9.8.

## Common mistakes

- Ignoring Contract `fileScopeMustNotChange`
- Skipping Testing step or using wrong command
- Checking boxes without evidence
- Implementing while spine batch owns the task
- Calling pi-only review tools from Cursor
- False "all tests pass" claims
- Spine CLI/tooling defects during manual work → defer to `@spine-operator-cursor.mdc` upstream reporting; do not workaround in task code
