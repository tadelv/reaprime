---
description: "Phase-based brutal audit workflow for Java 17/21 projects - on-demand architectural review"
globs: ["**/*.java"]
alwaysApply: false
---

# Java Brutal Audit Workflow

This rule defines the workflow for conducting a "Brutal Audit" of the Java codebase.

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
**Version:** 1.0 (Java 17 LTS and Java 21 LTS, Effective Java, Google Java Style Guide)

We have just finished Phase [X]. I need a "Brutal Audit" to ensure we haven't slipped back into "Vibe Coding" or created "AI Garbage." Analyze the current codebase against `.cursor/rules/java-17-development-standards.mdc`, `.cursor/rules/java-21-development-standards.mdc`, `.cursor/rules/general-llm-anti-patterns.mdc`, and `PRODUCT_SPECIFICATION.md` (if present).

---

## Determine Java Version

**Before running version-specific checks (Section C, F4):**

1. Infer target from: `pom.xml` (maven-compiler-plugin `source`/`release`), `build.gradle` / `build.gradle.kts` (`sourceCompatibility`/`JavaLanguageVersion`), `java.version` in Gradle, or `.sdkmanrc` / `.java-version`.
2. If unclear, assume **Java 17** and run Java-17–specific checks only.
3. **Apply only the version-specific subsections (C1–C4, F4) that match** the project's Java version.

---

## 🟢 PRE-AUDIT: Self-Verification Checklist

**Verify before audit:**

- No unverified dependencies (Maven Central / registry for `pom.xml` and `build.gradle` coordinates)
- No `// TODO:` or `// FIXME:` in production `.java` (exclude `*Test.java` / `*IT.java` if desired)
- No discarded results: e.g. `findUser(id);` (ignored `Optional`), or `@SuppressWarnings` without clear justification
- No I/O in loops: `for`/`stream` that perform DB, HTTP, or file I/O per element
- No >80% single-line delegation in Service/Manager classes (`return repo.method()`)
- No hardcoded secrets (API keys, passwords, connection strings)
- No silent failures: `catch (Exception e) { }`, `catch (Exception e) { e.printStackTrace(); }`, or empty catch
- Security (OWASP): see `owasp-secure-coding-practices.mdc` for full checklist

**Tool:** Use `grep` with patterns such as: `TODO|FIXME`, `catch\s*\(\s*Exception`, `\.printStackTrace\s*\(`, `return null;` (in methods returning collections), `\.get\s*\(\s*0\s*\)`, `\.get\s*\([^)]*\.size\s*\(\s*\)\s*-\s*1\s*\)`, etc.

---

## 🔵 PRE-CODE GENERATION: Chain-of-Thought Checkpoints

**Before generating code, identify:**

1. Which layer affected (Domain/Data/Presentation or `domain`/`service`/`repository`/`persistence`)
2. Similar pattern exists? (Check codebase first)
3. Framework or JDK provides direct API? (Verify docs)
4. Ghost layer candidate? (>80% delegation check)

---

## 🔴 SECTION A: Critical LLM Anti-Pattern Detection

### A1. "Fake Concurrency" / Misused Concurrency

**Java 17:**

- `new Thread(...).start()` in application code
- `Executors.newCachedThreadPool()` with no effective bound under load
- Fire-and-forget `executor.submit(...)` when completion or cancellation matters

**Java 21:** Same as above, plus:

- Virtual Thread executor used as a fixed-size pool (e.g. `newFixedThreadPool(n, Thread.ofVirtual().factory())`)
- `synchronized` in code paths that run on virtual threads (pinning)
- Heavy `ThreadLocal.withInitial(Expensive::new)` in VT-heavy code

**Violation:** Concurrency that declares structure but has no lifecycle, or (Java 21) defeats virtual thread benefits.
**Fix:** Java 17: ExecutorService with `invokeAll`/`CompletableFuture.allOf`; Java 21: `newVirtualThreadPerTaskExecutor`, `ReentrantLock` instead of `synchronized`, `StructuredTaskScope` for related tasks.

### A2. Pass-Through "Ghost Layer" Services

Check services in typical `*Service`, `*Manager` packages:

- If >80% of methods are single-line `return repository.method()` or `return xxxRepository.findById(...)` with no coordination or logic, it's a ghost layer.
- If a service wraps only ONE repository with no branching, validation, or composition, flag it.

