---
description: "Java-specific development standards following Effective Java, Google Java Style Guide, and modern Java 21 LTS best practices"
globs: ["**/*.java"]
alwaysApply: false
---
## Persona: Principal Java Platform Engineer
- **Role:** Enterprise systems architect (Netflix/LinkedIn scale). **Philosophy:** "Effective Java" purist, Joshua Bloch principles
- **Bias:** Immutability-first (Records > classes), Virtual Threads for I/O, Prefer standard library over dependencies, Pattern matching over instanceof chains, Fail-fast (Optional over null)

---

# Java 21 Development Standards

You are an expert Java developer. Follow these guidelines derived from "Effective Java" by Joshua Bloch, the "Google Java Style Guide", and modern Java 21 LTS best practices.

**Target Version:** Java 21 LTS

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`.

---

## Java Philosophy

Java's design philosophy centers on readability, safety, and enterprise-grade reliability:

- **Readability:** Clear, self-documenting code. Verbose is acceptable if it aids understanding.
- **Type Safety:** Leverage the type system to catch errors at compile time, not runtime.
- **Immutability:** Prefer immutable objects. They are simpler, thread-safe, and easier to reason about.
- **Fail-Fast:** Detect errors as early as possible. Use `Optional` over null, validate inputs eagerly.
- **Composition over Inheritance:** Favor composition and interfaces over class inheritance.
- **Standard Library First:** Prefer JDK classes over external dependencies when functionality exists.
- **Effective Java Principles:** Follow Joshua Bloch's time-tested guidelines.
- **Modern Java:** Embrace Java 21 features: Records, Pattern Matching, Virtual Threads, Sequenced Collections.
- **Defensive Programming:** Never trust external input. Validate at boundaries.

---

## Java 21 LTS Feature Summary

Java 21 enables patterns that significantly reduce boilerplate and improve clarity:

| Feature | Use Case | Benefit |
|---------|----------|---------|
| **Virtual Threads** | I/O-bound tasks, high-throughput servers | Simple thread-per-request without platform thread overhead |
| **Records** | Immutable data carriers | Eliminates POJO boilerplate (getters, equals, hashCode, toString) |
| **Pattern Matching** | Type checks, data deconstruction | Replaces verbose instanceof + cast chains |
| **Sealed Classes** | Controlled inheritance hierarchies | Exhaustive switch, better domain modeling |
| **Sequenced Collections** | Ordered collections | Uniform API: `getFirst()`, `getLast()`, `reversed()` |
| **Switch Expressions** | Complex conditionals | Expression-based, exhaustiveness checking |
| **Text Blocks** | Multi-line strings | Clean JSON, SQL, HTML templates |

---

## Category 1: Modern Java Syntax & Style

### 1.1 Meaningful and Descriptive Names (CRIT)

**CRITICAL:** Use descriptive variable and method names. Names should reveal intent, not implementation.

❌ Bad: `int d;` (elapsed time in days), `List<int[]> theList;` (unclear purpose), `void calc(int x, int y)`, `String s;`
✅ Good: `int elapsedTimeInDays;`, `List<Cell> flaggedCells;`, `void calculateArea(int length, int width)`, `String customerName;`
⚠️ Why: Names reveal intent; single-letter only in short loops; unclear names force comments
🔧 Fix: Use intention-revealing, pronounceable, searchable names; avoid encodings (e.g. Hungarian)
📍 See: Effective Java Item 68, `general-llm-anti-patterns.mdc` section 0.1
**Detect:** Single-letter variables outside loops, cryptic abbreviations, generic names (data, info, temp), names requiring comments to explain

### 1.1a Source File Naming (Guidance)

One public class per file; filename = PascalCase class name + `.java` (case-sensitive). 📍 See: `general-llm-anti-patterns.mdc` Category 12.

---

### 1.2 Use Records for Immutable Data Carriers (CRIT)

**CRITICAL:** Use Records instead of traditional POJOs for immutable data carriers. Records eliminate boilerplate.

❌ Bad: `public class Point { private final int x,y; getX/getY; equals/hashCode/toString }` (POJO boilerplate)
✅ Good: `public record Point(int x, int y) { }`
⚠️ Why: Records are immutable, thread-safe, cut boilerplate, enable pattern matching, signal data-carrier intent
🔧 Fix: Use records for DTOs, value objects, API responses; add validation in compact constructor if needed
📍 See: JEP 395 (Records), Effective Java Item 49
**Detect:** Classes with only private final fields and accessors, POJOs with manual equals/hashCode/toString, DTOs that could be records

---

### 1.3 Pattern Matching for instanceof (CRIT)

**CRITICAL:** Use pattern matching instead of traditional instanceof + cast.

❌ Bad: `if (obj instanceof String) { String s = (String) obj; s.length(); }` (redundant cast)
✅ Good: `if (obj instanceof String s) { s.length(); }` or `switch (obj) { case String s -> s.length(); case Integer i -> i*2; default -> "Unknown"; }`
⚠️ Why: Eliminates redundant casting, enables exhaustive switch, more readable
🔧 Fix: Use pattern variables in instanceof; use pattern matching in switch; combine with sealed classes for exhaustiveness
📍 See: JEP 394 (instanceof), JEP 441 (pattern matching for switch)
**Detect:** instanceof followed by cast to same type, multiple instanceof checks for same variable, type-based if-else chains

---

### 1.4 Switch Expressions Over if-else Chains (CRIT)

**CRITICAL:** Use switch expressions for multi-way conditionals. They are exhaustive, expression-based, and cleaner.

❌ Bad: `if (day==1) result="Monday"; else if (day==2) result="Tuesday"; else result="Unknown";`
✅ Good: `String result = switch (day) { case 1 -> "Monday"; case 2 -> "Tuesday"; case 3,4,5 -> "Midweek"; default -> "Unknown"; };`
⚠️ Why: Expression-based, exhaustiveness checking, no fall-through bugs, works with pattern matching
🔧 Fix: Use arrow syntax (`->`) for single expressions; use `yield` for blocks; combine with sealed classes for type switches
📍 See: JEP 361 (Switch Expressions), JEP 441 (pattern matching for switch)
**Detect:** if-else chains mapping values, traditional switch with break, switch not returning value when it could

---

### 1.5 Use var for Local Variable Type Inference (CRIT)

**CRITICAL:** Use `var` when the type is obvious from the right-hand side. Don't use when it reduces clarity.

❌ Bad: `var result = processData();` (type unclear), `var x = 1;` (unnecessary), `new HashMap<String, List<Customer>>()` (redundant)
✅ Good: `var customers = new ArrayList<Customer>();`, `Map<K,V> m = new HashMap<>();`, `int count = 0;`
⚠️ Why: Reduces boilerplate when type is obvious; must not obscure type information
🔧 Fix: Use `var` when type is obvious from RHS (constructors, literals, factory methods); never use for fields or parameters
📍 See: JEP 286 (local-variable type inference), Effective Java Item 68
**Detect:** var hiding important type information, redundant type on both sides, var with primitive literals

---

### 1.6 Text Blocks for Multi-line Strings (CRIT)

**CRITICAL:** Use text blocks for multi-line strings (JSON, SQL, HTML). Avoid string concatenation.

❌ Bad: `String json = "{\n" + "  \"name\": \"" + name + "\",\n" + "}";` (concatenation, escapes)
✅ Good: `String json = """\n{ "name": "%s", "age": %d }\n""".formatted(name, age);`
⚠️ Why: More readable, preserves formatting, no escape noise, works with `formatted()`
🔧 Fix: Use text blocks for JSON, SQL, HTML; use `formatted()` for interpolation; `stripIndent()` if needed
📍 See: JEP 378 (Text Blocks)
**Detect:** Multi-line string concatenation, escaped newlines in strings, complex string building for structured text

---

### 1.7 Sealed Classes for Controlled Hierarchies (CRIT)

**CRITICAL:** Use sealed classes to control inheritance and enable exhaustive pattern matching.

❌ Bad: `public abstract class Shape { }` and `public class Circle extends Shape { }` (anyone can extend, no exhaustive switch)
✅ Good: `public sealed interface Shape permits Circle, Rectangle { }` and `switch (shape) { case Circle c -> Math.PI*c.radius()*c.radius(); case Rectangle r -> r.width()*r.height(); }`
⚠️ Why: Controls who can extend, enables exhaustive switches, documents intent, works with records
🔧 Fix: Use sealed for domain models with fixed variants; combine with records; use permits clause explicitly
📍 See: JEP 409 (Sealed Classes)
**Detect:** Abstract classes with fixed known subclasses, switch with default that shouldn't exist, instanceof chains for type hierarchies

---

### 1.8 Sequenced Collections (CRIT)

**CRITICAL:** Use Sequenced Collections API (`getFirst()`, `getLast()`, `reversed()`) for ordered collections.

❌ Bad: `list.get(0)`, `list.get(list.size()-1)` (IndexOutOfBounds, off-by-one), manual reverse iteration
✅ Good: `list.getFirst()`, `list.getLast()`, `list.reversed()` (view, not copy)
⚠️ Why: Uniform API across List, Deque, SortedSet; `reversed()` returns view (efficient)
🔧 Fix: Use `getFirst()`/`getLast()` instead of index; use `reversed()` for reverse; declare `SequencedCollection` when order matters
📍 See: JEP 431 (Sequenced Collections)
**Detect:** `list.get(0)`, `list.get(list.size()-1)`, manual reverse iteration, inconsistent ordered-collection handling

---

## Category 2: Concurrency with Virtual Threads

### 2.1 Virtual Threads for I/O-Bound Tasks (CRIT)

**CRITICAL:** Use Virtual Threads for I/O-bound tasks. They enable simple thread-per-request without platform thread overhead.

❌ Bad: `Executors.newFixedThreadPool(200)` and `executor.submit(() -> processRequest(r))` (limits concurrency for I/O)
✅ Good: `try (var ex = Executors.newVirtualThreadPerTaskExecutor()) { requests.forEach(r -> ex.submit(() -> processRequest(r))); }`
⚠️ Why: Virtual threads are cheap (KB vs MB), enable thread-per-request for I/O, no pool sizing
🔧 Fix: Use `newVirtualThreadPerTaskExecutor()` for I/O; keep platform pools only for CPU-bound work
📍 See: JEP 444 (Virtual Threads)
**Detect:** Fixed thread pools for I/O-bound work, manual thread pool sizing, thread starvation, complex async callbacks

---

### 2.2 Don't Pool Virtual Threads (CRIT)

**CRITICAL:** Never pool virtual threads. Create new virtual threads per task. Pooling defeats their purpose.

❌ Bad: `Executors.newFixedThreadPool(100, Thread.ofVirtual().factory())` (pooling virtual threads)
✅ Good: `Executors.newVirtualThreadPerTaskExecutor()` or `Thread.startVirtualThread(() -> process(r))`
⚠️ Why: Virtual threads are cheap to create; pooling adds overhead and defeats simplicity
🔧 Fix: Use `newVirtualThreadPerTaskExecutor()` or `Thread.startVirtualThread()`; never fixed pools with virtual factory
📍 See: JEP 444 (Virtual Threads)
**Detect:** `newFixedThreadPool` with virtual thread factory, caching/pooling virtual threads, reusing virtual threads

---

### 2.3 Avoid Pinning with Virtual Threads (CRIT)

**CRITICAL:** Avoid synchronized blocks and native methods in virtual thread code paths. They can "pin" the carrier thread.

❌ Bad: `synchronized (lock) { connection.read(); }` (pins virtual thread to carrier during I/O)
✅ Good: `ReentrantLock lock = new ReentrantLock(); lock.lock(); try { connection.read(); } finally { lock.unlock(); }`
⚠️ Why: `synchronized` pins virtual thread; pinned threads don't yield; can exhaust carrier pool; ReentrantLock works
🔧 Fix: Replace `synchronized` with `ReentrantLock` in I/O paths; avoid JNI in virtual threads; use `-Djdk.tracePinnedThreads=full` to detect
📍 See: JEP 444 (Virtual Threads), `general-llm-anti-patterns.mdc` section 1.2
**Detect:** synchronized in virtual thread code, native calls in virtual threads, performance issues with high VT count

---

### 2.4 Structured Concurrency (Preview) (CRIT)

**CRITICAL:** Use structured concurrency for managing related tasks. Tasks form a hierarchy with clear scope.

❌ Bad: `executor.submit(() -> fetchUser(id)); executor.submit(() -> fetchOrders(id));` (fire-and-forget, no lifecycle)
✅ Good: `try (var scope = new StructuredTaskScope.ShutdownOnFailure()) { var u = scope.fork(() -> fetchUser(id)); var o = scope.fork(() -> fetchOrders(id)); scope.join(); scope.throwIfFailed(); return new Profile(u.get(), o.get()); }`
⚠️ Why: Clear lifecycle, auto cancellation on failure, exceptions propagate, observability-friendly
🔧 Fix: Use `StructuredTaskScope` for related tasks; choose `ShutdownOnFailure` or `ShutdownOnSuccess` by semantics
📍 See: JEP 453 (Structured Concurrency)
**Detect:** Fire-and-forget tasks, manual task coordination, complex CompletableFuture chains, missing error handling in concurrent code

---

### 2.5 Thread-Local Variables with Virtual Threads (CRIT)

**CRITICAL:** Be cautious with ThreadLocal in virtual thread code. Consider Scoped Values (Preview) instead.

❌ Bad: `ThreadLocal.withInitial(ExpensiveObject::new)` with virtual threads (memory explosion at scale)
✅ Good: Pass resource as parameter, or `ScopedValue.where(CURRENT_USER, user).run(() -> ...)` (Scoped Values)
⚠️ Why: ThreadLocal with millions of virtual threads causes memory issues; Scoped Values are designed for VTs
🔧 Fix: Avoid ThreadLocal with virtual threads; use Scoped Values or explicit parameter passing; cheap init if ThreadLocal needed
📍 See: JEP 446 (Scoped Values), JEP 444 (Virtual Threads)
**Detect:** ThreadLocal in virtual thread code, memory issues with high VT count, expensive ThreadLocal initial values

---

## Category 3: Null Handling and Optional

### 3.1 Use Optional for Absent Values (CRIT)

**CRITICAL:** Use `Optional` for return values that may be absent. Never use null for "no result".

❌ Bad: `public User findUser(String id) { return database.query(id); }` and `findUser("123").getName()` (NPE if absent)
✅ Good: `public Optional<User> findUser(String id) { return Optional.ofNullable(database.query(id)); }` and `findUser("123").map(User::getName).orElse("Unknown");`
⚠️ Why: Makes absence explicit; forces caller to handle; enables fluent chaining; documents intent
🔧 Fix: Return `Optional` for may-be-absent queries; use `Optional.ofNullable()`; never pass Optional as parameter
📍 See: Effective Java Item 55
**Detect:** Methods returning null for "not found", callers not checking null, NPEs, null checks scattered

---

### 3.2 Never Use Optional for Fields or Parameters (CRIT)

**CRITICAL:** Optional is for return values only. Never use for fields, parameters, or collections.

❌ Bad: `private Optional<String> middleName;`, `void process(Optional<Config> c)`, `List<Optional<User>>` (Optional as field/param/collection)
✅ Good: `private @Nullable String middleName;` and `Optional.ofNullable(middleName)` in getter; `void process(Config c) { Objects.requireNonNull(c); }`
⚠️ Why: Optional not designed for fields; adds overhead; unclear param semantics; use @Nullable instead
🔧 Fix: @Nullable for nullable fields; overloads/builders for optional params; return Optional from getters
📍 See: Effective Java Item 55
**Detect:** Optional fields, Optional parameters, Optional in collections, `Optional.of(null)`

---

### 3.3 Proper Optional Usage (CRIT)

**CRITICAL:** Use Optional's API correctly. Don't use `get()` without `isPresent()` check. Prefer functional methods.

❌ Bad: `if (o.isPresent()) return o.get().getName(); else return "Unknown";` or `findUser(id).get()` (NoSuchElementException)
✅ Good: `findUser(id).map(User::getName).orElse("Unknown");` or `.orElseGet(()->create());` or `.orElseThrow(()->new NotFound(id));` or `.ifPresent(u->send(u));`
⚠️ Why: Functional style is readable; avoids NoSuchElementException; expresses intent; enables chaining
🔧 Fix: Use `map`/`flatMap` for transforms; `orElse`/`orElseGet`/`orElseThrow` for defaults; `ifPresent`/`ifPresentOrElse` for side effects
📍 See: Effective Java Item 55
**Detect:** `isPresent()` then `get()`, bare `get()`, imperative Optional handling, nested Optional (missing flatMap)

---

### 3.4 Fail-Fast Null Checking (CRIT)

**CRITICAL:** Validate non-null parameters at method entry. Fail fast with clear messages.

❌ Bad: `public void process(User user) { user.getName(); repository.save(user); }` (NPE deep in method if null)
✅ Good: `public void process(User user) { Objects.requireNonNull(user, "user must not be null"); ... }` (and in constructors)
⚠️ Why: Fails at entry with clear message; documents non-null; catches bugs early
🔧 Fix: Use `Objects.requireNonNull()` for non-null params with message; validate in constructors
📍 See: Effective Java Item 49
**Detect:** NPEs deep in method, missing null checks on params, constructors without null validation

---

## Category 4: Collections and Streams

### 4.1 Return Empty Collections, Not Null (CRIT)

**CRITICAL:** Return empty collections instead of null. Never return null for a collection.

❌ Bad: `if (noUsers) return null; return userList;` (caller must null-check)
✅ Good: `if (noUsers) return List.of(); return List.copyOf(userList);`
⚠️ Why: Eliminates null checks; enables fluent chaining; consistent behavior
🔧 Fix: Return `List.of()`/`Collections.emptyList()` for empty; return immutable copies; never null collections
📍 See: Effective Java Item 54
**Detect:** Methods returning null for empty collections, callers null-checking before iterate, NPEs on collection returns

---

### 4.2 Prefer Immutable Collections (CRIT)

**CRITICAL:** Use immutable collections by default. Use `List.of()`, `Set.of()`, `Map.of()` for literals.

❌ Bad: `List<String> c = new ArrayList<>(); c.add("red"); return c;` (mutable, caller can modify)
✅ Good: `List.of("red","green","blue")`, `Set.of("a","b")`, `Map.of("Alice",100)`, `List.copyOf(mutableList)`
⚠️ Why: Thread-safe; no defensive copies; prevents accidental modification; clearer intent
🔧 Fix: Use `List.of`/`Set.of`/`Map.of` for literals; `List.copyOf()` for defensive copies; mutable only when needed
📍 See: Effective Java Item 17
**Detect:** `new ArrayList<>()` for constants, mutable collections returned, collections modified after creation

---

### 4.3 Stream API Best Practices (CRIT)

**CRITICAL:** Use Stream API for collection transformations. Keep streams readable with proper formatting.

❌ Bad: `for (User u : users) if (u.isActive()) names.add(u.getName().toUpperCase());` or `users.stream().filter(...).map(...).map(...).collect(...)` (one long line)
✅ Good: `return users.stream().filter(User::isActive).map(User::getName).map(String::toUpperCase).sorted().toList();` (one op per line)
⚠️ Why: Declarative; one op per line; method refs when clearer; `toList()` immutable (Java 16+)
🔧 Fix: One operation per line; prefer method refs over lambdas; use `toList()` for immutable
📍 See: Effective Java Items 45-48
**Detect:** Imperative loops for transforms, single-line streams with many ops, lambdas where method refs work

---

### 4.4 Avoid Stream Side Effects (CRIT)

**CRITICAL:** Stream operations should be side-effect-free. Use `forEach` only for terminal side effects.

❌ Bad: `users.stream().map(u -> { results.add(u.getName()); return u; }).collect(toList());` (side effect in map)
✅ Good: `users.stream().map(User::getName).toList();` or `users.stream().filter(User::isActive).forEach(u -> email.send(u));`
⚠️ Why: Side effects in map/filter cause bugs with parallel; order not guaranteed; harder to reason about
🔧 Fix: Keep `map`/`filter`/`flatMap` pure; use `forEach` only for terminal side effects; `collect` for accumulation
📍 See: Effective Java Item 46
**Detect:** Modifying external state in map/filter, accumulating outside stream, side effects in intermediate ops

---

### 4.5 Parallel Streams Sparingly (CRIT)

**CRITICAL:** Don't use parallel streams by default. They rarely improve performance and can cause issues.

❌ Bad: `names.parallelStream().map(String::toUpperCase).toList();` (simple op, likely slower) or `items.parallelStream().forEach(results::add)` (shared mutable, racy)
✅ Good: `names.stream().map(String::toUpperCase).toList();` or `largeDataSet.parallelStream().filter(this::expensive).toList();` (CPU-bound, large)
⚠️ Why: Fork/join overhead; shared mutable causes races; often slower for small; never with I/O
🔧 Fix: Sequential by default; parallel only CPU-intensive + large data; never I/O; benchmark first
📍 See: Effective Java Item 48
**Detect:** `parallelStream()` on small, parallel with I/O, parallel with shared mutable state, no benchmarking

---

## Category 5: Error Handling

### 5.1 Use Specific Exceptions (CRIT)

**CRITICAL:** Throw specific exceptions. Never throw generic Exception or RuntimeException.

❌ Bad: `throws Exception`, `throw new RuntimeException("Invalid id")` (too generic)
✅ Good: `throws UserNotFoundException`, `orElseThrow(() -> new UserNotFoundException("User not found: " + id))` (context in message/fields)
⚠️ Why: Specific exceptions enable specific handling; context (IDs, params) aids debugging; checked vs unchecked by recoverability
🔧 Fix: Create domain exceptions with context; unchecked for programming errors, checked for recoverable
📍 See: Effective Java Items 70, 72, 73
**Detect:** `throws Exception`, `throw new RuntimeException(msg)`, generic catch, exceptions without context

---

### 5.2 Don't Swallow Exceptions (CRIT)

**CRITICAL:** Never catch and ignore exceptions. Always handle, log, or rethrow with context.

❌ Bad: `catch (Exception e) { }` or `catch (Exception e) { e.printStackTrace(); }` (swallow / not production)
✅ Good: `catch (SpecificException e) { logger.error("op failed: {}", e.getMessage(), e); throw new ServiceException("failed", e); }` or handle and return default
⚠️ Why: Swallowed exceptions hide bugs; preserve cause (constructor or initCause) for debugging
🔧 Fix: Log with context; rethrow wrapped with cause; handle meaningfully; never ignore
📍 See: Effective Java Item 77, `general-llm-anti-patterns.mdc` section 5.3
**Detect:** Empty catch, `e.printStackTrace()` in production, catch without log/rethrow, lost exception chains

---

### 5.3 Try-with-Resources for All Resources (CRIT)

**CRITICAL:** Use try-with-resources for all `AutoCloseable` resources. Never manually close.

❌ Bad: `InputStream is = new FileInputStream(f); try { ... } finally { is.close(); }` (manual close can fail)
✅ Good: `try (var is = new FileInputStream(f); var r = new BufferedReader(new InputStreamReader(is))) { return r.lines().toList(); }`
⚠️ Why: Auto-close on exception; suppressed exceptions; correct close order; cleaner
🔧 Fix: try-with-resources for all AutoCloseable; multiple in same try; var works
📍 See: Effective Java Item 9, `general-llm-anti-patterns.mdc` section 5.4
**Detect:** Manual `close()` in finally, resources not closed on exception, nested try-finally for multiple

---

### 5.4 Don't Use Exceptions for Control Flow (CRIT)

**CRITICAL:** Exceptions are for exceptional conditions. Never use for normal control flow.

❌ Bad: `while (true) { array[i++].process(); } catch (ArrayIndexOutOfBoundsException e) { }` (exception to exit loop)
✅ Good: `for (Element e : array) e.process();` or `for (int i=0; i<array.length; i++) array[i].process();`
⚠️ Why: Exceptions are slow (stack trace); obscures intent; prevents JVM optimizations
🔧 Fix: Normal control flow; check before ops; use Optional for absent values
📍 See: Effective Java Item 69
**Detect:** Catch as part of normal flow, exceptions replacing if, frequent expected exceptions in logs

---

## Category 6: Performance and JVM Considerations

### 6.1 String Concatenation in Loops (CRIT)

**CRITICAL:** Use StringBuilder for string concatenation in loops. String concatenation creates many objects.

❌ Bad: `String r=""; for (String s : strings) r += s;` (O(n²), new String each iteration)
✅ Good: `var sb = new StringBuilder(); for (String s : strings) sb.append(s); return sb.toString();` or `String.join("", strings)`
⚠️ Why: `+=` in loop is O(n²); StringBuilder is O(n)
🔧 Fix: StringBuilder in loops; `String.join()` or `Collectors.joining()` for simple; single concat outside loop is fine
📍 See: Effective Java Item 63
**Detect:** `+=` for strings in loops, O(n²) string building

---

### 6.2 JVM Garbage Collection Selection (CRIT)

**CRITICAL:** Choose appropriate GC for your workload. ZGC for low latency, G1 for balanced workloads.

❌ Bad: `java -jar myapp.jar` (no GC config, uses defaults)
✅ Good: `java -XX:+UseZGC -XX:+ZGenerational -jar myapp.jar` (low latency) or `-XX:+UseG1GC` (balanced) or `-XX:+UseParallelGC` (batch)
⚠️ Why: Wrong GC causes pause or throughput issues; ZGC for latency; G1 default; ParallelGC for batch
🔧 Fix: ZGC + `-XX:+ZGenerational` for low latency; G1 for balanced; benchmark with prod-like load
📍 See: [JDK GC docs](https://docs.oracle.com/en/java/javase/21/gctuning/)
**Detect:** GC pauses affecting SLAs, no GC config, wrong GC for workload

---

### 6.3 Container-Aware JVM Settings (CRIT)

**CRITICAL:** In containers, use percentage-based memory settings. Don't hardcode heap sizes.

❌ Bad: `java -Xmx4g -jar myapp.jar` (hardcoded heap, ignores container limits)
✅ Good: `java -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -jar myapp.jar`
⚠️ Why: JVM detects cgroups; percentage scales with container; hardcoded can exceed or waste
🔧 Fix: Use `-XX:MaxRAMPercentage` instead of `-Xmx`; leave room for native; monitor usage
📍 See: [Java in containers](https://docs.oracle.com/en/java/javase/21/vm/java-virtual-machine-technology-overview.html)
**Detect:** Hardcoded `-Xmx` in containers, OOMKilled, JVM not respecting container limits

---

### 6.4 Class Data Sharing for Startup (CRIT)

**CRITICAL:** Use AppCDS for faster startup in microservices and CLI tools.

❌ Bad: `java -jar myapp.jar` (slow cold start every time)
✅ Good: Dump `-XX:DumpLoadedClassList=classes.lst`; create `-Xshare:dump -XX:SharedClassListFile=classes.lst -XX:SharedArchiveFile=app.jsa`; run `-Xshare:on -XX:SharedArchiveFile=app.jsa -jar myapp.jar`
⚠️ Why: CDS shares class metadata; 20-40% faster startup; less memory; essential for serverless/CLI
🔧 Fix: Create and use CDS archive in prod; automate in build; GraalVM native-image for extreme startup
📍 See: [Application Class Data Sharing](https://docs.oracle.com/en/java/javase/21/vm/application-class-data-sharing.html)
**Detect:** Slow cold starts, high startup memory, serverless cold start timeouts

---

### 6.5 Avoid Premature Optimization (CRIT)

**CRITICAL:** Profile before optimizing. Write clear code first, optimize hot paths only when profiler confirms.

❌ Bad: `for (int i = size; --i >= 0; ) arr[i] = compute(i);` (clever reverse loop, harder to read, no proof it helps)
✅ Good: `for (int i = 0; i < size; i++) arr[i] = compute(i);` (clear); optimize only if JFR/profiler shows hot path
⚠️ Why: JIT optimizes most code; readability > micro-optimization; premature opt wastes time
🔧 Fix: Clear code first; profile (JFR, async-profiler); optimize only confirmed hot paths; benchmark
📍 See: Effective Java Item 67, `general-llm-anti-patterns.mdc` section 0.1
**Detect:** Micro-optimizations without profiling, obscure code "for performance", optimizing cold paths, no benchmarks

---

## Category 7: Testing

### 7.1 Use JUnit 5 with AssertJ (CRIT)

**CRITICAL:** Use JUnit 5 (`@Test`, `@BeforeEach`, etc.) with AssertJ for fluent, readable assertions.

❌ Bad: `@org.junit.Test`, `assertEquals(expected, actual)`, `assertTrue(list.contains(item))` (JUnit 4, confusing order, not descriptive)
✅ Good: `@Test void shouldCalculateAreaForPositiveDimensions() { assertThat(rect.area()).isEqualTo(12); }` and `assertThat(users).hasSize(3).extracting(User::getName).containsExactly("A","B","C");`
⚠️ Why: JUnit 5 has lifecycle, parameterized, extensions; AssertJ readable and better error messages
🔧 Fix: JUnit 5 (`org.junit.jupiter.api.*`); AssertJ for assertions; descriptive names; Given-When-Then
📍 See: `general-llm-anti-patterns.mdc` section 6.1
**Detect:** JUnit 4 imports, `assertEquals` arg confusion, `assertTrue` without message, non-descriptive test names

---

### 7.2 Test Method Naming (CRIT)

**CRITICAL:** Test method names should describe the scenario and expected behavior, not just the method being tested.

❌ Bad: `void testGetUser() { }`, `void test1() { }` (no scenario, meaningless)
✅ Good: `void shouldReturnUserWhenIdExists() { }`, `void shouldThrowNotFoundExceptionWhenUserDoesNotExist() { }`, `void givenInvalidEmail_whenValidating_thenThrowsValidationException() { }`
⚠️ Why: Test names are documentation; describe scenario and expectation; diagnose failures without reading code
🔧 Fix: `should[Expected]When[Scenario]` or `given[State]_when[Action]_then[Expectation]`
📍 See: `general-llm-anti-patterns.mdc` section 6.2
**Detect:** `test` + method name, numbered tests, vague names like `testSuccess`

---

### 7.3 One Assertion Concept Per Test (CRIT)

**CRITICAL:** Each test should verify one behavior. Multiple assertions are fine if they verify the same concept.

❌ Bad: `void testUserService() { assertThat(service.create(user)).isNotNull(); assertThat(service.findById(id)).isPresent(); assertThat(service.delete(id)).isTrue(); }` (CRUD in one test)
✅ Good: `void shouldCreateUserWithGeneratedId() { User c = service.create(valid); assertThat(c.getId()).isNotNull(); assertThat(c.getName()).isEqualTo(valid.getName()); }` (one concept, multi-assert OK)
⚠️ Why: Single-concept tests easier to understand, maintain, diagnose; multi-assert for same concept is fine
🔧 Fix: Split by behavior; multi-assert for same concept OK; one clear purpose per test
📍 See: `general-llm-anti-patterns.mdc` section 6.2
**Detect:** Unrelated assertions in one test, CRUD in sequence, tests named after multiple operations

---

### 7.4 Parameterized Tests (CRIT)

**CRITICAL:** Use parameterized tests for testing same logic with different inputs. Avoid copy-paste test methods.

❌ Bad: `@Test void shouldValidateEmail1() {...}` `@Test void shouldValidateEmail2() {...}` (copy-paste, numbered)
✅ Good: `@ParameterizedTest @CsvSource({"test@example.com, true", "invalid, false"}) void shouldValidateEmail(String email, boolean exp) { assertThat(validator.isValid(email)).isEqualTo(exp); }`
⚠️ Why: Reduces duplication; easy to add cases; clear matrix; better coverage with less code
🔧 Fix: `@ParameterizedTest` with `@CsvSource`, `@ValueSource`, `@MethodSource`, or `@EnumSource`
📍 See: [JUnit 5 Parameterized Tests](https://junit.org/junit5/docs/current/user-guide/#writing-tests-parameterized-tests)
**Detect:** Copy-pasted tests with different inputs, numbered test methods, tests differing only in input

---

### 7.5 Mock External Dependencies (CRIT)

**CRITICAL:** Use mocks for external dependencies (databases, APIs, file systems). Don't test third-party code.

❌ Bad: `User user = realDatabase.findById("123"); assertThat(user).isNotNull();` (real DB, slow, flaky)
✅ Good: `when(mockRepo.findById("123")).thenReturn(Optional.of(expected)); Optional<User> r = service.getUser("123"); assertThat(r).contains(expected); verify(mockRepo).findById("123");`
⚠️ Why: Tests fast, deterministic, isolated; mocks give control; test your code, not frameworks
🔧 Fix: Mockito at boundaries (repo, clients); verify when important
📍 See: `general-llm-anti-patterns.mdc` section 6.1
**Detect:** Real DB/API in tests, slow/flaky tests, tests requiring external setup

---

## Category 8: Documentation

### 8.1 Javadoc for Public APIs (CRIT)

**CRITICAL:** Document all public APIs with Javadoc. Include @param, @return, @throws.

❌ Bad: `public User findUser(String id) throws UserNotFoundException { }` (no Javadoc)
✅ Good: `/** Finds user by id. @param id must not be null @return the user @throws UserNotFoundException if not found @throws NPE if id null */` before the method
⚠️ Why: Javadoc is the contract; preconditions, postconditions, exceptions; generates API docs
🔧 Fix: Document public classes/interfaces/methods; include `@param`, `@return`, `@throws`; document thread safety
📍 See: Effective Java Item 56
**Detect:** Public methods without Javadoc, missing @param/@return/@throws, Javadoc that just repeats name

---

### 8.2 Self-Documenting Code Over Comments (CRIT)

**CRITICAL:** Write self-documenting code. Comments should explain "why", not "what".

❌ Bad: `// Increment i by 1` `i++;` or `// Check if active` `if (u.isActive())` (comment states "what")
✅ Good: `// Per GDPR: inactive must not appear in exports (compliance 3.2)` then `users.stream().filter(User::isActive).toList();`
⚠️ Why: Code self-explanatory; "what" comments go stale; "why" comments add value
🔧 Fix: Descriptive names; extract methods; comment only "why"; keep comments updated
📍 See: Effective Java Item 56, `general-llm-anti-patterns.mdc` section 3.2
**Detect:** Comments restating code, outdated comments, commented-out code, excessive inline comments

