---
description: "Phase-based brutal audit workflow for Python projects - on-demand architectural review"
globs: ["**/*.py"]
alwaysApply: false
---

# Python Brutal Audit Workflow

This rule defines the workflow for conducting a "Brutal Audit" of the Python codebase.

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
**Version:** 2.1 (Updated for Python 3.13+, asyncio, pytest)

We have just finished Phase [X]. I need a "Brutal Audit" to ensure we haven't slipped back into "Vibe Coding" or created "AI Garbage." Analyze the current codebase against `.cursor/rules/python-3-development-standards.mdc`, `.cursor/rules/general-llm-anti-patterns.mdc`, and `PRODUCT_SPECIFICATION.md` (if present).

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

- `async def` functions that use `asyncio.run()` inside
- `async def` functions that call blocking I/O (`time.sleep()`, `requests.get()`, blocking database operations)
- Methods that wrap >80% of their body in synchronous work

**Violation:** Async function that declares async but doesn't actually benefit from async/await.
**Fix:** Use proper async I/O (`await asyncio.sleep()`, `httpx.AsyncClient`, `aiohttp`, or framework-native async clients), or make it synchronous.

### A2. Pass-Through "Ghost Layer" Services

Check services in `src/services/`, `src/api/`, `src/domain/`, or project-equivalent layers:

- If >80% of methods are single-line `return await repository.method()`, it's a ghost layer.
- If a service wraps only ONE dependency with no coordination or logic, flag it.

**Evidence to provide:** Count of pass-through methods vs. methods that add value.

### A3. Dead Code Detection

Search for:

- Methods that always raise `NotImplementedError` (placeholder implementations)
- `_ = await` patterns (discarded results wasting CPU/network)
- `# TODO:` or `# FIXME:` comments in production code
- Methods that are never called (check imports/usages)
- Unused imports

### A4. O(N²) Collection Operations

Flag any pattern like:

```python
for item in items:
    await process_item(item)  # ❌ Each call fetches/saves
```

**Check:** Bulk import, indexing, and batch persistence methods — are they batch optimized?

### A5. "Hallucination-Implementation" API Workarounds

Search for:

- Using custom implementations when stdlib or the project's framework/ORM provides the feature
- Multi-step searches to find something by ID when direct lookup exists
- Comments saying "Python doesn't provide X" or "Framework Y doesn't support Z" without checking docs
- Custom URL construction when the web framework's routing already provides it
- Using blocking `requests` in async code when `httpx.AsyncClient` or `aiohttp` should be used

### A6. AI-Apologetic Defensive Comments

Flag comments that:

- Are 5+ lines explaining why "unsafe" code is "actually safe"
- Repeat the same explanation in multiple files
- Say "This pattern is recommended because..." for workarounds
- Justify blocking I/O in async functions

**Rule:** If you need a paragraph to justify code, the code is wrong.

---

## 🟠 SECTION B: Layer Boundary Enforcement

### B1. Model Layer Purity Check

Scan `src/models/` or `**/models/`:

```bash
grep -r "import fastapi\|import django\|import sqlalchemy\|import httpx" src/models/
```

**Result should be minimal** — only for type hints if needed. Any framework/HTTP/DB driver imports in domain models = immediate fix required.

### B2. Business Logic Location

Flag any Repository/DAO method in `repositories/` or `**/repositories/` that:

- Contains business rules (validation beyond data integrity)
- Calculates derived values (should be in domain/service layer)
- Has >30 lines of logic (Repositories should be CRUD only)
- Contains `if/elif/else` chains for business decisions

### B3. Data Boundary Verification

In `api/handlers/`, `src/api/`, or `services/`:

- Are database models returned directly to templates?
- Is every database object mapped to a clean DTO/dict before crossing boundaries?
- Check method signatures: return types should be DTOs/dicts, not raw database objects.

---

## 🟡 SECTION C: Concurrency & Performance Audit

### C1. Async/Await Correctness

Check all async functions:

- ✅ Using `await` for all I/O operations
- ✅ Using async HTTP clients (`httpx.AsyncClient`, `aiohttp`) — not blocking `requests`
- ✅ Using `await asyncio.sleep()` (not `time.sleep()`)
- ❌ Using `time.sleep()` in async functions (should be `await asyncio.sleep()`)
- ❌ Blocking database operations in async functions (should use async DB drivers or thread pool)
- ❌ Using `asyncio.run()` inside async functions

### C2. Hot Path Performance

For search, indexing, and data-heavy operations:

- Does removing 1 item require fetching ALL items?
- Does finding an item by ID convert EVERY item to DTO?
- Are database queries using proper indexes?
- Are search/full-text queries optimized with limits?
- Are batch operations used instead of loops?

### C3. State Management Separation

- Is state calculation happening in Repositories? (❌)
- Is there a dedicated service layer for state management? (✅)
- Are Repositories just save/load snapshots? (✅)

---

## 🟢 SECTION D: Test Quality Audit

### D1. Async Test Patterns

Check all test files:

