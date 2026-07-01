---
description: "Documentation and markdown creation policy - when to create .md files, Diátaxis structure, and strategic docs for agents"
alwaysApply: true
---
# Documentation Files Policy

**CRITICAL: Never create markdown files (`.md`) unless explicitly requested by the user.**

## Rules

1. **Do NOT create markdown files for:**
   - Explaining code changes or fixes
   - Documenting what was implemented
   - Creating README files
   - Writing documentation or guides
   - Summarizing work done
   - Any other automatic documentation

2. **Only create markdown files when:**
   - The user explicitly requests a markdown file (e.g., "create a README", "write documentation in a .md file", "create a markdown file for X")
   - The user specifically asks for documentation to be written to a file

3. **Communication:**
   - Explain changes and fixes directly in your response to the user
   - Use code comments when code documentation is needed
   - Do not create separate markdown files to explain work

4. **Existing markdown files:**
   - You may read and reference existing markdown files
   - Do not modify existing markdown files unless explicitly asked

### Obsidian vault notes (scope exception)

**Repo/software docs** (`README`, `CONTRIBUTING`, `docs/`, change summaries, PR writeups): this policy still applies — do not create unsolicited `.md`.

**PKM vault notes** (user explicitly asks to create, edit, or template a note, daily note, or vault page): this policy does not block that work. Follow `obsidian-vault-standards.mdc` and installed [obsidian-skills](https://github.com/kepano/obsidian-skills) for OFM syntax.

❌ Bad: Refusing "create a daily note" because documentation-policy forbids new `.md` files
✅ Good: Create/edit vault note when user requested; reserve documentation-policy for repo docs unless user asked for vault content
⚠️ Why: Vaults are note-first; conflating PKM with repo docs blocks legitimate user intent
🔧 Fix: Check user intent (vault vs repo); domain-specific Obsidian rules override this policy for vault notes
📍 See: `obsidian-vault-standards.mdc`; `RULE_COMPOSITION.md` conflict example 3

**Detect:** Agent cites documentation-policy when user asked for a note, vault path or `.obsidian/` present but agent treats all `.md` as repo docs

### Taskplane task packets (scope exception)

**Repo/software docs** (`README`, `CONTRIBUTING`, `docs/`, change summaries, PR writeups): this policy still applies — do not create unsolicited `.md`.

**Task orchestration artifacts** (user explicitly asks to create, stage, or plan tasks; or work under a configured tasks root): `PROMPT.md`, `STATUS.md`, and area `CONTEXT.md` are execution contracts, not general documentation. Follow `taskplane-task-authoring.mdc` and templates in `.cursor/rules/taskplane/`.

Do not refuse "create a task packet" or "write PROMPT.md for this feature" because documentation-policy forbids new `.md` files.

Reserve documentation-policy for repo docs unless the user asked for task packets or vault notes.

See `RULE_COMPOSITION.md` conflict example 5.

**Detect:** Agent cites documentation-policy when user asked for task packets, tasks-root path present, but agent treats `PROMPT.md` as unsolicited repo docs

### pi-spine task packets (scope exception)

**Repo/software docs** (`README`, `CONTRIBUTING`, `docs/`, change summaries, PR writeups): this policy still applies — do not create unsolicited `.md`.

**Spine orchestration artifacts** (user explicitly asks to create, stage, or decompose spine tasks; or work under `.spine/` and the configured tasks root): `PROMPT.md`, `STATUS.md`, `{tasksRoot}/CONTEXT.md`, `dependencies.json`, and authoring-only `{tasksRoot}/_explore/**`, `{tasksRoot}/_authoring/**` are execution contracts, not general documentation. Follow `spine-task-authoring.mdc` and templates in `.cursor/rules/taskplane/`.

Do not refuse "create spine tasks" or "write PROMPT.md for spine batch" because documentation-policy forbids new `.md` files.

Do not hand-edit `.spine/runtime/**` or `.spine/batch-state.json` — runtime state is spine-owned.

Reserve documentation-policy for repo docs unless the user asked for spine task packets, Taskplane packets, or vault notes.

See `RULE_COMPOSITION.md` conflict examples 5 and 11.

**Detect:** Agent cites documentation-policy when user asked for spine tasks, `.spine/spine-config.json` present, but agent treats spine `PROMPT.md` as unsolicited repo docs

## Inline Comments: Say Why and How

When writing in-code comments: say **why** and **how**, not only what. Code alone is not documentation. Write comments as full sentences (capital letter, period); end-of-line comments may be short phrases. See `engineering-philosophy.mdc` section 2.6 (Always Say Why).

## Examples

❌ **DON'T do this:**

- After fixing a bug, creating `BUGFIX_SUMMARY.md`
- After implementing a feature, creating `FEATURE_DOCUMENTATION.md`
- Creating `CHANGELOG.md` or `UPDATE_NOTES.md` automatically

✅ **DO this instead:**

- Explain changes directly in your response
- Add code comments if inline documentation is needed
- Only create markdown files when the user explicitly asks for them

## Documentation Structure (Diátaxis Framework)

**CRITICAL:** When documentation is explicitly requested, structure it according to the [Diátaxis framework](https://diataxis.fr), which organizes documentation into four types based on user needs.

### Four Documentation Types

| Type | Orientation | User Need | Example Request |
|------|-------------|-----------|-----------------|
| **Tutorial** | Learning | "Can you teach me to...?" | "Create a getting started guide" |
| **How-to Guide** | Goal | "How do I...?" | "How to add a language rule file" |
| **Reference** | Information | "What is...?" | "Document the API endpoints" |
| **Explanation** | Understanding | "Why...?" or "How does... work?" | "Explain why we use this architecture" |

### Quick Decision Tree

- User asks to "teach" or "learn" → **Tutorial**
- User asks "how to" or "how do I" → **How-to Guide**
- User asks "what is" or needs API docs → **Reference**
- User asks "why" or "how does it work" → **Explanation**

### Mixed-Mode Documentation Anti-Pattern (CRIT)

**CRITICAL:** Each documentation type must be clearly separated; avoid mixing types in a single document.

❌ Bad: Tutorial that includes API reference sections, how-to guide with conceptual explanations, reference material mixed with tutorial steps
✅ Good: Separate sections/files for each type, clear navigation between types, single purpose per document
⚠️ Why: Mixed types confuse users, reduce discoverability, violate single responsibility principle
🔧 Fix: Identify primary user need, structure accordingly, use separate sections/files, cross-reference when needed
📍 See: [Diátaxis Framework](https://diataxis.fr)

**Detect:** Mixed purposes in single doc, tutorial with reference material, how-to with explanations, unclear user need, multiple document types in one file

### Implementation Guidelines

1. **Identify user need** from request to determine appropriate type
2. **Keep types separate** - don't mix tutorials with reference material
3. **Match structure** to type (tutorials are narrative, reference is factual)
4. **Use appropriate language** - tutorials are friendly, reference is precise

---

## Strategic Documentation for Agents

**CRITICAL:** When explicitly requested, use `docs/` folders for subsystem documentation that agents should read before working on features.

❌ Bad: Creating docs without user request, documenting obvious code, no project documentation, context only in code comments, agents must read entire codebase
✅ Good: User-requested `docs/` structure for complex subsystems, using "read docs/feature-name.md" pattern, maintain `docs/` folder with subsystem/feature docs, use scripts to force model to read relevant docs, keep docs up-to-date
⚠️ Why: Strategic docs help agents understand complex systems; automatic docs waste effort; reduces context window usage, provides focused context, enables faster agent work on large projects
🔧 Fix: Only create `docs/` when user requests; structure for agent consumption; use clear filenames; use scripts/instructions to force models to read relevant docs for large projects; maintain docs in `docs/` folder
📍 See: `cursor-integration.mdc` section 1.2 (Context Loading)

**Detect:** Creating docs without user request, documenting obvious code, no docs/ structure, context only in code

**Pattern:** When user says "write docs to docs/*.md" or explicitly requests documentation, create appropriately named documentation file following Diátaxis framework.

**When explicitly requested to create documentation:**
- Use `docs/` folder as default location
- When user says "write docs to docs/*.md", let the model pick appropriate filename
- Structure documentation following Diátaxis framework (see above)
- Use scripts/instructions to force models to read relevant docs for large projects

**Detect:** Documentation in root, unclear naming, scattered docs, no clear structure, no docs folder, all context in code, agents reading entire codebase for simple tasks