---

## Category 9: Architecture and Design

### 9.1 Favor Composition Over Inheritance (CRIT)

**CRITICAL:** Use composition instead of inheritance. Inheritance breaks encapsulation.

❌ Bad: `class LoggingList<E> extends ArrayList<E> { @Override add(e) { log(); return super.add(e); } }` (fragile, super.addAll may double-log)
✅ Good: `class LoggingList<E> implements List<E> { private final List<E> delegate; ... return delegate.add(e); }` (composition, delegate)
⚠️ Why: Inheritance exposes impl; base changes break subclasses; composition more flexible
🔧 Fix: Composition with delegation; inherit only when "is-a" fundamental; design for inheritance or prohibit
📍 See: Effective Java Items 18, 19
**Detect:** Extending concrete classes, overriding to add behavior, fragile base class

---

### 9.2 Design for Immutability (CRIT)

**CRITICAL:** Make classes immutable unless there's a good reason for mutability.

❌ Bad: `class User { private String name,email; void setName(...) void setEmail(...) }` (mutable, not thread-safe)
✅ Good: `record User(String name, String email) { User { Objects.requireNonNull(name); requireNonNull(email); } }` or final class with final fields, `withName()` for "change"
⚠️ Why: Thread-safe; shareable; no defensive copies; easier to reason; records make it easy
🔧 Fix: Records for data; final fields; no setters; defensive copy of mutable fields
📍 See: Effective Java Item 17
**Detect:** Setters on data classes, mutable fields without reason, data classes that could be records

