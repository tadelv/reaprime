---
description: "JavaScript/ECMAScript development standards following modern best practices, Airbnb/Google style guides, and JavaScript community conventions"
globs: ["**/*.js", "**/*.jsx", "**/*.mjs", "**/*.cjs", "**/*.ts", "**/*.tsx"]
alwaysApply: false
---

## Persona: Senior JavaScript Architect
- **Role:** Modern JavaScript/TypeScript expert (Node.js, React, frontend ecosystems). **Philosophy:** "Explicit > implicit", "Readability counts", "Type safety where possible"
- **Bias:** Modern ES6+ features (const/let > var, async/await > callbacks), Prefer TypeScript or JSDoc for types, Strict mode always, Prefer functional over imperative, Performance-conscious (lazy evaluation, memoization), Security-first (input validation, CSP)

---

# JavaScript Development Standards

This file contains JavaScript/ECMAScript-specific development standards that embody modern JavaScript best practices, follows conventions from [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript), [Google JavaScript Style Guide](https://google.github.io/styleguide/jsguide.html), and incorporates best practices from [MDN JavaScript Guide](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide) and [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices).

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`.

---

## JavaScript Philosophy

JavaScript's evolution (ES6+) has transformed it into a powerful, expressive language. These principles guide all JavaScript code:

1. **Explicit is better than implicit** - Use clear, obvious code over clever tricks
2. **Readability counts** - Code is read more often than written; prioritize clarity
3. **Modern features first** - Use ES6+ features (const/let, arrow functions, destructuring, async/await, modules) when available
4. **Type safety** - Use TypeScript when possible, or JSDoc types for better IDE support
5. **Async-first** - Prefer async/await over raw promises and callbacks
6. **Modular** - Use ES6 modules, keep modules focused and small
7. **Safety** - Always use strict mode, validate inputs, handle errors explicitly
8. **Performance-aware** - Write efficient code, but don't prematurely optimize
9. **Security-first** - Never trust user input, sanitize everything, avoid eval()
10. **Functional over imperative** - Prefer declarative patterns (map, filter, reduce) when appropriate

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`.

---

## Category 1: Modern JavaScript Syntax & Style

### 1.1 Meaningful and Descriptive Names (CRIT)

**CRITICAL:** Use descriptive variable and function names that clearly indicate their purpose. Names are one of the most important aspects of readable code.

❌ Bad: `function calc(x, y) { return x * y; }`, single-letter variables (`x`, `i`, `tmp`) except in short loops, abbreviations that aren't obvious (`usr`, `cnt`, `calc`), generic names (`data`, `value`, `result` without context), Hungarian notation or type prefixes
✅ Good: `function calculateArea(length, width) { return length * width; }`, full words not abbreviations, function names are verbs (calculate, process, validate), variable names are nouns (userData, totalCount), use domain-specific terminology, follow camelCase convention, make names self-documenting
⚠️ Why: Names don't indicate purpose; violates "Readability counts"; hard to understand code intent; makes code maintenance difficult
🔧 Fix: Use full words not abbreviations; names should describe purpose or content; function names should be verbs; variable names should be nouns; use domain-specific terminology; follow camelCase convention
📍 See: `general-llm-anti-patterns.mdc` section 0.1
**Detect:** Single-letter variables (except short loops), abbreviations that aren't obvious, generic names without context, names that don't describe purpose, Hungarian notation or type prefixes

---

### 1.2 Variable Declarations (CRIT)

**CRITICAL:** Use `const` by default, `let` when reassignment is needed, never `var`.

❌ Bad: `var userName = 'John';`, using `let` when `const` would work, variables declared but not initialized, reassigning `const` variables, `var` in loops (leaks to outer scope)
✅ Good: `const userName = 'John';`, `let userCount = 0; userCount = getUserCount();` (only when reassignment needed), `for (let i = 0; i < items.length; i++)` (proper scoping), `for (const item of items)` (prefer for...of), `const users = []; users.push({ name: 'John' });` (const for objects/arrays even if contents change)
⚠️ Why: `var` has function scope and hoisting issues; `var` in loops creates closure bugs; using `let` when `const` would work reduces intent clarity; variables can be declared but undefined causing bugs
🔧 Fix: Always use `const` unless reassignment is needed; use `let` only when variable will be reassigned; never use `var` in new code; initialize variables when declaring; use `const` for arrays/objects even if contents change (reference is constant)
📍 See: `general-llm-anti-patterns.mdc` section 5.6
**Detect:** Using `var` declarations, using `let` when `const` would work, variables declared but not initialized, reassigning `const` variables, `var` in loops creating closure bugs

---

### 1.3 Strict Mode (CRIT)

**CRITICAL:** Always use strict mode (`'use strict';`) or ES modules (which are strict by default).

❌ Bad: Missing `'use strict';` directive, not using ES modules, `undeclaredVar = data;` (creates global without strict mode)
✅ Good: `'use strict';` directive at top of file, ES modules (`export function processData(data) {}`) are strict by default, configure ESLint to enforce strict mode
⚠️ Why: Silent failures (undeclared variables become globals); allows dangerous features (eval with access to enclosing scope); not catching common mistakes; poor error messages
🔧 Fix: Always use `'use strict';` or ES modules; ES modules are strict by default (preferred); configure ESLint to enforce strict mode; never disable strict mode
📍 See: `general-llm-anti-patterns.mdc` section 5.2
**Detect:** Missing `'use strict';` directive, not using ES modules, silent failures that strict mode would catch, undeclared variables becoming globals

---

### 1.4 Semicolons (CRIT)

**CRITICAL:** Always use semicolons to terminate statements. Prevents Automatic Semicolon Insertion (ASI) errors.

❌ Bad: `const x = 1` (missing semicolon), `return x + y` (ASI can cause bugs), ASI-dependent code, inconsistent semicolon usage
✅ Good: `const x = 1;`, `return x + y;`, explicit semicolons after all statements, configure ESLint to enforce semicolons, use Prettier for automatic formatting
⚠️ Why: ASI can cause subtle bugs; automatic insertion doesn't always work as expected; inconsistent with team standards; makes code harder to read
🔧 Fix: Add semicolons after all statements; configure ESLint to enforce semicolons; use Prettier for automatic formatting (includes semicolons)
📍 See: `general-llm-anti-patterns.mdc` section 3.6
**Detect:** Missing semicolons after statements, ASI-dependent code, inconsistent semicolon usage, return statements without semicolons before expression

---

### 1.5 Arrow Functions vs Function Declarations (CRIT)

**CRITICAL:** Use arrow functions for callbacks and when `this` binding isn't needed. Use function declarations for hoisted functions and when `this` context matters.

❌ Bad: `numbers.map(function(n) { return n * 2; });` (function keyword for simple callbacks), `getName = () => this.name;` in class (creates new function per instance), `const calculate = (x) => x * 2;` when hoisting needed (ReferenceError)
✅ Good: `numbers.map(n => n * 2);` (arrow functions for callbacks), `function calculateTotal(items) { ... }` (function declaration for hoisting), `getName() { return this.name; }` (class method not arrow when this needed), `document.addEventListener('click', (e) => { this.handleClick(e); });` (arrow when lexical this desired), `greet() { return \`Hello, ${this.name}\`; }` (method shorthand in objects)
⚠️ Why: Verbose syntax when arrow function would be clearer; arrow functions in classes create per-instance functions (memory overhead); loses hoisting benefits of function declarations; unclear when to use which style
🔧 Fix: Use arrow functions for callbacks and when lexical `this` is needed; use function declarations for named functions that benefit from hoisting; use class methods (not arrow) for class instance methods; use method shorthand (`getName() {}`) for object methods
📍 See: `general-llm-anti-patterns.mdc` section 0.5
**Detect:** Using `function` keyword for simple callbacks, arrow functions in class methods that need `this`, mixing styles inconsistently, arrow functions in object methods that need `this`, arrow function when hoisting needed

---

### 1.6 Template Literals (CRIT)

**CRITICAL:** Use template literals for string interpolation. Avoid string concatenation with `+`.

❌ Bad: `const message = 'Hello, ' + userName + '! You have ' + count + ' messages.';`, string concatenation with `+` operator, complex string building with concatenation, escaping quotes unnecessarily
✅ Good: `const message = \`Hello, ${userName}! You have ${count} messages.\`;`, template literals for string interpolation, template literals for multi-line strings, expression interpolation in template literals, only use `+` for actual numeric addition
⚠️ Why: Harder to read especially with multiple variables; easy to make mistakes with quotes and spacing; verbose and error-prone; not modern JavaScript idiom
🔧 Fix: Always use template literals for string interpolation; use template literals for multi-line strings; only use `+` for actual numeric addition
📍 See: `general-llm-anti-patterns.mdc` section 3.6
**Detect:** String concatenation with `+` operator, complex string building with concatenation, escaping quotes in strings unnecessarily, multi-line strings using `+`

---

### 1.7 Destructuring (CRIT)

**CRITICAL:** Use destructuring for object and array access to improve readability and reduce verbosity.

❌ Bad: `const userName = user.name; const userEmail = user.email;` (manual property access), `const first = items[0]; const second = items[1];` (array access by index), missing default values in destructuring
✅ Good: `const { name: userName, email: userEmail, age: userAge = 0 } = user;` (object destructuring with defaults), `const [first, second, third] = items;` (array destructuring), `const { name, email = 'unknown@example.com' } = user;` (destructuring with defaults), `const { address: { street, city } } = user;` (nested destructuring), `function processUser({ name, email, age = 0 }) {}` (function parameters), `const { name, email, ...otherProps } = user;` (rest operator with destructuring)
⚠️ Why: Verbose and repetitive; harder to read; missing modern JavaScript idiom; no default values for missing properties
🔧 Fix: Use destructuring for object property access; use destructuring for array elements; provide default values when properties might be missing; use destructuring in function parameters; use rest operator with destructuring
📍 See: `general-llm-anti-patterns.mdc` section 0.1
**Detect:** Manual property access when destructuring would work, multiple lines accessing same object properties, array access by index when destructuring would be clearer, missing default values in destructuring

---

### 1.8 Spread and Rest Operators (CRIT)

**CRITICAL:** Use spread (`...`) for copying and combining, rest (`...`) for variadic functions and collecting remaining items.

❌ Bad: `const copy = originalArray.slice();` (using slice for copying), `function sum() { for (let i = 0; i < arguments.length; i++) {} }` (using arguments object), `const combined = [].concat(array1, array2);` (manual array concatenation)
✅ Good: `const copy = [...originalArray];` (spread for copying), `function sum(...numbers) { return numbers.reduce((total, num) => total + num, 0); }` (rest parameters), `const combined = [...array1, ...array2, ...array3];` (spread for combining), `const merged = { ...defaults, ...userProvided, ...overrides };` (object spread), `const [first, second, ...rest] = items;` (rest for collecting remaining), `const max = Math.max(...numbers);` (spread for function arguments)
⚠️ Why: Verbose and less readable; `arguments` is not a real array (no array methods); not using modern JavaScript features; harder to maintain
🔧 Fix: Use spread operator for copying arrays/objects; use rest parameters instead of `arguments`; use spread for combining arrays/objects; use rest for collecting remaining items in destructuring; use spread for function arguments instead of `.apply()`
📍 See: `general-llm-anti-patterns.mdc` section 0.1
**Detect:** Using `Array.prototype.slice()` for copying, using `arguments` object instead of rest parameters, manual array/object copying, concatenating arrays with `concat()`, using `.apply()` for function arguments

---

### 1.9 Optional Chaining and Nullish Coalescing (CRIT)

**CRITICAL:** Use optional chaining (`?.`) and nullish coalescing (`??`) for safe property access and default values.

❌ Bad: `const city = user.address.city;` (unsafe property access, TypeError if address is null), `const count = user.count || 0;` (using || for defaults fails for falsy valid values), `const city = user && user.address && user.address.city;` (manual null checks)
✅ Good: `const city = user?.address?.city;` (optional chaining, returns undefined if any part is null/undefined), `const count = user.count ?? 0;` (nullish coalescing only for null/undefined not if 0), `const result = api?.fetchData?.();` (optional chaining with method calls), `const firstItem = items?.[0];` (optional chaining with array access), `const value = obj?.data?.items?.[0]?.value ?? 'default';` (combining both)
⚠️ Why: Runtime errors from null/undefined access; incorrect defaults when falsy values are valid; verbose and error-prone null checking; not using modern JavaScript features
🔧 Fix: Use optional chaining (`?.`) for safe property access; use nullish coalescing (`??`) for default values when null/undefined; use `||` only when you want to replace falsy values; prefer `??` over `||` for default values; use optional chaining with method calls and array access
**Detect:** Nested property access without null checks, using `||` for default values when `0`, `''`, or `false` are valid, manual null/undefined checks, verbose conditional property access

---

### 1.10 Array Methods (CRIT)

**CRITICAL:** Use modern array methods (`map`, `filter`, `reduce`, `find`, `some`, `every`) instead of loops when appropriate.

❌ Bad: `for (let i = 0; i < numbers.length; i++) { doubled.push(numbers[i] * 2); }` (imperative loops for transformations), `for (let i = 0; i < users.length; i++) { if (users[i].active) { activeUsers.push(users[i]); } }` (loops for filtering), `let total = 0; for (let i = 0; i < items.length; i++) { total += items[i].price; }` (loops for aggregations)
✅ Good: `const doubled = numbers.map(n => n * 2);` (map for transformations), `const activeUsers = users.filter(user => user.active);` (filter for filtering), `const total = items.reduce((sum, item) => sum + item.price, 0);` (reduce for aggregations), `const user = users.find(u => u.id === userId);` (find for finding), `const hasActive = users.some(u => u.active);` (some/every for boolean checks), chain array methods for clarity
⚠️ Why: Verbose and imperative; more error-prone (off-by-one, indexing); less expressive; harder to understand intent; violates functional programming principles
🔧 Fix: Use `map()` for transformations; use `filter()` for filtering; use `reduce()` for aggregations; use `find()` for finding single elements; use `some()`/`every()` for boolean checks; chain array methods for clarity; prefer array methods over loops; use `for...of` only when array methods aren't appropriate
📍 See: `general-llm-anti-patterns.mdc` section 2.1
**Detect:** Using `for` loops for transformations, using loops for filtering/finding, not leveraging array methods, mixing imperative and functional styles

---

### 1.11 Object Property Shorthand (CRIT)

**CRITICAL:** Use object property shorthand and method shorthand for cleaner code.

❌ Bad: `const user = { name: name, email: email, age: age };` (verbose property syntax), `greet: function() { return 'Hello'; }` (old-style method syntax)
✅ Good: `const user = { name, email, age };` (property shorthand), `greet() { return 'Hello'; }` (method shorthand), `const obj = { [key]: 'value', [\`prefix_${key}\`]: 'another value' };` (computed property names)
⚠️ Why: Verbose and repetitive; violates modern JavaScript conventions; less clean code
🔧 Fix: Use property shorthand when variable name matches property name; use method shorthand in objects; use computed property names with brackets; prefer modern object syntax
**Detect:** Verbose object property syntax, not using shorthand when possible, old-style method syntax in objects

---

## Category 2: Async/Await and Promises

### 2.1 Async/Await Over Callbacks (CRIT)

**CRITICAL:** Use `async/await` instead of callbacks or raw Promises for better readability and error handling.

❌ Bad: `fetchUser(userId, (err, user) => { if (err) handleError(err); else fetchPosts(user.id, ...); });` (callback hell), `fetchUser(userId).then(user => fetchPosts(user.id)).then(posts => processData(posts)).catch(err => handleError(err));` (promise chains)
✅ Good: `async function loadUserData(userId) { try { const user = await fetchUser(userId); const posts = await fetchPosts(user.id); return processData(user, posts); } catch (err) { handleError(err); throw err; } }` (async/await with try/catch), `const [user, posts, comments] = await Promise.all([fetchUser(userId), fetchPosts(userId), fetchComments(userId)]);` (parallel execution with Promise.all)
⚠️ Why: Callback hell is hard to read and maintain; promise chains are verbose and hard to debug; error handling is scattered; difficult to control flow (try/catch doesn't work with callbacks)
🔧 Fix: Use `async/await` for all async operations; use `try/catch` for error handling; use `Promise.all()` for parallel execution; only use callbacks when library requires it
📍 See: `general-llm-anti-patterns.mdc` section 2.1
**Detect:** Callback-based async code, promise chains when async/await would be clearer, mixing callbacks and promises, error handling in promise chains

---

### 2.2 Promise Error Handling (CRIT)

**CRITICAL:** Always handle Promise rejections. Never leave promises unhandled.

❌ Bad: `async function loadData() { const data = await fetchData(); processData(data); }` (unhandled promise rejection), `fetch('/analytics', ...);` (fire-and-forget promise without error handling)
✅ Good: `async function loadData() { try { const data = await fetchData(); processData(data); } catch (error) { console.error('Failed to load data:', error); } }` (error handling with try/catch), `fetch('/analytics', ...).catch(error => console.error('Analytics failed:', error));` (fire-and-forget with error handling)
⚠️ Why: Unhandled promise rejections can crash Node.js; silent failures in production; no visibility into errors; difficult to debug
🔧 Fix: Use `try/catch` for async/await; use `.catch()` for promise chains; handle fire-and-forget promises; use top-level error handlers
📍 See: `general-llm-anti-patterns.mdc` section 5.3
**Detect:** Promises without `.catch()` or `try/catch`, async functions without error handling, fire-and-forget promises, unhandled promise rejections

---

### 2.3 Promise.all vs Promise.allSettled (CRIT)

**CRITICAL:** Use `Promise.all()` when all must succeed; use `Promise.allSettled()` when you need all results regardless of failures.

❌ Bad: `Promise.all([...])` when some failures are acceptable, sequential awaits when operations are independent, not handling partial failures
✅ Good: `await Promise.all([fetchA(), fetchB()]);` (all must succeed, fails fast), `await Promise.allSettled([fetchA(), fetchB()]);` (get all results even if some fail), `Promise.allSettled([...]).then(results => results.filter(r => r.status === 'fulfilled'))` (handle partial failures)
⚠️ Why: `Promise.all()` fails fast if any promise rejects (may not be desired); sequential awaits are slow when operations are independent; not handling partial failures leads to lost data
🔧 Fix: Use `Promise.all()` when all operations must succeed; use `Promise.allSettled()` when partial failures are acceptable; use `Promise.race()` for timeouts; handle partial failures appropriately
**Detect:** Using `Promise.all()` when some failures are acceptable, sequential awaits when operations are independent, not handling partial failures, not using `Promise.allSettled()` when appropriate

---

### 2.4 Parallel vs Sequential Operations (CRIT)

**CRITICAL:** Execute independent operations in parallel; execute dependent operations sequentially.

❌ Bad: `const user = await fetchUser(id); const posts = await fetchPosts(user.id);` when operations are independent, sequential execution of independent async operations
✅ Good: `const [user, posts] = await Promise.all([fetchUser(id), fetchPosts(user.id)]);` (parallel when independent), sequential when operations depend on previous results, `for (const item of items) { await processItem(item); }` only when order matters
⚠️ Why: Sequential execution of independent operations is slow; parallel execution improves performance; dependent operations must be sequential
🔧 Fix: Use `Promise.all()` for parallel independent operations; use sequential `await` only when operations depend on previous results; batch operations when possible
📍 See: `general-llm-anti-patterns.mdc` section 2.1
**Detect:** Sequential execution of independent async operations, not using `Promise.all()` for parallel operations, sequential loops when order doesn't matter

---

## Category 3: Type Safety and Documentation

### 3.1 TypeScript or JSDoc Types (CRIT)

**CRITICAL:** Use TypeScript when possible, or JSDoc types for better IDE support and type safety.

❌ Bad: No type annotations, function parameters without types, return types not documented, `any` types used without justification
✅ Good: `function calculateArea(length: number, width: number): number { ... }` (TypeScript), `/** @param {number} length @param {number} width @returns {number} */ function calculateArea(length, width) { ... }` (JSDoc), avoid `any` type, use union types when appropriate
⚠️ Why: No type safety; harder to refactor; poor IDE support; runtime errors from type mismatches
🔧 Fix: Use TypeScript when possible; use JSDoc types if TypeScript not available; document all function parameters and return types; avoid `any` type; use strict type checking
**Detect:** No type annotations, function parameters without types, return types not documented, `any` types used without justification, missing JSDoc comments

---

### 3.2 JSDoc Documentation (CRIT)

**CRITICAL:** Document functions with JSDoc comments for parameters, return values, and exceptions.

❌ Bad: Functions without documentation, missing parameter descriptions, return types not documented, exceptions not documented
✅ Good: `/** * Calculates area of rectangle. * @param {number} length - Length of rectangle * @param {number} width - Width of rectangle * @returns {number} Area of rectangle * @throws {Error} If length or width is negative */ function calculateArea(length, width) { ... }`
⚠️ Why: Poor code documentation; hard to understand function usage; missing parameter/return information; no exception documentation
🔧 Fix: Document all public functions with JSDoc; include parameter descriptions and types; document return types; document exceptions; keep documentation up to date
**Detect:** Functions without documentation, missing parameter descriptions, return types not documented, exceptions not documented

---

## Category 4: Code Organization and Modules

### 4.1 ES6 Modules Over CommonJS (CRIT)

**CRITICAL:** Use ES6 modules (`import`/`export`) instead of CommonJS (`require`/`module.exports`) when possible.

❌ Bad: `const fs = require('fs'); module.exports = { processData };` (CommonJS), mixing ES6 modules and CommonJS
✅ Good: `import fs from 'fs'; export function processData() {};` (ES6 modules), `import { named } from './module.js';` (named imports), `export default function processData() {};` (default exports), consistent module system throughout project
⚠️ Why: ES6 modules are standard; better tree-shaking; static analysis; better tooling support; CommonJS is legacy
🔧 Fix: Use ES6 modules (`import`/`export`); configure package.json with `"type": "module"`; use `.mjs` extension if needed; avoid mixing module systems
**Detect:** Using CommonJS (`require`/`module.exports`), mixing ES6 modules and CommonJS, inconsistent module system

---

### 4.2 Module Organization (CRIT)

**CRITICAL:** Keep modules focused and small. One responsibility per module.

❌ Bad: Large modules with multiple responsibilities, modules with 500+ lines, mixing unrelated functionality, circular dependencies
✅ Good: Focused modules with single responsibility, small modules (100-200 lines preferred), clear module boundaries, avoid circular dependencies, use barrel exports (`index.js`) for public API
⚠️ Why: Large modules are hard to understand and maintain; mixing responsibilities violates SRP; circular dependencies cause issues; unclear module boundaries
🔧 Fix: Keep modules focused and small; one responsibility per module; use barrel exports for public API; avoid circular dependencies; refactor large modules
📍 See: `general-llm-anti-patterns.mdc` section 1.7
**Detect:** Large modules with multiple responsibilities, modules with 500+ lines, mixing unrelated functionality, circular dependencies

### 4.2a Source File Naming (Guidance)

If project has convention keep it. New projects: kebab-case for most files; PascalCase for React/component files. No spaces or special chars. 📍 See: Google JS Style Guide; `general-llm-anti-patterns.mdc` Category 12.

---

### 4.3 Import Organization (CRIT)

**CRITICAL:** Organize imports: external dependencies first, then internal modules, with blank lines between groups.

❌ Bad: Unorganized imports, mixing import types, no blank lines between import groups, relative imports before external
✅ Good: `import fs from 'fs'; import path from 'path';` (external first), blank line, `import { helper } from './helpers.js';` (internal modules), blank line, `import type { User } from './types.js';` (type imports if TypeScript), consistent import ordering
⚠️ Why: Unorganized imports are hard to read; inconsistent ordering makes it hard to find imports; no clear separation between external and internal
🔧 Fix: Organize imports: external dependencies first, then internal modules, with blank lines between groups; use consistent import ordering; configure ESLint to enforce import order
**Detect:** Unorganized imports, mixing import types, no blank lines between import groups, relative imports before external dependencies

---

## Category 5: Code Quality & Best Practices

### 5.1 Early Returns and Guard Clauses (CRIT)

**CRITICAL:** Use early returns and guard clauses to reduce nesting and improve readability.

❌ Bad: Deeply nested if statements, `if (valid) { ... } else { return; }` (else clause unnecessary)
✅ Good: `if (!user) return null; if (!user.active) return null; processUser(user);` (early returns), guard clauses at function start, reduced nesting, clearer control flow
⚠️ Why: Deeply nested code is hard to read; unnecessary else clauses add complexity; guard clauses make preconditions explicit
🔧 Fix: Use early returns for error cases; use guard clauses at function start; reduce nesting; remove unnecessary else clauses
📍 See: `general-llm-anti-patterns.mdc` section 1.4
**Detect:** Deeply nested if statements, unnecessary else clauses, missing guard clauses, nested conditionals that could use early returns

---

### 5.2 Avoid Side Effects (CRIT)

**CRITICAL:** Minimize side effects. Prefer pure functions when possible.

❌ Bad: Functions that modify global state, functions that mutate parameters, functions with hidden side effects, impure functions when pure would work
✅ Good: Pure functions (same input always produces same output), `function add(a, b) { return a + b; }` (no side effects), `function process(items) { return items.map(item => ({ ...item, processed: true })); }` (immutable transformations), explicit side effects when necessary
⚠️ Why: Side effects make functions unpredictable; hard to test; hard to reason about; causes bugs; violates functional programming principles
🔧 Fix: Prefer pure functions; avoid modifying global state; avoid mutating parameters; make side effects explicit; use immutable data structures when possible
📍 See: `general-llm-anti-patterns.mdc` section 5.6
**Detect:** Functions that modify global state, functions that mutate parameters, functions with hidden side effects, impure functions when pure would work

---

### 5.3 Avoid Magic Numbers and Strings (CRIT)

**CRITICAL:** Extract magic numbers and strings to named constants.

❌ Bad: `if (count > 100) {}` (magic number), `status === 'active'` (magic string), repeated magic values throughout code
✅ Good: `const MAX_ITEMS = 100; if (count > MAX_ITEMS) {}`, `const STATUS_ACTIVE = 'active'; if (status === STATUS_ACTIVE) {}`, named constants for all magic values, grouped related constants together
⚠️ Why: Magic values are hard to understand; no single source of truth; makes code fragile; hard to maintain
🔧 Fix: Extract magic values to named constants; use UPPER_CASE for constants; group related constants together; document constant meanings
📍 See: `general-llm-anti-patterns.mdc` section 3.6
**Detect:** Hardcoded numbers/strings, repeated magic values throughout code, no constants file or configuration, magic values without explanation

---

### 5.4 Naming Conventions (CRIT)

**CRITICAL:** Follow consistent naming conventions: camelCase for variables/functions, PascalCase for classes, UPPER_CASE for constants.

❌ Bad: Inconsistent naming, `user_name` (snake_case in JavaScript), `UserName` for variables, mixing naming conventions
✅ Good: `const userName = 'John';` (camelCase for variables), `function processData() {}` (camelCase for functions), `class UserService {}` (PascalCase for classes), `const MAX_ITEMS = 100;` (UPPER_CASE for constants), consistent naming throughout codebase
⚠️ Why: Inconsistent naming reduces readability; violates JavaScript conventions; makes codebase harder to navigate
🔧 Fix: Use camelCase for variables and functions; use PascalCase for classes; use UPPER_CASE for constants; be consistent throughout codebase; configure ESLint to enforce naming conventions
**Detect:** Inconsistent naming, snake_case in JavaScript, PascalCase for variables, mixing naming conventions

---

## Category 6: Error Handling

### 6.1 Explicit Error Handling (CRIT)

**CRITICAL:** Always handle errors explicitly. Never use empty catch blocks or ignore errors.

❌ Bad: `try { processData(); } catch {}` (empty catch block), `try { processData(); } catch (e) {}` (ignoring errors), generic catch blocks without specific error handling
✅ Good: `try { processData(); } catch (error) { console.error('Failed to process:', error); throw error; }` (explicit error handling), catch specific error types when possible, handle errors appropriately (log, retry, or rethrow), use error objects with meaningful messages
⚠️ Why: Silent failures hide bugs; empty catch blocks swallow errors; generic error handling loses context; difficult debugging
🔧 Fix: Always handle errors explicitly; never use empty catch blocks; catch specific error types when possible; log errors with context; rethrow or handle appropriately
📍 See: `general-llm-anti-patterns.mdc` section 5.3
**Detect:** Empty catch blocks, ignoring errors, generic catch blocks without specific error handling, silent failures

---

### 6.2 Custom Error Classes (CRIT)

**CRITICAL:** Use custom error classes for better error handling and debugging.

❌ Bad: Throwing generic `Error` objects, `throw 'Something went wrong';` (throwing strings), no error context or codes
✅ Good: `class ValidationError extends Error { constructor(message) { super(message); this.name = 'ValidationError'; } }`, `throw new ValidationError('Invalid user input');`, custom error classes with context, error codes for programmatic handling
⚠️ Why: Generic errors are hard to handle programmatically; throwing strings loses stack traces; no error context makes debugging difficult
🔧 Fix: Create custom error classes extending `Error`; include error context and codes; throw error instances not strings; handle specific error types
**Detect:** Throwing generic `Error` objects, throwing strings, no error context or codes, missing custom error classes

---

## Category 7: Testing

### 7.1 Test Structure and Organization (CRIT)

**CRITICAL:** Write tests for all critical functionality. Use descriptive test names and organize tests logically.

❌ Bad: No tests, tests with unclear names, tests that test multiple things, tests without organization
✅ Good: `test('should return error when user is not found', () => { ... });` (descriptive test names), one assertion per test concept, organized test files mirroring source structure, use test frameworks (Jest, Mocha, Vitest)
⚠️ Why: No tests means no confidence in code; unclear test names make failures hard to understand; tests that test multiple things are hard to debug; poor organization makes tests hard to find
🔧 Fix: Write tests for all critical functionality; use descriptive test names; organize tests logically; use test frameworks; maintain test coverage
📍 See: `general-llm-anti-patterns.mdc` section 6.2
**Detect:** No tests, tests with unclear names, tests that test multiple things, tests without organization, missing test coverage

---

### 7.2 Async Testing (CRIT)

**CRITICAL:** Properly handle async operations in tests. Use `async/await` or promise assertions.

❌ Bad: Tests that don't wait for async operations, `setTimeout` for async testing, not awaiting promises in tests
✅ Good: `test('should fetch user data', async () => { const user = await fetchUser(id); expect(user).toBeDefined(); });` (async/await in tests), `await expect(fetchUser(id)).resolves.toBeDefined();` (promise assertions), proper async test handling
⚠️ Why: Tests that don't wait for async operations give false positives; `setTimeout` is flaky; not awaiting promises causes race conditions
🔧 Fix: Use `async/await` in async tests; use promise assertions; wait for all async operations; avoid `setTimeout` for async testing
📍 See: `general-llm-anti-patterns.mdc` section 6.4
**Detect:** Tests that don't wait for async operations, `setTimeout` for async testing, not awaiting promises in tests, flaky async tests

---

### 7.3 Test Isolation and Mocking (CRIT)

**CRITICAL:** Tests must be isolated. Mock external dependencies and avoid shared state.

❌ Bad: Tests that depend on each other, tests that modify shared state, tests that hit real APIs/databases, no mocking of external dependencies
✅ Good: Each test is independent, mock external dependencies, `jest.mock('./api');` (mock modules), `const mockFetch = jest.fn();` (mock functions), use test fixtures for data, clean up after tests
⚠️ Why: Tests that depend on each other are brittle; shared state causes test interference; hitting real APIs/databases makes tests slow and unreliable; no mocking makes tests depend on external systems
🔧 Fix: Make tests independent; mock external dependencies; use test fixtures; clean up after tests; avoid shared state
📍 See: `general-llm-anti-patterns.mdc` section 6.1, 6.4
**Detect:** Tests that depend on each other, tests that modify shared state, tests that hit real APIs/databases, no mocking of external dependencies, shared test data

---

## Category 8: Performance and Optimization

### 8.1 Avoid Premature Optimization (CRIT)

**CRITICAL:** Don't optimize prematurely. Profile first, then optimize based on actual bottlenecks.

❌ Bad: Optimizing code without profiling, micro-optimizations that reduce readability, optimizing code that's not a bottleneck
✅ Good: Profile code first to identify bottlenecks, optimize only hot paths, measure before and after optimization, prioritize readability over micro-optimizations
⚠️ Why: Premature optimization wastes time; optimizations may not be needed; reduces code readability; may introduce bugs
🔧 Fix: Profile code first; identify actual bottlenecks; optimize only hot paths; measure optimization impact; prioritize readability
📍 See: `general-llm-anti-patterns.mdc` section 0.1
**Detect:** Optimizing code without profiling, micro-optimizations that reduce readability, optimizing code that's not a bottleneck

---

### 8.2 Efficient Data Structures and Algorithms (CRIT)

**CRITICAL:** Use appropriate data structures and algorithms. Consider time and space complexity.

❌ Bad: Using arrays for lookups (O(n)), nested loops when single pass possible (O(n²)), inefficient algorithms
✅ Good: Use `Map` or `Set` for O(1) lookups, use `Set` for membership tests, avoid nested loops when possible, use efficient algorithms (e.g., binary search for sorted arrays)
⚠️ Why: Inefficient data structures cause performance issues; O(n²) algorithms don't scale; wrong data structure for use case
🔧 Fix: Use appropriate data structures; consider time/space complexity; avoid nested loops when possible; use efficient algorithms
📍 See: `general-llm-anti-patterns.mdc` section 2.3
**Detect:** Using arrays for lookups, nested loops when single pass possible, inefficient algorithms, not considering time/space complexity

---

## Category 9: Security

### 9.1 Input Validation and Sanitization (CRIT)

**CRITICAL:** Always validate and sanitize user input. Never trust user input.

❌ Bad: `db.users.insert({ name: userData.name, email: userData.email });` (no validation), `document.getElementById('comments').innerHTML = comment;` (XSS vulnerability), direct use of user input in queries/HTML
✅ Good: `const validated = userSchema.parse(userData); db.users.insert(validated);` (input validation with Zod/Joi/Yup), `const sanitized = DOMPurify.sanitize(comment); document.getElementById('comments').innerHTML = sanitized;` (sanitize HTML output), `await db.query('SELECT * FROM users WHERE id = ?', [userId]);` (parameterized queries), never trust user input
⚠️ Why: Security vulnerabilities (XSS, injection); data corruption; runtime errors; compliance violations
🔧 Fix: Validate all user input; sanitize HTML output; use parameterized queries; never trust user input
📍 See: `general-llm-anti-patterns.mdc` section 5.2
**Detect:** No input validation, direct use of user input in queries/HTML, no sanitization, trusting user input

---

### 9.2 Avoid eval() and Function Constructor (CRIT)

**CRITICAL:** Never use `eval()` or `Function` constructor. Use JSON.parse() or safe alternatives.

❌ Bad: `eval(code);` (eval - NEVER DO THIS), `new Function('a', 'b', 'return a + b');` (Function constructor), executing user input as code, dynamic code generation
✅ Good: `JSON.parse(jsonString);` (JSON.parse for data), use proper parsing libraries, if code execution absolutely needed use strict sandboxing (`vm.createContext` in Node.js with timeout)
⚠️ Why: Major security vulnerability; allows arbitrary code execution; no way to sanitize; performance issues
🔧 Fix: Never use `eval()`; never use `Function()` constructor; use `JSON.parse()` for data; use proper parsing libraries; if code execution absolutely needed use strict sandboxing
📍 See: `general-llm-anti-patterns.mdc` section 5.1
**Detect:** Using `eval()`, using `Function()` constructor, executing user input as code, dynamic code generation

---

### 9.3 Environment Variables (CRIT)

**CRITICAL:** Use environment variables for configuration. Never commit secrets.

❌ Bad: `const apiKey = "sk-live-1234567890abcdef";` (hardcoded secrets), passwords in code, secrets in version control
✅ Good: `const apiKey = process.env.API_KEY;` (environment variables), use `.env` files (not committed), use secrets management services in production, never commit secrets
⚠️ Why: Hardcoded secrets are security risk; can't be changed without code change; get committed to version control; security breach if repository is compromised
🔧 Fix: Use environment variables for all secrets; use `.env` files (not committed); use secrets management in production; never commit secrets
📍 See: `general-llm-anti-patterns.mdc` section 5.1
**Detect:** Hardcoded API keys, passwords in code, secrets in version control, environment variables not used for secrets

---

## Category 10: Node.js Specific

### 10.1 Process Management and Graceful Shutdown (CRIT)

**CRITICAL:** Handle process signals for graceful shutdown. Clean up resources before exiting.

❌ Bad: No signal handlers, abrupt process termination, resources not cleaned up, active connections not closed
✅ Good: `process.on('SIGTERM', async () => { await cleanup(); process.exit(0); });` (signal handlers for graceful shutdown), close database connections, close HTTP servers, clean up resources, use health checks
⚠️ Why: Abrupt termination loses data; resources not cleaned up cause leaks; active connections cause errors; poor user experience
🔧 Fix: Handle SIGTERM/SIGINT signals; clean up resources before exiting; close connections gracefully; use health checks
**Detect:** No signal handlers, abrupt process termination, resources not cleaned up, active connections not closed

---

### 10.2 Stream Processing (CRIT)

**CRITICAL:** Use streams for large data processing. Don't load entire files into memory.

❌ Bad: `const data = fs.readFileSync('large-file.txt');` (loading entire file into memory), `const json = JSON.parse(fs.readFileSync('large.json'));` (loading large JSON into memory)
✅ Good: `fs.createReadStream('large-file.txt').pipe(process.stdout);` (streaming), `const stream = fs.createReadStream('large.json');` (use streams for large files), process data in chunks, use pipeline for stream composition
⚠️ Why: Loading large files into memory causes memory issues; streams process data in chunks; more efficient for large files; better performance
🔧 Fix: Use streams for large data processing; don't load entire files into memory; process data in chunks; use pipeline for stream composition
📍 See: `general-llm-anti-patterns.mdc` section 2.2
**Detect:** Loading entire files into memory, not using streams for large files, memory issues with large data, synchronous file operations

---

## Category 11: Tooling and Configuration

### 11.1 ESLint Configuration (CRIT)

**CRITICAL:** Use ESLint to enforce code quality and catch common errors.

❌ Bad: No ESLint configuration, ESLint disabled, ignoring ESLint rules without justification, inconsistent code style
✅ Good: ESLint configured with appropriate rules, use recommended presets (eslint:recommended, @typescript-eslint/recommended), configure rules for project needs, fix ESLint errors, use pre-commit hooks
⚠️ Why: No code quality enforcement; inconsistent code style; common errors not caught; harder code reviews
🔧 Fix: Configure ESLint with appropriate rules; use recommended presets; fix ESLint errors; use pre-commit hooks; enforce consistent code style
**Detect:** No ESLint configuration, ESLint disabled, ignoring ESLint rules without justification, inconsistent code style

---

### 11.2 Prettier Configuration (CRIT)

**CRITICAL:** Use Prettier for consistent code formatting. Configure to match team preferences.

❌ Bad: No Prettier configuration, inconsistent formatting, manual formatting, formatting conflicts in code reviews
✅ Good: Prettier configured with `.prettierrc`, format on save, use pre-commit hooks, consistent formatting across codebase
⚠️ Why: Inconsistent formatting wastes time; manual formatting is error-prone; formatting conflicts in reviews
🔧 Fix: Configure Prettier; format on save; use pre-commit hooks; ensure consistent formatting
**Detect:** No Prettier configuration, inconsistent formatting, manual formatting, formatting conflicts in code reviews

---

## References

- [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
- [Google JavaScript Style Guide](https://google.github.io/styleguide/jsguide.html)
- [MDN JavaScript Guide](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide)
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)

---

*This file consolidates JavaScript/ECMAScript-specific development standards. For universal anti-patterns, see `general-llm-anti-patterns.mdc`.*
