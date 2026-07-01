---
description: "Phase-based brutal audit workflow for Go projects - on-demand architectural review"
globs: ["**/*.go"]
alwaysApply: false
---

# Go Brutal Audit Workflow

This rule defines the workflow for conducting a "Brutal Audit" of the Go codebase.

Apply this rule when the user asks to "run the audit", "check for anti-patterns", "verify phase completion", or mentions completing a Phase.

## Auditor Role & Behavior

You are the **Lead Architectural Auditor**. Your goal is to be critical, rigorous, and honest. Do not be polite about bad code. Flag "Vibe Coding" and "AI Garbage" relentlessly.

## Instructions

1. **Tool Usage**: Use `grep` and `codebase_search` to verify the checks below. Do not just "look" at files; verify them.
2. **Reporting**: Output the results in the format specified at the end.
3. **Sections**: You may be asked to run the full audit or specific sections (e.g., "Run Section A").

## Context

**Role:** Lead Architectural Auditor  
**Context:** Phase [X] Implementation Review  
**Version:** 2.0 (Updated for Go 1.21+, Effective Go, Uber Style Guide)

We have just finished Phase [X]. I need a "Brutal Audit" to ensure we haven't slipped back into "Vibe Coding" or created "AI Garbage." Analyze the current codebase against `.cursor/rules/go-1-21-development-standards.mdc`, `.cursor/rules/general-llm-anti-patterns.mdc`, and `PRODUCT_SPECIFICATION.md` (if present).

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

### A1. "Fake Goroutine" Pattern (Audit Report #1 Issue)

Search for this exact anti-pattern in goroutines:

- `go func() { process() }()` without `WaitGroup` or channel tracking
- Goroutines without lifecycle management (no shutdown mechanism)
- Fire-and-forget goroutines that cannot be cancelled

**Violation:** Goroutine that declares concurrency but has no lifecycle management.
**Fix:** Use `sync.WaitGroup`, `errgroup`, or context-based cancellation; never fire-and-forget.

### A2. Pass-Through "Ghost Layer" Services

Check services in typical service packages:

- If >80% of methods are single-line `return repository.Method()`, it's a ghost layer.
- If a service wraps only ONE dependency with no coordination or logic, flag it.

**Evidence to provide:** Count of pass-through methods vs. methods that add value.

### A3. Dead Code Detection

Search for:

- Methods that always return errors (placeholder implementations)
- `_ = func()` patterns (discarded results ignoring errors)
- `// TODO:` or `// FIXME:` comments in production code
- Methods that are never called (check imports/usages)
- Unused imports
- `panic(err)` in libraries/handlers (should return error)

### A4. O(N²) Collection Operations

Flag any pattern like:

```go
for _, item := range items {
    processItem(item) // ❌ Each call fetches/saves
}
```

**Check:** Bulk operations, batch import methods - are they batch optimized? Are slices/maps preallocated?

### A5. "Hallucination-Implementation" API Workarounds

Search for:

- Using custom implementations when stdlib provides the feature
- Multi-step searches to find something by ID when direct lookup exists
- Comments saying "Go stdlib doesn't provide X" (did anyone actually check the docs?)
- Custom implementations of stdlib functionality (JSON, HTTP, etc.)
- Using `interface{}` when generics would work

### A6. AI-Apologetic Defensive Comments

Flag comments that:

- Are 5+ lines explaining why "unsafe" code is "actually safe"
- Repeat the same explanation in multiple files
- Say "This pattern is recommended because..." for workarounds
- Justify ignoring errors or using `panic`

**Rule:** If you need a paragraph to justify code, the code is wrong.

---

## 🟠 SECTION B: Layer Boundary Enforcement

### B1. Package Boundary Purity Check

Scan domain/business logic packages:

```bash
grep -r "import.*database\|import.*sql\|import.*http" internal/domain/
```

**Result should be minimal** - only for type hints if needed. Framework imports in domain packages = immediate fix required.

### B2. Interface Location Verification

Check interface definitions:

