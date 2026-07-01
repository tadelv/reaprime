# STATUS.md template (runner-agnostic)

Create alongside `PROMPT.md` in the same task folder. Mirror step numbers and titles from PROMPT. Some runners auto-generate STATUS from PROMPT if omitted.

```markdown
**Current Step:** Step 0: Not started
**Status:** Ready
**Last Updated:** YYYY-MM-DD
**Review Level:** 2
**Review Counter:** 0
**Iteration:** 0
**Size:** M

---

## Step 0: Design or discovery

**Status:** Not Started

- [ ] Checkbox matching PROMPT Step 0
- [ ] Second item if applicable

> ⚠️ Hydrate: Use when details depend on prior step discoveries—worker expands checkboxes when entering this step.

## Step 1: Implementation

**Status:** Not Started

#### Segment: shared-lib

- [ ] Outcome checkbox

#### Segment: api

- [ ] Outcome checkbox

## Step 2: Testing and verification

**Status:** Not Started

- [ ] Run full test suite
- [ ] Fix failures

## Step 3: Documentation and delivery

**Status:** Not Started

- [ ] Docs updated
- [ ] Completion criteria met

---

## Reviews

| Date | Step | Type | Outcome |
|------|------|------|---------|
| | | | |

## Discoveries

| Date | Finding | Impact |
|------|---------|--------|
| | | |

## Execution Log

| Date | Event | Detail |
|------|-------|--------|
| | | |

## Blockers

| Date | Blocker | Resolution |
|------|---------|------------|
| | | |

## Notes

```

## Status emoji (optional, for human scan)

| Display | Meaning |
|---------|---------|
| Ready | Not started |
| In Progress | Active step |
| Complete | Step done |

## Hydration rules

- Match PROMPT step count and titles—do not add or renumber steps at runtime.
- Expand checkboxes **within** a step when the worker discovers concrete work items.
- Prefer outcome-level checkboxes over naming every function before reading source.
- Keep STATUS and PROMPT checkboxes aligned when both are pre-hydrated at author time.

Compatible with [Taskplane status format](https://github.com/HenryLach/taskplane/blob/main/docs/reference/status-format.md).
