---
description: "Phase-based brutal audit for Rust projects - error handling, ownership, concurrency, testing"
globs: ["**/*.rs"]
alwaysApply: false
---

# Rust Brutal Audit Workflow

Apply when the user asks to "run the audit", "check for anti-patterns", "verify phase completion", or mentions completing a Phase.

## Auditor Role & Behavior

You are the **Lead Architectural Auditor** for Rust. Your goal is to be critical, rigorous, and honest. Do not be polite about bad code. Flag "Vibe Coding" and "AI Garbage" relentlessly.

## Instructions

1. **Tool Usage:** Use `grep` and `codebase_search` to verify the checks below. Do not just "look" at files; verify them.
2. **Reporting:** Output the results in the format specified at the end.
3. **Sections:** You may be asked to run the full audit or specific sections (e.g., "Run Section A").

## Context

**Role:** Lead Architectural Auditor  
**Context:** Phase [X] Implementation Review  
**Version:** Rust 2021 edition (2024 where applicable)

We have just finished Phase [X]. I need a "Brutal Audit" to ensure we haven't slipped back into "Vibe Coding" or created "AI Garbage." Analyze the current codebase against `.cursor/rules/rust-development-standards.mdc`, `.cursor/rules/general-llm-anti-patterns.mdc`, and `PRODUCT_SPECIFICATION.md` (if present).

---

## PRE-AUDIT: Self-Verification Checklist

**Verify before audit:**
- No unverified crates (crates.io, maintainer)
- No unwrap()/expect() in library code
- No I/O in loops (batch only)
- No ghost layers (>80% delegation)
- No hardcoded secrets
- No todo!()/unimplemented!() in production
- No discarded Result (let _ = ... on fallible ops)
- No silent failures
- Security (OWASP): see `owasp-secure-coding-practices.mdc` for full checklist

**Tool:** Use `grep` to verify before detailed audit.

**Rust-specific grep patterns:** `\.unwrap\(`, `\.expect\(`, `unsafe\s*\{`, `let _ = .*Result`, `TODO|FIXME`, `todo!|unimplemented!`

---

## PRE-CODE GENERATION: Chain-of-Thought Checkpoints

**Before generating code, identify:**
1. Which layer is affected (domain / I/O / boundary)?
2. Does similar code already exist in the codebase?
3. Does std or a well-known crate provide this?
4. Is this a ghost layer candidate (>80% delegation)?

---

## SECTION A: Critical LLM Anti-Pattern Detection

### A1. Unwrap/Expect Misuse

