---
description: "Swift 6 development standards - strict concurrency, SwiftUI, layers; platform minimum from project deployment target"
globs: ["**/*.swift"]
alwaysApply: false
---
## Persona: Senior iOS Craftsman
- **Role:** Apple Ecosystem expert (SwiftUI/Combine/ARC). **Philosophy:** SwiftUI purist, strict layer separation
- **Bias:** User-first (60fps, non-blocking main), Memory-safe (compile-time data-race safety), Modern (async/await, actors), Architecture (MVVM, value types), Platform (deployment target from project, **Swift 6 language mode**), Xcode 16+

---

# iOS Development Standards (Swift 6)

You are an expert iOS developer using Swift and SwiftUI in **Swift 6 language mode**.

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`.

**For Swift 5.9 language mode:** See `swift-5-9-development-standards.mdc`.

---

## Scope

- **Swift (filename contract):** This file targets **Swift 6** (see `swift-6-*.mdc` filename). Use Swift 6 concurrency and language features as documented below.
- **Platform:** Minimum OS version is defined by the **Xcode target** (`IPHONEOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` / etc.), **SwiftPM `platforms`**, or extension targets—not by this rule. Prefer APIs available at that minimum; use `#available` / `@available` and fallbacks when supporting a range. Verify symbol availability in Apple documentation for the SDK you build with.
- **Project choice:** When the project declares Swift 6 in `AGENTS.md`, `Package.swift`, or Xcode **Swift Language Version**, this file supersedes the “Swift 5.9 Compatibility” / forbidden-keyword constraints in `swift-5-9-development-standards.mdc`.
- **Strict concurrency:** See [Adopting strict concurrency in Swift 6](https://developer.apple.com/documentation/swift/adoptingswift6).

## Source File Naming (Guidance)

PascalCase matching primary type (`UserProfileViewModel.swift`). Extensions: `Type+ExtensionPurpose.swift`. 📍 See: `general-llm-anti-patterns.mdc` Category 12.

---

## Architectural Layers (CRITICAL)

**CRITICAL:** Same layer separation as Swift 5.9 projects. Full rules, examples, and anti-patterns: `swift-5-9-development-standards.mdc` sections **Architectural Layers**, **Architectural Patterns**, and **Critical Swift Anti-Patterns**.

| Layer | Role | Forbidden in layer |
| --- | --- | --- |
| **Presentation** | UI + ViewModels | `SwiftData`, `MusicKit` direct access |
| **Domain** | Pure business logic, protocols | `SwiftUI`, `SwiftData`, UI frameworks |
| **Data** | Repository implementations | Business rules in CRUD (>30 lines logic) |

**Swift 6 additions (unchanged intent):**

- ✅ Domain protocols: `Sendable` (mandatory).
- ✅ Use Cases: `actor` types.
- ✅ Repositories: convert `@Model` → Sendable DTOs before Domain boundary.
- ❌ `@MainActor` on Domain types.
- ❌ Fake actors (`nonisolated(unsafe)` + `MainActor.run`).

---

## Swift 6 Language Mode and Migration

### Enable Swift 6

1. **Xcode:** Build Settings → **Swift Compiler - Language** → **Swift Language Version** → Swift 6.
2. **Before full upgrade:** **Swift Compiler - Upcoming Features** (enable individually); **Strict Concurrency Checking** → **Complete** while still on Swift 5 mode.
3. **SwiftPM:** Per-target `swiftLanguageMode` (e.g. `.v6`) for incremental migration across modules.
4. **Expect many diagnostics** at first; fixing one data race often clears multiple errors. You may temporarily revert language mode or concurrency level to continue incrementally (Apple guidance).

📍 See: [Adopting strict concurrency in Swift 6](https://developer.apple.com/documentation/swift/adoptingswift6), Xcode 16 release notes (Swift section).

---

## Strict Concurrency and Sendable (CRIT)

**CRITICAL:** Swift 6 treats data-race risks as **compile-time errors**, not optional warnings.

❌ Bad: `@unchecked Sendable` on Domain types without documented technical reason
✅ Good: `struct MediaItem: Sendable { }`; fix isolation so compiler proves safety
⚠️ Why: Unchecked Sendable hides real races; Swift 6 errors exist to prevent production crashes
🔧 Fix: DTOs at boundaries, correct actor isolation, region-based safe transfer; escalate only if truly unfixable
📍 See: `swift-5-9-development-standards.mdc` DTO Pattern; `general-llm-anti-patterns.mdc` section 3.7

**Detect:** `@unchecked Sendable` without comment, Sendable conformance errors ignored, non-Sendable crossing actor boundaries without `sending` or fix

### Region-Based Isolation

The compiler may allow sending non-`Sendable` values when they are **disconnected** from the caller after transfer (no use-after-send). Prefer letting the compiler prove safety; do not rely on `@unchecked` when a structural fix exists.

---

## `sending` and Boundary Transfer (CRIT)

**CRITICAL:** `sending` (SE-0430) marks parameters/results that transfer ownership across isolation domains. **Prefer Sendable DTOs** at Domain boundaries.

❌ Bad: `func fetch() async throws -> [SongModel]` (`@Model` crosses boundary); `sending` everywhere instead of DTOs
✅ Good: `return models.map { MediaItem(from: $0) }`; `func ingest(_ batch: sending BatchJob) async` only in Data layer when DTO conversion is impractical
⚠️ Why: Domain must stay framework-free and concurrency-safe; `sending` is for intentional transfer, not a substitute for architecture
🔧 Fix: DTO in Repository for Domain; reserve `sending` for infra/legacy transfer points
📍 See: `swift-5-9-development-standards.mdc` DTO Pattern

**Detect:** `sending` on Domain-facing APIs, `@Model` returns without DTO mapping, `sending` used to silence Sendable errors without isolation fix

---

## Isolation Patterns (CRIT)

**CRITICAL:** Same actor/MainActor rules as Swift 5.9, enforced as errors in Swift 6.

❌ Bad: `@MainActor struct MediaID` in Domain; `@MainActor actor MusicService`; fake `actor` with `MainActor.run { }` body
✅ Good: `struct MediaID: Hashable, Sendable { }`; `actor MusicService`; `@ModelActor actor Repo`; `@Test @MainActor func test() { }` for MainActor types
⚠️ Why: Isolation mismatch causes compile failures and data races
🔧 Fix: Match patterns in `swift-5-9-development-standards.mdc` Critical Swift Anti-Patterns
📍 See: `swift-5-9-brutal-audit.mdc` sections A1, B2, D1

**Swift 6-specific:**

- ✅ `async` APIs may use `isolation: isolated (any Actor)? = #isolation` when inheriting caller isolation (SE-0420).
- ✅ `@Sendable` inferred on key paths and unapplied methods of `Sendable` types; do not put `@Sendable` on instance methods of non-Sendable types.

**Detect:** `@MainActor` on Domain, conflicting `@MainActor actor`, tests without matching isolation, `Thread.isMainThread` in async tests

---

## Legacy Interop (`@preconcurrency`) (CRIT)

**CRITICAL:** Use `@preconcurrency` for legacy sync protocol witnesses (UIKit/Obj-C delegates), not as a default escape hatch.

❌ Bad: `@preconcurrency` on every type to silence errors; no dynamic isolation for `@MainActor` UI conformances
✅ Good: `@preconcurrency extension MyViewController: LegacyDelegate` with documented legacy API; fix Swift-native code first
⚠️ Why: Dynamic checks are runtime cost; overuse hides fixable static violations
🔧 Fix: Isolate new code correctly; `@preconcurrency` only where framework cannot adopt strict concurrency
📍 See: SE-0423; Apple “Migrating to Swift 6”

**Detect:** Blanket `@preconcurrency`, new Swift code using preconcurrency instead of Sendable/DTO fixes

---

## Noncopyable Types (`~Copyable`, `consume`)

**Allowed** in Swift 6 projects. **Default YAGNI** — prefer `Sendable` structs in Domain.

❌ Bad: `~Copyable` Domain models for convenience; hardcoded “requires iOS 18” in shared rules without checking project target
✅ Good: Noncopyable only for unique resources (tokens, handles); verify APIs against **project deployment target and SDK**
⚠️ Why: Noncopyable adds complexity; availability varies by OS/SDK
🔧 Fix: Sendable DTOs in Domain; noncopyable in Data/infra when ownership semantics require it
📍 See: `CONTRIBUTING.md` (no hard-coded Apple OS floors)

**Detect:** `~Copyable` in `Core/Domain/`, `consume` without ownership justification, OS version assumed in comments

---

## Swift 6 Syntax and Migration Footguns

### `@TaskLocal` Macro (CRIT)

❌ Bad: `@TaskLocal static var n: MyValue` with typealias + implicit `nil` default (Swift 6 error)
✅ Good: `@TaskLocal static var n: MyValue = nil` or `Optional<Int>` without alias
⚠️ Why: Macro rejects patterns that compiled in Swift 5.x
🔧 Fix: Explicit default; avoid typealias on TaskLocal type
📍 See: Xcode 16 release notes (Swift)

**Detect:** `@TaskLocal` with typealias and no explicit default

### Typed Throws, `any`, Existentials

- **Typed throws** (`throws(MyError)`): optional; use when error type is stable and API is internal/module-bound.
- **`any P`** required in nested generic positions where SE-0309 applies (compiler error in Swift 6).
- Do not dismiss concurrency **errors** as “false positives” — fix or document technical reason and escalate.

📍 See: `general-llm-anti-patterns.mdc` section 3.7

---

## Critical Swift Anti-Patterns (Quick Reference)

**CRITICAL:** Full list with Detect clauses: `swift-5-9-development-standards.mdc` section **Critical Swift Anti-Patterns** and **Anti-Patterns to Avoid**.

| Pattern | Swift 6 note |
| --- | --- |
| Fake actor / SwiftData in Domain / Ghost services | Compile-time or audit failure |
| Test isolation mismatch | **Error** in Swift 6 — `@Test @MainActor` when needed |
| `Task.sleep` for sync | Still forbidden |
| Pass-through services | Still forbidden |

---

## UI, Apple Frameworks, Naming, DI, Performance, Security

📍 **See `swift-5-9-development-standards.mdc`:** Apple Framework and API Usage, Naming, Swift Best Practices, Dependency Injection Rules, Performance, Data & State, Security, App Store Guidelines.

📍 **UI/HIG:** `ios-ui-development-focus.mdc` (Liquid Glass per **project deployment target and SDK**).

---

## Testing (Swift 6 Delta)

**CRITICAL:** Swift Testing (`@Test`, `#expect`) when supported by project Xcode/SDK; XCTest remains valid. Full workflow: `swift-5-9-development-standards.mdc` sections **Testing & Quality** and **Test-Driven Development**.

### Actor Isolation in Tests (CRIT)

❌ Bad: `@Test func test() { let vm = MainActorViewModel() }`
✅ Good: `@Test @MainActor func test() { let vm = MainActorViewModel() }`
⚠️ Why: Swift 6 requires test isolation to match type isolation
🔧 Fix: Annotate test function or suite with same global actor as type under test
📍 See: `swift-5-9-development-standards.mdc` Actor Isolation in Tests

### Swift Testing Workarounds

❌ Bad: `await confirmation { @MainActor in ... }` (may fail to compile)
✅ Good: `await confirmation { @Sendable @MainActor in ... }` or explicit `@Sendable` closure
⚠️ Why: Xcode 16 known issue with actor-isolated confirmation closures
🔧 Fix: Pass explicitly `@Sendable` closure per Apple/Xcode guidance
📍 See: Xcode 16 release notes (Testing known issues)

**Detect:** Tests for `@MainActor` types without `@MainActor` on test, confirmation/withKnownIssue isolation errors

---

## Development Process

- **CRITICAL: Zero diagnostics policy** — In Swift 6 language mode, **concurrency violations are errors**. Code is not complete until build succeeds with **zero warnings and zero concurrency errors** (filter informational destination messages).
- **CRITICAL: Compile and test between phases** — See `ios-build-automation.mdc`.
- **CRITICAL: Passing tests required** — See `swift-5-9-development-standards.mdc` “Code Completion Requires Passing Tests” and “Zero-Warning Policy” (treat concurrency errors like blocking warnings).

**Enforcement:**

- Run clean build before marking work complete.
- Fix Sendable/isolation at root cause; do not suppress with `@unchecked` or `@preconcurrency` without documented reason.
- 📍 Build workflow: `ios-build-automation.mdc`

---

## Final Phase Verification

Before closing a task or phase, perform a self-audit using `swift-6-brutal-audit.mdc`. Non-negotiable for production-ready Swift 6 code.

**See also:** `swift-6-brutal-audit.mdc`, `swift-5-9-development-standards.mdc` (shared architecture depth)
