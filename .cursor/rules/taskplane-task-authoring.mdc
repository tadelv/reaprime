---
description: "Create Taskplane-style task packets (PROMPT.md, STATUS.md, CONTEXT.md) for autonomous execution outside Cursor. Use when asked to create, stage, queue, or plan tasks—not when implementing code."
globs: ["**/PROMPT.md", "**/STATUS.md", "**/taskplane-tasks/**", "**/docs/task-management/**"]
alwaysApply: false
---

# Taskplane task authoring

Author runnable **task packets** for execution outside this chat. Packets are runner-agnostic file contracts: an executor with a fresh context should complete the work using only PROMPT, STATUS, listed docs, and the codebase.

**Related:** `@taskplane-worker-cursor.mdc` for implementing a packet in Cursor. Templates: `@.cursor/rules/taskplane/prompt-template.md`, `@.cursor/rules/taskplane/status-template.md`.

## When this rule applies

Apply when the user asks to:

- Create, stage, queue, or plan tasks or batches
- Write or update `PROMPT.md`, `STATUS.md`, or task-area `CONTEXT.md`
- Break a feature or spec into orchestratable work items

**Do not apply for implementation.** If the user asks to implement, fix, or ship code for a feature, defer to `@taskplane-worker-cursor.mdc` unless they also want new packets authored in the same turn—then author first, implement only if explicitly requested after.

If intent is ambiguous (create tasks vs implement now), ask once.

## Orchestration artifacts vs repo docs

`PROMPT.md`, `STATUS.md`, and area `CONTEXT.md` under a tasks root are **orchestration artifacts**, not unsolicited documentation. Creating them when the user requests task work is allowed. See `documentation-policy.mdc` (Taskplane task packets exception).

Do not create unsolicited README files, change summaries, or PR writeups unless asked.

## Packet layout

```text
{tasks-root}/{PREFIX-###-slug}/
├── PROMPT.md     # Definition (immutable above --- divider)
├── STATUS.md     # Execution memory (mirrors PROMPT steps)
├── .reviews/     # Runtime — do not create at author time
└── .DONE         # Runtime — do not create at author time
```

Optional at area level:

```text
{tasks-root}/CONTEXT.md   # Next Task ID, domain state, tech-debt backlog
```

Folder naming: `PREFIX-###-short-slug` (e.g. `AUTH-014-add-role-checks`).

## Before you write

1. **Locate tasks root** — Common defaults: `taskplane-tasks/`, `docs/task-management/`. Read project config if present (task areas: path, prefix, context file; reference docs; test commands; standards paths; protected docs; never-load list). If unknown, ask the user for tasks-root, ID prefix, and full test command.
2. **Read area `CONTEXT.md`** — Use `Next Task ID` for the new task; you will increment it in the same edit pass.
3. **Pick the area** — Match task domain to the area that owns the primary files being changed. If multiple areas exist and scope is unclear, ask.

## Authoring workflow

1. **Assign ID** — `PREFIX-###` from CONTEXT; increment `Next Task ID` in `CONTEXT.md`.
2. **Assess complexity** — Score review level (table below). Do not default to Level 0 for non-trivial work.
3. **Assess size** — S (&lt;2h), M (2–4h), L (4–8h), XL (8h+). **Split XL** into multiple tasks with explicit dependencies.
4. **Create folder** — `{area.path}/{PREFIX-###-slug}/`.
5. **Write `PROMPT.md`** — Follow `@.cursor/rules/taskplane/prompt-template.md`.
6. **Write `STATUS.md`** — Mirror PROMPT steps; use `⚠️ Hydrate` on discovery-dependent steps. Follow `@.cursor/rules/taskplane/status-template.md`.
7. **Handoff** — Report the absolute path to `PROMPT.md`. Do not implement product code in the same turn unless the user explicitly asks after the packet exists.

## Review level rubric

Score each dimension **0–2**:

| Dimension | 0 (low) | 1 (medium) | 2 (high) |
|-----------|---------|------------|----------|
| Blast radius | Single file | One service/module | Multiple services |
| Pattern novelty | Existing patterns | Adapting patterns | New patterns |
| Security | No auth/sensitive data | Touches auth | Auth/crypto changes |
| Reversibility | Easy revert | Migration needed | Data model change |

| Sum | Review level |
|-----|----------------|
| 0–1 | 0 — None |
| 2–3 | 1 — Plan before code |
| 4–5 | 2 — Plan + code review |
| 6–8 | 3 — Plan + code + test review |

Document level and score in PROMPT under `## Review Level`.

## PROMPT content requirements