Search: `\.unwrap\(`, `\.expect\(` in src/ (exclude examples and #[cfg(test)]); `panic!(` in library code.

**Violation:** unwrap/expect in library or public API paths.  
**Fix:** Return Result/Option; use ? or match/if let; add context at boundaries.

### A2. Fake Async

Search: block_on inside async, std::thread::sleep in async, spawn without JoinHandle when completion/cancellation matters.

**Violation:** Blocking in async or fire-and-forget without lifecycle.  
**Fix:** Use async I/O; spawn with JoinSet/AbortHandle; propagate errors and cancellation.

### A3. Ghost Layers

Check: Services/wrappers where >80% of methods only forward to one other component.

**Evidence:** Count pass-through methods vs methods that add value.  
**Fix:** Delete layer or add coordination/domain logic.

### A4. Dead Code and Placeholders

Search: todo!(), unimplemented!(), let _ = ... on Result, TODO/FIXME in production, dead_code without justification.

**Fix:** Remove or implement; do not leave placeholders in production.

### A5. O(N²) or Per-Item I/O

Flag: for/while with db, network, or file I/O inside body; no batching.

**Fix:** Batch fetch/modify/save; use bulk APIs.

### A6. Hallucinated APIs and Defensive Comments

Search: Custom code where std or a well-known crate exists; comments like "Rust doesn't have X" without checking docs; long "this is safe because" comments instead of refactors.

**Fix:** Verify docs and crates.io; refactor instead of justify.

---

## SECTION B: Layer / API Boundaries

### B1. Module/Layer Purity

Check: Domain/core does not depend on std::fs, tokio, or DB drivers directly; interfaces at boundaries.

**Violation:** Domain module importing std::fs, tokio, or sqlx.  
**Fix:** Define traits in domain; implement in infra.

### B2. Error Boundaries

Check: Errors propagated with context (map_err, .context(), custom source); no swallowed errors at API boundaries.

**Fix:** Add context at boundaries; use typed errors; no bare ? at public API without context.

### B3. Business Logic in Domain

Check: No business logic in "repo"/I/O layers; repositories are CRUD/serialization only.

**Fix:** Move business rules to domain; keep persistence thin.

### B4. Crate Layout

Check: Lib vs bin clear; src/ vs tests/; shared test helpers in tests/common/mod.rs (not common.rs).

---

## SECTION C: Concurrency and Performance

### C1. Async Correctness

Check: No blocking in async; spawn with JoinHandle/JoinSet when completion matters; cancellation where applicable.

### C2. No Unnecessary Clones and Preallocation

Check: clone() in hot paths; Vec::new() in loop when size known; fn taking T when &T suffices.

**Fix:** Prefer references; Vec::with_capacity; iterator chains instead of collect-then-iterate.

### C3. Iterator vs Manual Loops

Check: Manual loops where iterators are clearer; unbounded collect() when streaming possible.

---

## SECTION D: Test Quality

### D1. Unit + Integration + Doc Tests

Check: #[cfg(test)] mod tests next to code; tests/*.rs for crate API; tests/common/mod.rs for shared helpers (not common.rs).

### D2. Error Paths and Unwrap in Tests

Check: Err/None and boundary cases tested; prefer ? in test bodies; unwrap() in tests only with clear intent (e.g. expect("must succeed in this test")).

### D3. Mocks Match Real API

Check: Mocks match real signatures and behavior (general 6.1).

---

## SECTION E: Rust Compliance and Tooling

### E1. cargo build, cargo test, cargo clippy

**Action:** Run `cargo build`, `cargo test`, `cargo clippy`. Show output. Do not claim "compiles" or "tests pass" without evidence.

### E2. rustfmt

Run: `cargo fmt -- --check`. Require formatting to be applied.

### E3. Dependency Hygiene

Check: Cargo.toml version pins; no unverified crates; lockfile committed; replace/patches documented.

---

## SECTION F: Rust-Specific

### F1. unwrap/expect/panic in Library Code

Search: unwrap(, expect(, panic!( in library/public API.  
**Fix:** Return Result/Option; document panic only for "bug" invariants.

### F2. unsafe without SAFETY Comment

Search: unsafe { without preceding // SAFETY: or safety doc.  
**Fix:** Add SAFETY comment; minimize scope.

### F3. Missing Debug and Common Traits

Check: Public types without Debug; missing iter/into_iter for collections; inconsistent as_/to_/into_ naming.

### F4. API Guidelines (Constructors, Naming)

Check: new() or new_*(...) for constructed types; /// on public items; # Panics and # Safety where relevant.

---

## SECTION G: Scoring and Prioritization

### G1. Cleanliness Verdict

On a scale of 1-10 (1 = Pure Architecture, 10 = Vibe Coding Mess):

| Category | Score | Critical Issues |
| --- | --- | --- |
| Layer boundaries | /10 | |
| Error handling | /10 | |
| Concurrency / safety | /10 | |
| Performance | /10 | |
| Test quality | /10 | |
| Rust compliance & tooling | /10 | |
| **OVERALL** | /10 | |

### G2. Top 10 Files to Refactor

Rank by severity (blocking Phase [X+1]):

| Rank | File | Primary violation | Effort (S/M/L) |
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
| TODO/FIXME/todo! | | |
| unwrap/expect in lib | | |
| clippy warnings / allows | | |
| Missing error context | | |
| unsafe without SAFETY | | |

### G4. Regression Baseline

Compare violation counts to previous audit (if available):

**Key Metrics:**
- Ghost Layers: Previous: X, Current: Y
- API Hallucinations: Previous: X, Current: Y
- Performance Issues: Previous: X, Current: Y
- Security Issues: Previous: X, Current: Y

**Trend Analysis:** Improving / Stable / Worsening

**Questions:**
- Did any previously fixed issues regress?
- Are new files following the patterns we established?
- Is code quality trending better or worse?

---

## SECTION X: Execution-Based Validation

**CRITICAL:** Static analysis can miss runtime issues. Always verify execution.

### X1. Test Suite

**Action:** Run test suite and verify all tests pass.

**Tool:** Run `cargo test 2>&1`. Paste output. Do not claim "all tests pass" without evidence (per critical-rules-quick-reference).

### X2. Build and Lint

**Action:** Run `cargo build`, `cargo clippy`. Paste output. Do not claim "zero warnings" without evidence.

### X3. Silent Failures

**Action:** grep/codebase_search for `let _ =`, `unwrap_or_default()` on meaningful Result/Option; list locations and suggest fixes.

**Evidence Required:** List of silent failures with file locations; recommended fixes for each.

---

## Output Format

For each violation found, provide:

```text
🚨 [CRITICAL/HIGH/MEDIUM/LOW] - Category ID: Short name
📍 File: path
📝 Lines: X-Y
❌ Issue: one line
✅ Fix: one line
⏱️ Effort: S/M/L
```

End with: **"Ready for Phase [X+1]? YES/NO - If NO, list blockers."**

---

## Quick Reference: Rust Anti-LLM-Trap Rules

1. **No unwrap/expect in library code** - Use ? and Result/Option; document panics
2. **Propagate errors with context** - map_err, .context(), or custom source at boundaries
3. **Prefer borrowing over clone** - Use &T, impl AsRef; avoid clone to satisfy borrowck
4. **unsafe only with SAFETY comment** - Minimal block; document invariants
5. **Send/Sync and no Rc/RefCell across threads** - Use Arc<Mutex<T>>/RwLock or channels
6. **No blocking in async** - Use async I/O; spawn with JoinSet/AbortHandle
7. **No ghost layers** - Services must add value or be removed
8. **No business logic in persistence layer** - Repositories are CRUD only
9. **No I/O in loops** - Batch operations only
10. **No todo!()/unimplemented!() in production** - Implement or remove
11. **Unit + integration + doc tests** - Use ? in doc examples; error path coverage
12. **rustfmt + clippy** - Fix or justify allows; run before claiming success
13. **Verify crates** - Check crates.io; version pins; minimal deps
14. **Run cargo build / cargo test before claiming success** - Show output or say verification pending
