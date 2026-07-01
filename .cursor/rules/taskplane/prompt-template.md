# PROMPT.md template (runner-agnostic)

Copy this skeleton into `{tasks-root}/{PREFIX-###-slug}/PROMPT.md`. Replace placeholders. Content above the `---` divider is immutable during execution.

```markdown
# Task: PREFIX-### — Short descriptive name

**Created:** YYYY-MM-DD
**Size:** S|M|L

## Review Level: 0|1|2|3

**Assessment:** One sentence why this level.
**Score:** N/8 — Blast radius: N, Pattern novelty: N, Security: N, Reversibility: N

## Mission

What to build or change, and why it matters. The executor starts with no chat history—include everything needed to begin.

## Dependencies

- **None**
```

Or machine-parseable forms (use consistently):

```markdown
## Dependencies

- PREFIX-002
- other-area/AREA-003
- **Task:** PREFIX-004 (short note)
- **External:** prerequisite outside the repo (e.g. service running, migration applied)
```

## Context to Read First

List only what this task needs. Use backticked paths.

**Tier 2 (area context):**

- `{tasks-root}/CONTEXT.md`

**Tier 3 (reference docs):**

- `path/to/architecture.md`
- `AGENTS.md` or project standards doc

## Environment

- **Workspace:** repo or monorepo name
- **Services required:** none, or list ports/commands

## File Scope

Paths the executor may create or modify. Batch orchestrators use this to reduce merge conflicts.

- `src/module/example.ts`
- `tests/module/example.test.ts`

## Segment DAG (optional — multi-repo only)

```markdown
## Segment DAG

Repos:
- shared-lib
- api
- web-client

Edges:
- shared-lib -> api
- api -> web-client
```

## Steps

Use `### Step N: Name`. Checkboxes must be concrete and verifiable.

### Step 0: Design or discovery (optional)

- [ ] Read listed context and confirm approach
- [ ] Document decisions in STATUS Discoveries if needed

### Step 1: Implementation

For multi-repo work, use segment markers:

#### Segment: shared-lib

- [ ] Outcome-level checkbox (not every function name unless known upfront)

#### Segment: api

- [ ] Outcome-level checkbox

### Step 2: Testing and verification

> ZERO test failures allowed unless PROMPT documents a known baseline.

- [ ] Run full project test command: `REPLACE_WITH_PROJECT_TEST_COMMAND`
- [ ] Run targeted tests for changed modules
- [ ] Fix all failures introduced by this task

### Step 3: Documentation and delivery

- [ ] Update "Must Update" docs below
- [ ] Review "Check If Affected" docs
- [ ] Log discoveries in STATUS.md
- [ ] Create completion marker only if your runner expects the worker to do so

## Documentation Requirements

**Must Update:**

- `path/to/doc.md` — reason

**Check If Affected:**

- `path/to/other.md`

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing (or documented baseline exception)
- [ ] Documentation requirements satisfied

## Git Commit Convention

All commits for this task MUST include the task ID:

- **Implementation:** `feat(PREFIX-###): description`
- **Bug fixes:** `fix(PREFIX-###): description`
- **Tests:** `test(PREFIX-###): description`
- **Checkpoints:** `checkpoint: PREFIX-### description`

## Do NOT

- Expand scope beyond this PROMPT—log tech debt in area CONTEXT.md
- Skip the Testing step
- Modify protected standards docs without user approval
- Load docs not listed in Context to Read First
- Commit without the task ID prefix

---

## Amendments (Added During Execution)

```

## Review level quick reference

| Level | Meaning |
|-------|---------|
| 0 | Trivial (docs-only, config, boilerplate) |
| 1 | Plan review before implementation |
| 2 | Plan + code review |
| 3 | Plan + code + test review |

Score each dimension 0–2: blast radius, pattern novelty, security, reversibility. Sum → 0–1=L0, 2–3=L1, 4–5=L2, 6–8=L3.

## Per-step review override (optional)

```markdown
### Step 2: Add authorization checks
> **Review override: code review** — touches auth boundaries.
```

## Checkpoint markers (optional — fewer reviews for single-deliverable tasks)

```markdown
### Step 0: Design
**Plan-review checkpoint**

### Step 4: Verify
**Code review checkpoint**
```

Compatible with [Taskplane task format](https://github.com/HenryLach/taskplane/blob/main/docs/reference/task-format.md).
