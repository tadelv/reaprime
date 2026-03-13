# TDD Workflow Design

**Date:** 2026-03-12
**Status:** Approved

## Goal

Introduce test-driven development as the standard development workflow for Streamline-Bridge. Define test tiers, process flow, MCP verification protocol, and tooling (skill file, scenario format, CLAUDE.md updates).

## Approach

**Layered skill:** Create a project-specific TDD workflow skill (`.claude/skills/tdd-workflow/SKILL.md`) that layers on top of the generic `superpowers:test-driven-development` skill. The project skill owns the process orchestration (tiers, phases, iteration loops); the generic skill enforces core red-green-refactor discipline.

## Test Tiers

| Tier | What | How it runs | When to use |
|------|------|-------------|-------------|
| **Unit tests** | Isolated logic — single controller, model, DAO, service | `flutter test test/path_test.dart` | Always. Every feature/fix gets unit tests. |
| **Integration tests** | Multi-component flows — wire real controllers with mock transport boundaries | `flutter test test/path_test.dart` (same runner, real collaborators, mocks at hardware edge) | When the change spans multiple controllers/services |
| **MCP verification** | API surface — REST endpoints, WebSocket streams, end-to-end through running app | Claude-driven: start app in simulate mode via MCP tools, execute scenario, verify responses | When the change affects API behavior, workflow state, or anything a skin/client consumes |

Integration tests live in `test/` alongside unit tests — no `integration_test/` directory. The difference is what they wire up.

During planning, decide which tiers apply. Not every change needs all three. Zero tiers is valid for pure documentation changes (still run `flutter analyze`).

## Process Flow

### Phase 1 — Plan & Design (before any code)
1. Explore codebase, understand the problem.
2. Design solution approach.
3. Decide which test tiers apply.
4. Sketch what tests will verify (behaviors/assertions, not full test code).
5. Present plan for user review. Iterate until accepted.

### Phase 2 — Write Tests (no implementation code yet)
1. Write MCP verification scenario as structured YAML in `test/mcp_scenarios/` (if MCP tier applies).
2. Write integration tests (if applicable) — real controllers wired together.
3. Write unit tests — isolated, one behavior per test.
4. Verify all tests fail for the right reason. Follow `superpowers:test-driven-development` discipline.

Test writing order is outside-in (API surface → multi-component → unit). This forces design from the consumer's perspective.

### Phase 3 — Implement (now write production code)
1. Write minimal implementation to make unit tests pass.
2. Run unit tests, confirm green. Run `flutter analyze`.
3. Run integration tests.
   - If failing: understand why, fix implementation (not tests), re-check unit tests green, re-check integration.
4. Run MCP verification scenario.
   - If issues: fix implementation, confirm unit + integration still green, re-run MCP.

Implementation order is inside-out (unit → integration → MCP). Build from the core outward.

### Phase 4 — Self-Review (Claude-driven, 1-3 iterations)
1. Review own code for readability, DRY, SRP.
2. Make improvements. Re-run all passing tests to confirm still green.
3. Stop after 1 pass if code is clean. Max 3 passes.

### Phase 5 — Done
1. Run full `flutter test` + `flutter analyze`.
2. Report completion with evidence (test output, MCP verification results).

## MCP Verification Protocol

### Scenario Format

Location: `test/mcp_scenarios/*.yaml`

```yaml
name: scale-connection-weight-flow
description: Verify scale discovery, connection, and weight measurement through API

preconditions:
  app_start:
    connectDevice: MockDe1
    connectScale: MockScale

steps:
  - tool: devices_list
    expect:
      status: 200
      body_contains:
        - MockScale

  - tool: machine_get_state
    expect:
      status: 200

  - tool: scale_tare
    expect:
      status: 200

postconditions:
  - app_stop
```

### Execution

Claude reads the scenario file, executes each step using MCP tools, compares actual vs expected. Reports pass/fail per step. Stops on first failure with actual vs expected details.

### Regression

Scenarios persist in `test/mcp_scenarios/`. When verifying a new feature, Claude runs both the new scenario and existing scenarios in the directory to catch regressions.

## Deliverables

1. `.claude/skills/tdd-workflow/SKILL.md` — project-specific TDD process skill
2. `test/mcp_scenarios/` — directory for persistent MCP verification scenarios
3. CLAUDE.md updates — slim Verification Loop, add test tier docs, reference skill
