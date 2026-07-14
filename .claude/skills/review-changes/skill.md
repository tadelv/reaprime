---
name: Review Changes
description: Structured code review using the code-review-graph MCP tools
---

## Review Changes

Perform a risk-aware code review using the knowledge graph.

### Steps

1. Run `detect_changes` to get risk-scored change analysis.
2. Run `get_affected_flows` to find impacted execution paths.
3. For high-risk areas, run `query_graph` with `tests_for` to check coverage.
4. Run `get_impact_radius` to understand the blast radius.

### Output Format

Group findings by risk level with: what changed, test coverage, suggested improvements, merge recommendation.
