---
description: "Phase completion verification workflow - triggers brutal audits after phase completion"
globs: []
alwaysApply: false
---

# Phase Completion Audit Workflow

This rule provides guidance for running brutal audits after completing a development phase or milestone.

## When to Run Audits

Apply this workflow when:

- The user mentions completing a "Phase" or "Milestone"
- The user asks to "verify phase completion"
- The user wants to ensure code quality before proceeding to the next phase
- Code quality concerns arise during development

## Available Audit Workflows

The repository includes comprehensive brutal audit workflows:

### Swift/iOS Projects (Swift 5.9)

- **File:** `swift-5-9-brutal-audit.mdc`
- **Use when:** Swift 5.9 language mode (platform minimum is project-defined)
- **Covers:** Architectural patterns, concurrency, performance, test quality, Swift 6 readiness, UI compliance

### Swift/iOS Projects (Swift 6)

- **File:** `swift-6-brutal-audit.mdc`
- **Use when:** Swift 6 language mode (platform minimum is project-defined)
- **Covers:** Architectural patterns, strict concurrency compliance, performance, test quality, UI compliance

### Python Projects

- **File:** `python-3-brutal-audit.mdc`
- **Use when:** Working on Python 3.13+ projects
- **Covers:** Async/await patterns, layer boundaries, performance, test quality, type safety, web compliance

### Java Projects

- **File:** `java-brutal-audit.mdc`
- **Use when:** Working on Java 17 or Java 21 LTS projects
- **Covers:** Concurrency (ExecutorService/Virtual Threads), layer boundaries, Effective Java patterns, Optional/Records, test quality, JVM tuning

### Go Projects

- **File:** `go-1-21-brutal-audit.mdc`
- **Use when:** Working on Go 1.21+ projects
- **Covers:** Effective Go, concurrency, testing, structure

### JavaScript/TypeScript Projects

- **File:** `javascript-3-brutal-audit.mdc`
- **Use when:** Working on JavaScript/TypeScript projects
- **Covers:** Modern ES, tooling, testing

### Rust Projects

- **File:** `rust-brutal-audit.mdc`
- **Use when:** Working on Rust (edition 2021 or 2024) projects
- **Covers:** Error handling, ownership, async/concurrency, testing, API guidelines, unsafe

## Workflow Steps

1. **Identify the project type** (Swift/iOS, Python, Java, Go, JavaScript/TypeScript, or Rust)
2. **Invoke the appropriate audit** by mentioning:
   - "run the audit"
   - "check for anti-patterns"
   - "verify phase completion"
   - "run the Swift audit", "run the Python audit", "run the Java audit", "run the Go audit", "run the Rust audit", or "run the JavaScript audit"
3. **Review the audit results** — output depends on scope:

   **Full phase-completion audit** (default when the user says "run the audit" or "verify phase completion" without naming a section):
   - Per-violation report: severity (CRITICAL/HIGH/MEDIUM/LOW), file, lines, recommended fix, effort estimate
   - **Section G** from the invoked language audit: cleanliness score table (G1), Top 10 files (G2), technical debt tracker (G3)
   - Exit line: `Ready for Phase [X+1]? YES/NO`

   **Section-specific audit** (e.g. "Run Section A"):
   - Output only for the requested section(s)
   - Section G deliverables are not required unless Section G is explicitly requested or a full audit is run

   All `*-brutal-audit.mdc` files share Section G structure; see the invoked audit file for the exact template.

4. **Address blockers** — before proceeding to the next phase (applies to **full** audits, not sectional spot-checks):
   - Fix all CRITICAL and HIGH severity issues
   - Document any acceptable technical debt
   - Ensure the full audit concludes with "Ready for Phase [X+1]? YES"

## Integration with Development Standards

These audits complement the always-on rules:

- **Always-on rules** (`general-llm-anti-patterns.mdc`, language-specific standards) prevent issues during development
- **Brutal audits** provide deep, milestone-based validation after phase completion

Both work together to ensure code quality throughout the development lifecycle.

## Best Practices

- Run audits after each major phase completion
- Don't skip audits even if code "looks good"
- Use audit results to track technical debt over time
- Address CRITICAL issues before proceeding to next phase
- Keep audit reports for regression tracking

## See Also

- `RULE_COMPOSITION.md` - Standard section order and rule structure
- `swift-5-9-brutal-audit.mdc` - Swift 5.9/iOS comprehensive audit
- `swift-6-brutal-audit.mdc` - Swift 6/iOS comprehensive audit
- `python-3-brutal-audit.mdc` - Python comprehensive audit
- `java-brutal-audit.mdc` - Java 17/21 comprehensive audit
- `go-1-21-brutal-audit.mdc` - Go 1.21+ comprehensive audit
- `javascript-3-brutal-audit.mdc` - JavaScript/TypeScript comprehensive audit
- `rust-brutal-audit.mdc` - Rust comprehensive audit
- `critical-rules-quick-reference.mdc` - Quick reference for when to run audits
- Language-specific development standards files for ongoing guidance