---

### 9.3 Interface-Based Design (CRIT)

**CRITICAL:** Program to interfaces, not implementations. Return interface types.

❌ Bad: `ArrayList<User> getUsers()`, `void process(ArrayList<User> users)` (exposes implementation)
✅ Good: `List<User> getUsers() { return List.copyOf(users); }`, `void process(List<User> users)`, `Collection<User> getAllUsers()` when sufficient
⚠️ Why: Flexibility to change impl; clients don't depend on concrete; enables polymorphism
🔧 Fix: Return/accept interface types; use most general interface that's sufficient
📍 See: Effective Java Item 64
**Detect:** Returning `ArrayList`/`HashMap`/`HashSet`, params typed to concrete, impl details in API

---

### 9.4 Functional Core, Imperative Shell (CRIT)

**CRITICAL:** Keep business logic pure (no side effects). Push I/O and mutation to the edges.

❌ Bad: `void processOrder(id) { Order o = db.find(id); if (o.getTotal()>1000) { o.setDiscount(0.1); email.send(o); } db.save(o); }` (I/O + mutation in core)
✅ Good: `DiscountResult calculateDiscount(Order o) { return o.total()>1000 ? new DiscountResult(o.withDiscount(0.1), true) : new DiscountResult(o, false); }` then `processOrder` does I/O in/out, calls calculateDiscount (pure) in between
⚠️ Why: Pure core testable without mocks; easier to reason; side effects at edges
🔧 Fix: Separate pure from I/O; return values instead of mutating; push I/O to boundaries
📍 See: `general-llm-anti-patterns.mdc` section 1.4
**Detect:** Business logic doing I/O, untestable methods needing mocks, side effects scattered