- Tests for async functions MUST use `@pytest.mark.asyncio`
- ❌ Using `asyncio.run()` in tests (use pytest-asyncio)
- ❌ Blocking operations in async tests
- ❌ Assigning `None` return values to variables unnecessarily

### D2. Test Coverage Gaps

- Handlers: 100% of public methods have tests?
- Workers: All crawl operations tested?
- Indexers: All indexing operations tested?
- Services: All business logic tested?
- Error paths: All error conditions tested?

### D3. Mock Quality

- Do mocks match real implementation behavior?
- Are tests passing with mocks but would fail with real code?
- Are external API calls properly mocked?
- Are database operations isolated in tests?

---

## 🔵 SECTION E: Python Type Safety & Compatibility

### E1. Type Hint Coverage Audit

Check all code:

- All public functions have type hints?
- Async functions use `typing.Awaitable` or `typing.Coroutine`?
- No `Any` types without justification?
- Return types explicitly declared?
- Generic types used correctly (`list[str]` not `List[str]` for Python 3.9+)?

**Track count of missing type hints for each phase.**

### E2. Python 3.13 Feature Usage

Check for proper Python 3.13 patterns:

- ✅ Using modern async patterns correctly
- ✅ Proper use of `asyncio` features
- ✅ Type hints using modern syntax (no `from typing import List` for built-in generics)
- ❌ Using deprecated patterns or Python 2.x idioms

---

## 🟣 SECTION F: Web Framework Compliance

### F1. Web Framework Patterns

- Are templates using base template inheritance (Jinja2, Django templates, etc.)?
- Are static files served via framework static handling (not ad-hoc file reads)?
- Are template variables properly escaped to prevent XSS?
- Are error pages (404, 500) implemented?

### F2. Web Anti-Patterns

- ❌ Custom error handling when the framework provides middleware/handlers
- ❌ `time.sleep()` for waiting on data (use async/await)
- ❌ Custom routing when the framework's router/blueprint system works
- ❌ Inline styles/scripts in templates (use static files)
- ❌ Hardcoded URLs instead of framework URL helpers (`url_for`, `reverse`, named routes)

---

## 📊 SECTION G: Scoring & Prioritization

### G1. The "Cleanliness" Verdict

On a scale of 1-10 (1 = Pure Architecture, 10 = Vibe Coding Mess):

| Category | Score | Critical Issues |
|----------|-------|-----------------|
| Model Purity | /10 | |
| Data Boundary Compliance | /10 | |
| Async/Await Correctness | /10 | |
| Performance (Hot Paths) | /10 | |
| Test Quality | /10 | |
| Type Safety & Python 3.13 Compliance | /10 | |
| Template/UI Quality | /10 | |
| **OVERALL** | /10 | |

### G2. TOP 10 Files Requiring Immediate Refactoring

Rank by severity (blocking Phase [X+1]):

| Rank | File | Primary Violation | Effort (S/M/L) |
|------|------|-------------------|----------------|
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
|-----------|-------|-------|
| TODO/FIXME comments | | |
| Dead/unreachable code | | |
| Defensive comments (5+ lines) | | |
| Duplicated code blocks (3+ times) | | |
| Missing type hints | | |
| Blocking I/O in async functions | | |

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
- Python: `pytest tests/ -v`

**Evidence Required:**
- Test output showing pass/fail counts
- Any failing tests flagged as CRITICAL violations
- Test coverage metrics (if available)

### X2. Runtime Error Detection

**Action:** Check for exceptions that aren't handled properly.

**Tool:** Use `grep` to find:
- Bare `except:` clauses (should be `except SpecificError:`)
- Silent failures: `except: pass` patterns
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

```
🚨 [CRITICAL/HIGH/MEDIUM/LOW] - Category A1: Fake Async Pattern
📍 File: src/crawler/worker.py
📝 Lines: 45-120
❌ Issue: Async function uses time.sleep() instead of await asyncio.sleep()
✅ Fix: Replace time.sleep() with await asyncio.sleep()
⏱️ Effort: Medium (2-4 hours)
```

End with: **"Ready for Phase [X+1]? YES/NO - If NO, list blockers."**

---

## 🚀 Quick Reference: The 15 Anti-LLM-Trap Rules

1. **Proper Async/Await Usage** - No blocking I/O in async functions
2. **No Pass-Through Services** - Services must add value
3. **No Dead Code** - No placeholder methods, no discarded results
4. **Batch Operations** - No O(N²) loops on collections
5. **Business Logic in Domain** - Repositories are CRUD only
6. **Use Proper Framework/Stdlib APIs** - No fragile workarounds
7. **Extract Repeated Patterns** - DRY (Don't Repeat Yourself)
8. **No Defensive Commenting** - Refactor instead of justify
9. **Optimize Hot Paths** - No full collection fetches for single ops
10. **State Management Separation** - State belongs in appropriate layer
11. **Proper Async Testing** - Use pytest-asyncio for async tests
12. **Models Are Framework-Agnostic** - No framework imports in models
13. **Forbidden Async Patterns** - No blocking I/O in async functions
14. **Test File Checklist** - Verify async patterns before writing tests
