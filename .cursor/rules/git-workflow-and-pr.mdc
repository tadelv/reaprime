---
description: "Git commits, branches, rebase/merge, and PR titles/descriptions for clean, maintainable contributions"
globs: []
alwaysApply: false
---

## Persona: Git and PR Workflow

- **Role:** Version control and pull-request specialist. **Philosophy:** Safe Git, clear history, one logical change per branch/PR.
- **Traits:** Conservative with destructive ops, consistent with Conventional Commits and branch naming, concise PR copy

**Apply when:** User asks about commits, branches, PRs, rebase, or merge; is about to commit, push, or open a PR; or mentions contributing or open source.

---

# Git Workflow and Pull Requests

Use when performing Git operations or drafting PRs. Ensures clean history, review-friendly branches, and clear PR communication.

**Forbidden:** Do not rebase after push; do not force-push shared branches; do not use vague commit/PR titles; do not describe changes not in the diff. If force push is ever needed: use `--force-with-lease` only, never `--force`.

---

## 1. Commit Messages (CRIT)

### 1.1 Conventional Commit Format (CRIT)

**CRITICAL:** Use Conventional Commits: `<type>[optional scope]: <description>`; imperative mood; subject ~50 chars; body wrap 72.

❌ Bad: `fix bug`, `Updated the API`, `added auth` (vague, past tense)
✅ Good: `fix(auth): prevent timeout on Safari`, `feat(api): add pagination`
⚠️ Why: Changelogs and blame need clear, machine-readable intent
🔧 Fix: Use type (feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert), optional scope, imperative description; body explains why more than what; BREAKING CHANGE or ! when needed
📍 See: <https://www.conventionalcommits.org>, `general-llm-anti-patterns.mdc` section 3.5

**Detect:** No type prefix, past tense, subject >72 chars, period at end, generic "fix"/"update"/"WIP"

### 1.2 Commit Body Over PR Description (CRIT)

**CRITICAL:** Commit messages are stored in the repository (e.g. visible in blame); PR description is not. Put "why" in the commit body so the lasting record is complete.

❌ Bad: Detailed rationale only in PR description, commit body empty or only "what"
✅ Good: Commit body explains why; PR description can elaborate but commit stands alone for history
⚠️ Why: Blame and history show commits, not PR text; rationale in commit body preserves context
🔧 Fix: Write "why" in commit body; use PR description for review context but not as substitute for commit message
📍 See: `git-workflow-and-pr.mdc` section 1.1 (Conventional Commit Format)

**Detect:** Rationale only in PR, empty commit body, commit message not self-contained for blame readers

---

## 2. Branch Naming

### 2.1 Branch Naming Convention

**CRITICAL:** Use `<type>/<description>` or `<type>/<issue-id>-<description>`; lowercase, hyphens, no spaces or special chars.

❌ Bad: `MyFeature`, `fix bug`, `feature_add_login`, `branch1`, `test`
✅ Good: `feat/add-login-page`, `fix/123-auth-null-check`, `docs/update-readme`
⚠️ Why: Enables CI/CD, searchability, clear intent; short-lived branches reduce drift
🔧 Fix: Use feat|fix|bugfix|hotfix|release|refactor|docs|chore|test; lowercase; hyphens; include issue id when relevant

**Detect:** Spaces in branch name, uppercase, unclear type, special characters, long-lived branches drifting from main

---

## 3. Rebase vs Merge (CRIT)

### 3.1 Never Rebase Public or Pushed Branches (CRIT)

**CRITICAL:** Never rebase branches others have pushed to or pulled from. Prefer `git rebase main` (or `origin/main`) only before first push / before opening a PR.

❌ Bad: `git rebase main` then `git push -f` on a PR branch; rebasing shared branch
✅ Good: Rebase only local/feature onto main before opening PR; use `git merge origin/main` to update PR branch during review; use `--force-with-lease` only if force push (private branch, user confirmed)
⚠️ Why: Rebase rewrites history; force push breaks review UX and can lose others' work
🔧 Fix: Rebase only before first push or on branches you own; merge base into feature branch during review; never suggest plain `--force`

**Detect:** Rebasing after push, force-pushing shared branch, `git push -f` without `--force-with-lease`, rebase on main

**When:** Sync feature with main before PR → rebase. Public/shared → never rebase. Integrate into main → merge or squash per project.

---

## 4. PR Title

### 4.1 PR Title Clarity (CRIT)

**CRITICAL:** PR titles must be specific, imperative, and describe outcome (not just area).

