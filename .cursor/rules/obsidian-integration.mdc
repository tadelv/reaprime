---
description: "Obsidian CLI commands and plugin dev loop when user interacts with a vault"
globs: []
alwaysApply: false
---

# Obsidian integration

When the user asks to read, create, search, or manage vault content—or develop plugins/themes—use the Obsidian CLI. Requires **Obsidian to be open**. Authoritative command list: `obsidian help` — [CLI docs](https://help.obsidian.md/cli).

**Upstream skills (install, do not duplicate):** [obsidian-skills](https://github.com/kepano/obsidian-skills)

```bash
npx skills add https://github.com/kepano/obsidian-skills
```

Or copy skills into project `.cursor/skills/` per Cursor documentation.

## Targeting

| Parameter | Use |
|-----------|-----|
| `file=` | Wikilink-style name (no path/extension required) |
| `path=` | Exact path from vault root, e.g. `folder/note.md` |
| `vault=` | First arg to target a vault: `obsidian vault="My Vault" search query="x"` |
| `silent` | Flag: do not open files after command |
| `--copy` | Copy command output to clipboard |
| `total` | On list commands: return count only |

Default target: active file in most recently focused vault.

## Common commands

| Command | Description |
|---------|-------------|
| `obsidian read file="My Note"` | Read note content |
| `obsidian create name="New" content="# Hi" template="T" silent` | Create note |
| `obsidian append file="My Note" content="line"` | Append to note |
| `obsidian search query="term" limit=10` | Search vault |
| `obsidian daily:read` / `daily:append content="- [ ] task"` | Daily note |
| `obsidian property:set name="status" value="done" file="My Note"` | Frontmatter property |
| `obsidian backlinks file="My Note"` | Backlinks |
| `obsidian tasks daily todo` | Task queries |

Multiline CLI content: use `\n` for newline, `\t` for tab in `content=`.

## Plugin development loop

1. `obsidian plugin:reload id=my-plugin`
2. `obsidian dev:errors` — fix and repeat from step 1 if errors
3. `obsidian dev:screenshot path=screenshot.png` or `obsidian dev:dom selector=".workspace-leaf" text`
4. `obsidian dev:console level=error`

Also: `obsidian eval code="..."`, `obsidian dev:css selector="..." prop=...`, `obsidian dev:mobile on` — see `obsidian help`.

## Vault standards

For OFM, Bases, and Canvas anti-patterns when editing vault files, see `obsidian-vault-standards.mdc`.

❌ Bad: Claiming `obsidian create` succeeded without command output or with Obsidian closed
✅ Good: Run command; show output or "CLI verification pending"
📍 See: `general-llm-anti-patterns.mdc` sections 3.8, 3.9
