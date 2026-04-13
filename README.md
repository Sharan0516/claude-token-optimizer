# claude-skill-router

Reduce Claude Code's system prompt overhead by loading skills on-demand instead of all at once, and compact memory indexes to prevent bulk loading of memory files.

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

## Memory Router

Memory files are a bigger source of system prompt overhead than skills. In a typical heavily-customized setup, the memory system can account for over 90% of system prompt overhead -- skills are only one piece.

Claude Code loads `MEMORY.md` and follows every markdown link in it, pulling each referenced `.md` file into the system prompt. With 6 project directories and 76 memory files totaling ~42,000 tokens, that is the dominant cost.

The memory router compacts each `MEMORY.md` by removing markdown links. Without links, Claude Code loads only the index -- not the files. The actual memory files stay on disk and are read on-demand when relevant to the current task.

### How it works

**Before (linked format -- triggers auto-loading):**
```
## Active Projects
- [Philips CPQ Project](project_philips_cpq.md) - Contract pricing POC for Philips, $75K/12-week MVP
- [East & West Coast Trip](project_east_west_coast_trip.md) - 19-contact trip plan: Bay Area, Boston, NYC
```

**After (compact catalog -- no auto-loading):**
```
## Active Projects
- Philips CPQ Project -- Contract pricing POC for Philips, $75K/12-week MVP [project]
- East & West Coast Trip -- 19-contact trip plan: Bay Area, Boston, NYC [project]
```

Each entry keeps the title and inline description. The `[type]` tag is read from the file's frontmatter. No information is lost -- it is just not linked, so Claude Code does not follow the reference automatically.

### Usage

```bash
# Compact all MEMORY.md files across all project directories
./memory-router.sh

# Restore originals from backups
./memory-restore.sh
```

The script:
- Finds all `~/.claude/projects/*/memory/MEMORY.md` files
- Backs each one up to `MEMORY.md.backup`
- Reads frontmatter from linked files to extract type tags
- Writes a compacted version with no markdown links
- Is idempotent: safe to run again, skips already-compacted files

Restart Claude Code after running to apply changes.

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

## Prompt Audit Skill

The repo includes a built-in audit skill that combines token analysis with memory quality checking. If you use the skill-router, it is automatically available via natural language:

- "audit my system prompt"
- "why is Claude slow"
- "check memory quality"

The audit runs three phases:

1. **Token Audit** -- scans skills, CLAUDE.md, memory files, MCP servers, and context store. Shows a breakdown with a Healthy/Moderate/Heavy/Critical verdict.
2. **Memory Quality Audit** -- classifies every MEMORY.md entry as SELF-CONTAINED, GOOD POINTER, WEAK POINTER, STALE, or CONFLICTING. Suggests fixes for weak entries.
3. **Recommendations** -- prioritized list of optimizations with estimated impact. Asks before applying any changes.

To install the audit skill into your vault:

```bash
cp -r prompt-audit ~/.claude/skill-vault/prompt-audit
```

Then add this row to your skill-router catalog:

```markdown
| prompt-audit | audit system prompt, prompt audit, why is claude slow, audit memory, memory quality | ~/.claude/skill-vault/prompt-audit/ |
```

The audit can also be run standalone without the skill-router:

```bash
python3 audit.py
python3 audit.py --json
python3 audit.py --path /path/to/project
```

## The Bigger Picture

The skill router tackles one source of prompt overhead. If you're experiencing degraded performance with a heavily customized Claude Code setup, audit everything that loads into the system prompt:

| Source | What loads | Can you optimize it? |
|---|---|---|
| Skills (`~/.claude/skills/`) | Description of every skill | Yes -- `migrate.sh` (this repo) |
| Memory files | All files linked from MEMORY.md | Yes -- `memory-router.sh` (this repo) |
| CLAUDE.md | All instructions, every turn | Split into project-level files |
| MCP plugins | Tool registrations for every connected server | Disconnect unused servers |
| Deferred tools | Name listing of all deferred tools | Managed by extensions |

The principle is the same everywhere: keep the always-loaded footprint small, pull details on demand.

## Repository Structure

```
claude-skill-router/
  README.md               This file
  skill-router/
    SKILL.md              Template router - copy to ~/.claude/skills/skill-router/
  prompt-audit/
    SKILL.md              Audit skill for token analysis + memory quality
    audit.py              Standalone audit script (also used by the skill)
  migrate.sh              Move skills to vault, install router
  restore.sh              Move skills back, remove router
  add-skill.sh            Add a single new skill to the vault
  memory-router.sh        Compact MEMORY.md files to prevent bulk loading
  memory-restore.sh       Restore MEMORY.md files from backups
  audit.py                Standalone audit script (same as prompt-audit/audit.py)
  LICENSE
```

## License

MIT. See [LICENSE](LICENSE).
