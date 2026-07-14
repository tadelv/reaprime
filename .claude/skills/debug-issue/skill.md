---
name: Debug Issue
description: Systematically debug issues using the code-review-graph MCP tools
---

## Debug Issue

Use the knowledge graph to trace and debug issues.

### Steps

1. Use `semantic_search_nodes` to find code related to the issue.
2. Use `query_graph` with `callers_of` and `callees_of` to trace call chains.
3. Use `detect_changes` to check if recent changes caused the issue.
4. Use `get_impact_radius` on suspected files to see what else is affected.
5. Use `get_affected_flows` to find impacted execution paths.
