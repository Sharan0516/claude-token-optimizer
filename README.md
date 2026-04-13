# claude-token-optimizer

Audit and reduce Claude Code's system prompt token overhead. Optimizes skills, memory files, and gives you visibility into everything consuming your context window.

## The Problem

The more you build on top of Claude Code, the more tokens load into the system prompt on every conversation. Skills, CLAUDE.md instructions, memory files, MCP plugin registrations, deferred tool lists -- all of it gets packed in before you type a single character.

With a heavily customized setup (20+ skills, detailed CLAUDE.md, dozens of memory files, multiple MCP servers), the system prompt can reach 15,000-45,000+ tokens. At some point, the model starts competing with its own instructions: dropping rules, hallucinating details, producing less precise output.

It's not the model getting worse. It's what you're loading into it.

**Real results from a 35-skill, 76-memory-file setup:**

```
BEFORE                                    AFTER
Skills:   ~1,500 tokens (35 loaded)       Skills:   ~200 tokens (1 router catalog)
Memory:  ~42,000 tokens (76 files)        Memory:  ~900 tokens (6 compact indexes)
CLAUDE.md: ~2,200 tokens                  CLAUDE.md: ~2,200 tokens (unchanged)
─────────────────────────────             ─────────────────────────────
Total:   ~46,000 tokens                   Total:   ~3,300 tokens

                                          81% reduction. Same capabilities.
```

## What's Inside

This repo gives you three tools that work independently or together:

| Tool | What it does | Command |
|---|---|---|
| **Audit** | Scan your full system prompt overhead with a breakdown by source | `python3 audit.py` |
| **Skill Router** | Move skills to a vault, load on-demand via a lightweight catalog | `./migrate.sh` |
| **Memory Router** | Compact MEMORY.md indexes to prevent bulk file loading | `./memory-router.sh` |

Start with the audit to see where your tokens are going. Then apply whichever optimizations make sense.

## Quick Start

```bash
git clone https://github.com/sharan0516/claude-token-optimizer.git
cd claude-token-optimizer

# 1. See where your tokens are going
python3 audit.py

# 2. Optimize skills (moves to vault, installs router)
./migrate.sh

# 3. Optimize memory (compacts MEMORY.md indexes)
./memory-router.sh

# 4. See the improvement
python3 audit.py
```

Restart Claude Code after running the optimizers. Changes take effect on the next session.

## Audit

The audit script scans five sources of system prompt overhead and produces a colored terminal report:

```bash
python3 audit.py            # terminal report
python3 audit.py --json     # machine-readable JSON
python3 audit.py --path .   # check project-level CLAUDE.md from specific directory
```

It shows:
- Token breakdown by category (skills, CLAUDE.md, memory, MCP servers, context store)
- Verdict: Healthy / Moderate / Heavy / Critical
- Savings summary if optimizations are already applied (before vs. after)
- Potential savings if optimizations are not yet applied
- Prioritized recommendations

The audit detects whether the skill-router and memory-router are active and adjusts its calculations accordingly.

## Skill Router

Claude Code loads a description of every skill in `~/.claude/skills/` into the system prompt. The skill router replaces all those descriptions with one lightweight catalog (~200 tokens). Skills move to `~/.claude/skill-vault/` and load on-demand only when your intent matches a trigger.

```bash
./migrate.sh      # move skills to vault, install router
./restore.sh      # undo everything, move skills back
./add-skill.sh ~/.claude/skills/my-new-skill   # add a new skill to the vault
```

### How the router works

1. **You talk** -- Claude reads your message normally
2. **Router matches** -- one small skill scans a catalog table for trigger keywords
3. **Skill loads** -- if matched, the full SKILL.md is read from the vault and executed. If no match, Claude proceeds normally.

The catalog is a markdown table inside the router's SKILL.md:

```
| Skill         | Triggers                                    | Vault Path                          |
|---------------|---------------------------------------------|-------------------------------------|
| meeting-prep  | prep for meeting, meeting briefing          | ~/.claude/skill-vault/meeting-prep/ |
| legal         | review contract, legal review, draft NDA    | ~/.claude/skill-vault/legal/        |
```

