---
description: "Execute a Taskplane-style task packet in Cursor: read PROMPT.md and STATUS.md, stay within File Scope, update checkboxes honestly, run verification before claiming done. Use when implementing or executing a task—not when creating new task packets."
alwaysApply: false
---

# Taskplane worker (Cursor)

Execute work defined in a **task packet** (`PROMPT.md` + `STATUS.md`). The PROMPT is the contract; STATUS is your memory between turns. Stay within scope; verify before claiming done.

**Related:** `@taskplane-task-authoring.mdc` for creating packets. Universal verification rules: `general-llm-anti-patterns.mdc` sections 3.8 and 3.9.

Manual activation: `@taskplane-worker-cursor` in chat when the agent does not auto-select this rule.

## When this rule applies

Apply when the user:

- References a task ID (`PREFIX-###`) or `@PROMPT.md`
- Asks to execute, implement, or continue a staged task
- Works from a task folder with active PROMPT/STATUS

**Do not apply** when the user only wants new packets authored—use `@taskplane-task-authoring.mdc`.

If the user authored packets for an external runner and did not ask you to implement in Cursor, do not start coding unless they explicitly request it.

## Startup (every session)

1. Read **full `PROMPT.md`** — Mission, Dependencies, Context to Read First, File Scope, Do NOT, Testing step, Completion Criteria, Review Level.
2. Read **`STATUS.md`** — Current step, first unchecked checkbox in scope.
3. Load **only** docs listed in Context to Read First (plus files needed for the current checkbox).
4. Confirm **dependencies** are satisfied (prior tasks merged, external prerequisites met). If blocked, say so and stop.

Do not load the entire codebase when PROMPT lists specific paths.

## Execution loop

1. **One checkbox at a time** within the current step (or current segment in multi-repo steps).
2. **Implement** only within File Scope.
3. **Update STATUS** — Mark `- [x]` when the outcome is truly done; update step status if your workflow uses it.
4. **Tests** — At step boundaries, run targeted tests when PROMPT implies them. On the dedicated Testing step, run the **exact** command(s) written in PROMPT.
5. **Commits** — Use the task ID prefix from PROMPT's Git Commit Convention at step boundaries when committing (not necessarily after every checkbox).
6. **Verification claims** — Show test/build output or state **verification pending**. Never claim tests pass or builds succeed without evidence.

## PROMPT is the contract

- Content **above** the `---` divider is canonical. Do not expand scope, add steps, or rewrite Mission without **explicit user approval**.
- **Amendments** section: only for reporting contradictions or missing prerequisites—escalate to the user, do not use it for scope creep.
- **Do not** add, remove, or renumber steps in PROMPT or STATUS at runtime. The step list is fixed at author time.
- **Hydration** — You may add checkboxes **within** the current step when you discover concrete work after reading source. Prefer outcome-level items, not a line-by-line implementation journal. Commit STATUS updates when your team relies on STATUS for crash recovery.

## File scope and discoveries

- Create and modify only paths under **File Scope** (and paths logically required to complete a scoped change, e.g. imports—if unsure, ask).
- Log unexpected findings in STATUS **Discoveries** table.
- Out-of-scope needs → ask the user or add a bullet to area `CONTEXT.md` tech debt—no drive-by refactors.

## Review levels (generic)

Interpret **Review Level** from PROMPT:

| Level | Your behavior in Cursor |
|-------|-------------------------|
| 0 | Implement and test; no formal plan gate unless you choose a quick self-check |
| 1 | Brief plan in chat or STATUS Notes before coding the step; then implement |
| 2 | Plan before implementation steps; after code, self-review against File Scope and Mission before marking checkboxes |
| 3 | As 2, plus explicit test-review pass on the Testing step |

Honor per-step lines like `> **Review override: code review**` and checkpoint markers (`**Plan-review checkpoint**`, `**Code review checkpoint**`) in PROMPT.

If an **external runner** performs cross-model reviews, do not duplicate that pipeline in chat unless PROMPT asks you to; implement REVISE feedback when the user provides it.

## Multi-repo segments

When PROMPT uses `#### Segment: {id}`:

- Complete segment work in dependency order within the step.
- Do not cross into another repo's segment until the PROMPT order allows it.

## Documentation and completion

- Complete **Must Update** and review **Check If Affected** lists in PROMPT before claiming done.
- Satisfy all **Completion Criteria** checkboxes.
- Create `.DONE` or other completion markers **only** if PROMPT assigns that to the worker and your runner does not create them automatically.

End state: report what changed (paths), test evidence or explicit verification pending with commands attempted, remaining unchecked items if any. Not a generic "done." See `general-llm-anti-patterns.mdc` §9.8.

## Common mistakes to avoid

- Checking boxes without corresponding code, tests, or doc updates
- Claiming "already implemented" without reading code and running tests
- Skipping the Testing step or using a different command than PROMPT specifies
- Editing PROMPT to reduce work instead of asking the user
- Adding new steps to STATUS that never existed in PROMPT
- Ignoring File Scope
- Loading `@codebase` when PROMPT lists three files
- Mixing packet authoring and implementation in one turn without user direction
- False "all tests pass" / "builds clean" claims
- End-state violates **Quantity**: missing evidence, paths, or verification status (§9.8)
- Scope recap essay violates **Relation**: user needs contract status, not narration (§9.7)

## Handoff to external runner

When the user created packets in Cursor for execution elsewhere:

- Do not partially implement unless asked.
- Ensure PROMPT and STATUS are consistent and Definition of Ready is met (`@taskplane-task-authoring.mdc`).
- Report the packet path; the user runs their chosen orchestrator.

## Related rules

- `@taskplane-task-authoring.mdc` — packet creation
- Language-specific `.mdc` files for code under File Scope
- `git-workflow-and-pr.mdc` — commits and PRs when applicable
- `general-llm-anti-patterns.mdc` — false compilation/test claims, silent failures
