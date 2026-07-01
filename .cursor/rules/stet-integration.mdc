---
description: "Stet CLI usage - commands and dismiss reasons for Cursor and stet-assisted review"
alwaysApply: false
---

# Stet integration

When the user asks to dismiss findings, run stet, or triage reviews, use the commands and dismiss reasons below.

## Commands

| Command | Description |
|---------|-------------|
| `stet doctor` | Verify Ollama, Git, models |
| `stet start [ref]` | Start review from baseline |
| `stet run` | Re-run incremental review |
| `stet finish` | Persist state, clean up |
| `stet list` | List active findings with IDs |
| `stet status` | Show session status |
| `stet dismiss <id> [reason]` | Mark finding dismissed; prefer giving a reason (feeds optimize/shadowing). Also: `stet rerun`, `stet cleanup`, `stet optimize`. |

## Dismiss reasons

Valid values for `stet dismiss <id> <reason>`: `false_positive`, `already_correct`, `wrong_suggestion`, `out_of_scope`.

| Reason | Use when |
|--------|----------|
| **false_positive** | Not a real issue; model misread; redundant or low-signal nit. |
| **already_correct** | Code already correct; concern addressed; finding about removed lines fixed by the change. |
| **wrong_suggestion** | Suggestion wrong or harmful (wrong tool, would make code inconsistent). |
| **out_of_scope** | Wrong scope (e.g. generated files, meta/curated docs). |

**Quick pick:** Worse/inconsistent → `wrong_suggestion`; wrong scope → `out_of_scope`; already correct → `already_correct`; else → `false_positive`.

❌ Bad: `stet dismiss abc123` with no reason when user said "not useful"; or using a reason that doesn't match (e.g. wrong_suggestion when it's noise).
✅ Good: `stet dismiss abc123 false_positive` (or the reason that matches); prefer giving a reason.
📍 See: Project `docs/review-quality.md` (or stet README) for examples.

## Review model (when stet injects this rule)

Report only actionable findings; prefer fewer, high-confidence. Do not report issues that exist only in removed lines (-) and are already fixed by the added lines (+).
