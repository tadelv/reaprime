# Contributing to Decent.app

Thanks for contributing. This guide tells you what's required to land a PR — items marked **(required)** are hard gates, not suggestions.

> **Naming note:** The display name is **Decent.app**. The repo, package, and bundle ID still use legacy `reaprime` / `streamline-bridge` identifiers. See the naming table in [`CLAUDE.md`](CLAUDE.md) before renaming anything.

## Quick Reference

| What | Where |
|------|-------|
| Architecture & conventions | [`CLAUDE.md`](CLAUDE.md) |
| PR template | [`.github/pull_request_template.md`](.github/pull_request_template.md) |
| API specs (authoritative) | `assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml` |
| API docs | [`doc/Api.md`](doc/Api.md) |
| Dev-loop scripts | `scripts/sb-dev.sh` (macOS/Linux) |
| CI checks | [`.github/workflows/pr-checks.yml`](.github/workflows/pr-checks.yml) |
| Agent guidance (Cursor, Copilot, etc.) | [`AGENTS.md`](AGENTS.md) |

## Before You Start

- **Non-trivial features:** Open an issue first to align on scope.
- **Small fixes** (typos, one-line bugs): Go straight to a PR.
- **Read [`CLAUDE.md`](CLAUDE.md)** — it covers architecture, conventions, test patterns, and gotchas. Agents and humans both need it.

## Local Setup

Requirements: Flutter (stable), Node.js 20+ (for the DYE2 bundled plugin).

```bash
flutter pub get
(cd packages/dye2-plugin && npm ci && npm run build)

# Run with simulated hardware (no DE1 / scale required):
flutter run --dart-define=simulate=1
```

See [`CLAUDE.md`](CLAUDE.md) for the full command reference.

## Branching & PRs

- Branch from `main`. Push to your fork, open a PR against `tadelv/reaprime:main`.
- One feature or fix per PR. No bundling unrelated changes.
- Reference the issue: `Fixes #123` or `Related #123`.
- A maintainer will review. Expect a few rounds of feedback.
- **Do not push directly to `main`** — branch protection is active, and even with push access, direct pushes bypass reviews and CI.

## Guardrails (required)

These are hard gates. PRs that skip them will be returned.

### 1. Tests

**New behavior needs a test.** Bug fixes need a regression test.

| Tier | Location | When required |
|------|----------|---------------|
| Unit | `test/` | New logic, models, handlers, DAOs |
| Integration | `test/` (mock transport edge) | Multi-component flows |
| End-to-end | `.agents/skills/decent-app/scenarios/` | API surface changes |

Web server handlers have a strong unit-test convention — see `test/services/webserver/de1handler_cup_warmer_test.dart` for the pattern.

### 2. Spec & Docs (required)

**Every API change must update the spec in the same PR.** The spec is authoritative — stale spec = stale agent knowledge.

| Change | Update this |
|--------|-------------|
| REST endpoint added/changed | `assets/api/rest_v1.yml` + `doc/Api.md` |
| WebSocket topic added/changed | `assets/api/websocket_v1.yml` + `doc/Api.md` |
| Plugin event/API changed | `doc/Plugins.md` |
| Skin behavior changed | `doc/Skins.md` |
| Profile handling changed | `doc/Profiles.md` |
| Device discovery/connection changed | `doc/DeviceManagement.md` |

### 3. Local Gates (required)

Run these before pushing. Same checks that CI runs:

```bash
flutter analyze                          # must be clean — no new warnings
flutter test                             # all must pass
(cd packages/dye2-plugin && npm run build)  # plugin must build
```

`dart format` is currently **advisory** in CI — the codebase predates the Dart 3.7 "tall style" formatter. Format your own changes (`dart format lib test`) but don't reformat untouched files in the same PR.

### 4. Architecture Boundaries (required)

- **No 3rd-party BLE imports** outside `lib/src/services/ble/`. Wrap library-specific types at the transport boundary.
- **Constructor dependency injection** — no service locators.
- **Single Responsibility** — each controller/service has one job.
- See [`CLAUDE.md` → Conventions & Gotchas](CLAUDE.md) for the full list.

### 5. PR Template (required)

Fill out the PR template. Sections marked `(required)` must be completed. The template lives at [`.github/pull_request_template.md`](.github/pull_request_template.md).

## Code Style

- `dart format` is the source of truth. Format your changes.
- `flutter analyze` must be clean. Don't merge with new warnings.
- Follow existing patterns in the file you're editing — don't introduce a different style.
- Commits: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`). Subject ≤72 chars. Explain the *why* in the body.

## Commit Messages

```
feat: add cup warmer temperature control endpoint

Added GET/PUT /api/v1/de1/cup_warmer with temperature range
validation (0–80°C). Updates rest_v1.yml spec and Api.md.
```

## License & Sign-Off

By submitting a PR you agree your contribution is licensed under the same terms as the repository. No CLA required.

## Questions

Open an issue or start a discussion. For agent-specific guidance, see [`AGENTS.md`](AGENTS.md) and [`CLAUDE.md`](CLAUDE.md).
