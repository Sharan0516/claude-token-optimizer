---
name: prompt-audit
version: "1.0"
description: >-
  Audit and optimize Claude Code system prompt overhead. Scans skills,
  CLAUDE.md files, memory files, MCP servers, and context store to identify
  token bloat, weak memory pointers, stale entries, and conflicting instructions.
  Runs a 3-phase guided workflow: token audit, memory quality audit, and
  prioritized recommendations. Always presents findings before fixing anything.
  Use when the user says "audit system prompt", "prompt audit", "check system
  prompt", "why is claude slow", "audit memory", "memory quality check",
  "optimize claude code", or asks about system prompt size or overhead.
---

# prompt-audit

> **Version:** 1.0 | **Created:** 2026-04-13
> **Changelog:** See [Changelog](#changelog) at end of file.
> **Dependency:** `audit.py` must live alongside this SKILL.md in the same vault directory.

## Philosophy

System prompt bloat is a performance and quality problem. Every token loaded into
context on every turn competes with the user's actual work. This skill makes the
overhead visible, classifies its quality, and offers targeted fixes -- without
auto-applying anything the user hasn't approved.

**Core principles:**
1. **Review, don't fix.** Present findings first. Offer to fix. Never auto-apply.
2. **Show the math.** Token counts, percentages, and verdicts make the cost concrete.
3. **Classify, don't lecture.** Use the standard taxonomy (SELF-CONTAINED, GOOD POINTER,
   WEAK POINTER, STALE, CONFLICTING) consistently so findings are scannable.
4. **Batch the asks.** Present all recommendations at once, let the user pick which to apply.
5. **Memory one-liners only.** Auto-apply only applies to WEAK POINTER rewrites.
   Never delete files, never rewrite CLAUDE.md sections without confirmation.

---

## Phase 1 -- Token Audit

Run the audit script from the skill's vault directory:

```
python3 ~/.claude/skill-vault/prompt-audit/audit.py
```

The script scans and reports tokens for each component:

| Component | What it scans |
|-----------|---------------|
| Skills (active) | `~/.claude/skills/` -- each loaded SKILL.md description block |
| Skill Router | Checks if skill-router is installed; estimates savings if not |
| CLAUDE.md (global) | `~/.claude/CLAUDE.md` -- full token count |
| CLAUDE.md (project) | `~/.claude/projects/*/CLAUDE.md` -- per-project files |
| Memory files | All `~/.claude/projects/*/memory/MEMORY.md` files |
| MCP servers | Parsed from `settings.json` and `settings.local.json` |
| Context store | `~/.claude/context/` -- on-demand reference, not always loaded |

**Verdict thresholds:**

| Tokens | Verdict |
|--------|---------|
| < 5,000 | Healthy |
| 5,001 -- 10,000 | Moderate |
| 10,001 -- 15,000 | Heavy |
| > 15,000 | Critical |

Display the full breakdown table with per-component token counts and percentages,
then print the verdict with a one-line interpretation. Stop and present Phase 1
results before starting Phase 2.

---

## Phase 2 -- Memory Quality Audit

For each MEMORY.md found during Phase 1, scan every bullet-point entry and
classify it using the taxonomy below. Use the entry text to determine the rating
-- do not read linked files unless necessary to disambiguate.

### Memory Entry Taxonomy

**SELF-CONTAINED**
The bullet IS the full instruction. Claude can act on it without reading any file.
Example: `No em dashes -- Never use em dashes in outreach drafts.`
No action needed.

**GOOD POINTER**
The bullet links to or references a file AND includes a clear trigger that tells
Claude when to load it.
Pattern: `[Title](file.md) -- READ before/when [specific trigger].`
Example: `[GTM Pipeline](gtm-pipeline.md) -- READ before drafting any outreach sequence.`
No action needed.

**WEAK POINTER**
The bullet references a file but lacks a trigger. Claude cannot tell when to read it.
The description alone does not tell Claude when the file is relevant.
Example: `[Philips CPQ Project](project_philips_cpq.md) - Contract pricing POC for Philips...`
Action: Add "READ before/when [trigger]" prefix.

