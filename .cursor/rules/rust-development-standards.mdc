---
description: "Rust development standards: idioms, style, anti-patterns (Rust 2021 edition, 2024 where applicable)"
globs: ["**/*.rs"]
alwaysApply: false
---

## Persona: Rust Systems Engineer
- **Role:** Systems/library author. **Philosophy:** Safety and clarity over cleverness; lean on the type system and the compiler.
- **Bias:** Errors as values (Result/Option); no hidden panics in libraries; ownership by default; std/crates.io over custom code; rustfmt + clippy.

---

# Rust Development Standards

**Target:** Rust 2021 edition (or 2024 where applicable).

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`.

---

## Philosophy

- **Errors as values:** Result/Option; propagate with ?; handle at boundaries; no silent failures.
- **Ownership by default:** Prefer references/borrows; avoid unnecessary clone; no hidden panics in library code.
- **Std and crates.io:** Prefer standard library and well-maintained crates over custom reimplementations.
- **Tooling:** rustfmt, clippy; run cargo build / cargo test before claiming success.

---

## Category 1: Error Handling

### 1.1 Handle Result/Option; Never Ignore (CRIT)

**CRITICAL:** Handle or propagate Result/Option; never ignore; propagate with context (map_err, .context(), or custom source).

❌ Bad: `let _ = foo()`, `bar().unwrap()` in library code
✅ Good: `foo()?` or `foo().map_err(|e| Error::Context { source: e })`; use anyhow::Context or thiserror at boundaries
⚠️ Why: Ignored errors hide bugs and make debugging impossible.
🔧 Fix: Use ? and add context at API boundaries; use typed errors (thiserror/anyhow).
📍 See: Rust Book ch 9; `general-llm-anti-patterns.mdc` section 5.3

**Detect:** `let _ =` on Result/IO, unwrap() in lib, bare ? at public API without context

### 1.2 Panic Discipline (CRIT)

**CRITICAL:** No unwrap()/expect() in library or public API code except with a one-line justification; document panics in # Panics.

❌ Bad: `fn load(path: &Path) -> Config { ... unwrap() }` in lib
✅ Good: `fn load(path: &Path) -> Result<Config, Error> { ... }`; in binaries, expect() only at boundaries with comment
⚠️ Why: Panics in libraries are not recoverable; callers cannot handle them.
🔧 Fix: Return Result/Option; use ?; document any remaining panics in doc comment.
📍 See: Rust Book ch 9; `general-llm-anti-patterns.mdc` section 5.3

**Detect:** `.unwrap(`, `.expect(` outside main/tests/examples, panic! in library code

### 1.3 Result vs Option (CRIT)

**CRITICAL:** Use Result for fallible operations; Option for "may be absent"; do not use Option when absence is an error.

❌ Bad: `fn parse(s: &str) -> Option<u32>` when parse failure is an error
✅ Good: `fn parse(s: &str) -> Result<u32, ParseError>`
⚠️ Why: Option loses error information; callers cannot recover or log.
🔧 Fix: Result for I/O, parsing, validation; Option for optional values only.
📍 See: Rust Book ch 9

**Detect:** Option for parse/IO failure, Result for "no value" without error type

---

## Category 2: Unsafe and Concurrency

### 2.1 Unsafe Only with Documented Invariants (CRIT)

**CRITICAL:** Use unsafe only with documented invariants; minimize scope; prefer std/safe abstractions.

❌ Bad: `unsafe { *ptr.add(i) = x }` with no comment
✅ Good: `// SAFETY: ptr is valid for len elements, i < len.` then minimal unsafe block
⚠️ Why: Unsafe without documentation causes undefined behavior and maintenance bugs.
🔧 Fix: Add // SAFETY: comment; shrink block; prefer Mutex, Atomic*, safe wrappers.
📍 See: Rustonomicon; `general-llm-anti-patterns.mdc` section 3.7

**Detect:** `unsafe {` without SAFETY comment, broad unsafe scope

### 2.2 Send and Sync (CRIT)

**CRITICAL:** Types used across threads must be Send/Sync where required; do not hide non-Send behind AssertUnwindSafe without justification.

❌ Bad: `unsafe impl Send for T` where T contains Rc<RefCell<U>>
✅ Good: Arc<Mutex<T>> or Arc<RwLock<T>> for shared state; let compiler derive when possible
⚠️ Why: Incorrect Send/Sync causes data races and undefined behavior.
🔧 Fix: Use thread-safe types; document any manual impl with Safety comment.
📍 See: Rust Book ch 16; `general-llm-anti-patterns.mdc` section 1.2

**Detect:** unsafe impl Send/Sync without comment, Rc/RefCell in thread-shared type

### 2.3 Async: No Blocking in Async (CRIT)

**CRITICAL:** Do not block inside async code; use spawn/cancellation explicitly (e.g. JoinSet, AbortHandle); no fire-and-forget without lifecycle.

❌ Bad: `block_on(...)` inside async fn, `spawn(...)` with no JoinHandle or cancellation
✅ Good: Use tokio::spawn with JoinHandle or JoinSet; use AbortHandle for cancellation; no blocking calls in async
⚠️ Why: Blocking in async stalls the runtime; fire-and-forget loses errors and prevents shutdown.
🔧 Fix: Use async I/O; spawn with JoinSet/AbortHandle; propagate errors and cancellation.
📍 See: `general-llm-anti-patterns.mdc` section 1.2 (fake abstraction)

**Detect:** block_on inside async, std::thread::sleep in async, spawn without JoinHandle when completion matters

### 2.4 Shared Mutable State (CRIT)

**CRITICAL:** No shared mutable state without synchronization; use Arc<Mutex<T>>, Arc<RwLock<T>>, or channels; avoid Rc<RefCell<T>> across threads.

❌ Bad: `static mut CACHE: Option<Vec<u8>> = None`, Rc<RefCell<T>> passed to spawn
✅ Good: Arc<Mutex<Vec<u8>>> or channel for cross-thread communication
⚠️ Why: Unsynchronized shared mutable state is undefined behavior.
🔧 Fix: Use Arc+Mutex/RwLock or channels; no static mut without sync.
📍 See: `general-llm-anti-patterns.mdc` section 5.6

**Detect:** Rc<RefCell<T>> across thread boundary, static mut without sync

---

## Category 3: Ownership and Cloning

### 3.1 Prefer References; Avoid Unnecessary Clone (CRIT)

**CRITICAL:** Prefer references/borrows; avoid .clone() when &T or Cow suffices; do not clone only to satisfy the borrow checker without refactoring.

❌ Bad: `fn process(s: String)` then `process(my_string.clone())` when read-only
✅ Good: `fn process(s: &str)` and `process(&my_string)` or `impl AsRef<str>`
⚠️ Why: Unnecessary clone costs allocation and encourages more clones.
🔧 Fix: Take &T or impl AsRef<T>; use Cow when ownership is conditional.
📍 See: Rust Book ch 4; `general-llm-anti-patterns.mdc` section 2.3

**Detect:** .clone() in hot paths, fn taking T when &T suffices, Arc when & suffices

### 3.2 Flexible API Boundaries (CRIT)

**CRITICAL:** Accept impl AsRef<Path>, impl Iterator<Item = T>, &[T], etc., to avoid forcing ownership.

❌ Bad: `fn read(path: PathBuf)`, `fn process(items: Vec<T>)` when caller has &Path or slice
✅ Good: `fn read(path: impl AsRef<Path>)`, `fn process(items: &[T])` or `impl IntoIterator<Item = T>`
⚠️ Why: Forcing ownership forces unnecessary clones and allocations.
🔧 Fix: Use impl AsRef, &[T], iterators; follow API Guidelines "flexibility".
📍 See: Rust API Guidelines (flexibility)

**Detect:** fn taking String when &str suffices, Vec when &[T] suffices

### 3.3 No Unbounded Collects (CRIT)

**CRITICAL:** Do not load entire iterators into memory when streaming or bounded iteration is possible.

❌ Bad: `let all: Vec<_> = huge_iter.collect(); for x in all { ... }` when processing one-by-one
✅ Good: `for x in huge_iter { ... }` or .take(n) / chunking when bounded
⚠️ Why: Unbounded collect can exhaust memory; aligns with performance-first collection handling.
🔧 Fix: Use iterators directly; use take()/chunks when a bound exists.
📍 See: `general-llm-anti-patterns.mdc` section 2.1, 2.3

**Detect:** collect() on large/unbounded iterator before loop, full load when streaming possible

---

## Category 4: Traits and API Design

### 4.1 Trait Design (CRIT)

**CRITICAL:** Respect orphan rules; ensure object safety when trait objects are needed; avoid trait creep (e.g. one trait with 10+ unrelated methods).

❌ Bad: Trait with 10+ methods, used as dyn Trait but not object-safe
✅ Good: Split into focused traits; use object-safe traits (no Self in params, no generic methods) when using dyn
⚠️ Why: Huge traits are hard to implement and use; non-object-safe traits cannot be used as dyn.
🔧 Fix: Split traits by concern; document object safety; prefer impl Trait when dyn not needed.
📍 See: Rust Book ch 10; Rust API Guidelines (interoperability)

**Detect:** Trait with many unrelated methods, dyn Trait used but trait has generic methods

### 4.2 Naming and Common Traits (CRIT)

**CRITICAL:** Follow Rust API Guidelines: as_/to_/into_ for conversions (C-CONV); iter/iter_mut/into_iter for collections; implement Debug and common traits (Clone, Default, Eq) where appropriate.

❌ Bad: `fn get_data(&self) -> &[u8]` when it is a view (use as_), public type without Debug
✅ Good: `fn as_bytes(&self) -> &[u8]`, `#[derive(Debug)]` or impl Debug for public types
⚠️ Why: Inconsistent naming and missing Debug confuse users and hurt diagnostics.
🔧 Fix: as_ (view), to_ (cheap copy), into_ (consuming); add Debug; add iter/iter_mut/into_iter for collections.
📍 See: Rust API Guidelines (C-CONV, C-ITER, C-DEBUG)

**Detect:** get_* when as_/to_/into_ fits, missing Debug on public type, missing iter/into_iter for collection

### 4.3 Constructors and Documentation (CRIT)

**CRITICAL:** Use inherent fn new() or fn new_*(...) for construction (C-CTOR); /// for public items; document # Panics and # Safety for unsafe.

❌ Bad: No new() when type is constructed in multiple places, public fn without ///, unsafe without Safety comment
✅ Good: fn new(), fn new_with_config(cfg: Config); /// with args/returns/panics; // SAFETY: for unsafe
⚠️ Why: Predictable constructors and docs are expected; missing safety docs are dangerous.
🔧 Fix: Add static constructors; add /// and panic/safety notes per API Guidelines.
📍 See: Rust API Guidelines (predictability, debuggability); `documentation-policy.mdc`

**Detect:** No new() for constructed type, public item without ///, unsafe without SAFETY comment

---

## Category 5: Collections and I/O

### 5.1 No I/O or Heavy Work in Loops (CRIT)

**CRITICAL:** Never do I/O or heavy work per item in a loop; use iterators and batching.

❌ Bad: `for x in items { write!(f, "{}", x)? }` in hot path without buffering, db/network per item
✅ Good: Buffer or batch writes; bulk APIs for DB/network; iterator chains
⚠️ Why: Per-item I/O causes O(N) syscalls and resource exhaustion.
🔧 Fix: Batch or buffer; use bulk APIs; align with universal 2.1.
📍 See: `general-llm-anti-patterns.mdc` section 2.1

**Detect:** write!/read/db/network inside for/while loop without batching

### 5.2 Preallocation (CRIT)

**CRITICAL:** Use Vec::with_capacity (and similar) when size is known; avoid repeated growth in hot paths.

❌ Bad: `let mut v = Vec::new(); for x in iter { v.push(x) }` when len is known
✅ Good: `let mut v = Vec::with_capacity(iter.size_hint().0); for x in iter { v.push(x) }`
⚠️ Why: Repeated growth causes reallocations and copies.
🔧 Fix: with_capacity when size known or bounded; use size_hint() when available.
📍 See: `general-llm-anti-patterns.mdc` section 2.3

**Detect:** Vec::new() in loop, push in loop without with_capacity when size known

---

## Category 6: Dependencies and Module Layout

### 6.1 Verify Crates (CRIT)

**CRITICAL:** Verify crates on crates.io; prefer minimal, well-maintained deps; no unversioned or unvetted dependencies (slopsquatting prevention).

❌ Bad: Adding a crate by name without checking crates.io, download count, or maintainer
✅ Good: Check crates.io, version pin in Cargo.toml, prefer std when sufficient
⚠️ Why: Slopsquatting and hallucinated names cause build failures and supply-chain risk.
🔧 Fix: Verify before adding; pin version; document replace/patches.
📍 See: `general-llm-anti-patterns.mdc` section 4.2, 4.2d

**Detect:** Unverified crate in Cargo.toml, no version constraint, heavy dep for trivial use

### 6.2 Module Layout (CRIT)

**CRITICAL:** Clear lib.rs/main.rs split; one main responsibility per module (SRP); avoid giant single-file or mixed binary/lib concerns.

❌ Bad: Giant lib.rs, mixed binary and library logic in one file
✅ Good: Focused modules (e.g. config, io, domain); main.rs only wires and calls lib
⚠️ Why: Mixed concerns create god modules and make testing and reuse hard.
🔧 Fix: Split into modules by responsibility; keep binary thin.
📍 See: Rust Book ch 12-03; `general-llm-anti-patterns.mdc` section 1.7

**Detect:** Single file >250 lines with mixed concerns, lib logic in main.rs

---

## Category 7: Style and Tooling

### 7.1 rustfmt (CRIT)

**CRITICAL:** Always use rustfmt; run before commit or in CI; mention 2024 style edition if project uses it.

❌ Bad: Manual indentation, inconsistent line length, no rustfmt in CI
✅ Good: `cargo fmt` before commit; CI: `cargo fmt -- --check`
⚠️ Why: Consistent style is standard; rustfmt is the single source of truth.
🔧 Fix: Run cargo fmt; add fmt check to CI.
📍 See: Rust Style Guide; `general-llm-anti-patterns.mdc` section 3.7

**Detect:** Inconsistent indentation, no rustfmt in CI

### 7.2 Clippy (CRIT)

**CRITICAL:** Use cargo clippy; fix or explicitly allow with a short reason; no "clippy is wrong" without a fix or documented reason.

❌ Bad: #[allow(clippy::xyz)] without comment, clippy warnings ignored in CI
✅ Good: Fix lint; or // Allowed: ... with reason; track allows in audit
⚠️ Why: Warnings indicate real issues; dismissing without fix creates debt.
🔧 Fix: Fix or allow with justification; run clippy in CI.
📍 See: `general-llm-anti-patterns.mdc` section 3.7, 3.8

**Detect:** #[allow(...)] without comment, clippy not in CI

### 7.3 Build and Test Claims (CRIT)

**CRITICAL:** Run cargo build and cargo test before claiming success; do not claim "compiles" or "tests pass" without output.

❌ Bad: "All code compiles with zero warnings" without running cargo build
✅ Good: "cargo build succeeded" with paste of output, or "Build verification pending"
⚠️ Why: False claims waste time and break trust.
🔧 Fix: Run cargo build / cargo test; show output or say verification pending.
📍 See: `general-llm-anti-patterns.mdc` section 3.8, 3.9

**Detect:** Claims "compiles"/"tests pass" without evidence

### 7.4 Source File Naming (Guidance)

**Guidance:** snake_case .rs files; mod name matches file name. Per general-llm-anti-patterns.mdc Category 12.

❌ Bad: CamelCase.rs, MyModule.rs
✅ Good: config.rs, http_client.rs
📍 See: Rust API Guidelines; `general-llm-anti-patterns.mdc` Category 12

**Detect:** PascalCase or mixed case .rs filenames

---

## Category 8: Testing

### 8.1 Unit Tests (CRIT)

**CRITICAL:** Use #[cfg(test)] mod tests { use super::* }; test both success and error paths.

❌ Bad: No #[cfg(test)] next to code, only happy path
✅ Good: #[cfg(test)] mod tests beside logic; tests for Ok/Err and edge cases
⚠️ Why: Untested code regresses; missing error-path tests hide bugs.
🔧 Fix: Add unit tests next to code; cover Err/None and boundaries.
📍 See: Rust Book ch 11; `general-llm-anti-patterns.mdc` section 6.2

**Detect:** No #[cfg(test)] mod tests, only Ok() tested

### 8.2 Doc Tests (CRIT)

**CRITICAL:** Use ? in doc examples when the example can fail; avoid unwrap() in examples (API Guidelines documentation).

❌ Bad: `/// let x = load().unwrap();` in doc comment
✅ Good: `/// let x = load()?;` or `/// # Ok::<(), Error>(())` at end of example
⚠️ Why: Examples with unwrap encourage the same in user code; ? shows proper propagation.
🔧 Fix: Use ? in examples; add error type or Ok(()) when needed.
📍 See: Rust API Guidelines (documentation)

**Detect:** unwrap() in /// example, missing ? in fallible example

### 8.3 Integration Tests and Mocks (CRIT)

**CRITICAL:** Integration tests in tests/*.rs using crate public API; mocks must match real API (signatures and behavior).

❌ Bad: Duplicate logic from unit tests, mock that returns different shape than real impl
✅ Good: tests/*.rs for crate API; mockall/traits or manual mocks that match real behavior
⚠️ Why: Wrong mocks give false confidence; integration tests should exercise real API.
🔧 Fix: tests/ for integration; ensure mocks match real API (general 6.1).
📍 See: `general-llm-anti-patterns.mdc` section 6.1, 6.2

**Detect:** No tests/ layout, mock returning different type/behavior than real

---

## Category 9: Anti-Patterns

### 9.1 Ghost Layers (CRIT)

**CRITICAL:** Types that only forward to one other type with no logic are ghost layers; delete or add value.

❌ Bad: >80% of methods are `self.inner.method(...)` with no coordination or logic
✅ Good: Layer coordinates multiple deps or adds domain logic; otherwise remove
⚠️ Why: Adds complexity without value; violates SRP.
🔧 Fix: Delete if >80% delegation; keep only if it adds value.
📍 See: `general-llm-anti-patterns.mdc` section 1.1

**Detect:** >80% pass-through methods, single dependency wrapper

### 9.2 Business Logic in Persistence Layer (CRIT)

**CRITICAL:** Repositories/transport are dumb I/O; business logic belongs in domain/core.

❌ Bad: Repository with switch on business rules, validation beyond data integrity
✅ Good: Repository is CRUD/serialization only; domain layer holds rules
⚠️ Why: Mixing concerns creates god objects and untestable code.
🔧 Fix: Move business logic to domain; keep persistence thin.
📍 See: `general-llm-anti-patterns.mdc` section 1.4

**Detect:** switch/match on business rules in io/repo modules

### 9.3 Placeholder and Dead Code (CRIT)

**CRITICAL:** No todo!(), unimplemented!(), or placeholder code in production paths.

❌ Bad: `fn run() { unimplemented!() }`, TODO in production code
✅ Good: Implement or remove; use #[allow(dead_code)] with comment only for intentional unused code
⚠️ Why: Placeholders break at runtime; dead code adds noise.
🔧 Fix: Implement or delete; do not commit unimplemented!() to main.
📍 See: `general-llm-anti-patterns.mdc` section 1.3

**Detect:** todo!(), unimplemented!(), TODO/FIXME in production

### 9.4 Duplicate Error Handling (CRIT)

**CRITICAL:** Use ? and shared error types; avoid repeated match/if let on the same Result pattern.

❌ Bad: Same 10-line match on Result in five places
✅ Good: Shared error type; ? at call sites; map_err at boundaries
⚠️ Why: Duplication violates DRY and makes changes error-prone.
🔧 Fix: Extract error type; use ? and map_err; centralize conversion.
📍 See: `general-llm-anti-patterns.mdc` section 3.1

**Detect:** Repeated identical Result handling blocks

---

## Summary: Critical Rust Rules

1. **Error handling:** Handle Result/Option; never ignore; panic discipline in libs; Result vs Option.
2. **Unsafe/concurrency:** SAFETY comment; Send/Sync correct; no blocking in async; no shared mutable state without sync.
3. **Ownership:** Prefer references; flexible API boundaries; no unbounded collects when streaming possible.
4. **Traits/API:** Trait design and object safety; naming (as_/to_/into_, iter); constructors and documentation.
5. **Collections/I/O:** No I/O in loops; preallocation when size known.
6. **Dependencies/modules:** Verify crates; clear module layout and SRP.
7. **Style/tooling:** rustfmt, clippy; run cargo build/test before claiming success; source file naming.
8. **Testing:** Unit + doc tests (? not unwrap) + integration; error paths; mocks match real API.
9. **Anti-patterns:** No ghost layers, no business logic in persistence, no placeholders in prod, no duplicate error handling.

---

## References

- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) (naming, interoperability, documentation, predictability, dependability)
- [The Rust Book](https://doc.rust-lang.org/book/) — Ch 9, 10, 11, 12, 12-03, 16
- [Rust by Example](https://doc.rust-lang.org/rust-by-example/) — Testing, Error handling
- [The Rustonomicon](https://doc.rust-lang.org/nomicon/) — Unsafe, Send/Sync
- [Rust Edition Guide](https://doc.rust-lang.org/edition-guide/) — 2021; 2024 for rustfmt/style
- [Cargo Book](https://doc.rust-lang.org/cargo/) — Tests, project layout
- rustfmt, Clippy, cargo doc

---

**See also:** `rust-brutal-audit.mdc` for phase verification.
