---
description: "Phase-based brutal audit workflow for Swift/iOS projects - on-demand architectural review"
globs: ["**/*.swift"]
alwaysApply: false
---

# Swift/iOS Brutal Audit Workflow

This rule defines the workflow for conducting a "Brutal Audit" of the Swift/iOS codebase.

Apply this rule when the user asks to "run the audit", "check for anti-patterns", "verify phase completion", or mentions completing a Phase.

## Scope

- **Swift:** Audits **Swift 5.9** language-mode expectations (see `swift-5-9-*.mdc` filename). Swift 6-only syntax remains a finding unless the project has moved to Swift 6.
- **For Swift 6 projects:** Use `swift-6-brutal-audit.mdc` and `swift-6-development-standards.mdc`.
- **Platform:** Minimum OS is **project-defined** (Xcode deployment targets / SwiftPM `platforms`). Do not assume a fixed iOS version; verify Liquid Glass (or successor) APIs against the project's SDK and Apple documentation.

## Auditor Role & Behavior

You are the **Lead Architectural Auditor**. Your goal is to be critical, rigorous, and honest. Do not be polite about bad code. Flag "Vibe Coding" and "AI Garbage" relentlessly.

## Instructions

1. **Tool Usage**: Use `grep` and `codebase_search` to verify the checks below. Do not just "look" at files; verify them.
2. **Reporting**: Output the results in the format specified at the end.
3. **Sections**: You may be asked to run the full audit or specific sections (e.g., "Run Section A").

## Context

**Role:** Lead Architectural Auditor  
**Context:** Phase [X] Implementation Review  
**Version:** 2.1 (Swift 5.9; platform minimum from project; Swift Testing when supported by project SDK)

We have just finished Phase [X]. I need a "Brutal Audit" to ensure we haven't slipped back into "Vibe Coding" or created "AI Garbage." Analyze the current codebase against `.cursor/rules/swift-5-9-development-standards.mdc`, `.cursor/rules/general-llm-anti-patterns.mdc`, and `PRODUCT_SPECIFICATION.md` (if present).

---

## 🟢 PRE-AUDIT: Self-Verification Checklist

**Verify before audit:**
- No unverified imports (check registry)
- No TODO/FIXME in production
- No discarded results (`_ = expensiveOp()`)
- No I/O in loops (batch operations)
- No >80% delegation methods
- No hardcoded secrets
- No silent failures
- Security (OWASP): see `owasp-secure-coding-practices.mdc` for full checklist

**Tool:** Use `grep` to verify before detailed audit.

---

## 🔵 PRE-CODE GENERATION: Chain-of-Thought Checkpoints

**Before generating code, identify:**
1. Which layer affected (Domain/Data/Presentation)
2. Similar pattern exists? (Check codebase first)
3. Framework provides direct API? (Verify docs)
4. Ghost layer candidate? (>80% delegation check)

---

## 🔴 SECTION A: Critical LLM Anti-Pattern Detection

### A1. "Fake Actor" Pattern (Audit Report #1 Issue)

Search for this exact anti-pattern in actors:

- `nonisolated(unsafe) private let context: ModelContext`
- Methods that wrap >80% of their body in `MainActor.run { }`

**Violation:** Actor that declares concurrency but forces everything onto MainActor.
**Fix:** Use `@ModelActor` for background SwiftData, or honest `@MainActor class`.

### A2. Pass-Through "Ghost Layer" Services

Check services in `Core/Data/Services/`:

- If >80% of methods are single-line `return try await repository.method()`, it's a ghost layer.
- If a service wraps only ONE repository with no coordination or logic, flag it.

**Evidence to provide:** Count of pass-through methods vs. methods that add value.

### A3. Dead Code Detection

Search for:

- Methods that always throw the same error (placeholder implementations)
- `_ = try await` patterns (discarded results wasting CPU/network)
- `// TODO:` or `// FIXME:` comments in production code
- Methods that are never called (check imports/usages)

### A4. O(N²) Collection Operations

Flag any pattern like:

```swift
for item in items {
    try await processItem(item) // ❌ Each call fetches/saves
}
```

**Check:** `addItems()`, `removeItems()`, bulk import methods - are they batch optimized?

### A5. "Hallucination-Implementation" API Workarounds

Search for:

