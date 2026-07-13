# Agent Instructions

Use `doc/AI_REPO_MAP.md` first for orientation. Read broader docs only when the task needs them.

## Workflow

### Starting Work

**Before any planning or implementation, always ask the user:**
1. **Branch strategy:** New branch, worktree, or current branch?
2. **Completion strategy:** PR, local merge to main, or leave as-is?

**Do not push to remote or create PRs until the user explicitly instructs you to.** Commit locally as needed, but wait.

**`main` has branch protection.** Pushing directly bypasses protections — always use PRs.

**Worktree gotcha:** Worktree branches track `origin/main` — pushing will push directly to `main`. Create a PR:
```bash
git push -u origin HEAD:feature/my-branch-name
gh pr create --base main
```

### Planning

For non-trivial features or fixes:
1. Explore the codebase and design the approach.
2. Write a plan in `doc/plans/` covering: steps, files to change, architecture considerations, testing.
3. Present to user for review. Iterate until approved. Only then implement.

**Skip planning only for:** simple typo fixes, single-line changes, or tasks with very specific instructions.

### During Implementation

- Plan with the user before complex or risky operations.
- Test-first: write tests before implementation.
- Preserve existing user changes. Do not revert unrelated work.
- Match existing code style. Do not refactor adjacent code unless the task demands it.
- Update `assets/api/rest_v1.yml` or `assets/api/websocket_v1.yml` in the same commit as endpoint changes.
- Use `rg` (ripgrep) for targeted code search before opening large files: `rg -n "symbolName" lib/`. When `rg` is not installed, fall back to `grep -rn`. Use this for finding constants, command handlers, UI labels, and protocol definitions — one `rg` call replaces reading entire files.
- Use `rtk` (https://github.com/rtk-ai/rtk) to compress noisy command output when installed. Once set up (`brew install rtk && rtk init -g --agent pi`), Bash commands auto-rewrite — `git status` becomes `rtk git status`, `flutter test` becomes `rtk flutter test`. Saves ~80% of tokens on build, test, git, and diff output. When `rtk` is not installed, commands run normally — no workflow change needed.

### Verification

After every meaningful code change:
1. Run relevant tests + `flutter analyze`. Fix immediately if anything fails.
2. Run full `flutter test` before committing and before claiming done.
3. Evidence before assertions — show test output, not just "tests pass."

For API/spec changes, smoke-test via `scripts/sb-dev.sh` + `curl`/`websocat`. See `.agents/skills/decent-app/verification.md`.

### Pre-Commit / Pre-PR Checklist

**Before opening a PR, merging locally, or considering work done:**
0. **Fill out the PR template** at `.github/pull_request_template.md` — sections marked required are hard gates. See `CONTRIBUTING.md`.
1. **Archive design docs** from `doc/plans/` to `doc/plans/archive/<meaningful-subfolder-name>/`. Design docs are worth keeping (the *why*). Implementation plans (step-by-step task lists) are not — delete them.
2. **Check doc updates:** `doc/Api.md` if endpoints changed, `doc/Skins.md` if skin behavior changed, `doc/Plugins.md` if events changed, `doc/Profiles.md` if profile handling changed, `doc/DeviceManagement.md` if device flows changed.

All three steps are required, not optional.

## Hard Rules

- Never import 3rd-party BLE libraries (e.g. `universal_ble`) outside `lib/src/services/ble/`.
- All BLE operations use 128-bit UUID format.
- Scale write paths must catch `DeviceNotConnectedException` at the lowest-level write helper.
- Keep Flutter build and run flows non-interactive. Prefer `--dart-define=simulate=1` for smoke tests.
- Use prefixed imports for domain models that share names with Drift-generated code: `import '...shot_record.dart' as domain;` or `hide Workflow` on the database import.
- No emojis in comments or documentation.

## Code Style

- Do not add explanatory comments to new or substantially rewritten code; use clear names and small functions. Preserve existing comments and required notices.
- Put rationale, hardware constraints, and debugging history in the matching `doc/AI_*_NOTES.md` file.
- Prefer immutability when practical.
- Constructor dependency injection — no service locators.
- Stream subscriptions always cancelled in `dispose()`.

## Vocabulary

Use existing project terminology. Match the naming in `doc/` and the AI_* files. Examples: "ConnectionManager phases" not "connection lifecycle states", "transport abstraction" not "BLE wrapper", "simulated devices" not "mock hardware mode".

If your output contradicts documented architecture or conventions, surface it explicitly rather than silently overriding.

## Tracking

**For contributors:** GitHub Issues on `tadelv/reaprime` is the canonical issue tracker. Open issues, feature requests, and bug reports there.

**For the maintainer:** A personal Obsidian vault is used for priority tracking and sprint planning. Use the `obsidian-todo-sync` skill for maintainer task management. For public-facing issue work (triage, labeling, closing), use GitHub Issues (`gh issue` commands).

**Triage labels** (used on `tadelv/reaprime`):

| Label | Meaning |
|-------|---------|
| `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | Fully specified, ready for an AFK agent |
| `ready-for-human` | Requires human implementation |
| `wontfix` | Will not be actioned |

## Deep References

- Fast file routing: `doc/AI_REPO_MAP.md`.
- BLE footguns, transport threading, connection lifecycle: `doc/AI_BLE_NOTES.md`.
- Build, flash, simulate, platform quirks: `doc/AI_BUILD_NOTES.md`.
- REST/WS API contracts and compat: `doc/AI_API_NOTES.md`.
- Drift DB schema, migrations, SharedPreferences: `doc/AI_STORAGE_NOTES.md`.
- Crashlytics triage and debugging: `doc/AI_DEBUG_NOTES.md`.
- Test tiers, widget patterns, mock helpers: `doc/AI_TESTING_NOTES.md`.
- Full project docs: `doc/Api.md`, `doc/Skins.md`, `doc/Plugins.md`, `doc/Profiles.md`, `doc/DeviceManagement.md`, `doc/RELEASE.md`.
- Contributing: `CONTRIBUTING.md`.
- Dev-loop skill: `.agents/skills/decent-app/SKILL.md`.
- API specs: `assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml`.
- Archived design docs: `doc/plans/archive/` (the *why* behind shipped features).

## Naming Reference

| Layer | Value |
|-------|-------|
| User-facing name | **Decent.app** (short: "Decent") |
| Dart package name | `reaprime` |
| Plugin file extension | `.reaplugin` |
| Bundle ID | `net.tadel.reaprime` |
| Database name | `streamline_bridge` |
| GitHub repo | `tadelv/reaprime` |

## Don't

- Don't push directly to `main`. Use PRs.
- Don't import BLE libraries outside the transport layer.
- Don't create new Drift tables without a schema version bump + migration.
- Don't add API endpoints without updating the OpenAPI/AsyncAPI spec in the same commit.
- Don't add new global state without a clear ownership boundary.
- Don't `--amend` or force-push on `main`.
- Don't create `CONTEXT.md` or `doc/adr/` — `AGENTS.md` + `doc/` are the equivalents.