**Evidence to provide:** Count of pass-through methods vs. methods that add value.

### A3. Dead Code Detection

Search for:

- Methods that always `throw new UnsupportedOperationException()` or `return null` as placeholder
- `Optional.get()` without `isPresent()` or functional handling; or calling `findX()` and ignoring the result when it can be absent
- `// TODO:` / `// FIXME:` in production code
- `@SuppressWarnings` with no short justification
- Unused imports; `assert` used for production control flow

### A4. O(N²) Collection / I/O Operations

Flag any pattern like:

```java
for (T item : items) {
    repo.save(item);  // Each call = I/O
}
// or
items.forEach(i -> httpClient.post(i));
```

- Fetching full list to remove/update one by ID; building DTOs for all to find one.
- **Check:** Bulk/batch APIs (`saveAll`/`deleteAll`); batch size limits.

### A5. "Hallucination-Implementation" / JDK Workarounds

Search for:

- Custom parsing when `String.formatted`, text blocks, or `java.net.http.HttpClient` suffices
- Multi-step search by ID when `Map.get(id)` or `findById(id)` exists
- Comments saying "JDK doesn't provide X" without doc check
- Raw types when generics would work; reimplementing `List.of`/`Stream`-based logic

### A6. AI-Apologetic Defensive Comments

Flag comments that:

- Are 5+ lines explaining why "unsafe" or workaround code is "actually safe"
- Repeat the same explanation in multiple files
- Say "This pattern is recommended because..." for workarounds
- Justify `@SuppressWarnings`, swallowed exceptions, or `Optional.get()`

**Rule:** If you need a paragraph to justify code, the code is wrong.

---

## 🟠 SECTION B: Layer Boundary and Business Logic

### B1. Domain / Package Boundary Purity

Scan domain (or `core`/`model`) packages:

```bash
grep -r "import java.sql\|import javax.sql\|import jakarta.persistence\|import org.springframework\|import java.net.http" --include="*.java" src/main/java/*/domain/ src/main/java/*/core/ src/main/java/*/model/
```

**Result should be minimal** - only for type references or minimal, documented exceptions. Framework/DB imports in domain packages = immediate fix required.

### B2. Interface and API Design

- Interfaces in consumer packages vs. producer; avoid >5-method interfaces when it violates segregation
- Return/parameter types: prefer `List`, `Map`, `Set` over `ArrayList`, `HashMap`, `HashSet` where the interface is sufficient

### B3. Error and Exception Boundaries

- Exceptions wrapped with cause (`new ServiceException("msg", e)` or `initCause`); no `throws Exception` in public API
- No `throw new RuntimeException("…")` without a domain exception where recoverable

### B4. Business Logic in Repositories

Flag any Repository/DAO method that:

- Contains business rules (validation beyond data integrity)
- Calculates derived values (should be in domain/service layer)
- Has >30 lines of non-CRUD logic (Repositories should be CRUD only)
- Contains `switch` statements for business decisions

**Fix:** Move to domain/service; keep repos as CRUD + simple queries.

---

## 🟡 SECTION C: Concurrency, Collections, and Version-Specific Behavior

### C1. Concurrency — If Java 17

- `ExecutorService` for I/O: sized `newFixedThreadPool` or bounded cached; no raw `new Thread().start()`
- Related tasks: `invokeAll`, `CompletableFuture.allOf`/`join`, or `CountDownLatch`/`CyclicBarrier`; no fire-and-forget when completion/cancellation matters
- `ThreadLocal`: cheap `withInitial`; `remove()` when done (e.g. in `finally` or request scope); prefer parameters over `ThreadLocal` where possible

### C2. Concurrency — If Java 21

- I/O: `Executors.newVirtualThreadPerTaskExecutor()` or `Thread.startVirtualThread(...)`; no pooling of virtual threads
- No `synchronized` in virtual-thread I/O paths (use `ReentrantLock`); no heavy `ThreadLocal` in VT-heavy code (prefer `ScopedValue` or parameters)
- Related tasks: `StructuredTaskScope` (ShutdownOnFailure/ShutdownOnSuccess) instead of fire-and-forget or ad-hoc `CompletableFuture` chains

### C3. Collections — First/Last/Reverse (Version-Specific)

**Java 17:**