- Using `MusicCatalogSearchRequest` when `MusicCatalogResourceRequest` exists
- Multi-step searches to find something by ID
- Comments saying "MusicKit doesn't provide X" (did anyone actually check?)
- Custom URL construction that Apple APIs already provide

### A6. AI-Apologetic Defensive Comments

Flag comments that:

- Are 5+ lines explaining why "unsafe" code is "actually safe"
- Repeat the same explanation in multiple files
- Say "This pattern is recommended because..." for workarounds
- Justify `nonisolated(unsafe)` usage

**Rule:** If you need a paragraph to justify code, the code is wrong.

---

## 🟠 SECTION B: Layer Boundary Enforcement

### B1. Domain Layer Purity Check

Scan `Core/Domain/`:

```bash
grep -r "import SwiftData\|import MusicKit\|import SwiftUI" Core/Domain/
```

**Result must be empty.** Any violations = immediate fix required.

### B2. @MainActor on Domain Types

Check `Core/Domain/Models/`:

- ❌ Any `@MainActor` annotation on Domain types
- ✅ All types should be `Sendable` without actor isolation

### B3. DTO Boundary Verification

In `Core/Data/Repositories/`:

- Are SwiftData `@Model` classes ever returned directly?
- Is every database object mapped to a `Sendable` struct before crossing the boundary?
- Check method signatures: return types should be Domain DTOs, not `@Model` types.

### B4. Business Logic Location

Flag any Repository method that:

- Contains `switch` statements for business rules (repeat modes, shuffle algorithms)
- Calculates "next index" or manages state transitions
- Has >30 lines of logic (Repositories should be CRUD only)

---

## 🟡 SECTION C: Concurrency & Performance Audit

### C1. SwiftData Concurrency

Check all actors using `ModelContext`:

- ✅ Using `@ModelActor` macro
- ✅ Using `@MainActor class` (honest about MainActor requirement)
- ❌ Using `nonisolated(unsafe)` + `MainActor.run` (fake actor)

### C2. Hot Path Performance

For queue operations, playback, and search:

- Does removing 1 item require fetching ALL items?
- Does finding an item by ID convert EVERY item to DTO?
- Are there `fetchLimit` and `fetchOffset` on FetchDescriptors?

### C3. State Management Separation

- Is state calculation happening in Repositories? (❌)
- Is there a dedicated Domain layer state manager? (✅)
- Are Repositories just save/load snapshots? (✅)

---

## 🟢 SECTION D: Test Quality Audit

### D1. Actor Isolation in Tests

Check all test files:

- Tests for `@MainActor` types MUST have `@MainActor` on test function/struct
- ❌ `Thread.isMainThread` in async tests
- ❌ `let result = try await voidReturningMethod()` (assigning Void to constant)

### D2. Test Coverage Gaps

- Services: 100% of public methods have tests?
- ViewModels: All state changes tested?
- Error paths: All error conditions tested?

### D3. Mock Quality

- Do mocks match real implementation behavior?
- Are tests passing with mocks but would fail with real code?

---

## 🔵 SECTION E: Swift 6 Readiness

### E1. Concurrency Warnings Audit

Run build and count warnings related to:

- `Sendable` conformance issues
- Actor isolation boundary crossings
- MainActor assumption violations
- "Non-sendable type X cannot cross actor boundary"

**These warnings become ERRORS in Swift 6.** Track count for each phase.

### E2. Forbidden Swift 5.9 Violations

Search for Swift 6-only keywords (we target Swift 5.9):

- ❌ `sending` keyword
- ❌ `consume` keyword

---

## 🟣 SECTION F: UI/UX Compliance (HIG / project design system)

### F1. Liquid Glass Compliance

- Liquid Glass (or current Apple materials per HIG) must match the **project deployment target and SDK**; verify names and availability in Apple documentation—do not flag APIs that are correctly guarded with `#available` / project wrappers.
- Are new UI components using Liquid Glass materials (when required by project design system)?
- Check for proper modifier syntax per project (e.g. `.liquidGlass(material:refraction:)` if that is the project API)

### F2. UI Anti-Patterns

- ❌ Custom `ZStack` overlays for modals (use `.sheet(item:)`)
- ❌ `Task.sleep` for waiting on data/player readiness
- ❌ Custom components duplicating system functionality

---

## 📊 SECTION G: Scoring & Prioritization

### G1. The "Cleanliness" Verdict

