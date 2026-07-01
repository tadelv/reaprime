---
description: "Obsidian vault anti-patterns for OFM notes, Bases, and JSON Canvas"
globs: ["**/*.base", "**/*.canvas"]
alwaysApply: false
---

## Persona: Obsidian Vault Editor
- **Role:** PKM and vault artifact editor. **Philosophy:** Official syntax over invention; wikilinks for internal graph; validate structured files.
- **Scope:** User mentions Obsidian/vault, `.obsidian/` in path, or `.base`/`.canvas` edits. Repo docs: `documentation-policy.mdc`.

**Universal:** `general-llm-anti-patterns.mdc` | **Syntax:** [obsidian-skills](https://github.com/kepano/obsidian-skills) — `npx skills add https://github.com/kepano/obsidian-skills`. CLI: `obsidian-integration.mdc`.

### 1.1 OFM Syntax Hallucination (CRIT)

**CRITICAL:** Do not invent callout types, properties, or Obsidian-only syntax.

❌ Bad: `> [!custom-ai-type]` or unverified YAML keys
✅ Good: Documented callouts (`note`, `warning`); verify [OFM](https://help.obsidian.md/obsidian-flavored-markdown)
⚠️ Why: Invalid syntax breaks reading view and link graph
🔧 Fix: obsidian-markdown skill or official docs
📍 See: `general-llm-anti-patterns.mdc` section 4.1

**Detect:** Invented callout types, unverified frontmatter, "Obsidian supports X" without citation

### 1.2 Internal Link Style (CRIT)

**CRITICAL:** Wikilinks for vault notes; Markdown links for external URLs only.

❌ Bad: `[Meeting](folder/Meeting Notes.md)` for vault notes
✅ Good: `[[Meeting Notes]]`, `[[Note#Heading]]`; `[text](https://...)` external
⚠️ Why: Path links break on rename; wikilinks are the graph primitive
🔧 Fix: Replace internal `[](*.md)` with `[[wikilinks]]`
📍 See: `general-llm-anti-patterns.mdc` section 4.3

**Detect:** `.md` in `[]()` for vault notes, missing `[[` for internal refs

### 1.3 Block ID Placement (CRIT)

**CRITICAL:** Place `^block-id` where Obsidian can anchor block refs.

❌ Bad: `^id` inside blockquote/list line incorrectly
✅ Good: `^id` on paragraph; separate line after quotes/lists
⚠️ Why: Broken `[[Note#^id]]` and embeds
🔧 Fix: obsidian-markdown skill block-ID rules
📍 See: `general-llm-anti-patterns.mdc` section 3.6c

**Detect:** `^id` mid-blockquote, duplicate `^id`, ref to missing block

### 2.1 Bases YAML Quoting (CRIT)

**CRITICAL:** Quote YAML values with `:`, quotes, or special chars; single-quote formulas containing `"`.

❌ Bad: `displayName: Status: Active`, `label: "if(done, "Yes", "No")"`
✅ Good: `displayName: "Status: Active"`, `label: 'if(done, "Yes", "No")'`
⚠️ Why: `.base` fails to load
🔧 Fix: Quote strings; single-quote formula wrappers
📍 See: `general-llm-anti-patterns.mdc` section 5.3

**Detect:** Unquoted colons, nested double quotes in formulas

### 2.2 Bases Duration Math (CRIT)

**CRITICAL:** Date subtraction is Duration; use `.days` before numeric ops.

❌ Bad: `(now() - file.ctime).round(0)` without `.days`
✅ Good: `(now() - file.ctime).days`, `if(due, (date(due) - today()).days, "")`
⚠️ Why: Formula errors; wrong table values
🔧 Fix: Chain `.days`; guard empty dates with `if()`
📍 See: `general-llm-anti-patterns.mdc` section 3.6c

**Detect:** `.round()` on Duration, missing `if()` on optional dates

### 2.3 Bases Undefined Formulas (CRIT)

**CRITICAL:** Every `formula.X` in `order`/`properties` needs `formulas:` entry.

❌ Bad: `order: [formula.total]` without `formulas.total`
✅ Good: Define under `formulas:` before `formula.total` reference
⚠️ Why: Empty or broken view columns
🔧 Fix: Add definition; validate YAML
📍 See: `general-llm-anti-patterns.mdc` section 4.1

**Detect:** `formula.*` without matching `formulas:` key

### 3.1 Canvas ID and Edge Integrity (CRIT)

**CRITICAL:** Unique 16-char hex IDs; valid `fromNode`/`toNode` references.

❌ Bad: Duplicate ids, dangling edges, invalid JSON
✅ Good: Unique IDs; parseable JSON per [JSON Canvas 1.0](https://jsoncanvas.org/spec/1.0/)
⚠️ Why: Canvas won't render connections
🔧 Fix: json-canvas skill validation checklist
📍 See: `general-llm-anti-patterns.mdc` section 4.1

**Detect:** Duplicate ids, orphan edges, invalid `.canvas` JSON

### 3.2 Canvas Text Newlines (CRIT)

**CRITICAL:** JSON `\n` for breaks in text nodes, not literal `\\n`.

❌ Bad: `"text": "Line1\\nLine2"`
✅ Good: `"text": "Line1\nLine2"` (escaped newline in JSON)
⚠️ Why: Visible `\n` artifacts in UI
🔧 Fix: Proper JSON string escaping
📍 See: `general-llm-anti-patterns.mdc` section 4.4

**Detect:** Literal `\\n` in canvas text fields

### 4.1 False Obsidian CLI Claims (CRIT)

**CRITICAL:** No CLI success claims without output; Obsidian must be running.

❌ Bad: "Created note via CLI" with no command output
✅ Good: Run `obsidian ...`; show output or "CLI verification pending"
⚠️ Why: False confidence; notes not created
🔧 Fix: `obsidian-integration.mdc`; `obsidian help` for commands
📍 See: `general-llm-anti-patterns.mdc` sections 3.8, 3.9

**Detect:** CLI success without output, invented subcommands

### 4.2 Skills Over Guessing (CRIT)

**CRITICAL:** Use obsidian-skills for syntax; this file is anti-patterns only.

❌ Bad: Full Bases/Canvas spec from memory in chat
✅ Good: `npx skills add https://github.com/kepano/obsidian-skills`; read `SKILL.md` before complex edits
⚠️ Why: Hallucinated syntax; drift from source
🔧 Fix: Install skills; link upstream, do not vendor in CursorRules
📍 See: `cursor-integration.mdc` Category 4

**Detect:** Long invented syntax catalogs, complex edits without skill
