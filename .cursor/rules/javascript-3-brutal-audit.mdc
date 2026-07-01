---
description: "Phase-based brutal audit workflow for JavaScript/TypeScript projects - on-demand architectural review"
globs: ["**/*.js", "**/*.jsx", "**/*.mjs", "**/*.cjs", "**/*.ts", "**/*.tsx"]
alwaysApply: false
---

# JavaScript/TypeScript Brutal Audit Workflow

This rule defines the workflow for conducting a "Brutal Audit" of the JavaScript/TypeScript codebase.

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
**Version:** 2.0 (Updated for ES6+, TypeScript, Node.js, React)

We have just finished Phase [X]. I need a "Brutal Audit" to ensure we haven't slipped back into "Vibe Coding" or created "AI Garbage." Analyze the current codebase against `.cursor/rules/javascript-3-development-standards.mdc`, `.cursor/rules/general-llm-anti-patterns.mdc`, and `PRODUCT_SPECIFICATION.md` (if present).

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

### A1. "Fake Async" Pattern (Audit Report #1 Issue)

Search for this exact anti-pattern in async functions:

- `async function` that only wraps synchronous code
- `async function` that doesn't use `await` anywhere
- Functions that declare async but do blocking operations inside

**Violation:** Async function that declares async but doesn't actually benefit from async/await.
**Fix:** Either use proper async I/O (`await fetch()`, `await fs.promises.readFile()`), or make it synchronous.

### A2. Pass-Through "Ghost Layer" Services

Check services in typical service/controller directories:

- If >80% of methods are single-line `return await repository.method()`, it's a ghost layer.
- If a service wraps only ONE dependency with no coordination or logic, flag it.

**Evidence to provide:** Count of pass-through methods vs. methods that add value.

### A3. Dead Code Detection

Search for:

- Functions that always throw errors (placeholder implementations)
- `_ = await` patterns (discarded results wasting CPU/network)
- `// TODO:` or `// FIXME:` comments in production code
- Methods that are never called (check imports/usages)
- Unused imports
- Functions with empty catch blocks (`catch {}` or `catch (e) {}`)

### A4. O(N²) Collection Operations

Flag any pattern like:

```javascript
for (const item of items) {
    await processItem(item); // ❌ Each call fetches/saves
}
```

**Check:** Bulk operations, batch import methods - are they batch optimized? Use `Promise.all()` for parallel operations.

### A5. "Hallucination-Implementation" API Workarounds

Search for:

- Using custom implementations when stdlib/framework provides the feature
- Multi-step workarounds when direct API exists
- Comments saying "X doesn't provide Y" (did anyone actually check the docs?)
- Using `eval()` or `Function()` constructor (security risk)
- Custom implementations of standard functionality

### A6. AI-Apologetic Defensive Comments

Flag comments that:

- Are 5+ lines explaining why "unsafe" code is "actually safe"
- Repeat the same explanation in multiple files
- Say "This pattern is recommended because..." for workarounds
- Justify using `eval()`, ignoring errors, or unsafe patterns

**Rule:** If you need a paragraph to justify code, the code is wrong.

---

## 🟠 SECTION B: Layer Boundary Enforcement

### B1. Module Boundary Verification

Check module system consistency:

- ✅ Using ES6 modules (`import`/`export`) consistently
- ✅ Not mixing CommonJS (`require`/`module.exports`) with ES6 modules
- ❌ Mixing module systems in same file/project
- ❌ Using CommonJS when ES6 modules are available
- ✅ Proper import organization (external, then internal, blank lines)

### B2. Type Boundary Verification

Check TypeScript/JSDoc usage:

- ✅ Public functions have type annotations (TypeScript or JSDoc)
- ✅ Function parameters and return types documented
- ❌ Using `any` type without justification
- ❌ Missing type annotations on public APIs
- ✅ Type safety enforced (TypeScript strict mode or JSDoc types)

### B3. Dependency Injection Patterns

Check for global state and dependency patterns:

- ✅ Dependencies passed explicitly (dependency injection)
- ✅ No global mutable state
- ❌ Global variables (except constants)
- ❌ Module-level mutable state
- ❌ Singleton patterns with mutable state

### B4. Business Logic Location

Flag any Repository/DAO methods that:

