# claude-skill-router

Reduce Claude Code's system prompt overhead by loading skills on-demand instead of all at once.

## The Problem

Claude Code loads a description of every skill in `~/.claude/skills/` into the system prompt at the start of each conversation. Each skill adds ~30-50 tokens of description. That's small individually, but it adds up alongside everything else in the system prompt: CLAUDE.md instructions, memory entries, MCP plugin registrations, deferred tool lists, and context store snapshots.

With a heavily customized setup (20+ skills, detailed CLAUDE.md, memory files, multiple MCP servers), the combined system prompt can reach 10,000-15,000+ tokens before you type a single character. The more you build on top of Claude Code, the more you load into every conversation, and at some point the model starts competing with its own instructions.

The result: instruction-dropping, less precise output, and the feeling that Claude got worse when really you just gave it too much to hold in its head at once.

**Before (35 skills registered):**
```
Skill descriptions in system prompt: ~1,500 tokens
Total system prompt (skills + CLAUDE.md + memory + plugins): ~10,000-15,000 tokens
Every skill loaded: yes, even the 34 you don't need right now
```

**After (skill-router pattern):**
```
Skill descriptions in system prompt: ~200 tokens (router catalog only)
Total system prompt: reduced by ~1,300 tokens
Skills available: all of them, loaded on-demand
```

The skill router is one piece of a larger principle: **load on-demand, not upfront.** The same approach can be applied to CLAUDE.md sections, memory files, and other sources of prompt overhead.

> Note: This only affects skills you install in `~/.claude/skills/`. Extension skills like `document-skills:*`, `example-skills:*`, and other namespace-prefixed skills are controlled by their respective extensions and are not affected.

## How It Works

Three steps on every turn:

1. **You talk** - Claude reads your message normally
2. **Router matches** - one lightweight skill scans a compact catalog table to see if your intent matches any skill trigger
3. **Skill loads** - if matched, the full skill SKILL.md is read from `~/.claude/skill-vault/` and executed; if not, Claude proceeds normally

The catalog is a simple markdown table stored inside the router's `SKILL.md`:

```
| Skill         | Triggers                                    | Vault Path                          |
|---------------|---------------------------------------------|-------------------------------------|
| meeting-prep  | prep for meeting, meeting briefing          | ~/.claude/skill-vault/meeting-prep/ |
| legal         | review contract, legal review, draft NDA    | ~/.claude/skill-vault/legal/        |
| brainstorm    | brainstorm, pressure-test, challenge this   | ~/.claude/skill-vault/brainstorm/   |
```

Match is generous - "get me ready for my call with Acme" triggers `meeting-prep` even without exact keyword match. For compound tasks, skills load sequentially.

## Why This Matters

Claude Code's context window is shared between:
- The system prompt (skills, CLAUDE.md, memory, plugins, tool registrations)
- The conversation history
- Your actual task content

Every token in the system prompt is a token the model processes on every turn. Skills are just one contributor, but they're the easiest to optimize because the pattern is straightforward: keep a lightweight index, load the full content only when needed.

This is the same principle behind lazy loading in software, database indexes, or any system where you separate the catalog from the content. You don't load every book in the library to find the one you need. You check the index first.

## Installation

```bash
git clone https://github.com/sharan0516/claude-skill-router.git
cd claude-skill-router
./migrate.sh
```

That is it. The script:
- Scans `~/.claude/skills/` for all installed skills
- Moves them to `~/.claude/skill-vault/`
- Generates a catalog table from the skills it found
- Installs the router's `SKILL.md` into `~/.claude/skills/skill-router/`

Restart Claude Code after running - the new system prompt takes effect on the next session.

## Uninstall

```bash
./restore.sh
```

Moves everything back from `~/.claude/skill-vault/` to `~/.claude/skills/` and removes the router.

## Adding New Skills

When you install a new skill that should be vaulted:

```bash
./add-skill.sh ~/.claude/skills/my-new-skill
```

This moves the skill to the vault and appends a new row to the router's catalog. If you need to customize the trigger keywords, edit `~/.claude/skills/skill-router/SKILL.md` directly after running the script.

To add a skill manually, just append a row to the catalog table in `~/.claude/skills/skill-router/SKILL.md`:

```markdown
| my-skill | trigger phrase one, trigger phrase two | ~/.claude/skill-vault/my-skill/ |
```

## The Bigger Picture

The skill router tackles one source of prompt overhead. If you're experiencing degraded performance with a heavily customized Claude Code setup, audit everything that loads into the system prompt:

| Source | What loads | Can you optimize it? |
|---|---|---|
| Skills (`~/.claude/skills/`) | Description of every skill | Yes - this repo |
| CLAUDE.md | All instructions, every turn | Split into project-level files |
| Memory files | All entries via MEMORY.md | Prune stale entries regularly |
| MCP plugins | Tool registrations for every connected server | Disconnect unused servers |
| Deferred tools | Name listing of all deferred tools | Managed by extensions |

The principle is the same everywhere: keep the always-loaded footprint small, pull details on demand.

## Repository Structure

```
claude-skill-router/
  README.md               This file
  skill-router/
    SKILL.md              Template router - copy to ~/.claude/skills/skill-router/
  migrate.sh              Move skills to vault, install router
  restore.sh              Move skills back, remove router
  add-skill.sh            Add a single new skill to the vault
  LICENSE
```

## License

MIT. See [LICENSE](LICENSE).
