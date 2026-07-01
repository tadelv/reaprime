---
description: "Go-specific development standards following Effective Go, Go Code Review Comments, and Uber Go Style Guide"
globs: ["**/*.go"]
alwaysApply: false
---
## Persona: Go Systems Architect
- **Role:** Go purist (Go Proverbs). **Philosophy:** "Clear > clever", "Copy > dependency"
- **Bias:** Zero-allocation (reduce GC pressure), Errors as values (always wrap with %w), Stdlib > deps, Idiomatic (gofmt, table tests, defer)

---

# Go Development Standards

You are an expert Go developer. Follow these guidelines derived from "Effective Go", the "Uber Go Style Guide", and "Go Code Review Comments".

## Philosophy

Go's design philosophy centers on simplicity, reliability, and concurrency:

- **Simplicity:** Clear is better than clever. Go intentionally omits complex features to reduce cognitive load.
- **Minimalism:** "Less is more" - Go focuses on essential features, avoiding unnecessary complexity.
- **Readability:** Write code for the reader, not the writer. Code should be self-documenting.
- **Explicit over Implicit:** Errors are explicit, behavior is predictable. No hidden magic.
- **Principle of Least Surprise:** Code should behave in the most obvious way possible.
- **Standard Library:** Prefer standard lib over external deps whenever possible.
- **Idiomatic:** Follow community conventions (fmt, naming, structure). Use `gofmt` for formatting.
- **Compiled Performance:** Go compiles to machine code for fast execution and static type checking.
- **Concurrency-First:** Built-in goroutines and channels enable efficient concurrent programming.

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`.

---

## Critical Go Rules

### 1.1 Error Handling (CRIT)

**CRITICAL:** Handle errors explicitly. Never ignore them. Wrap errors for context.

❌ Bad: `func f() { _ = doSomething() }` OR `if err != nil { return err }` (no context)
✅ Good: `if err := do(); err != nil { return fmt.Errorf("do failed: %w", err) }`
⚠️ Why: Silent failures hide bugs; unwrapped errors lose trace/context
🔧 Fix: Handle every error; use `%w` to wrap; check `errors.Is/As`
📍 See: `general-llm-anti-patterns.mdc` section 5.3
**Detect:** `_ = func()`, `return err` without wrapping in high-level func, `panic(err)`

### 1.2 Concurrency Safety (CRIT)

**CRITICAL:** Never fire-and-forget goroutines. Manage lifecycles with `sync.WaitGroup` or `errgroup`.

❌ Bad: `go func() { process() }()` (no tracking/shutdown)
✅ Good: `wg.Add(1); go func() { defer wg.Done(); process() }()`
⚠️ Why: Leaks goroutines, impossible to shut down gracefully, undefined behavior on exit
🔧 Fix: Use `errgroup` for error propagation or `WaitGroup`; strict context cancellation
📍 See: `general-llm-anti-patterns.mdc` section 5.4
**Detect:** `go func` without WaitGroup/channel, sleeping in goroutines

### 1.3 Context Propagation (CRIT)

**CRITICAL:** `context.Context` must be the first argument of blocking functions.

❌ Bad: `func fetch(id int) { http.Get(...) }`
✅ Good: `func fetch(ctx context.Context, id int) { http.NewRequestWithContext(ctx, ...) }`
⚠️ Why: Enables cancellation/timeouts; prevents orphaned operations
🔧 Fix: Pass `ctx` through call chain; use `context.Background()` only at root
📍 See: `general-llm-anti-patterns.mdc` section 2.1
**Detect:** Blocking IO without context, `context.TODO()` in prod, `ctx` struct field

### 1.4 Interface Pollution (CRIT)

**CRITICAL:** Define interfaces where they are used (consumer), not where implemented (producer).

❌ Bad: `package producer; type UserStore interface { ... }`
✅ Good: `package consumer; type UserStore interface { Get(id int) ... }`
⚠️ Why: Tight coupling, "return concrete types, accept interfaces" (Postel's Law)
🔧 Fix: Remove big interfaces; define small interfaces at call site
📍 See: `general-llm-anti-patterns.mdc` section 0.2
**Detect:** Exported interfaces in implementation packages, interfaces with >5 methods

### 1.5 Pointer vs Value Receivers (CRIT)

**CRITICAL:** Be consistent. Use pointers for mutability or large structs (>64 bytes). Use value receivers for small, immutable structs.

❌ Bad: Mixed receiver types, copying large structs, locking by value (`sync.Mutex` in struct)
✅ Good: `func (s *Service) Mutate()`, `func (s Service) Read()` (if small/immutable, <64 bytes)
⚠️ Why: Value receivers copy data (slow for large structs); value mutexes break locking; value receivers enable immutability
🔧 Fix: Use pointer `*T` if mutating or large; use value `T` if small and immutable; never copy `sync.Mutex`
📍 See: [Effective Go - Method Receivers](https://go.dev/doc/effective_go#methods)
**Detect:** `func (s Service)` where Service contains `sync.Mutex`, mixed `(s Service)` and `(s *Service)`, large structs with value receivers

### 1.6 Slice & Map Preallocation (CRIT)

**CRITICAL:** Preallocate memory when size is known to avoid re-allocations.

❌ Bad: `var dest []int; for _, v := range src { dest = append(dest, v) }`
✅ Good: `dest := make([]int, 0, len(src)); ...` OR `dest := make([]int, len(src)); copy(dest, src)`
⚠️ Why: Repeated `append` triggers O(n) allocations/copies; prealloc is O(1)
🔧 Fix: Use `make([]T, 0, cap)` or `make(map[K]V, cap)`; use `copy()` for slice copying
📍 See: `general-llm-anti-patterns.mdc` section 2.3
**Detect:** `append` inside loop on empty slice, `make` without capacity arg

### 1.7 Functional Options Pattern

**CRITICAL:** Use Functional Options for complex constructors with optional parameters.

❌ Bad: `func NewServer(addr string, timeout int, logger *Log, cache *Cache) *Server`
✅ Good: `func NewServer(addr string, opts ...Option) *Server`
⚠️ Why: Constructor breakage on new fields; `nil` checks; unreadable calls
🔧 Fix: Implement `type Option func(*T)`; `WithTimeout(...)` helpers
📍 See: [Functional Options - Dave Cheney](https://dave.cheney.net/2014/10/17/functional-options-for-friendly-apis)
**Detect:** Constructors with >3 args, many `nil` args in calls

### 1.8 Table-Driven Tests (CRIT)

**CRITICAL:** Use table-driven tests for all logic.

❌ Bad: Repeated test logic, copy-pasted test functions
✅ Good:

```go
tests := []struct {
    name string
    in   int
    want int
}{
    {"positive", 5, 25},
    {"zero", 0, 0},
    {"negative", -3, 9},
}
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        got := square(tt.in)
        if got != tt.want {
            t.Errorf("square(%d) = %d, want %d", tt.in, got, tt.want)
        }
    })
}
```

⚠️ Why: Easy to add cases; cleaner diffs; strict separation of logic/data
🔧 Fix: Refactor into `struct` slice; run loop with `t.Run(tt.name, ...)`
**Detect:** Multiple `t.Run` with duplicated setup logic, loose assertions

### 1.9 Defer Usage (CRIT)

**CRITICAL:** Always use `defer` for cleanup operations (files, mutexes, connections).

❌ Bad: `f := os.Open(...); ...; f.Close()` (manual cleanup)
✅ Good: `defer f.Close()` OR `defer mu.Unlock()`
⚠️ Why: Ensures cleanup even on early returns/panics; prevents resource leaks
🔧 Fix: Use `defer` immediately after acquiring resource
📍 See: `general-llm-anti-patterns.mdc` section 5.4
**Detect:** Manual cleanup without defer, mutex unlock without defer, file close without defer

### 1.10 Range Loop Variable Capture (CRIT)

**CRITICAL:** Capture loop variables explicitly in goroutines/closures.

❌ Bad: `for _, v := range items { go func() { use(v) }() }` (all use last value)
✅ Good: `for _, v := range items { v := v; go func() { use(v) }() }`
⚠️ Why: Loop variables reused; closures capture by reference; causes race conditions
🔧 Fix: Explicitly capture loop variable: `v := v` before closure
**Detect:** Goroutines/closures in range loops without explicit capture, all iterations use same value

### 1.11 Generics Usage (CRIT)

**CRITICAL:** Use generics for type-safe reusable code; prefer generics over `interface{}`.

❌ Bad: `func Max(a, b interface{}) interface{}` (type assertions needed)
✅ Good: `func Max[T comparable](a, b T) T` (type-safe)
⚠️ Why: Generics provide type safety; reduce runtime assertions; clearer APIs
🔧 Fix: Use generics for reusable logic; use constraints (`comparable`, `any`, custom); avoid `interface{}`
📍 See: Section 3.3 for `interface{}` abuse
**Detect:** `interface{}` when generics would work, excessive type assertions, no generic constraints

### 1.12 Channel Patterns (CRIT)

**CRITICAL:** Use channels for communication, not just synchronization; always close channels properly.

❌ Bad: `for { select { case <-done: return } }` (busy wait, channel never closed)
✅ Good: `for v := range ch { process(v) }` OR `select { case <-ctx.Done(): return }`
⚠️ Why: Prevents goroutine leaks, enables proper shutdown, avoids resource exhaustion
🔧 Fix: Close channels when done; use `range` over channels; prefer context-based cancellation
**Detect:** Channels never closed, select without default causing blocking, busy-wait patterns

### 1.13 Zero Values (CRIT)

**CRITICAL:** Leverage Go's zero values; design types to be useful at zero value.

❌ Bad: `var s Service; s.Init()` required, zero value unusable
✅ Good: `var s Service; s.Do()` works, zero value is valid state
⚠️ Why: Zero values reduce boilerplate; idiomatic Go; better ergonomics
🔧 Fix: Design types usable at zero value; avoid mandatory Init() methods; use zero values meaningfully
**Detect:** Mandatory Init() methods, zero value causes panics, types unusable without setup

### 1.14 Named Return Values (CRIT)

**CRITICAL:** Use named return values only when they improve readability or enable deferred modifications.

❌ Bad: `func divide(a, b int) (int, error)` with unclear return meaning
✅ Good: `func divide(a, b int) (result int, err error)` OR `func divide(a, b int) (int, error)` (if clear)
⚠️ Why: Named returns can improve clarity but add verbosity; use when deferred functions modify them
🔧 Fix: Use named returns for clarity or when deferred functions need to modify them
📍 See: [Effective Go - Named Results](https://go.dev/doc/effective_go#named-results)
**Detect:** Named returns that don't improve clarity, unnamed returns that are unclear

### 1.15 Multiple Return Values (CRIT)

**CRITICAL:** Use multiple return values for operations that can fail; error is always last.

❌ Bad: `func parse() string`, `func parse() (string, bool)` (bool for error)
✅ Good: `func parse() (string, error)`, `func read() ([]byte, error)`
⚠️ Why: Multiple returns enable explicit error handling; error last is Go convention
🔧 Fix: Return `(result, error)` for operations that can fail; error is always last
📍 See: [Effective Go - Multiple Returns](https://go.dev/doc/effective_go#multiple-returns)
**Detect:** Single return for operations that can fail, error not last, bool instead of error

### 1.16 Embedding (CRIT)

**CRITICAL:** Use embedding to compose types; prefer composition over inheritance.

❌ Bad: Wrapper methods that only delegate, unnecessary indirection
✅ Good: `type Reader struct { io.Reader }`, `type Server struct { *http.Server }`
⚠️ Why: Embedding promotes methods; enables composition; cleaner than delegation
🔧 Fix: Embed interfaces/types directly; use embedding instead of wrapper methods
📍 See: [Effective Go - Embedding](https://go.dev/doc/effective_go#embedding)
**Detect:** Wrapper methods that only call embedded type, types that should embed instead

### 1.17 Control Structures (CRIT)

**CRITICAL:** Use Go's control structures idiomatically; no parentheses needed.

❌ Bad: `if (condition) { }`, `for (i := 0; i < 10; i++) { }` (parentheses)
✅ Good: `if condition { }`, `for i := 0; i < 10; i++ { }`
⚠️ Why: Go doesn't require parentheses; cleaner syntax; idiomatic Go
🔧 Fix: Remove parentheses from if/for/switch; use Go's syntax
📍 See: [Effective Go - Control Structures](https://go.dev/doc/effective_go#control-structures)
**Detect:** Parentheses in if/for/switch, C/Java-style control structures

### 1.18 Initialization (CRIT)

**CRITICAL:** Use initialization patterns idiomatically; prefer constants for immutable values.

❌ Bad: `var timeout = 10 * time.Second` (should be const), redundant initialization
✅ Good: `const timeout = 10 * time.Second`, `var cache = make(map[string]int)`
⚠️ Why: Constants enable compile-time evaluation; proper initialization reduces errors
🔧 Fix: Use `const` for immutable values; initialize variables properly
📍 See: [Effective Go - Constants](https://go.dev/doc/effective_go#constants), [Effective Go - Variables](https://go.dev/doc/effective_go#variables)
**Detect:** Variables that should be constants, redundant initialization, uninitialized variables

### 1.19 Sync Primitives (CRIT)

**CRITICAL:** Use appropriate sync primitives for specific use cases.

❌ Bad: `var mu sync.Mutex; var once sync.Once` (using wrong primitive)
✅ Good: `sync.Once` for one-time init, `sync.Pool` for object reuse, `atomic` for counters
⚠️ Why: Wrong primitive causes performance issues, race conditions, or unnecessary overhead
🔧 Fix: Match primitive to use case: Once for init, Pool for reuse, atomic for counters
**Detect:** Mutex used for one-time init, manual pooling instead of sync.Pool, mutex for simple counters

### 1.20 File Embedding (CRIT)

**CRITICAL:** Use `go:embed` for embedding static files instead of string literals.

❌ Bad: `const html = "<html>...</html>"` (large string literals)
✅ Good: `//go:embed template.html` `var template string`
⚠️ Why: Cleaner code, better tooling support, compile-time validation
🔧 Fix: Use `go:embed` directive for static files
**Detect:** Large string literals in code, manual file reading at runtime

