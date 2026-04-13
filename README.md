# claude-skill-router

Stop Claude Code from reading thousands of words of skill descriptions on every conversation. Load skills on-demand, only when you need them.

## The Problem

Claude Code loads every skill in `~/.claude/skills/` into the system prompt at the start of each conversation. With 15+ skills installed, that means the model is parsing 10,000-50,000 words of instructions before you type a single character.

The result: instruction-dropping, hallucinations, and slower responses - because the model is already deep into its context window before the conversation begins.

**Before (15 skills loaded always):**
```
System prompt: ~12,000 tokens
Tokens available for actual work: ~188,000
Skills active right now: 15 (you'll use 1)
```

**After (skill-router pattern):**
```
System prompt: ~400 tokens
Tokens available for actual work: ~199,600
Skills active right now: 1 (loaded on-demand)
```

> Note: This only affects skills you install in `~/.claude/skills/`. Extension skills like `document-skills:*`, `example-skills:*`, and other namespace-prefixed skills are controlled by their respective extensions and are not affected.

## How It Works

Three steps on every turn:

1. **You talk** - Claude reads your message normally
2. **Router matches** - one lightweight skill (400 tokens) scans a compact catalog table to see if your intent matches any skill trigger
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

## Why This Works

Claude Code's context window is shared between:
- The system prompt (all skills, CLAUDE.md, memory files)
- The conversation history
- Your actual task content

Skills are verbose by design - they contain step-by-step instructions, examples, and edge cases. A typical skill runs 500-3,000 tokens. With 20 skills, that is 10,000-60,000 tokens sitting in the system prompt on every turn, even when you are asking about something completely unrelated.

The router replaces all of that with a single ~400-token catalog. The full skill content only enters context when it is actually needed, and it enters as a tool call result - not as part of the permanent system prompt overhead.

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

## Before / After Comparison

| | Before | After |
|---|---|---|
| System prompt tokens | ~12,000-50,000 | ~400 |
| Skills loaded per turn | All of them | 0 or 1 |
| Skills available | All installed | All installed |
| Latency impact | High (parse everything) | Minimal (one catalog read) |
| Instruction-dropping risk | High with 15+ skills | Near zero |

The skills are not deleted. They are not disabled. They are simply not loaded until you need them.

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
