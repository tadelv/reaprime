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

Ask the user before creating branches: new branch, worktree, or current branch? Ask before pushing or creating PRs.

### Planning

For non-trivial features, explore the codebase and write a plan in `doc/plans/`. Present to user before implementing.

### Verification

Every change must pass `flutter test` and `flutter analyze`. For API/spec changes, smoke-test via `scripts/sb-dev.sh` + `curl`/`websocat`.