- **Heading:** `# Task: PREFIX-### — Name` (em dash). Required for consistent parsing across runners.
- **Mission:** What and why; self-contained for a cold-start executor.
- **Dependencies:** Machine-parseable section. Use `- **None**`, bare `PREFIX-003`, `area/PREFIX-003`, `- **Task:**`, `- **External:**`. Avoid prose-only dependency lists.
- **Context to Read First:** Minimal tiered list (area CONTEXT + only needed reference docs).
- **File Scope:** Every path or directory the executor may touch. Critical for parallel batches—overlapping scope forces serial execution or merge risk.
- **Steps:** `### Step N: Title` with `- [ ]` checkboxes. Each checkbox = one verifiable outcome, not vague intent.
- **Testing step:** Include the project's real test command (e.g. `npm test`, `cargo test`, `pytest`). Full suite as quality gate; targeted tests belong in implementation steps.
- **Documentation Requirements:** Must Update / Check If Affected lists.
- **Completion Criteria**, **Git Commit Convention** (task ID in every commit), **Do NOT** guardrails.
- **Divider:** `---` then empty `## Amendments (Added During Execution)` — nothing below the divider at author time.

### Checkbox quality

| Weak (avoid) | Strong (prefer) |
|--------------|-----------------|
| Add validation | Add `validateUserInput()` in `UserService.ts` and unit tests in `UserService.test.ts` |
| Update API | Register `GET /health` in `routes.ts` returning 200 and `{ status: "ok" }` |

If the executor might claim work "already exists," say: verify behavior and tests, or implement if missing.

### Step count

- Ideal: 3–8 steps, 3–10 checkboxes per implementation step.
- More than ~3 major implementation steps without a split → consider multiple tasks with dependencies.

## STATUS.md requirements

- Mirror PROMPT step numbers and titles exactly.
- Pre-hydrate checkboxes where outcomes are known; use `⚠️ Hydrate` where Step N depends on discoveries from Step N-1.
- Do not pre-create 15+ micro-checkboxes naming every function before anyone reads the codebase.
- Workers must not add, remove, or renumber steps at runtime—design the full step list in PROMPT up front.

## Batch planning (multiple tasks)

When authoring several packets for one initiative:

1. Draw dependency order first (what blocks what).
2. Minimize overlapping **File Scope** across tasks that may run in parallel.
3. Use area-qualified IDs (`billing/BIL-004`) when prefixes collide across areas.
4. Split XL work into M-sized tasks with explicit `## Dependencies` chains.

## Multi-repo tasks

When work spans multiple repositories or top-level packages:

- Use `#### Segment: {id}` under each step (segment id must match project workspace config).
- Order: shared/common work → consumers → integration/docs in the packet repo.
- Optional `## Segment DAG` with `Repos:` and `Edges:` when intra-task ordering matters.
- More than ~10 segments → split into separate tasks with dependencies.

## Tiered context loading (put in PROMPT)

| Tier | Content | When loaded |
|------|---------|-------------|
| 1 | PROMPT + STATUS | Always |
| 2 | Area CONTEXT.md | When listed in Context to Read First |
| 3 | Reference docs | Only paths listed for this task |

Never list docs from the project's "never load" / exclude list.

## Standards for executors outside Cursor

Executors will **not** load `.cursor/rules/`. Copy what they need into PROMPT:

- Pointers to `AGENTS.md`, language standards, or team docs in **Context to Read First**
- Exact test and lint commands in the Testing step
- Coding conventions in **Do NOT** or Mission where it prevents drift

## Definition of ready (check before handoff)

- [ ] `Next Task ID` incremented in area `CONTEXT.md`
- [ ] Folder name matches `PREFIX-###-slug`
- [ ] PROMPT has parseable heading, Mission, Dependencies, File Scope, steps with checkboxes, Testing step with real command, Do NOT, Completion Criteria, commit convention, Amendments placeholder
- [ ] STATUS mirrors PROMPT steps (and segments if multi-repo)
- [ ] Review level assigned with justification (not 0 by default for M+ work)
- [ ] Size is S/M/L, or XL was split
- [ ] No secrets in PROMPT; no `.DONE` / `.reviews/` created at author time
- [ ] Handoff path to `PROMPT.md` reported
- [ ] No product code implemented unless user explicitly requested after authoring

## Common mistakes to avoid

- Implementing the feature instead of writing the packet
- Vague checkboxes or missing File Scope
- STATUS steps out of sync with PROMPT
- Non-parseable Dependencies section
- Forgetting to increment `Next Task ID`
- Embedding API keys or credentials in PROMPT
- Creating runtime completion artifacts at author time
- Putting orchestration instructions in PROMPT instead of outcomes (the runner handles loops and reviews)
- Leaving standards only in Cursor rules with no reference in PROMPT

## External format reference

Packets follow conventions compatible with the [Taskplane task format](https://github.com/HenryLach/taskplane/blob/main/docs/reference/task-format.md) and [status format](https://github.com/HenryLach/taskplane/blob/main/docs/reference/status-format.md). Teams using other runners can map the same files to their tooling.

## Minimal example (structure only)

```markdown
# Task: APP-007 — Add health endpoint

**Created:** 2026-05-26
**Size:** S

## Review Level: 1

## Mission
Add GET /health returning 200 for load balancers.

## Dependencies
- **None**

## File Scope
- `src/routes/health.ts`

## Steps
### Step 0: Implement
- [ ] Add handler and register route

### Step 1: Verify
- [ ] Run `npm test`

## Completion Criteria
- [ ] Tests pass

---

## Amendments (Added During Execution)
```
