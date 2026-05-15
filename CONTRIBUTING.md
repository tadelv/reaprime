# Contributing to Decent.app

Thanks for taking the time to contribute. This guide covers the basics so your PR lands smoothly.

> **Naming note:** The display name is **Decent.app**. The repo, package, and bundle ID still use legacy `reaprime` / `streamline-bridge` identifiers — see the naming table in [`CLAUDE.md`](CLAUDE.md) before renaming anything.

## Before you start

For non-trivial features, open an issue first to align on scope. Small fixes can go straight to a PR.

## Local setup

Requirements:

- Flutter (stable channel)
- Node.js 20+ (for the bundled DYE2 plugin)
- Optional: a DE1 / Bengle machine and a compatible scale, or use simulated devices.

```bash
flutter pub get
(cd packages/dye2-plugin && npm ci && npm run build)

# Run with simulated hardware (no machine/scale required):
flutter run --dart-define=simulate=1
```

See [`CLAUDE.md`](CLAUDE.md) for the full command reference and architecture overview.

## Branch & PR workflow

- Branch from `main`. Push the branch to your fork and open a PR against `tadelv/reaprime:main`.
- Keep PRs focused — one feature or fix per PR.
- Reference the issue you're closing in the PR description (`Fixes #123`).
- A maintainer will review; expect a few rounds of feedback.

## Required checks

Every PR runs through [`.github/workflows/pr-checks.yml`](.github/workflows/pr-checks.yml). Before pushing, run the same checks locally:

```bash
dart format --output=none --set-exit-if-changed lib test  # advisory for now
flutter analyze
flutter test
(cd packages/dye2-plugin && npm run build)
```

`dart format` is currently **advisory** in CI — the codebase predates the Dart 3.7 "tall style" formatter and a mass-reformat hasn't happened yet. Format your own changes (`dart format lib test`) but don't reformat untouched files in the same PR.

## Tests

The project uses three test tiers:

| Tier | Where | Mocks |
|------|-------|-------|
| Unit | `test/` | Direct collaborators |
| Integration | `test/integration/` | Only the transport edge |
| End-to-end | `.agents/skills/decent-app/scenarios/` (markdown recipes) | App runs in `simulate=1` mode |

**New behavior needs a test.** API handlers in `lib/src/services/webserver/` have a strong unit-test convention — see `test/services/webserver/de1handler_cup_warmer_test.dart` for a template.

For the end-to-end smoke-test recipe (start app, drive it via `curl` / `websocat`), see [`.agents/skills/decent-app/verification.md`](.agents/skills/decent-app/verification.md).

## Documentation obligations

These are not optional — the spec and docs are part of the API contract:

- **REST or WebSocket change** → update `assets/api/rest_v1.yml` or `assets/api/websocket_v1.yml` **in the same PR**.
- **User-facing API change** → update `doc/Api.md`.
- **Plugin / skin / profile / device-management surface change** → update the matching file under `doc/`.

Stale specs mislead clients and downstream agents.

## Code style

- `dart format` is the source of truth. CI fails on unformatted code.
- `flutter analyze` must be clean. Don't merge with new warnings.
- No 3rd-party BLE library imports outside `lib/src/services/ble/` — wrap library-specific types at the transport boundary.
- Constructor dependency injection, no service locators.
- See [`CLAUDE.md`](CLAUDE.md) → *Conventions & Gotchas* for the full list (RxDart patterns, StreamBuilder rules, BLE discovery, workflow dual-representation, etc.).

## Commit messages

Conventional Commits style (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`). Keep the subject ≤72 chars; explain the *why* in the body when it isn't obvious from the diff.

## License & sign-off

By submitting a PR you agree your contribution is licensed under the same terms as the rest of the repository. No CLA required.

## Questions

Open an issue or start a discussion. For agent-specific guidance (Claude Code / Cursor / etc.), see `AGENTS.md` and `CLAUDE.md`.