- Contain business rules (validation beyond data integrity)
- Calculate derived values (should be in domain/service layer)
- Have >30 lines of logic (Repositories should be CRUD only)
- Contain complex `if/else` chains for business decisions

---

## 🟡 SECTION C: Concurrency & Performance Audit

### C1. Async/Await Correctness

Check all async functions:

- ✅ Using `await` for all async operations
- ✅ Using `try/catch` for error handling
- ✅ Not using blocking operations in async functions
- ❌ Using `setTimeout` for async testing (use proper async patterns)
- ❌ Blocking operations in async functions (fs.readFileSync, etc.)
- ❌ Unhandled promise rejections

### C2. Promise Patterns

Check promise usage:

- ✅ Using `Promise.all()` for parallel independent operations
- ✅ Using `Promise.allSettled()` when partial failures are acceptable
- ✅ Using `async/await` instead of promise chains
- ❌ Sequential `await` when operations are independent
- ❌ Fire-and-forget promises without error handling
- ❌ Promise chains when `async/await` would be clearer

### C3. Hot Path Performance

For hot paths (APIs, data processing):

- ✅ Using modern array methods (`map`, `filter`, `reduce`) instead of loops
- ✅ Using `Map` or `Set` for O(1) lookups
- ✅ Avoiding nested loops when single pass possible
- ❌ Using arrays for lookups (O(n) instead of O(1))
- ❌ Nested loops when single pass possible (O(n²) instead of O(n))
- ❌ Loading entire files into memory (use streams for large files)

### C4. Modern JavaScript Features

Check for modern ES6+ usage:

- ✅ Using `const`/`let` (never `var`)
- ✅ Using template literals instead of string concatenation
- ✅ Using destructuring for object/array access
- ✅ Using spread/rest operators appropriately
- ✅ Using optional chaining (`?.`) and nullish coalescing (`??`)
- ❌ Using `var` declarations
- ❌ String concatenation with `+`
- ❌ Manual property access when destructuring would work

---

## 🟢 SECTION D: Test Quality Audit

### D1. Async Test Patterns

Check all test files:

- ✅ Tests for async functions use `async/await`
- ✅ Tests wait for async operations to complete
- ✅ Using promise assertions when appropriate
- ❌ Tests that don't wait for async operations
- ❌ Using `setTimeout` for async testing
- ❌ Not awaiting promises in tests

### D2. Test Coverage Gaps

- Services: 100% of public methods have tests?
- Controllers/Handlers: All routes/handlers tested?
- Error paths: All error conditions tested?
- Edge cases: Boundary conditions tested?
- Async operations: All promise rejections tested?

### D3. Test Quality

- ✅ Tests are isolated (no shared state)
- ✅ External dependencies are mocked
- ✅ Tests don't hit real APIs/databases
- ✅ Tests have descriptive names
- ❌ Tests that depend on each other
- ❌ Tests that modify shared state
- ❌ Tests that hit real APIs/databases

### D4. Mock Quality

- Do mocks match real implementation behavior?
- Are tests passing with mocks but would fail with real code?
- Are external API calls properly mocked?

---

## 🔵 SECTION E: JavaScript/TypeScript Compliance

### E1. Type Safety Coverage

Check type annotations:

- ✅ All public functions have type annotations (TypeScript or JSDoc)
- ✅ Function parameters and return types documented
- ✅ No `any` types without justification
- ❌ Missing type annotations on public APIs
- ❌ Excessive use of `any` type
- ❌ Missing JSDoc comments for JavaScript files

**Track count of missing type annotations for each phase.**

### E2. Modern JavaScript Features Usage

Check for proper ES6+ patterns:

- ✅ Using `const`/`let` (never `var`)
- ✅ Using template literals
- ✅ Using destructuring
- ✅ Using arrow functions appropriately
- ✅ Using modern array methods
- ❌ Using deprecated patterns or ES5 idioms
- ❌ Missing modern JavaScript features when available

### E3. Code Quality Tooling

Check linting and formatting:

- ✅ ESLint configured and passing
- ✅ Prettier configured and code formatted
- ✅ No ESLint errors/warnings ignored without justification
- ❌ No ESLint configuration
- ❌ ESLint errors/warnings ignored
- ❌ Inconsistent code formatting