**STALE**
Contains a date that is more than 30 days old (relative to today's date) AND
a status word suggesting unfinished work: "pending", "needed", "planned",
"to do", "in progress", "draft", "wip", "tbd".
Action: Flag for review or archive.

**CONFLICTING**
The same topic appears in multiple MEMORY.md files (across different projects)
with different values or contradictory instructions.
Action: Flag both entries; ask user which to keep.

### Phase 2 Output Format

Present a table for each MEMORY.md file found:

```
File: ~/.claude/projects/<project>/memory/MEMORY.md
---
| Entry (truncated to 80 chars) | Rating | Suggested Fix |
|-------------------------------|--------|---------------|
| No em dashes -- Never use...  | SELF-CONTAINED | -- |
| [GTM Pipeline](gtm-pipeline.md) -- READ before... | GOOD POINTER | -- |
| [Philips CPQ Project](proj...) -- Contract pricing POC | WEAK POINTER | Add: "READ before discussing Philips, CPQ, or contract pricing POC" |
| [East Coast trip -- pending hotel bookings] (2025-12-01) | STALE | Review or archive -- status word "pending" with date >30 days old |
```

After all tables, print a summary count:
- X SELF-CONTAINED entries
- X GOOD POINTER entries
- X WEAK POINTER entries (need trigger rewrites)
- X STALE entries (need review)
- X CONFLICTING entries (need resolution)

---

## Phase 3 -- Recommendations

Generate a prioritized numbered list based on Phase 1 and Phase 2 findings.
Present ALL recommendations before asking anything.

**Recommendation priority order:**

1. **Skill-router not installed** (if detected)
   - State the estimated savings (skill descriptions loaded per-turn without router vs.
     loaded on-demand with router).
   - Recommend running `migrate.sh` from the skill-router repo.

2. **Memory files are >50% of total overhead**
   - Recommend running `memory-router.sh` to compact MEMORY.md files.
   - Show estimated before/after token savings using the script's own estimates
     (~400 tokens per linked file, ~15 tokens per compacted entry).

3. **WEAK POINTER rewrites** (one per finding, show before/after)
   ```
   Before: [East & West Coast Trip](project_east_west_coast_trip.md) - 19-contact trip plan...
   After:  [East & West Coast Trip](project_east_west_coast_trip.md) -- READ before planning travel,
           scheduling Bay Area / Boston / NYC meetings, or discussing the April 2026 trip.
   ```

4. **STALE entries to review** -- list each with its date and status word.

5. **CONFLICTING entries to resolve** -- list both entries and their locations.

6. **CLAUDE.md is >3,000 tokens**
   - Suggest splitting global CLAUDE.md: move project-specific rules to project-level
     `CLAUDE.md` files so they only load in that project's context.

7. **MCP servers >5**
   - List all connected servers by name.
   - Suggest disconnecting any not used in the past 30 days.

### After Presenting Recommendations

Ask:

> "Which of these would you like me to apply? I can:
> - (A) Rewrite all WEAK POINTER entries (shows before/after for each, applies on approval)
> - (B) Walk through STALE entries one by one
> - (C) Show CONFLICTING entries side-by-side for resolution
> - (D) Show the memory-router.sh command to run
> - Or tell me a specific number from the list above."

---

## Applying Fixes

### Memory WEAK POINTER rewrites

For each WEAK POINTER the user approves:
1. Show the exact before/after diff for the entry line.
2. Ask: "Apply this rewrite? (yes / skip / edit)"
3. On yes: use Edit tool to make the change in-place.
4. On edit: accept the user's revised trigger text, show the new after, then apply.
5. Never rewrite multiple entries in one Edit call -- one entry per confirmation.

### Stale entry review

For each STALE entry:
1. Show the full entry text and the file it lives in.
2. Ask: "Archive this entry, keep it, or update the status?"
3. On archive: comment it out (prefix with `<!-- ARCHIVED: -->`) rather than deleting.
4. On keep: leave as-is.
5. On update: accept new text from user and apply with Edit.

### Conflicting entry resolution

For each CONFLICTING pair:
1. Show both entries side-by-side with their file paths.
2. Ask: "Which version is correct? Or provide the text you want to keep."
3. On choice: update the winning file (or both if the user provides new text),
   then comment out the losing entry with `<!-- SUPERSEDED BY: [file] -->`.

---

## Rules

- Never auto-fix without showing the user what will change and getting explicit approval.
- Present all findings first, then offer fixes -- never interleave discovery and patching.
- Use the SELF-CONTAINED / GOOD POINTER / WEAK POINTER / STALE / CONFLICTING taxonomy only.
  Do not invent new rating labels.
- For memory one-liner rewrites: show before/after for every entry before applying any of them.
- Never delete memory files or CLAUDE.md sections -- only rewrite inline or comment out.
- The audit.py script must exist at `~/.claude/skill-vault/prompt-audit/audit.py`.
  If missing, say: "audit.py is missing from the vault directory. Copy it from
  ~/claude-skill-router/audit.py first, then re-run the skill."
- Token counts are estimates (1 token ~ 4 chars). Treat them as directional, not exact.
- Dates for STALE detection are relative to today's date (available via system-reminder).

---

## Changelog

### 1.0 -- 2026-04-13
- Initial version: 3-phase audit workflow (token audit, memory quality, recommendations)
- Taxonomy: SELF-CONTAINED, GOOD POINTER, WEAK POINTER, STALE, CONFLICTING
- Supports audit.py for token scanning and memory-router.sh for bulk compaction
