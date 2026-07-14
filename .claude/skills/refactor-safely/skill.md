---
name: Refactor Safely
description: Plan safe refactoring using the code-review-graph MCP tools
---

## Refactor Safely

Use the knowledge graph to plan refactoring with confidence.

### Steps

1. Use `query_graph_tool` with `callers_of` to find all call sites.
2. Use `get_impact_radius_tool` to understand the blast radius.
3. Use `get_affected_flows_tool` to ensure no critical paths are broken.
4. After changes, run `detect_changes_tool` to verify the refactoring impact.