### E4. Strict Mode Enforcement

Check for strict mode:

- ✅ Using `'use strict';` or ES modules (strict by default)
- ✅ ESLint configured to enforce strict mode
- ❌ Missing `'use strict';` in non-module files
- ❌ Undeclared variables becoming globals

---

## 🟣 SECTION F: Framework/Platform Compliance

### F1. Node.js Patterns (if applicable)

Check Node.js specific patterns:

- ✅ Using streams for large file processing
- ✅ Handling process signals (SIGTERM, SIGINT) for graceful shutdown
- ✅ Closing resources properly (database connections, file handles)
- ✅ Using environment variables for configuration
- ❌ Loading entire files into memory
- ❌ No signal handlers for graceful shutdown
- ❌ Resources not cleaned up

### F2. React Patterns (if applicable)

Check React specific patterns:

- ✅ Using hooks correctly (Rules of Hooks)
- ✅ Proper component composition
- ✅ Avoiding unnecessary re-renders
- ✅ Using proper key props in lists
- ❌ Violations of Rules of Hooks
- ❌ Direct DOM manipulation
- ❌ Missing key props or using index as key

### F3. Security Patterns

Check security-related code (full OWASP checklist: `owasp-secure-coding-practices.mdc`):

- ✅ Input validation at boundaries
- ✅ Output sanitization (XSS prevention)
- ✅ Using parameterized queries (SQL injection prevention)
- ✅ No `eval()` or `Function()` constructor
- ✅ No hardcoded secrets
- ❌ Using `eval()` or `Function()` constructor
- ❌ Hardcoded API keys or passwords
- ❌ Direct use of user input in queries/HTML

---

## 📊 SECTION G: Scoring & Prioritization

### G1. The "Cleanliness" Verdict

On a scale of 1-10 (1 = Pure Architecture, 10 = Vibe Coding Mess):

| Category | Score | Critical Issues |
| --- | --- | --- |
| Module Boundary Compliance | /10 | |
| Type Safety | /10 | |
| Async/Await Correctness | /10 | |
| Performance (Hot Paths) | /10 | |
| Test Quality | /10 | |
| Modern JavaScript Features | /10 | |
| Security Compliance | /10 | |
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
| Missing type annotations | | |
| Unhandled promise rejections | | |
| ESLint warnings/errors | | |

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
- JavaScript: `npm test`

**Evidence Required:**
- Test output showing pass/fail counts
- Any failing tests flagged as CRITICAL violations
- Test coverage metrics (if available)

### X2. Runtime Error Detection

**Action:** Check for exceptions that aren't handled properly.

**Tool:** Use `grep` to find:
- Bare `catch` clauses without specific error types
- Silent failures: `catch { }` empty blocks
- Unhandled promise rejections

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
🚨 [CRITICAL/HIGH/MEDIUM/LOW] - Category A1: Fake Async Pattern
📍 File: src/services/userService.js
📝 Lines: 45-120
❌ Issue: Async function doesn't use await, only wraps synchronous code
✅ Fix: Remove async or use proper async I/O operations
⏱️ Effort: Medium (2-4 hours)
```

End with: **"Ready for Phase [X+1]? YES/NO - If NO, list blockers."**

---

## 🚀 Quick Reference: The 15 Anti-LLM-Trap Rules

1. **Proper Async/Await Usage** - No fake async, proper error handling
2. **No Pass-Through Services** - Services must add value
3. **No Dead Code** - No placeholder methods, no discarded results
4. **Batch Operations** - Use Promise.all(), no O(N²) loops
5. **Business Logic in Domain** - Repositories are CRUD only
6. **Use Proper JavaScript/TypeScript APIs** - No fragile workarounds
7. **Extract Repeated Patterns** - DRY (Don't Repeat Yourself)
8. **No Defensive Commenting** - Refactor instead of justify
9. **Optimize Hot Paths** - Use Map/Set for lookups, modern array methods
10. **Module System Consistency** - ES6 modules, no mixing with CommonJS
11. **Proper Async Testing** - Use async/await in tests, wait for operations
12. **Type Safety** - TypeScript or JSDoc types, no excessive `any`
13. **Modern JavaScript Features** - Use const/let, template literals, destructuring
14. **Security First** - No eval(), validate input, no hardcoded secrets