---

## Category 10: Anti-Patterns to Avoid

### 10.1 God Classes (CRIT)

**CRITICAL:** Classes should have single responsibility. No class should be "the place where everything happens".

❌ Bad: `class UserManager { createUser(); sendEmail(); generateReport(); validatePayment(); updateInventory(); }` (50+ unrelated methods)
✅ Good: `UserService`, `EmailService`, `ReportGenerator`, `PaymentValidator`, `InventoryService` (one responsibility each)
⚠️ Why: Violates SRP; hard to test; changes affect unrelated functionality
🔧 Fix: One class, one responsibility; extract cohesive functionality
📍 See: `general-llm-anti-patterns.mdc` section 1.6
**Detect:** 500+ lines, unrelated methods, "Manager"/"Util" doing everything

---

### 10.2 Checked Exception Abuse (CRIT)

**CRITICAL:** Use checked exceptions only for recoverable conditions. Use unchecked for programming errors.

❌ Bad: `void process(String data) throws DataException { if (data==null) throw new DataException("null"); }` (programming error as checked; callers wrap in RuntimeException)
✅ Good: `void process(String data) { Objects.requireNonNull(data); }` (unchecked); `User findUser(String id) throws UserNotFoundException` (recoverable, checked)
⚠️ Why: Checked = recoverable; programming errors (null, illegal state) = unchecked; too many checked = unusable API
🔧 Fix: Unchecked for programming errors; checked only when caller can recover
📍 See: Effective Java Items 70, 71
**Detect:** Checked for null/illegal, callers always wrap in RuntimeException, excessive throws

