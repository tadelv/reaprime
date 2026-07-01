---
description: "Python-specific development standards following PEP 8, PEP 20 (Zen of Python), and Pythonic best practices"
globs: ["**/*.py"]
alwaysApply: false
---
## Persona: Principal Python Backend Engineer
- **Role:** High-scale systems (Instagram/Dropbox scale). **Philosophy:** PEP 20 "Explicit > implicit", "Readability counts"
- **Bias:** Hate magic (explicit imports/types), Obsessed asyncio safety (snapshot before await), Prefer Pydantic over dicts, Prefer @dataclass over boilerplate

---

# Python Development Standards

This file contains Python-specific development standards that embody the ethos of Python as expressed in [PEP 20 - The Zen of Python](https://peps.python.org/pep-0020/), follows the [PEP 8 - Style Guide for Python Code](https://peps.python.org/pep-0008/), and incorporates best practices from [The Hitchhiker's Guide to Python - Code Style](https://docs.python-guide.org/writing/style/), [Pythonic Code Best Practices](https://www.codementor.io/blog/pythonic-code-6yxqdoktzt), and [The Zen of Python: Design Philosophy & Readability](https://llego.dev/posts/zen-python-guide-design-philosophy-readability/).

**For universal anti-patterns:** See the general anti-LLM-traps rules file.

---

## The Zen of Python (PEP 20)

These principles guide all Python code:

1. Beautiful is better than ugly.
2. Explicit is better than implicit.
3. Simple is better than complex.
4. Complex is better than complicated.
5. Flat is better than nested.
6. Sparse is better than dense.
7. Readability counts.
8. Special cases aren't special enough to break the rules.
9. Although practicality beats purity.
10. Errors should never pass silently.
11. Unless explicitly silenced.
12. In the face of ambiguity, refuse the temptation to guess.
13. There should be one-- and preferably only one --obvious way to do it.
14. Although that way may not be obvious at first unless you're Dutch.
15. Now is better than never.
16. Although never is often better than *right* now.
17. If the implementation is hard to explain, it's a bad idea.
18. If the implementation is easy to explain, it may be a good idea.
19. Namespaces are one honking great idea -- let's do more of those!

---

## PEP 8 Style Guide Compliance

All Python code must follow [PEP 8](https://peps.python.org/pep-0008/) conventions. Key requirements:

- **Indentation:** 4 spaces per level (never tabs)
- **Line Length:** Maximum 79 characters (99 for team agreement, 72 for docstrings/comments)
- **Imports:** Standard library → third-party → local, each group separated by blank line
- **Naming:** `snake_case` for functions/variables, `PascalCase` for classes, `UPPER_CASE` for constants
- **Whitespace:** One space around operators, after commas, but not inside parentheses/brackets
- **String Quotes:** Use double quotes for docstrings, single quotes for strings (be consistent)

**Remember:** "A foolish consistency is the hobgoblin of little minds" - consistency within a project is more important than blind adherence to PEP 8.

---

## Category 1: Pythonic Style & Readability

### 1.1 Meaningful and Descriptive Names (CRIT)

**CRITICAL:** Use descriptive variable and function names that clearly indicate their purpose.

❌ Bad: `def calc(x, y): z = x * y; return z`, `proc(d)`, single-letter vars (`x`, `i`, `tmp`)
✅ Good: `def calculate_area(length: float, width: float) -> float:`, `user_data`, `total_count`
⚠️ Why: Names don't indicate purpose; violates "Readability counts"; hard to maintain
🔧 Fix: Use full words; function names verbs; variable names nouns; follow PEP 8
📍 See: `general-llm-anti-patterns.mdc` section 0.1

**Detect:** Single-letter variables (except `i` in short loops), abbreviations (`usr`, `cnt`), generic names (`data`, `value` without context), Hungarian notation

### 1.1a Source File Naming (Guidance)

Modules: short, all-lowercase, underscores allowed (`my_module.py`). Packages: all-lowercase, underscores discouraged. 📍 See: PEP 8 Package and Module Names; `general-llm-anti-patterns.mdc` Category 12.

---

### 1.2 Explicit is Better Than Implicit (CRIT)

**CRITICAL:** Prefer explicit code over implicit magic. Code should be self-documenting.

❌ Bad: `def make_complex(*args): return dict(**locals())`, implicit `return None`, missing type hints
✅ Good: `def make_complex(x: float, y: float) -> dict[str, float]: return {'x': x, 'y': y}`
⚠️ Why: `locals()` returns too much; implicit None easy to miss; violates "Explicit > implicit"
🔧 Fix: Use explicit params; return None explicitly; add type hints (PEP 484); avoid `locals()`
📍 See: `general-llm-anti-patterns.mdc` section 0.1

**Detect:** `*args`/`**kwargs` when specific params clearer, `locals()`/`globals()`, implicit return, missing type hints

---

### 1.3 Simple and Uncluttered Syntax (CRIT)

**CRITICAL:** Keep code simple and uncluttered. Break complex expressions into steps.

❌ Bad: `result = (((x+y)*z)/w)+((a*b)/c) if cond else default`, nested list comprehension 3+ levels
✅ Good: Use intermediate variables; `for` loops over deeply nested comprehensions
⚠️ Why: Hard to read; violates "Simple is better than complex"; difficult to debug
🔧 Fix: Break complex expressions; use intermediate vars; prefer clarity over cleverness
📍 See: `general-llm-anti-patterns.mdc` section 0.1

**Detect:** Complex one-liners, nested comprehensions 3+ levels, dense code without whitespace

---

### 1.4 One Statement Per Line (CRIT)

**CRITICAL:** One statement per line. Don't combine multiple statements with semicolons.

❌ Bad: `print('foo'); print('bar')`, `if x == 1: print('foo')`, complex comparison on one line
✅ Good: One statement per line; break complex comparisons into named variables
⚠️ Why: Violates "Sparse is better than dense"; harder to read and debug; violates PEP 8
🔧 Fix: One statement per line; extract complex conditions to variables; no semicolons
📍 See: PEP 8

**Detect:** Semicolons combining statements, compound if with action on same line

---

### 1.5 Using Built-in Types and Functions (CRIT)

**CRITICAL:** Use built-in types and functions. Don't reimplement standard library.

❌ Bad: `def custom_length(items): count=0; [count:=count+1 for _ in items]; return count`, list for key-value pairs
✅ Good: `len()`, `sum()`, `max()`, `Counter`, `defaultdict`; dict for key-value, set for unique
⚠️ Why: Reinventing wheel; less efficient; violates "one obvious way"
🔧 Fix: Use built-ins (`len`, `sum`, `max`, `sorted`); use `collections`; match structure to use case
📍 See: `general-llm-anti-patterns.mdc` section 0.4

**Detect:** Custom implementations of len/sum/max, list for key-value pairs, ignoring collections module

---

### 1.6 Simple Iterations Over Index Manipulation (CRIT)

**CRITICAL:** Prefer direct iteration. Use `enumerate()` when index needed, not `range(len())`.

❌ Bad: `for i in range(len(items)): items[i]`, manual counter `count += 1` in loop
✅ Good: `for item in items:`, `for i, item in enumerate(items):`, `zip(names, ages)`
⚠️ Why: Verbose, error-prone (off-by-one); violates "Simple is better than complex"
🔧 Fix: Use `for item in items`; use `enumerate()` for index; use `zip()` for parallel
📍 See: `general-llm-anti-patterns.mdc` section 2.3

**Detect:** `range(len())` when iteration works, manual loop counters, complex index calculations

---

### 1.7 Assignment Tricks and Tuple Unpacking (CRIT)

**CRITICAL:** Use tuple unpacking and walrus operator (`:=`) where appropriate.

❌ Bad: `temp=x; x=y; y=temp`, `x=point[0]; y=point[1]`, `value=calc(); if value>100: process(value)` (duplicate calc)
✅ Good: `x, y = y, x`, `x, y = point`, `if (value := calc()) > 100: process(value)`
⚠️ Why: Verbose; misses Python's elegant features; violates "Simple is better than complex"
🔧 Fix: Use tuple unpacking for swap; unpack function returns; use walrus operator when needed
📍 See: `general-llm-anti-patterns.mdc` section 0.1

**Detect:** Manual variable swap, index access instead of unpacking, duplicate call when walrus would work

---

### 1.8 Using Containers to Simplify Logic (CRIT)

**CRITICAL:** Replace if/elif chains with dictionary lookups. Use dicts for mappings and config.

❌ Bad: `if status=='success': return 200; elif status=='not_found': return 404; ...`
✅ Good: `STATUS_CODES = {'success': 200, ...}; return STATUS_CODES.get(status, default)`
⚠️ Why: Verbose and repetitive; violates "Simple is better than complex"; hard to maintain
🔧 Fix: Use dict for mappings; use dict.get() with default; use containers for config
📍 See: `general-llm-anti-patterns.mdc` section 0.1

**Detect:** Long if/elif chains for mappings, config in if/elif, repeated lookups without dict

---

### 1.9 Function Arguments Best Practices (CRIT)

**CRITICAL:** Use list param instead of `*args` when clearer. Use keyword args for optional params.

❌ Bad: `def send(message, *args)`, `def create_user(name, email, age, address, phone, country, zipcode)`
✅ Good: `def send(message: str, recipients: list[str])`, keyword args with defaults for optional
⚠️ Why: Unclear API; hard to remember order; violates "Explicit > implicit"
🔧 Fix: Use list param for sequences; use keyword args for 3+ optional params; follow YAGNI
📍 See: `general-llm-anti-patterns.mdc` section 1.2

**Detect:** `*args` when list clearer, `**kwargs` when specific params work, 5+ positional args

---

### 1.10 Avoid the Magical Wand (CRIT)

**CRITICAL:** Use straightforward approaches. Prefer `@dataclass` over custom metaclasses.

❌ Bad: Custom metaclass for simple data class, modifying import behavior, advanced metaprogramming
✅ Good: `@dataclass` for data carriers, standard imports, simple classes
⚠️ Why: Reduces readability; violates "Simple is better than complex"; tool incompatibility
🔧 Fix: Use `@dataclass` over metaclasses; reserve advanced techniques for proven need
📍 See: `general-llm-anti-patterns.mdc` section 0.2

**Detect:** Custom metaclass for simple case, non-standard import hooks, metaprogramming when simple works

---

### 1.11 We Are All Responsible Users (CRIT)

**CRITICAL:** Use single underscore for "internal use". Avoid name mangling unless needed.

❌ Bad: `self.__name` (name mangling) for simple encapsulation, getter/setter boilerplate
✅ Good: `self._name` (convention), `@property` for controlled access
⚠️ Why: Name mangling usually unnecessary; violates "Simple is better than complex"
🔧 Fix: Use `_` prefix for internal; use `@property` when needed; trust conventions
📍 See: PEP 8

**Detect:** `__` for simple privacy, complex encapsulation when convention suffices

---

### 1.12 Simple is Better Than Complex (CRIT)

**CRITICAL:** Prefer simple solutions. Prefer functions over classes for simple operations.

❌ Bad: Factory/Builder for simple task, complex class hierarchy for list processing
✅ Good: `def process_numbers(nums): return [n*2 for n in nums if n>0]`
⚠️ Why: Over-engineering; violates "Simple is better than complex"; maintenance burden
🔧 Fix: Start with simplest solution; prefer functions over classes; use `@dataclass` for data
📍 See: `general-llm-anti-patterns.mdc` section 0.2

**Detect:** Factory/Builder for simple cases, complex hierarchy for trivial logic, premature patterns

---

### 1.13 Flat is Better Than Nested (CRIT)

**CRITICAL:** Avoid 4+ levels of nesting. Use early returns and guard clauses.

❌ Bad: `if a: if b: if c: if d: ...` (6 levels), deeply nested if/for
✅ Good: Early returns `if not user_data: return None`; guard clauses
⚠️ Why: Hard to read; violates "Flat is better than nested"; error-prone
🔧 Fix: Use early returns; extract nested logic; limit to 2-3 levels
📍 See: PEP 8, `general-llm-anti-patterns.mdc` section 0.1

**Detect:** 4+ nesting levels, nested try/except, comprehensions beyond 2 levels

---

### 1.14 Readability Counts (CRIT)

**CRITICAL:** Prioritize readability. Add docstrings for public APIs (PEP 257).

❌ Bad: `def f(d): return [x for x in [y for y in d.values() if y] if len(x)>5]`, cryptic names
✅ Good: Descriptive names; docstrings; break complex expressions; PEP 8 spacing
⚠️ Why: Violates "Readability counts"; hard to maintain; violates PEP 8/257
🔧 Fix: Use descriptive names; add docstrings; prefer clarity over cleverness; follow PEP 8
📍 See: PEP 8, PEP 257, `general-llm-anti-patterns.mdc` section 0.1

**Detect:** Cryptic names (`x`, `tmp`), nested comprehensions 2+ levels, missing docstrings on public APIs

---

### 1.15 Sparse is Better Than Dense (CRIT)

**CRITICAL:** Break complex operations into steps. Limit function length (<30 lines).

❌ Bad: `result = [x.upper().strip().replace(...) for x in filter(lambda y:..., map(str, data)) if '@' not in x]`
✅ Good: Intermediate variables; blank lines between functions; one logical op per line
⚠️ Why: Violates "Sparse is better than dense"; hard to debug; violates PEP 8 spacing
🔧 Fix: Break into steps; use intermediate vars; limit function length; follow PEP 8 blank lines
📍 See: PEP 8

**Detect:** 50+ line functions, multiple ops on one line, chained calls 5+ methods, missing blank lines

---

## Category 2: Python Idioms & Conventions

### 2.1 Truth Value Testing (CRIT)

**CRITICAL:** Use truthiness. Use `is None` for None, `not seq` for empty sequences.

❌ Bad: `if attr == True:`, `if attr == None:`, `if len(seq) == 0:`
✅ Good: `if attr:`, `if attr is None:`, `if not seq:`
⚠️ Why: Not Pythonic; verbose; violates conventions
🔧 Fix: Use truthiness; `is None` not `== None`; `not seq` not `len(seq)==0`
📍 See: PEP 8

**Detect:** `== True`/`== False`, `== None`, `len(seq)==0`, `count>0` when `count` suffices

---

### 2.2 Dictionary Access (CRIT)

**CRITICAL:** Use `dict.get(key, default)` for safe access. Never use `dict.has_key()` (Python 2).

❌ Bad: `d.has_key('key')`, `d['key']` without checking, KeyError risk
✅ Good: `'key' in d`, `d.get('key', default)`, use `.get()` for optional access
⚠️ Why: `.has_key()` removed in Python 3; KeyError risk; not Pythonic
🔧 Fix: Use `in` operator; use `.get()` with default; use `[key]` only when key exists
📍 See: PEP 8

**Detect:** `has_key()`, `[key]` without existence check, no default on optional access

---

### 2.3 Sets vs Lists for Membership Testing (CRIT)

**CRITICAL:** Use sets for membership when many items or repeated searches. O(1) vs O(n).

❌ Bad: `valid_ids = [1,2,...10000]; if id in valid_ids` (O(n) per lookup)
✅ Good: `valid_ids = {1,2,...10000}` or `set(lst)`; O(1) lookup
⚠️ Why: List `in` is O(n); set `in` is O(1); slow for large/repeated
🔧 Fix: Use set when duplicates not needed and repeated membership; convert list to set once
📍 See: `general-llm-anti-patterns.mdc` section 2.3

**Detect:** List for repeated membership, large collection with `in` on list

---

### 2.4 List Comprehensions and Generator Expressions (CRIT)

**CRITICAL:** Use comprehensions for lists; generators for iteration. Don't use for side effects.

❌ Bad: `[print(x) for x in seq]`, `max([...])` when `max((...))` works, verbose loop when comp clearer
✅ Good: Loop for side effects; comprehension for list; generator `(...)` when just iterating
⚠️ Why: Comprehension for side effects wastes memory; generator saves memory; verbose when comp clearer
🔧 Fix: Use loop for side effects; use generator expression when iterating only; prefer comprehension over verbose loop
📍 See: PEP 8

**Detect:** Comprehension for side effects only, list when generator works, verbose loop when comprehension clearer

---

### 2.5 Filtering Lists (CRIT)

**CRITICAL:** Never modify a list while iterating. Create new list with comprehension.

❌ Bad: `for i in lst: lst.remove(i)`, `while x in lst: lst.remove(x)`
✅ Good: `filtered = [v for v in seq if v != x]`, `seq[::] = [v for v in seq if v != x]` for in-place
⚠️ Why: Modifying during iteration skips elements; unpredictable; violates `general-llm-anti-patterns`
🔧 Fix: Use comprehension to create new list; use slice assignment if must modify original
📍 See: `general-llm-anti-patterns.mdc` section 2.1

**Detect:** `remove()` in loop, modifying list during iteration, multiple passes to remove

---

### 2.6 Modifying List Values (CRIT)

**CRITICAL:** Assignment creates reference, not copy. Use `enumerate()` when index needed.

❌ Bad: `b=a; for i in range(len(a)): a[i]+=3` (b changes), `range(len(a))` when enumerate works
✅ Good: `a = [i+3 for i in a]` for new list; `b=a[:]` for copy; `enumerate(a)` for index
⚠️ Why: Shared reference causes unexpected side effects; manual counter not Pythonic
🔧 Fix: Create new list for independent copy; use `enumerate()`; use `[:]` for shallow copy
📍 See: `general-llm-anti-patterns.mdc` section 1.6

**Detect:** Mutating shared list, `range(len())` when enumerate works, reference vs copy confusion

---

### 2.7 File Handling (CRIT)

**CRITICAL:** Always use `with open()`. Never manually close files.

❌ Bad: `f = open('file.txt'); ...; f.close()` (resource leak on exception)
✅ Good: `with open('file.txt') as f: ...` (auto-close on exception)
⚠️ Why: File may not close on exception; resource leak; not Pythonic
🔧 Fix: Use `with open()`; use `pathlib.Path` for modern handling; never manual `close()`
📍 See: `general-llm-anti-patterns.mdc` section 5.4

**Detect:** Manual open/close, file not in context manager, resource not released on exception

---

### 2.8 Line Continuations (CRIT)

**CRITICAL:** Use parentheses for line continuation. Never use backslashes (fragile).

❌ Bad: `line1 \` or `from x import a, b \` (backslash continuation)
✅ Good: Parentheses `(line1, line2)` or `from x import (a, b, c)` for continuation
⚠️ Why: Backslash fragile (whitespace breaks it); error-prone; not Pythonic
🔧 Fix: Use parentheses for implicit continuation; use brackets for lists; never backslashes
📍 See: PEP 8

**Detect:** Backslash line continuation, trailing whitespace after backslash

---

### 2.9 Async State Snapshotting (CRIT)
**CRITICAL:** Capture state to local variables before `await` to prevent race conditions.
❌ Bad: `async def update(u): u = await get(); await save(u)` (u may change during await)
✅ Good: `async def update(u): u = await get(); snap = UserSnapshot(u.name, u.email); await save(snap)`
⚠️ Why: State may change during await, causing race conditions
🔧 Fix: Always snapshot mutable state before await operations
📍 See: `general-llm-anti-patterns.mdc` section 1.2
**Detect:** Mutable objects used after await without snapshotting, shared state modified during async ops

---

## Category 3: PEP 8 Compliance

### 3.1 Indentation (CRIT)

**CRITICAL:** Use 4 spaces per level. Never mix tabs and spaces.

❌ Bad: Tabs, mixing tabs/spaces, 2 or 8 spaces instead of 4
✅ Good: 4 spaces per level; use `python -m tabnanny` to check
⚠️ Why: PEP 8 requires 4 spaces; tabs cause editor issues; mixing breaks Python
🔧 Fix: Configure editor 4 spaces; never tabs; use tabnanny
📍 See: PEP 8

**Detect:** Tabs for indentation, mixed tabs/spaces, inconsistent indentation

---

### 3.2 Line Length (CRIT)

**CRITICAL:** Limit lines to 79 chars (99 team agreement). Docstrings/comments 72 chars.

❌ Bad: Lines >79 chars without wrapping, docstrings >72 chars
✅ Good: Use parentheses for wrapping; hanging indents for params; use `black`
⚠️ Why: Violates PEP 8; hard to read in diffs; poor code review
🔧 Fix: Wrap at 79; use parentheses; keep docstrings 72; use black formatter
📍 See: PEP 8

**Detect:** Lines >79 chars, long docstrings, no proper line continuation

---

### 3.3 Import Organization (CRIT)

**CRITICAL:** Organize imports: stdlib → third-party → local. Blank line between groups.

❌ Bad: Mixed import groups, no blank lines, unused imports, unsorted
✅ Good: stdlib → third-party → local; blank line between; use `isort`
⚠️ Why: Violates PEP 8; unclear dependencies; hard to maintain
🔧 Fix: Group imports; blank line between groups; sort; remove unused; use isort
📍 See: PEP 8

**Detect:** Imports not grouped, missing blank lines, unused imports, inconsistent order

---

### 3.4 Naming Conventions (CRIT)

**CRITICAL:** PEP 8: `snake_case` functions/vars, `PascalCase` classes, `UPPER_CASE` constants.

❌ Bad: `camelCase` for functions, `snake_case` for classes, inconsistent naming
✅ Good: `snake_case` functions/vars, `PascalCase` classes, `UPPER_CASE` constants
⚠️ Why: Violates PEP 8; inconsistent with Python community; harder to read
🔧 Fix: Follow PEP 8 exactly; snake_case for funcs/vars; PascalCase for classes
📍 See: PEP 8, section 1.1

**Detect:** camelCase for functions, snake_case for classes, single-letter vars (except loops)

---

### 3.5 Whitespace Usage (CRIT)

**CRITICAL:** Space around operators, after commas; not inside parentheses.

❌ Bad: `def calc(x,y,z):`, `result=x+y*z`, `return( result )`
✅ Good: Space around operators; space after comma; no space inside parens; use `black`
⚠️ Why: Violates PEP 8; harder to read; inconsistent
🔧 Fix: Space around operators; space after comma; use black/autopep8
📍 See: PEP 8

**Detect:** Missing spaces around operators, no space after comma, extra space inside parens

---

## Category 4: Python-Specific Anti-Patterns

### 4.1 Misuse of `*args` and `**kwargs` (CRIT)

**CRITICAL:** Use explicit parameters when 2-3 specific params suffice. Don't catch-all with *args/**kwargs.

❌ Bad: `def create_user(*args, **kwargs):` when explicit params clearer, no type hints for kwargs
✅ Good: Explicit params; use *args/**kwargs only for decorators/wrappers; TypedDict for kwargs
⚠️ Why: Unclear API; no type checking; violates "Explicit > implicit"
🔧 Fix: Use explicit params when possible; document expected params; use TypedDict for kwargs
📍 See: section 1.9, `general-llm-anti-patterns.mdc` section 1.2

**Detect:** *args/**kwargs when 2-3 explicit params work, kwargs passed through without validation

---

### 4.2 Improper Exception Handling (CRIT)

**CRITICAL:** Never use bare `except:`. Catch specific exceptions. Log or propagate errors.

❌ Bad: `except: pass`, `except Exception: return False` (swallows all), try clause too broad
✅ Good: Specific exceptions; log before handle; re-raise when needed; minimal try clause
⚠️ Why: Violates PEP 20 "Errors should never pass silently"; hidden bugs; silent data loss
🔧 Fix: Catch specific exceptions; log errors; limit try to minimum; document if silenced
📍 See: `general-llm-anti-patterns.mdc` section 5.3

**Detect:** Bare except, except Exception without logging, try clause too broad, silent pass

---

### 4.3 Type Hint Neglect (CRIT)

**CRITICAL:** Use type hints for params and return (PEP 484). Use `|` for union (3.10+).

❌ Bad: `def process(data, options):` (no hints), `Any` to avoid typing, no return type
✅ Good: Type hints on all params/returns; TypedDict for dicts; `|` for union
⚠️ Why: Unclear API; no IDE support; runtime type errors; violates "Explicit > implicit"
🔧 Fix: Add type hints; use TypedDict; use `|` for union; run mypy
📍 See: PEP 484, section 1.2

**Detect:** Functions without type hints, Any to avoid typing, no return annotation, no hints on public APIs

---

### 4.4 List Comprehension Abuse (CRIT)

**CRITICAL:** If comprehension is unreadable, use a loop. PEP 8 emphasizes readability.

❌ Bad: Nested comprehension 3+ levels, complex logic in comprehension, 5+ lines in one comp
✅ Good: Loop for complex logic; extract to function; limit comprehension to 2 levels
⚠️ Why: Violates "Readability counts"; hard to debug; violates "Sparse is better than dense"
🔧 Fix: Use loop when comprehension unclear; extract to function; prefer readability
📍 See: section 1.3, 1.14, PEP 8

**Detect:** Nested comprehension 3+ levels, complex logic in comp, comprehension 5+ lines

---

### 4.5 Global State and Mutable Defaults (CRIT)

**CRITICAL:** Never use mutable defaults (`def f(items=[])`). Avoid global state. Use `None` as default.

❌ Bad: `def add_item(item, items=[])`, `global var`, mutable default args
✅ Good: `def add_item(item, items=None): items = items or []`, pass state explicitly
⚠️ Why: Mutable defaults shared across calls; global state makes testing impossible
🔧 Fix: Use `None` as default, create new object inside; pass state; dependency injection
📍 See: `general-llm-anti-patterns.mdc` section 5.6

**Detect:** `def f(items=[])`, `global` keyword, module-level mutable state

---

### 4.6 Monkey Patching Guidelines (CRIT)

**CRITICAL:** Use monkey patching only when necessary. Prefer pytest `monkeypatch` fixture in tests.

❌ Bad: Undocumented patch, patch without preserving original, modifying own code
✅ Good: Use pytest monkeypatch in tests; document why/what/when to remove; store original
⚠️ Why: Hidden behavior; can break with updates; violates "Explicit > implicit"
🔧 Fix: Prefer dependency injection; use monkeypatch fixture; document and store original
📍 See: section 1.10

**Detect:** setattr on modules/classes without doc, no original preserved, own code patched

---

## Category 5: Python Standard Library & Idioms

### 5.1 Reinventing Standard Library (CRIT)

**CRITICAL:** Use standard library. PEP 20: "There should be one obvious way."

❌ Bad: Custom Counter implementation, manual JSON parsing when `json` exists, not using pathlib
✅ Good: `from collections import Counter`, `pathlib.Path`, `json`, `itertools`, `@dataclass`
⚠️ Why: Reinventing wheel; more code; bugs stdlib solved; violates "one obvious way"
🔧 Fix: Check stdlib before implementing; use collections, pathlib, json, itertools
📍 See: section 1.5, `general-llm-anti-patterns.mdc` section 0.4

**Detect:** Custom Counter/defaultdict, manual file handling vs pathlib, reimplementing itertools

---

### 5.2 Not Using Context Managers (CRIT)

**CRITICAL:** Use `with` for resources. Use `pathlib.Path` for file operations.

❌ Bad: `f=open(f); ...; f.close()` (resource leak), try/finally when `with` works
✅ Good: `with open(f) as f:`, `with path.open() as f`, context managers for DB
⚠️ Why: Resource leak on exception; error-prone; violates PEP 8
🔧 Fix: Always use `with`; use pathlib.Path; create custom context managers when needed
📍 See: section 2.7, `general-llm-anti-patterns.mdc` section 5.4

**Detect:** Manual open/close, DB connections without context manager, try/finally instead of with

---

### 5.3 Ignoring Modern Python Features (CRIT)

**CRITICAL:** Use `@dataclass`, type hints, f-strings, `pathlib`, `match/case` when appropriate.

❌ Bad: Manual `__init__`/`__repr__` when `@dataclass` works, `.format()` instead of f-strings
✅ Good: `@dataclass`, f-strings, pathlib, match/case (3.10+), type hints
⚠️ Why: Boilerplate; error-prone; violates "Simple is better than complex"
🔧 Fix: Use @dataclass; f-strings; pathlib; match/case when appropriate
📍 See: section 1.5, 4.3, PEP 484

**Detect:** Manual __init__ when dataclass works, .format() instead of f-string, os.path vs pathlib

---

## Category 6: Documentation & Testing

### 6.1 Missing Docstrings (PEP 257) (CRIT)

**CRITICAL:** Public functions, classes, modules must have docstrings (PEP 257).

❌ Bad: Public function/class without docstring, docstring not PEP 257 format
✅ Good: Docstring with Args, Returns; wrap at 72 chars; include examples for complex
⚠️ Why: Unclear API; violates PEP 257; harder to use; no IDE help
🔧 Fix: Add docstrings; follow PEP 257; include Args/Returns; wrap at 72
📍 See: PEP 257, PEP 8, `documentation-policy.mdc`

**Detect:** Public function without docstring, class without docstring, module without docstring

---

### 6.2 PEP 8 Compliance Tools (CRIT)

**CRITICAL:** Use black, flake8, isort, mypy for automated PEP 8 and type checking.

❌ Bad: No linting in CI, manual style enforcement, inconsistent formatting
✅ Good: Use black (formatter), flake8 (linter), isort (imports), mypy (types)
⚠️ Why: Inconsistent formatting; manual enforcement error-prone; violates PEP 8
🔧 Fix: Add black/flake8/isort/mypy to CI; use black for formatting
📍 See: PEP 8

**Detect:** No linting in CI, manual format enforcement, no formatter

**Tools:** black (formatter), autopep8 (PEP 8), flake8 (linter), isort (imports), mypy (types)

---

## Category 7: Legacy Code Handling

### 7.1 Dealing with Legacy Code (CRIT)

**CRITICAL:** Systematic approach: version control, remove dead code, add tests, run linters, format, refactor gradually.

❌ Bad: Commented code in prod, no tests, no linting, inconsistent style
✅ Good: Delete commented code; add tests before refactoring; use black/flake8/isort; refactor incrementally
⚠️ Why: Technical debt; risky refactoring; no quality checks
🔧 Fix: Version control; remove dead code; add tests; run linters; format; refactor one module at a time
📍 See: `general-llm-anti-patterns.mdc` section 8.2 (Strangler Fig)

**Detect:** Commented code in prod, no tests, no linting, no version control, mixed styles

---

## Summary: Critical Python Rules

These patterns represent the most critical violations of Python's ethos and PEP 8:

1. **Meaningful Names** - Use descriptive variable and function names that clearly indicate purpose
2. **Explicit is Better Than Implicit** - Use type hints, explicit parameters, clear names
3. **Simple and Uncluttered Syntax** - Keep code simple and readable
4. **Use Built-in Types** - Leverage Python's built-in types and functions
5. **Simple Iterations** - Prefer straightforward iteration over index manipulation
6. **Assignment Tricks** - Use tuple unpacking and modern assignment features
7. **Containers Simplify Logic** - Use data structures to streamline code
8. **Simple is Better Than Complex** - Avoid over-engineering
9. **Flat is Better Than Nested** - Use early returns, limit nesting
10. **Readability Counts** - Write code for humans to read (PEP 8)
11. **Errors Should Never Pass Silently** - Handle exceptions properly (PEP 20)
12. **There Should Be One Obvious Way** - Use standard library (PEP 20)
13. **Follow PEP 8** - Indentation, line length, naming, whitespace, imports
14. **Use Python Idioms** - Truthiness, dictionary access, list comprehensions, context managers
15. **Performance Matters** - Use sets for membership testing, generators for large data
16. **Handle Legacy Code Systematically** - Version control, tests, linters, gradual refactoring

**Quick Reference:**

- **Naming:** Descriptive, meaningful names that indicate purpose
- **Style:** Explicit over implicit, simple over complex, flat over nested, readable code
- **Built-ins:** Use built-in types, functions, and data structures
- **Iteration:** Simple iterations, enumerate(), zip(), avoid index manipulation
- **Assignment:** Tuple unpacking, walrus operator, multiple assignment
- **Containers:** Use dicts/lists/sets to simplify logic and configuration
- **PEP 8:** 4 spaces, 79 char lines, organized imports, proper naming, whitespace
- **Idioms:** Truthiness, `in` operator, `.get()`, list comprehensions, generators, `enumerate()`, `with` statements
- **Performance:** Sets for membership (O(1)), generators for large data, avoid modifying lists during iteration
- **Python-Specific:** Proper use of *args/**kwargs, exception handling, type hints, comprehensions, monkey patching (section 4.6)
- **Standard Library:** Use built-in modules, context managers, modern features
- **Legacy Code:** Version control, remove dead code, add tests, run linters, format code, write idiomatic Python
- **Testing & Docs:** Docstrings (PEP 257), PEP 8, proper testing

**Remember:**

- "If the implementation is hard to explain, it's a bad idea." (PEP 20)
- "A foolish consistency is the hobgoblin of little minds" - consistency within a project is more important than blind adherence to PEP 8
- "We are all responsible users" - use conventions, not enforcement
- "Readability counts" - meaningful names and simple syntax are essential
- "There should be one obvious way" - use built-in types and standard library
- Performance: Use sets for membership testing when you have many items or repeated searches

---

## Final Phase Verification

Before closing a task or phase, the agent must perform a self-audit using the instructions in `python-3-brutal-audit.mdc`. This is a non-negotiable step for production-ready code.

**See also:** `python-3-brutal-audit.mdc` for comprehensive phase review checklist

---

*This file embodies the principles of [PEP 20 - The Zen of Python](https://peps.python.org/pep-0020/), [PEP 8 - Style Guide for Python Code](https://peps.python.org/pep-0008/), [The Hitchhiker's Guide to Python - Code Style](https://docs.python-guide.org/writing/style/), [Pythonic Code Best Practices](https://www.codementor.io/blog/pythonic-code-6yxqdoktzt), and [The Zen of Python: Design Philosophy & Readability](https://llego.dev/posts/zen-python-guide-design-philosophy-readability/) and should guide all Python development in this project.*