### 1.21 Idempotency Checks (CRIT)
**CRITICAL:** Check existence before creation to ensure idempotent operations.
❌ Bad: `func Create(id int) { db.Insert(User{ID: id}) }` (duplicate on retry)
✅ Good: `func Create(id int) error { if exists(id) { return nil }; return db.Insert(User{ID: id}) }`
⚠️ Why: Non-idempotent ops cause duplicates, errors on retry, data corruption
🔧 Fix: Check existence before create, use upsert patterns, return early if exists
📍 See: `general-llm-anti-patterns.mdc` section 1.4
**Detect:** Create ops without existence checks, no upsert patterns, errors on duplicate retries

## Style & Formatting

### 2.0 Formatting (CRIT)

**CRITICAL:** Always use `gofmt` for formatting; it enforces Go's standard style.

❌ Bad: Manual formatting, inconsistent indentation, spaces instead of tabs
✅ Good: Run `gofmt -w .` or `go fmt ./...` before committing
⚠️ Why: Consistent formatting improves readability; gofmt is the standard; all Go code uses it
🔧 Fix: Use `gofmt` or configure editor to format on save; never manually format
📍 See: [Effective Go - Formatting](https://go.dev/doc/effective_go#formatting)
**Detect:** Inconsistent indentation, spaces for indentation, manual alignment

**Formatting Rules:**

- **Indentation:** Use tabs (gofmt emits tabs by default)
- **Line Length:** No limit; wrap if too long and indent with extra tab
- **Parentheses:** Go needs fewer parentheses; control structures don't use them

## Uber Style & Idioms

### 2.1 Prefix Unexported Globals (Style)

**CRITICAL:** Top-level unexported variables must have a `_` prefix to avoid scope confusion. *Note: This is Uber-specific style; Effective Go doesn't require this.*

❌ Bad: `var defaultTimeout = 10 * time.Second`
✅ Good: `var _defaultTimeout = 10 * time.Second`
⚠️ Why: Clearly distinguishes global scope from local scope; avoids collisions
🔧 Fix: Rename unexported globals with leading underscore
**Detect:** Top-level unexported vars without `_` prefix

### 2.1a Source File Naming (Guidance)

Lowercase; multiple words with underscores (`http_client.go`). Test files: `*_test.go`. 📍 See: Effective Go; `general-llm-anti-patterns.mdc` Category 12.

### 2.2 Mutex Grouping (Style)

**CRITICAL:** Place `sync.Mutex` directly above the fields it protects.

❌ Bad: Mutex field far from the fields it protects
✅ Good: `mu sync.Mutex; // protects:; balance int`
⚠️ Why: Documentation/clarity on what the lock covers; prevents locking errors
🔧 Fix: Move mutex field; add comment indicating guarded fields
**Detect:** `sync.Mutex` field at top of struct with no comments

### 2.3 Import Grouping (Style)

**CRITICAL:** Group imports: stdlib first, then 3rd party, then local, separated by blank lines.

❌ Bad: Mixed imports or no separation
✅ Good:

```go
import (
    "fmt"
    "os"

    "github.com/pkg/errors"

    "myproj/api"
)
```

⚠️ Why: Clear dependency structure; standard convention enforced by linters
🔧 Fix: Regroup imports manually or use `goimports -local`
**Detect:** Imports not separated by blank lines, stdlib mixed with 3rd party

### 2.4 Naming Conventions (CRIT)

**CRITICAL:** Follow Go naming conventions: exported (capitalized) vs unexported, package names, acronyms.

❌ Bad: `func getData()`, `type jsonParser struct`, `package myPackage`
✅ Good: `func GetData()`, `type JSONParser struct`, `package mypackage`
⚠️ Why: Exported vs unexported controls API surface; package names should be lowercase
🔧 Fix: Capitalize exported identifiers; lowercase package names; acronyms all caps (JSON, XML)
**Detect:** Mixed case package names, lowercase exported funcs, inconsistent acronym casing

**Package Naming:**

- Lowercase, single-word names (no underscores, no mixedCaps)
- Package name is base name of source directory (`src/encoding/base64` → `base64`)
- Short, concise, evocative
- Exported names can avoid repetition (e.g., `bufio.Reader`, not `bufio.BufReader`)

**Getters:**
❌ Bad: `func GetName() string`, `func GetBalance() int`
✅ Good: `func Name() string`, `func Balance() int`
⚠️ Why: Go convention; package name provides context (`obj.Name()`, not `obj.GetName()`)
🔧 Fix: Remove "Get" prefix from getter methods
**Detect:** Methods named `Get*` that only return values

**Interface Naming:**

- Single-method interfaces: use "-er" suffix (`Reader`, `Writer`, `Closer`)
- Multiple methods: descriptive names (`ReadWriter`, `ReadWriteCloser`)

### 2.5 Package Design (CRIT)

**CRITICAL:** Packages should have single responsibility; use `internal/` for private APIs.

❌ Bad: Package with 20+ files doing everything, exported types that should be internal
✅ Good: Focused packages, `internal/` for project-private code, clear package boundaries
⚠️ Why: Large packages violate SRP; exported types create API surface; internal prevents external use
🔧 Fix: Split large packages; move private code to `internal/`; minimize exported surface
**Detect:** Packages with >10 files, exported types only used internally, no `internal/` usage

### 2.6 Documentation (CRIT)

**CRITICAL:** Public APIs must have `godoc` comments; use examples for complex APIs.

❌ Bad: `func Process()`, no examples, missing package doc
✅ Good: `// Process handles data transformation.`, `// Example:`, package-level doc
⚠️ Why: Undocumented APIs are hard to use; examples show usage; package docs explain purpose
🔧 Fix: Add `godoc` comments to all exported symbols; include examples; document packages
**Detect:** Exported funcs/types without comments, no examples, missing package doc

### 2.7 Doc Comments (CRIT)

**CRITICAL:** Comments before top-level declarations are doc comments; they document the package or exported symbol.

❌ Bad: `func Process()`, no doc comment, missing package doc
✅ Good: `// Process handles data transformation.`, `// Package api provides HTTP handlers.`
⚠️ Why: Doc comments are the primary documentation; godoc generates docs from them
🔧 Fix: Add doc comments to all exported symbols; document packages with package comment
📍 See: [Effective Go - Commentary](https://go.dev/doc/effective_go#commentary), [Go Doc Comments](https://go.dev/doc/comment)
**Detect:** Exported funcs/types without doc comments, missing package doc, doc comments not before declaration

### 2.8 Tooling (CRIT)

**CRITICAL:** Use Go's built-in tooling for formatting and imports.

**gofmt:**
❌ Bad: Manual formatting, inconsistent indentation
✅ Good: Run `gofmt -w .` or `go fmt ./...` before committing
⚠️ Why: Enforces standard formatting; all Go code uses gofmt
🔧 Fix: Use `gofmt` or configure editor to format on save
**Detect:** Inconsistent indentation, spaces for indentation, manual alignment

### 2.9 Static Analysis Tools (CRIT)

**CRITICAL:** Use `go vet` and `staticcheck` before committing.

❌ Bad: Committing without running `go vet ./...`
✅ Good: `go vet ./... && staticcheck ./...` before commit
⚠️ Why: Catches bugs early, enforces best practices, prevents common mistakes
🔧 Fix: Run static analysis tools in CI/CD, use pre-commit hooks
**Detect:** No static analysis in CI, unchecked code, common vet issues

### 2.10 Build Tags and Conditional Compilation (CRIT)

**CRITICAL:** Use build tags for platform-specific code and feature flags.

❌ Bad: `if runtime.GOOS == "windows" { }` (runtime checks)
✅ Good: `//go:build windows` OR `// +build windows`
⚠️ Why: Compile-time selection, smaller binaries, clearer intent
🔧 Fix: Use build tags for platform/arch-specific code
**Detect:** Runtime OS/arch checks, ifdef-style comments, platform-specific files without tags

### 2.11 Module Management (CRIT)

**CRITICAL:** Properly manage dependencies and module versions.

❌ Bad: `go get` without version, uncommitted go.sum, replace directives without reason
✅ Good: `go get package@version`, commit go.sum, document replace directives
⚠️ Why: Reproducible builds, security, clear dependency tracking
🔧 Fix: Pin versions, commit go.sum, document why replaces are needed
**Detect:** Missing go.sum, replace without comment, unpinned dependencies

### 2.12 Code Generation (Style)

**CRITICAL:** Use `go:generate` directive for code generation tasks.

❌ Bad: Manual code generation, generated code in version control without source
✅ Good: `//go:generate stringer -type=Status`, run `go generate ./...`
⚠️ Why: Reproducible builds, clear generation source, avoids manual errors
🔧 Fix: Use `go:generate` for stringer, mockgen, protobuf; document generation steps
**Detect:** Manual code generation, missing go:generate directives, generated code without source

## Anti-Patterns

### 3.1 Init() Abuse

**CRITICAL:** Avoid `init()` functions for logic or I/O. Use explicit constructors.

❌ Bad: `func init() { db = connect() }`
✅ Good: `func NewDatabase() (*DB, error)`
⚠️ Why: Global state side effects; hard to test; error handling impossible in init
🔧 Fix: Move initialization logic to explicit `New*` functions returning error
**Detect:** `func init()` doing I/O or setting globals

### 3.2 Panic Misuse

**CRITICAL:** Do not use `panic()` for control flow or recoverable errors.

❌ Bad: `if err != nil { panic(err) }` (in libraries/handlers)
✅ Good: Return error
⚠️ Why: Panics crash the app; only use for unrecoverable startup errors (Must*)
🔧 Fix: Replace `panic` with error return
**Detect:** `panic()` outside of `main` or `Must*` functions

### 3.3 Interface{} (Any) Abuse

**CRITICAL:** Use strong types or Generics instead of `interface{}`/`any`.

❌ Bad: `func process(data interface{})`
✅ Good: `func process(data ConcreteType)` OR `func process[T any](data T)`
⚠️ Why: Loses type safety; requires runtime assertions; harder to read
🔧 Fix: Use specific type or generic constraint
**Detect:** `interface{}` as function arg (unless generic/reflection needed)

### 3.4 Nil Interface Checks (CRIT)

**CRITICAL:** Check for nil interfaces properly; `== nil` may not work as expected.

❌ Bad: `if err == nil { return }` (may fail with typed nil)
✅ Good: `if err != nil { return err }` OR check concrete type
⚠️ Why: Typed nil interfaces are not equal to nil; causes subtle bugs
🔧 Fix: Always check `err != nil`; use type assertions for typed nil checks
**Detect:** Direct nil comparison on interfaces, typed nil not caught

### 3.5 Variable Shadowing (CRIT)

**CRITICAL:** Avoid variable shadowing; use `:=` carefully.

❌ Bad: `err := do(); if err := do2(); err != nil { }` (shadows outer err)
✅ Good: `err := do(); if err2 := do2(); err2 != nil { }`
⚠️ Why: Shadowing hides bugs, makes debugging harder, loses error context
🔧 Fix: Use different variable names in inner scopes; be explicit with `:=` vs `=`
**Detect:** Variable redeclared in inner scope with same name, shadowed errors

### 3.6 Recover Usage (CRIT)

**CRITICAL:** Use `recover` only in deferred functions to handle panics gracefully; keep panic/recover within package.

❌ Bad: `recover()` outside deferred function, exposing panics to callers
✅ Good: `defer func() { if err := recover(); err != nil { log.Println(err) } }()`
⚠️ Why: Recover only works in deferred functions; panics should be converted to errors at package boundary
🔧 Fix: Use recover in deferred functions; convert panics to errors before returning to caller
📍 See: [Effective Go - Recover](https://go.dev/doc/effective_go#recover)
**Detect:** Recover outside deferred function, panics exposed to callers, recover not converting to error

## Testing Guidelines

### 4.1 Parallel Tests

**CRITICAL:** Use `t.Parallel()` for all independent unit tests.

❌ Bad: Tests running sequentially (default)
✅ Good: `func TestX(t *testing.T) { t.Parallel(); ... }`
⚠️ Why: Speeds up test suite execution; detects race conditions
🔧 Fix: Add `t.Parallel()` to top of test functions; capture loop vars
**Detect:** Tests without `t.Parallel()` (unless integration/stateful)

### 4.2 Test Main Usage

**CRITICAL:** Avoid `TestMain` for simple setup; use helper functions/defer.

❌ Bad: Using `TestMain` for simple db connection setup
✅ Good: Helper `setupTest(t)` that returns teardown closure
⚠️ Why: Global state in tests makes them brittle and hard to parallelize
🔧 Fix: Move global setup to per-test helper functions
**Detect:** `func TestMain` doing simple setup logic

### 4.3 Test Helpers (CRIT)

**CRITICAL:** Use `t.Helper()` in test helper functions.

❌ Bad: Helper function without `t.Helper()`
✅ Good: `func helper(t *testing.T) { t.Helper(); ... }`
⚠️ Why: Marks function as helper; improves error reporting (shows actual test line)
🔧 Fix: Add `t.Helper()` to top of all helper functions
**Detect:** Helper functions without `t.Helper()`, unclear error locations in test output

### 4.4 Subtests (CRIT)

**CRITICAL:** Use `t.Run()` for subtests; enables better test organization.

❌ Bad: Multiple test functions for related cases
✅ Good: `t.Run("case1", func(t *testing.T) { ... })`
⚠️ Why: Better organization, parallel execution, clearer output
🔧 Fix: Group related tests using `t.Run()` subtests
**Detect:** Related tests not using subtests, multiple test functions for same feature

### 4.5 Benchmarking (CRIT)

**CRITICAL:** Write benchmarks for performance-critical code.

❌ Bad: No benchmarks for hot paths, guessing at performance
✅ Good: `func BenchmarkXxx(b *testing.B) { for i := 0; i < b.N; i++ { ... } }`
⚠️ Why: Performance regressions go unnoticed, optimization without measurement
🔧 Fix: Write benchmarks for critical paths, run with `go test -bench`, compare results
**Detect:** No benchmarks for performance-critical code, performance claims without data

### 4.6 Test Coverage (CRIT)

**CRITICAL:** Use test coverage to ensure critical code is tested.

❌ Bad: No coverage metrics, untested critical paths
✅ Good: `go test -cover`, `go test -coverprofile=coverage.out`, aim for >80% coverage on business logic
⚠️ Why: Untested code is a liability, coverage reveals gaps, critical paths need validation
🔧 Fix: Run coverage regularly, set coverage goals, focus on business logic coverage
**Detect:** No coverage reports, critical paths with low coverage, coverage goals not met

### 4.7 Fuzz Testing (Style)

**CRITICAL:** Use fuzz testing for functions that process untrusted input.

❌ Bad: Only testing known inputs, missing edge cases
✅ Good: `func FuzzXxx(f *testing.F) { f.Add(input); f.Fuzz(func(t *testing.T, data []byte) { ... }) }`
⚠️ Why: Discovers edge cases, finds security vulnerabilities, validates input handling
🔧 Fix: Write fuzz tests for parsers, validators, encoders; run with `go test -fuzz`
**Detect:** No fuzz tests for input processing, only happy path tests, missing edge case validation

## Summary: Critical Go Rules

These patterns represent the most critical Go best practices:

1. **Error Handling** - Handle errors explicitly, wrap with context
2. **Concurrency Safety** - Manage goroutines, use WaitGroup/errgroup
3. **Context Propagation** - Context as first parameter
4. **Interface Design** - Define interfaces at use site
5. **Receiver Types** - Pointers for mutability/large structs
6. **Memory Preallocation** - Preallocate slices/maps when size known
7. **Functional Options** - Use for complex constructors
8. **Table-Driven Tests** - Use for all logic tests
9. **Defer Usage** - Always use defer for cleanup
10. **Range Loop Capture** - Capture loop variables explicitly
11. **Generics** - Use for type-safe reusable code
12. **Channel Patterns** - Close channels, use range/context
13. **Zero Values** - Design types usable at zero value
14. **Named Returns** - Use when improving clarity or enabling deferred modifications
15. **Multiple Returns** - Error is always last
16. **Embedding** - Prefer composition over inheritance
17. **Control Structures** - No parentheses needed
18. **Initialization** - Use constants for immutable values
19. **Sync Primitives** - Use appropriate sync primitives (Once, Pool, atomic)
20. **File Embedding** - Use go:embed for static files
21. **Formatting** - Always use gofmt
22. **Naming Conventions** - Exported vs unexported, package names, getters
23. **Package Design** - Single responsibility, use internal/
24. **Documentation** - godoc comments for public APIs
25. **Doc Comments** - Comments before declarations document symbols
26. **Tooling** - Use gofmt and goimports
27. **Static Analysis** - Use go vet and staticcheck
28. **Build Tags** - Use build tags for platform-specific code
29. **Module Management** - Pin versions, commit go.sum, document replaces
30. **Code Generation** - Use go:generate for code generation
31. **Test Helpers** - Use t.Helper() in helpers
32. **Subtests** - Use t.Run() for organization
33. **Benchmarking** - Write benchmarks for performance-critical code
34. **Test Coverage** - Use coverage metrics, aim for >80% on business logic
35. **Fuzz Testing** - Use fuzz testing for input processing functions

---

## References

- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)
- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md)