---

### 10.3 Premature Optimization (CRIT)

**CRITICAL:** Don't optimize without evidence. Clarity first, optimize later if profiler confirms.

❌ Bad: `final int MAGIC_SIZE = 1024;` and complex unreadable code "for performance" (no measurement)
✅ Good: `items.stream().filter(this::isValid).map(this::transform).toList();` (clear); optimize only after JFR shows hot path
⚠️ Why: JIT is smart; premature opt wastes time; measure before optimizing
🔧 Fix: Clear code first; profile (JFR); optimize only confirmed hot paths; benchmark
📍 See: Effective Java Item 67, `general-llm-anti-patterns.mdc` section 0.1
**Detect:** "Optimizations" without measurements, unclear code "for performance", magic numbers for "efficiency"

---

### 10.4 Raw Types (CRIT)

**CRITICAL:** Never use raw types. Always parameterize generic types.

❌ Bad: `List users = new ArrayList(); users.add("not a user"); User u = (User) users.get(0);` (raw, ClassCastException)
✅ Good: `List<User> users = new ArrayList<>(); users.add(new User("Alice")); User u = users.get(0);`
⚠️ Why: Raw types lose type safety; ClassCastException at runtime; only for backwards compat
🔧 Fix: Parameterized types always; `<?>` for unknown; bounded wildcards where appropriate
📍 See: Effective Java Item 26
**Detect:** `List`/`Map`/`Set` without type params, unchecked warnings, ClassCastExceptions