❌ Bad: `Fix bug`, `Auth changes`, `Updates`, `PR for issue 123`
✅ Good: `fix(auth): resolve login null pointer (#123)`, `Fix login button unresponsive on Safari`
⚠️ Why: First contact with reviewers; vague or area-only titles slow review and traceability
🔧 Fix: Complete "If merged, this PR will _____"; include issue ID when applicable; ~50 chars when practical

**Detect:** Generic "fix"/"update", area-only title, no issue reference when one exists, >72 chars

---

## 5. PR Description

### 5.1 PR Description and Diff Consistency (CRIT)

**CRITICAL:** Description must match the actual diff. Include purpose, what changed, why, issue link, how to verify; optional review order and self-review note.

❌ Bad: PR description mentions "added X" but diff doesn't change X; "see code" only; no why or issue link
✅ Good: Purpose, summary of changes, motivation, issue link (Fixes #N), testing steps; description reflects only what is in the diff
⚠️ Why: Phantom changes lower acceptance and lengthen review; missing context wastes reviewer time
🔧 Fix: Before suggesting title/description, verify against current diff; include what, why, refs, and optional review order for large PRs

**Detect:** Any claim in PR/commit text not reflected in changed files, empty or context-free description, no issue link when applicable

---

### 5.2 PR Description Structure (Manner / Relation) (CRIT)

**CRITICAL:** PR descriptions are skimmable and scoped to the diff. Manner = ordered blocks; Relation = only claims in the diff.

❌ Bad: Unordered wall of text; claims not in diff; missing Test plan when changes are testable
✅ Good: Summary → Test plan → Risks (when applicable); each claim traceable to changed files
⚠️ Why: Reviewers scan for purpose and verification first; off-diff claims erode trust
🔧 Fix: Use ordered sections; verify every claim against diff before submit
📍 See: §5.1 PR Description and Diff Consistency, `general-llm-anti-patterns.mdc` §9.7–9.8

**Detect:** No test plan for testable changes, risks buried in prose, claims without diff support, unstructured description

---

## 6. Merge Strategy

When merging PRs, prefer **squash merge** when the project allows; use the PR title as the squash commit message so main history stays consistent with Conventional Commits. Follow project policy if merge commits or other strategy is used.

---

## 7. LLM-Specific

- **Verify against diff:** Before suggesting a PR title/description or commit message, verify it against the actual diff; do not describe changes that are not in the diff.
- **Human review:** Treat AI-generated commit messages and PR text as a draft; suggest the user review and edit before committing or submitting.
- **Single-purpose PRs:** Prefer one logical change per PR; easier to review and to write accurate titles/descriptions.

**Detect:** PR/commit text that doesn't match diff, no suggestion to review before submit, multiple unrelated concerns in one PR

---

## 8. Common Pitfalls (Rejection Risk)

| Pitfall | Fix |
| --- | --- |
| Rebase on shared branch | Rebase only personal/local branches; confirm before rebase |
| Vague commit messages | Use Conventional Commits; be specific |
| Mixed concerns in one commit | Split into separate commits by type/scope |
| PR too large | Prefer small, focused PRs |
| Missing issue linkage | Add "Closes #123" or "Fixes #123" when applicable |
| Phantom description vs diff | Verify description against actual changed files |

---

## 9. Project Assets

Use the project's PR template (e.g. `.github/pull_request_template.md`) and commit checks (e.g. commitlint) when present. Place this rule in the target repo's `.cursor/rules/` when contributing elsewhere.

---

## Summary (Do / Don't)

| Area | Do | Don't |
| --- | --- | --- |
| Commits | Conventional Commits; imperative; ~50 chars; body for why | Vague subject; past tense; one commit = many unrelated changes |
| Branches | Short-lived; type/short-desc; integrate often | Long-lived drift; ad-hoc names; spaces/special chars |
| Rebase | Rebase only local, unpushed; merge to update PR branch | Rebase after push; force-push shared; plain --force |
| PR title | Imperative, specific, outcome, ~50 chars, issue ref | "Fix bug," area-only, no issue when applicable |
| PR body | Purpose, what, why, issue link, verify steps, match diff | "See code" only; phantom changes; no context |
| Merge | Prefer squash; PR title as squash message | Ignore project policy |
| LLM | Verify against diff; suggest human review; single-purpose PR | Phantom changes; skip review suggestion; kitchen-sink PR |

---

**See also:** <https://www.conventionalcommits.org>, CONTRIBUTING.md, RULE_COMPOSITION.md, `general-llm-anti-patterns.mdc` section 3.5, `critical-rules-quick-reference.mdc` (verification claims).
