# Accessibility: Onboarding & Landing Views

**Issue:** [#93 — Screen Reader Accessibility](https://github.com/tadelv/reaprime/issues/93)
**Date:** 2026-04-07
**Scope:** Welcome, Permissions, Initialization, Scan, Import, Landing/SkinView

## Current State

Zero `Semantics` widgets across all onboarding/landing views. No `semanticLabel` on any icons. No `excludeSemantics` on decorative icons. Progress indicators and checkboxes lack semantic labels.

## Approach: Full Screen Reader Experience (B)

### Patterns Applied Per View

1. **Decorative icons** (paired with text) → `excludeSemantics: true` — screen reader skips, text conveys meaning
2. **Meaningful icons** (standalone, convey info) → `Icon(semanticLabel: '...')`
3. **Progress indicators** → wrap in `Semantics(label: '...', child: ...)`
4. **Checkboxes/toggles** → `semanticLabel` set
5. **State groups** → `MergeSemantics` for icon+text rows (read as one unit)
6. **Focus ordering** → `FocusTraversalGroup` on each step's main content
7. **Live regions** → `Semantics(liveRegion: true)` on status text that changes

### Testing Strategy

- Run on macOS with `simulate=1`
- Use Xcode Accessibility Inspector to verify semantics tree
- Widget tests asserting on `SemanticsController` for key interactions

## Out of Scope

- Dashboard, Settings, Shot History (future work, tracked in Obsidian)
- Streamline.js skin button TalkBack issue (web-side fix, separate PR)