On a scale of 1-10 (1 = Pure Architecture, 10 = Vibe Coding Mess):

| Category | Score | Critical Issues |
| --- | --- | --- |
| Domain Purity | /10 | |
| DTO Compliance | /10 | |
| Concurrency Safety | /10 | |
| Performance (Hot Paths) | /10 | |
| Test Quality | /10 | |
| Swift 6 Readiness | /10 | |
| **OVERALL** | /10 | |

### G2. TOP 10 Files Requiring Immediate Refactoring

Rank by severity (blocking Phase [X+1]):

| Rank | File | Primary Violation | Effort (S/M/L) |
| --- | --- | --- | --- |
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | | | |
| 7 | | | |
| 8 | | | |
| 9 | | | |
| 10 | | | |

### G3. Technical Debt Tracker

| Debt Type | Count | Files |
| --- | --- | --- |
| TODO/FIXME comments | | |
| Dead/unreachable code | | |
| Defensive comments (5+ lines) | | |
| Duplicated code blocks (3+ times) | | |
| Swift 6 warnings | | |

### G4. Regression Baseline

Compare violation counts to previous audit (if available):

**Key Metrics:**
- Ghost Layers: Previous: X, Current: Y
- API Hallucinations: Previous: X, Current: Y
- Performance Issues: Previous: X, Current: Y
- Security Issues: Previous: X, Current: Y

**Trend Analysis:**
- Improving: Violation count decreased
- Stable: Violation count unchanged
- Worsening: Violation count increased

**Questions:**
- Did any previously fixed issues regress?
- Are new files following the patterns we established?
- Is code quality trending better or worse?

---

## 🟢 SECTION X: Execution-Based Validation

**CRITICAL:** Static analysis can miss runtime issues. Always verify execution.

### X1. Test Suite Execution

**Action:** Run test suite and verify all tests pass.

**Tool:** Use `run_terminal_cmd` to execute test suite:
- Swift: `swift test`

**Evidence Required:**
- Test output showing pass/fail counts
- Any failing tests flagged as CRITICAL violations
- Test coverage metrics (if available)

### X2. Runtime Error Detection

**Action:** Check for exceptions that aren't handled properly.

**Tool:** Use `grep` to find:
- Bare `catch` clauses without specific error types
- Silent failures: `catch { }` empty blocks
- Generic error handling without logging

**Evidence Required:**
- List of unhandled exceptions with file locations
- Severity: CRITICAL if in production paths

### X3. Silent Failure Detection

**Action:** Verify error messages contain context.

**Tool:** Use `codebase_search` to find error handling patterns:
- Error messages without context (no variable values, no stack trace)
- Errors logged but not handled
- Generic error messages that don't help debugging

**Evidence Required:**
- List of silent failures with file locations
- Recommended fixes for each

---

## 📝 Output Format

For each violation found, provide:

```text
🚨 [CRITICAL/HIGH/MEDIUM/LOW] - Category A1: Fake Actor Pattern
📍 File: Core/Data/Repositories/QueueRepository.swift
📝 Lines: 45-120
❌ Issue: Actor uses nonisolated(unsafe) + MainActor.run
✅ Fix: Convert to @ModelActor or @MainActor class
⏱️ Effort: Medium (2-4 hours)
```

End with: **"Ready for Phase [X+1]? YES/NO - If NO, list blockers."**

---

## 🚀 Quick Reference: The 15 Anti-LLM-Trap Rules

1. **Proper SwiftData Concurrency** - No `nonisolated(unsafe)` + `MainActor.run`
2. **No Pass-Through Services** - Services must add value
3. **No Dead Code** - No placeholder methods, no discarded results
4. **Batch Operations** - No O(N²) loops on collections
5. **Business Logic in Domain** - Repositories are CRUD only
6. **Use Proper Apple APIs** - No fragile workarounds
7. **Extract Repeated Patterns** - DRY (Don't Repeat Yourself)
8. **No Defensive Commenting** - Refactor instead of justify
9. **Optimize Hot Paths** - No full collection fetches for single ops
10. **State Management Separation** - State belongs in Domain layer
11. **Proper Actor Isolation in Tests** - Match type isolation
12. **Domain Types Are Isolation-Agnostic** - No `@MainActor` on Domain
13. **Forbidden Async Patterns** - No `Thread.isMainThread` in async
14. **Test File Checklist** - Verify isolation before writing tests