Match is generous -- "get me ready for my call with Acme" triggers `meeting-prep` without exact keyword match.

> Note: This only affects skills you install in `~/.claude/skills/`. Extension skills like `document-skills:*`, `example-skills:*`, and other namespace-prefixed skills are controlled by their respective extensions.

## Memory Router

Memory files are typically the biggest source of system prompt overhead. Claude Code loads `MEMORY.md` and follows every markdown link in it, pulling each referenced `.md` file into the system prompt. With many projects and memory files, this can be 30,000-40,000+ tokens.

The memory router compacts each `MEMORY.md` by removing markdown links. Without links, Claude Code loads only the compact index -- not the individual files. Memory files stay on disk and are read on-demand when relevant.

```bash
./memory-router.sh      # compact all MEMORY.md files
./memory-restore.sh     # restore from backups
```

### Before and after

**Before (linked format -- triggers auto-loading):**
```
## Feedback
- [No em dashes](feedback_no_em_dashes.md) - Never use em dashes in written content
- [Output location](feedback_output_location.md) - All files go to ~/claude-outputs/
```

**After (compact catalog -- no auto-loading):**
```
## Feedback
- No em dashes -- Never use em dashes in written content. Signals LLM text. [feedback]
- Output location -- All files go to ~/claude-outputs/ with subfolders by type [feedback]
```

Each entry keeps the title and description. The `[type]` tag comes from the file's frontmatter. No information is lost -- it's just not linked, so Claude Code doesn't follow the reference automatically.

### Writing good one-liners

After compacting, the quality of your one-line descriptions matters. Two patterns:

**Self-contained** (the one-liner IS the instruction):
```
- No em dashes -- Never use em dashes in outreach or emails. Signals LLM text. [feedback]
```

**Pointer with trigger** (tells Claude when to read the full file):
```
- Gmail automation -- READ before any Playwright Gmail compose operation [reference]
```

Weak one-liners like "Voice profile -- posting preferences [user]" won't trigger Claude to read the file when it should. Add a "READ before/when [specific action]" prefix for reference-type entries.

## Prompt Audit Skill

The repo includes a Claude Code skill for interactive auditing. If you use the skill-router, add it to your vault:

```bash
cp -r prompt-audit ~/.claude/skill-vault/prompt-audit
```

Then add to your router catalog:
```
| prompt-audit | audit system prompt, prompt audit, why is claude slow, memory quality | ~/.claude/skill-vault/prompt-audit/ |
```

Triggers: "audit my system prompt", "why is Claude slow", "check memory quality"

The skill runs three phases: token audit, memory quality classification (self-contained / good pointer / weak pointer / stale / conflicting), and prioritized recommendations.

## The Bigger Picture

| Source | What loads | Optimization |
|---|---|---|
| Skills | Description of every installed skill | `migrate.sh` -- skill router |
| Memory files | All files linked from MEMORY.md | `memory-router.sh` -- compact indexes |
| CLAUDE.md | Full file, every turn | Split into project-level files |
| MCP plugins | Tool registrations for every server | Disconnect unused servers |
| Deferred tools | Name listing of all deferred tools | Managed by extensions |

The principle is the same everywhere: **keep the always-loaded footprint small, pull details on demand.**

## Repository Structure

```
claude-token-optimizer/
  audit.py                Audit script -- scan system prompt token usage
  migrate.sh              Move skills to vault, install skill-router
  restore.sh              Move skills back, remove skill-router
  add-skill.sh            Add a single skill to the vault
  memory-router.sh        Compact MEMORY.md files
  memory-restore.sh       Restore MEMORY.md files from backups
  skill-router/
    SKILL.md              Template router skill
  prompt-audit/
    SKILL.md              Audit skill (for use via skill-router)
    audit.py              Audit script (copy, also at repo root)
  LICENSE
```

## License

MIT. See [LICENSE](LICENSE).