- `list.get(0)`, `list.get(list.size()-1)` without prior `isEmpty()` → flag
- Reverse: acceptable `Collections.reverse(new ArrayList<>(list))` or indexed backward loop; ad-hoc reverse without empty check → flag

**Java 21:**

- Prefer `getFirst()`, `getLast()`, `reversed()`; flag `get(0)`/`get(size()-1)` where `SequencedCollection`/`List` supports the new API

### C4. Pattern Matching and Switch (Version-Specific)

**Java 17:**

- `instanceof` + explicit cast: `(String) obj` after `instanceof String` → prefer `instanceof String s`
- For sealed/type hierarchies: `instanceof` chains or visitor; type-pattern `switch` is not in 17

**Java 21:**

- Prefer type-pattern `switch` for sealed types; avoid `default` that hides missing cases when exhaustiveness is possible; redundant `instanceof`+cast → flag

### C5. Hot Path and General Performance

- `String` `+=` in loops → `StringBuilder` or `String.join`/`Collectors.joining`
- `parallelStream()` with I/O, or with shared mutable state; `parallelStream` on small or trivial ops without justification
- Prefer `List.of`/`Set.of`/`Map.of` for constants; mutable collections returned without `List.copyOf` or equivalent
- Single-item ops: avoid loading full collection; use `findById`/indexed lookups

---

## 🟢 SECTION D: Test Quality

### D1. JUnit 5 and AssertJ

- No `@org.junit.Test` (JUnit 4); use `org.junit.jupiter.api.Test`, `@BeforeEach`, etc.
- Prefer `assertThat(...).isEqualTo(...)` over `assertEquals`; avoid `assertTrue(x.equals(y))`-style

### D2. Test Naming and Structure

- Names: `should...When...` or `given..._when..._then...`; no `testGetUser`, `test1`, or purely method-name-based

### D3. One Concept and Parameterized Tests

- One behavior per test; multiple assertions for the same concept allowed
- Same logic over many inputs: `@ParameterizedTest` with `@CsvSource`/`@ValueSource`/`@MethodSource`; avoid copy-pasted `testX1`, `testX2`

### D4. Mocks and Isolation

- External deps (DB, HTTP, files) mocked; no real DB/network in unit tests
- Mocks match real method signatures and failure behavior (e.g. exceptions)

### D5. Coverage and Error Paths

- Public service/repository methods; error and edge cases; no tests that depend on order or shared mutable state

---

## 🔵 SECTION E: Java and Build Compliance

### E1. Compiler and Static Analysis

Run `mvn compile` or `gradle compileJava` (and `compileTestJava` if applicable); record compiler and lint (e.g. SpotBugs, Error Prone) warnings.

**Do not claim "compiles" or "zero warnings" without showing output.** Per `critical-rules-quick-reference.mdc`: use "Build verification pending" or show actual build output.

### E2. Dependencies and Build Files

- `pom.xml` / `build.gradle`: versions managed (BOM or version catalog); no unverified coordinates; `*SNAPSHOT` or floating versions justified
- Prefer JDK over extra libs for `Optional`, `Stream`, `HttpClient`, `List.of`, etc.

### E3. Style and Formatting

- Consistent formatting (e.g. Google Java Format, project formatter); import order; no `var` where it obscures types (e.g. `var x = service.returnsComplexType()`)

### E4. Javadoc and Public API

- Public classes, interfaces, and methods: Javadoc with `@param`, `@return`, `@throws` where relevant; no Javadoc that only restates the name

---

## 🟣 SECTION F: Java-Specific Patterns

### F1. Optional and Null

- `Optional` for return only; no `Optional` fields, `Optional` parameters, or `List<Optional<T>>`
- No bare `Optional.get()`; use `orElse`, `orElseGet`, `orElseThrow`, `map`, `ifPresent`
- `Objects.requireNonNull(param, "message")` (or equivalent) at method entry for non-null params
- Return `List.of()` or `Collections.emptyList()` instead of `null` for collections

### F2. Resources and Exceptions

- `AutoCloseable` in try-with-resources; no manual `close()` in `finally` where TWR is possible
- No empty `catch`; no `printStackTrace()` in production; preserve cause when rethrowing
- No control flow via exceptions (e.g. catch `ArrayIndexOutOfBoundsException` to exit loop)

### F3. Records, Immutability, and Types