- ❌ Interfaces defined in producer packages (where implemented)
- ✅ Interfaces defined in consumer packages (where used)
- ❌ Exported interfaces in implementation packages
- ❌ Interfaces with >5 methods (violates interface segregation)

### B3. Error Boundary Verification

Check error handling across boundaries:

- Are errors wrapped with `%w` for context?
- Are errors checked at every boundary?
- Is `context.TODO()` used in production code? (should use proper context)
- Are errors propagated without context? (should use `fmt.Errorf("failed: %w", err)`)

### B4. Business Logic Location

Flag any Repository/DAO method that:

- Contains business rules (validation beyond data integrity)
- Calculates derived values (should be in domain/service layer)
- Has >30 lines of logic (Repositories should be CRUD only)
- Contains `switch` statements for business decisions

---

## 🟡 SECTION C: Concurrency & Performance Audit

### C1. Context Propagation

Check all blocking I/O functions:

- ✅ `context.Context` is first parameter
- ✅ Context passed through call chain
- ❌ Blocking I/O without context parameter
- ❌ `context.TODO()` in production code (should use proper context)
- ❌ `context.Background()` except at root
- ❌ Context stored in struct fields (should be parameter)

### C2. Goroutine Management

Check all goroutine usage:

- ✅ Using `sync.WaitGroup` or `errgroup` for lifecycle
- ✅ Using context cancellation for shutdown
- ❌ Fire-and-forget goroutines (`go func() { ... }()` without tracking)
- ❌ Goroutines without cancellation mechanism
- ❌ Sleeping in goroutines without context cancellation

### C3. Channel Patterns

Check all channel usage:

- ✅ Channels closed when done
- ✅ Using `range` over channels
- ✅ Using context-based cancellation instead of channels for shutdown
- ❌ Channels never closed (leaks goroutines)
- ❌ `select` without `default` causing blocking
- ❌ Busy-wait patterns with channels

### C4. Hot Path Performance

For hot paths (APIs, data processing):

- Are slices preallocated with `make([]T, 0, capacity)`?
- Are maps preallocated with `make(map[K]V, capacity)`?
- Does removing 1 item require fetching ALL items?
- Does finding an item by ID convert EVERY item?
- Are batch operations used instead of loops?

---

## 🟢 SECTION D: Test Quality Audit

### D1. Table-Driven Test Patterns

Check all test files:

- ✅ Tests use table-driven pattern for logic
- ✅ Test cases defined as struct slice
- ✅ `t.Run()` used for subtests
- ❌ Repeated test logic, copy-pasted test functions
- ❌ Multiple test functions for same feature (should use subtests)

### D2. Test Coverage Gaps

- Services: 100% of public methods have tests?
- Repositories: All CRUD operations tested?
- Error paths: All error conditions tested?
- Edge cases: Boundary conditions tested?
- Concurrent code: Race conditions tested?

### D3. Test Quality

- ✅ Using `t.Parallel()` for independent tests
- ✅ Using `t.Helper()` in helper functions
- ✅ Tests are isolated (no shared state)
- ❌ Tests that depend on each other
- ❌ Tests that modify global state
- ❌ Tests without cleanup (resource leaks)

### D4. Mock Quality

- Do mocks match real implementation behavior?
- Are tests passing with mocks but would fail with real code?
- Are external dependencies properly mocked?

---

## 🔵 SECTION E: Go Compliance & Tooling

### E1. Static Analysis Warnings Audit

Run and count warnings from:

- `go vet ./...` - Standard Go vet warnings
- `staticcheck ./...` - Additional static analysis warnings
- Build warnings (compiler warnings)

**Track count for each phase.** These indicate real issues.

### E2. Module Management

Check `go.mod` and dependency management:

- ✅ `go.sum` committed to version control
- ✅ Dependency versions pinned
- ✅ `replace` directives documented (if any)
- ❌ Missing `go.sum`
- ❌ Unpinned dependencies
- ❌ Replace directives without comments

### E3. Code Formatting & Style

Check code formatting:

