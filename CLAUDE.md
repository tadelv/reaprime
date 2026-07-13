# CLAUDE.md

@AGENTS.md

## Claude-Specific

### Commands

```bash
# Run
./flutter_with_commit.sh run              # Standard (injects git commit version)
flutter run --dart-define=simulate=1      # All simulated devices
flutter run --dart-define=simulate=machine,scale  # Specific types

# Test & Lint
flutter test                              # All tests
flutter test test/unit_test.dart          # Specific file
flutter analyze                           # Static analysis

# Build (Linux via Docker/Colima)
make build-arm                            # ARM64
make build-amd                            # x86_64
make dual-build                           # Both
```

### Branching

**Before any planning or implementation, always ask the user:**
1. **Branch strategy:** New branch, worktree, or current branch?
2. **Completion strategy:** PR, local merge to main, or leave as-is?

**Do not push to remote or create PRs until the user explicitly instructs you to.** Commit locally as needed, but wait for the user to say when to push.

**Do not assume.** `main` has branch protection requiring PRs. Pushing directly bypasses protections.

**Worktree gotcha:** Worktree branches track `origin/main` — pushing will push directly to `main`. To create a proper PR from a worktree:
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