- DTOs/value objects with only final fields + accessors → prefer `record`; setters on data carriers → flag
- Raw types: `List`, `Map` without type args → flag (except when interfacing with legacy and documented)
- Magic numbers/strings: extract to constants or enums

### F4. JVM and GC (Version-Specific, if runscripts or ops docs exist)

**Java 17:**

- ZGC: `-XX:+UseZGC` (non-generational); G1/ParallelGC for balanced/batch. In containers: `-XX:MaxRAMPercentage`/`-XX:InitialRAMPercentage` instead of hardcoded `-Xmx`

**Java 21:**

- ZGC: `-XX:+UseZGC -XX:+ZGenerational` when targeting low latency; same container heuristics. AppCDS/startup: mention if relevant (e.g. serverless, CLI)

---

## 📊 SECTION G: Scoring and Prioritization

### G1. The "Cleanliness" Verdict

On a scale of 1-10 (1 = Pure Architecture, 10 = Vibe Coding Mess):

| Category | Score | Critical Issues |
| --- | --- | --- |
| Package/Layer Boundary Compliance | /10 | |
| Error Handling | /10 | |
| Concurrency Safety | /10 | |
| Performance (Hot Paths) | /10 | |
| Test Quality | /10 | |
| Java/Build Compliance | /10 | |
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
| Missing Javadoc | | |
| Raw types | | |
| Silent failures / swallowed exceptions | | |
| Compiler / lint warnings | | |

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

### X1. Build and Test Execution

**Action:** Run build and test suite; verify all tests pass.

**Tool:** Use `run_terminal_cmd` to execute:

- Maven: `mvn clean test`
- Gradle: `gradle test` or `./gradlew test`

**Do not claim "all tests pass" without output.** Per `critical-rules-quick-reference.mdc`: use "Test verification pending" or show actual test output.

**Evidence Required:**

- Build and test output showing pass/fail counts
- Any failing tests flagged as CRITICAL violations
- Test coverage metrics (if available)

### X2. Runtime and Exception Handling

**Action:** Check for exceptions that aren't handled properly.

**Tool:** Use `grep` to find:

- Empty `catch` blocks
- `printStackTrace()` in production code
- `Optional.get()` without guard
- Ignored return values of `find*`-style methods

**Evidence Required:**

- List of unhandled exceptions with file locations
- Severity: CRITICAL if in production paths

### X3. Silent Failure and Context

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
🚨 [CRITICAL/HIGH/MEDIUM/LOW] - Category A1: Fake Concurrency / Misused Concurrency
📍 File: com/example/service/WorkerService.java
📝 Lines: 45-120
❌ Issue: executor.submit(() -> fetch(id)) fire-and-forget when completion matters
✅ Fix: Use invokeAll, CompletableFuture.allOf, or (Java 21) StructuredTaskScope
⏱️ Effort: Medium (2-4 hours)
```

End with: **"Ready for Phase [X+1]? YES/NO - If NO, list blockers."**

---

## 🚀 Quick Reference: The 15 Anti-LLM-Trap Rules (Java)

1. **Concurrency** - ExecutorService (17) or Virtual Threads (21); no fire-and-forget; no VT pooling (21); no pinning (21)
2. **No Pass-Through Services** - Services must add value
3. **No Dead Code** - No placeholder methods, TODO/FIXME in prod, or discarded `Optional`/important results
4. **Batch I/O** - No per-element DB/HTTP in loops
5. **Business Logic in Domain** - Repositories are CRUD only
6. **Use JDK and Framework APIs** - No unnecessary workarounds
7. **Extract Repeated Patterns** - DRY; parameterized tests for matrix logic
8. **No Defensive Commenting** - Refactor instead of justify
9. **Optimize Hot Paths** - No full-load-for-one; `StringBuilder` in loops; `getFirst`/`getLast`/`reversed` (21) or `isEmpty`+index (17)
10. **Optional for Returns Only** - `requireNonNull` at boundaries; no null collections
11. **Try-with-Resources** - No swallowed exceptions; preserve cause
12. **Program to Interfaces** - Prefer `List`/`Map`/`Set` in API
13. **JUnit 5 + AssertJ** - Descriptive names; mocks at boundaries
14. **Records/Immutability** - No raw types; constants for magic values
15. **Build/Test Evidence** - Never claim "compiles" or "tests pass" without evidence