---

### 10.5 Magic Numbers and Strings (CRIT)

**CRITICAL:** Extract magic values to named constants. Don't scatter literals through code.

❌ Bad: `if (status == 1) { }`, `Thread.sleep(5000);`, `role.equals("admin")` (unclear literals)
✅ Good: `STATUS_ACTIVE`, `Duration RETRY_DELAY = Duration.ofSeconds(5)`, `ROLE_ADMIN` or `enum Status { ACTIVE, INACTIVE }`
⚠️ Why: Named constants document intent; single source; enums better for fixed sets
🔧 Fix: Extract to named constants; enums for fixed sets; group related constants
📍 See: `general-llm-anti-patterns.mdc` section 3.6
**Detect:** Numeric literals in conditions, string literals in comparisons, repeated literals, unclear numbers

---

## Summary: Critical Java 21 Rules

These patterns represent the most critical Java 21 best practices:

1. **Records** - Use for immutable data carriers, eliminate POJO boilerplate
2. **Pattern Matching** - Replace instanceof + cast, enable exhaustive switches
3. **Virtual Threads** - Use for I/O-bound tasks, don't pool them
4. **Switch Expressions** - Use for multi-way conditionals, ensure exhaustiveness
5. **Sealed Classes** - Control inheritance, enable exhaustive switches
6. **Optional** - Return for absent values, never use for fields/parameters
7. **Immutability** - Make classes immutable by default, use records
8. **Fail-Fast** - Validate early with `Objects.requireNonNull()`
9. **Try-with-Resources** - Use for all AutoCloseable resources
10. **Collections** - Return empty not null, prefer immutable, use Sequenced Collections
11. **Streams** - Use for transformations, avoid side effects, format readably
12. **Specific Exceptions** - Throw specific, never swallow, preserve cause
13. **Composition** - Favor over inheritance
14. **JVM Tuning** - ZGC for latency, container-aware settings, AppCDS for startup
15. **Testing** - JUnit 5 + AssertJ, descriptive names, parameterized tests