- ✅ Code formatted with `gofmt`
- ✅ Imports organized (stdlib, 3rd party, local, blank lines)
- ✅ Using `goimports` for import management
- ❌ Manual formatting inconsistent with `gofmt`
- ❌ Imports not grouped properly
- ❌ Mixed import styles

### E4. Documentation Compliance

Check public APIs:

- ✅ All exported functions have `godoc` comments
- ✅ Package has package-level documentation
- ✅ Complex functions have examples
- ❌ Exported functions without documentation
- ❌ Missing package documentation

---

## 🟣 SECTION F: Go-Specific Patterns

### F1. Init() Function Abuse

Search for `func init()`:

- ❌ `init()` functions doing I/O or setting globals
- ❌ `init()` functions with logic (should be explicit constructors)
- ✅ `init()` only for simple constant initialization (if at all)

### F2. Panic Misuse

Search for `panic(`:

- ❌ `panic(err)` in libraries/handlers (should return error)
- ❌ `panic()` for control flow
- ✅ `panic()` only in `Must*` functions or unrecoverable startup errors

### F3. Interface{} / Any Abuse

Search for `interface{}` or `any`:

- ❌ Using `interface{}` when generics would work
- ❌ Excessive type assertions
- ✅ Using generics for type-safe reusable code
- ✅ `interface{}` only for reflection or truly dynamic code

### F4. Zero Value Design

Check type design:

- ✅ Types usable at zero value
- ✅ No mandatory `Init()` methods required
- ❌ Types that panic at zero value
- ❌ Types unusable without setup

---

## 📊 SECTION G: Scoring & Prioritization

### G1. The "Cleanliness" Verdict

On a scale of 1-10 (1 = Pure Architecture, 10 = Vibe Coding Mess):

| Category | Score | Critical Issues |
| --- | --- | --- |
| Package Boundary Compliance | /10 | |
| Error Handling | /10 | |
| Concurrency Safety | /10 | |
| Performance (Hot Paths) | /10 | |
| Test Quality | /10 | |
| Go Compliance & Tooling | /10 | |
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
| Missing error wrapping | | |
| Fire-and-forget goroutines | | |
| go vet / staticcheck warnings | | |

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
- Go: `go test ./...`

**Evidence Required:**
- Test output showing pass/fail counts
- Any failing tests flagged as CRITICAL violations
- Test coverage metrics (if available)

### X2. Runtime Error Detection

**Action:** Check for exceptions that aren't handled properly.

**Tool:** Use `grep` to find:
- Ignored errors: `_ = function()` patterns
- Silent failures: `if err != nil { return }` without logging
- Generic error handling without context

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
🚨 [CRITICAL/HIGH/MEDIUM/LOW] - Category A1: Fake Goroutine Pattern
📍 File: internal/service/worker.go
📝 Lines: 45-120
❌ Issue: Goroutine launched without WaitGroup or context cancellation
✅ Fix: Use sync.WaitGroup or errgroup for lifecycle management
⏱️ Effort: Medium (2-4 hours)
```

End with: **"Ready for Phase [X+1]? YES/NO - If NO, list blockers."**

---

## 🚀 Quick Reference: The 15 Anti-LLM-Trap Rules

1. **Proper Goroutine Management** - Use WaitGroup/errgroup, never fire-and-forget
2. **No Pass-Through Services** - Services must add value
3. **No Dead Code** - No placeholder methods, no discarded results (`_ = func()`)
4. **Batch Operations** - No O(N²) loops on collections, preallocate slices/maps
5. **Business Logic in Domain** - Repositories are CRUD only
6. **Use Proper Go Stdlib APIs** - No fragile workarounds
7. **Extract Repeated Patterns** - DRY (Don't Repeat Yourself)
8. **No Defensive Commenting** - Refactor instead of justify
9. **Optimize Hot Paths** - Preallocate, use batch operations
10. **Context Propagation** - Context first parameter, proper cancellation
11. **Proper Error Handling** - Wrap errors with `%w`, never ignore
12. **Interface Design** - Define interfaces where used, not where implemented
13. **Table-Driven Tests** - Use table-driven tests for all logic
14. **Channel Patterns** - Close channels, use context for cancellation
