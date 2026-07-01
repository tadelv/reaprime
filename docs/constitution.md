# reaprime — Constitution

**Last Updated:** 2026-07-01

Upstream principles for this project. Edit this file before decomposing work into spine task packets. Agents load it via `referenceDocs` in `.spine/spine-config.json`.

---

## Mission

Describe what this project delivers and who it serves. One or two sentences.

---

## Guiding principles

### Simplicity

Prefer the smallest change that satisfies the requirement. Delete before you abstract.

### Testing

- Every behavior change includes a test or explicit verification step in the task contract.
- Run the project's test command before marking work complete.
- Do not claim tests pass without evidence.

### User experience

- Optimize for the operator and end-user path, not internal convenience.
- Failures must be visible, actionable, and safe by default.

### Performance

- Avoid I/O in loops; batch reads and writes.
- Measure before optimizing hot paths.

### Security

- No secrets in source control.
- Validate untrusted input at system boundaries.

---

## Non-negotiable rules

1. **Scope discipline** — Task workers stay within PROMPT File Scope unless the operator amends the packet.
2. **No silent failures** — Errors propagate with context; do not swallow exceptions.
3. **Honest verification** — Build and test claims require output or "verification pending."
4. **Reversibility** — Prefer changes that can be reverted without data loss.

---

## How this file is used

| Consumer | Usage |
|----------|-------|
| Task authoring | Mission and "Context to Read First" in `PROMPT.md` |
| Workers | Injected when listed in `referenceDocs` (not in `neverLoad`) |
| Reviewers | Principles inform plan/code review; reviewers do not auto-load `referenceDocs` |

Optional: align with [spec-kit](https://github.com/github/spec-kit) `.specify/memory/constitution.md` if you use Path 4 upstream authoring. pi-spine does not require spec-kit.