**Quick Reference:**

| Category | Key Points |
|----------|------------|
| **Modern Syntax** | Records, pattern matching, switch expressions, var, text blocks, sealed classes |
| **Concurrency** | Virtual threads for I/O, don't pool, avoid pinning, structured concurrency |
| **Null Handling** | Optional for returns only, `Objects.requireNonNull()`, never return null collections |
| **Collections** | `List.of()` for immutables, Sequenced Collections API, Stream for transformations |
| **Exceptions** | Specific types, don't swallow, try-with-resources, no control flow |
| **Performance** | Profile first, ZGC for latency, container-aware, AppCDS, StringBuilder in loops |
| **Testing** | JUnit 5, AssertJ, descriptive names, parameterized tests, mock externals |
| **Design** | Immutability, composition, interfaces, functional core |

---

## References

- [Effective Java, 3rd Edition](https://www.oreilly.com/library/view/effective-java/9780134686097/) by Joshua Bloch
- [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html)
- [JEP 444: Virtual Threads](https://openjdk.org/jeps/444)
- [JEP 440: Record Patterns](https://openjdk.org/jeps/440)
- [JEP 441: Pattern Matching for switch](https://openjdk.org/jeps/441)
- [JEP 431: Sequenced Collections](https://openjdk.org/jeps/431)

---

*This file embodies the principles of "Effective Java" by Joshua Bloch, the Google Java Style Guide, and modern Java 21 LTS best practices. It should guide all Java development in this project.*
