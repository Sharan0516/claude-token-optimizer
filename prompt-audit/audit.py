#!/usr/bin/env python3
# Claude Code System Prompt Audit
# Run: python3 audit.py [--json] [--path /path/to/project]
# Make executable: chmod +x audit.py

import os
import sys
import json
import re
import argparse
from pathlib import Path
from collections import defaultdict

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CHARS_PER_TOKEN = 4  # 1 token ~ 4 chars (Claude tokenizer approximation)

CLAUDE_DIR = Path.home() / ".claude"
SKILLS_DIR = CLAUDE_DIR / "skills"
SKILL_VAULT_DIR = CLAUDE_DIR / "skill-vault"
PROJECTS_DIR = CLAUDE_DIR / "projects"
CONTEXT_DIR = CLAUDE_DIR / "context"
SETTINGS_FILES = [
    CLAUDE_DIR / "settings.json",
    CLAUDE_DIR / "settings.local.json",
]

# Token thresholds for color coding
THRESHOLD_GREEN = 3000
THRESHOLD_YELLOW = 8000

# System prompt verdict thresholds
VERDICT_HEALTHY = 5000
VERDICT_MODERATE = 10000
VERDICT_HEAVY = 15000

# ---------------------------------------------------------------------------
# Terminal colors
# ---------------------------------------------------------------------------

class Colors:
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    RED     = "\033[91m"
    YELLOW  = "\033[93m"
    GREEN   = "\033[92m"
    CYAN    = "\033[96m"
    WHITE   = "\033[97m"
    DIM     = "\033[2m"

def colorize(text, color):
    if not sys.stdout.isatty():
        return text
    return f"{color}{text}{Colors.RESET}"

def token_color(tokens):
    if tokens < THRESHOLD_GREEN:
        return Colors.GREEN
    if tokens < THRESHOLD_YELLOW:
        return Colors.YELLOW
    return Colors.RED

# ---------------------------------------------------------------------------
# Token estimation
# ---------------------------------------------------------------------------

def estimate_tokens(text):
    if not text:
        return 0
    return max(1, len(text) // CHARS_PER_TOKEN)

def file_tokens(path):
    try:
        content = Path(path).read_text(encoding="utf-8", errors="replace")
        return estimate_tokens(content), content
    except (OSError, PermissionError):
        return 0, ""

# ---------------------------------------------------------------------------
# Section 1: Skills
# ---------------------------------------------------------------------------

def extract_skill_description(skill_md_path):
    """Extract the YAML frontmatter description or the first non-empty paragraph."""
    try:
        content = Path(skill_md_path).read_text(encoding="utf-8", errors="replace")
    except (OSError, PermissionError):
        return ""

    # Try YAML frontmatter first
    if content.startswith("---"):
        end = content.find("---", 3)
        if end != -1:
            frontmatter = content[3:end]
            # Multi-line description: grab everything after "description: >" or "description: >-"
            m = re.search(r'description:\s*>[-|]?\s*\n((?:[ \t]+.+\n?)+)', frontmatter)
            if m:
                lines = m.group(1).strip().splitlines()
                return " ".join(l.strip() for l in lines if l.strip())
            # Single-line description
            m = re.search(r'description:\s*["\']?(.+?)["\']?\s*$', frontmatter, re.MULTILINE)
            if m:
                return m.group(1).strip()

    # Fallback: first meaningful paragraph after any frontmatter
    body = re.sub(r'^---.*?---\s*', '', content, flags=re.DOTALL)
    for line in body.splitlines():
        line = line.strip()
        if line and not line.startswith('#') and not line.startswith('>'):
            return line[:200]

    return ""


def audit_skills():
    """
    Skills contribute to the system prompt in two ways:
    1. ~/.claude/skills/ subdirs with SKILL.md -> loaded as slash-command descriptions
    2. ~/.claude/skill-vault/ entries listed in skill-router catalog -> catalog rows only
       (full SKILL.md is loaded lazily on demand, not at session start)
    """
    results = []

    # --- Slash-command skills: ~/.claude/skills/**/SKILL.md ---
    slash_skills = []
    if SKILLS_DIR.exists():
        for entry in sorted(SKILLS_DIR.iterdir()):
            if entry.name.startswith('_') or entry.name.startswith('.'):
                continue
            if entry.is_dir():
                skill_md = entry / "SKILL.md"
                if skill_md.exists():
                    desc = extract_skill_description(skill_md)
                    tokens = estimate_tokens(desc) if desc else 10
                    slash_skills.append({
                        "name": entry.name,
                        "path": str(skill_md),
                        "description": desc[:120] if desc else "(no description)",
                        "tokens": tokens,
                        "source": "slash-command",
                    })

    # --- Skill-router catalog: one row per vault skill (~15 tokens each) ---
    # The catalog table in SKILL.md (skill-router) is what loads at session start,
    # not the full vault SKILL.md files. Count the catalog itself.
    router_md = SKILLS_DIR / "skill-router" / "SKILL.md"
    router_tokens = 0
    vault_skill_count = 0
    if router_md.exists():
        toks, content = file_tokens(router_md)
        router_tokens = toks
        # Count table rows = vault skills registered
        vault_skill_count = len(re.findall(r'^\|[^|]+\|[^|]+\|[^|]+\|', content, re.MULTILINE))

    results = slash_skills
    skill_router_entry = None
    if router_tokens:
        skill_router_entry = {
            "name": "skill-router (catalog)",
            "path": str(router_md),
            "description": f"Skill-router catalog with {vault_skill_count} vault skills",
            "tokens": router_tokens,
            "source": "slash-command",
        }
        # Remove skill-router from slash_skills if already added, re-add with detail
        results = [s for s in results if s["name"] != "skill-router"]
        if skill_router_entry:
            results.append(skill_router_entry)

    subtotal = sum(s["tokens"] for s in results)
    return {
        "items": results,
        "subtotal": subtotal,
        "count": len(results),
        "vault_skill_count": vault_skill_count,
    }


# ---------------------------------------------------------------------------
# Section 2: CLAUDE.md files
# ---------------------------------------------------------------------------

def audit_claude_md(project_path):
    results = []

    # Global CLAUDE.md
    global_md = CLAUDE_DIR / "CLAUDE.md"
    if global_md.exists():
        toks, _ = file_tokens(global_md)
        results.append({"path": str(global_md), "tokens": toks, "label": "~/.claude/CLAUDE.md"})

    # Project-level: scan cwd and up to 3 parent directories
    search_path = Path(project_path).resolve()
    visited = set()
    depth = 0
    while depth <= 3 and search_path not in visited:
        visited.add(search_path)
        candidate = search_path / "CLAUDE.md"
        if candidate.exists() and candidate != global_md:
            toks, _ = file_tokens(candidate)
            label = str(candidate).replace(str(Path.home()), "~")
            results.append({"path": str(candidate), "tokens": toks, "label": label})
        parent = search_path.parent
        if parent == search_path:
            break
        search_path = parent
        depth += 1

    subtotal = sum(r["tokens"] for r in results)
    return {"items": results, "subtotal": subtotal, "count": len(results)}


# ---------------------------------------------------------------------------
# Section 3: Memory files
# ---------------------------------------------------------------------------

def find_memory_dir():
    """
    Claude Code stores per-project memory in:
    ~/.claude/projects/<encoded-path>/memory/
    The current project's memory directory maps to the cwd path.
    We return ALL memory dirs found (they can all be loaded depending on context).
    """
    if not PROJECTS_DIR.exists():
        return []

    dirs = []
    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue
        mem_dir = project_dir / "memory"
        if mem_dir.exists() and mem_dir.is_dir():
            dirs.append(mem_dir)
    return dirs


def audit_memory():
    results = []
    memory_dirs = find_memory_dir()

    for mem_dir in memory_dirs:
        index_file = mem_dir / "MEMORY.md"
        if not index_file.exists():
            continue

        index_toks, index_content = file_tokens(index_file)
        label = str(index_file).replace(str(Path.home()), "~")
        results.append({
            "path": str(index_file),
            "label": label,
            "tokens": index_toks,
            "type": "index",
        })

        # Find referenced .md files in the same directory
        for f in sorted(mem_dir.iterdir()):
            if f.name == "MEMORY.md" or not f.name.endswith(".md") or f.name.startswith("_"):
                continue
            toks, _ = file_tokens(f)
            flabel = str(f).replace(str(Path.home()), "~")
            results.append({
                "path": str(f),
                "label": flabel,
                "tokens": toks,
                "type": "memory-file",
            })

    subtotal = sum(r["tokens"] for r in results)
    return {
        "items": results,
        "subtotal": subtotal,
        "count": len(results),
        "note": "estimate - memory loading behavior varies by session context",
    }


# ---------------------------------------------------------------------------
# Section 4: MCP servers
# ---------------------------------------------------------------------------

# Average tokens per tool description (name + description + parameters schema)
TOKENS_PER_TOOL = 75

def parse_mcp_servers():
    """Read MCP server registrations from all known config locations."""
    servers = {}

    config_paths = list(SETTINGS_FILES)
    # macOS Claude desktop config
    desktop_config = Path.home() / "Library" / "Application Support" / "Claude" / "claude_desktop_config.json"
    if desktop_config.exists():
        config_paths.append(desktop_config)

    for cfg_path in config_paths:
        if not cfg_path.exists():
            continue
        try:
            data = json.loads(cfg_path.read_text(encoding="utf-8", errors="replace"))
            for name, cfg in data.get("mcpServers", {}).items():
                if name not in servers:
                    servers[name] = {"config": cfg, "source": str(cfg_path)}
        except (json.JSONDecodeError, OSError, PermissionError):
            pass

    return servers


# Known tool counts for common MCP servers (used as fallback estimate)
KNOWN_TOOL_COUNTS = {
    "flywheel":             29,
    "playwright":           21,
    "computer-use":         24,
    "computer_use":         24,
    "computeruse":          24,
    "granola":              2,
    "plugin_apollo_apollo": 2,
    "apollo":               5,
    "github":               20,
    "slack":                15,
    "linear":               10,
    "notion":               12,
    "google-drive":         8,
    "filesystem":           7,
    "brave-search":         2,
    "puppeteer":            9,
    "fetch":                2,
}


def estimate_tool_count(server_name, config):
    """Best-effort tool count: exact if known, else heuristic."""
    name_lower = server_name.lower().replace("-", "_")
    for k, v in KNOWN_TOOL_COUNTS.items():
        if k.replace("-", "_") in name_lower or name_lower in k.replace("-", "_"):
            return v, "known"
    return 10, "estimated"  # conservative default


def audit_mcp():
    servers = parse_mcp_servers()
    results = []

    # Also check for a dynamic MCP state file written by Claude Code at runtime.
    # Claude Code v2.x stores the live MCP tool manifest in a session env file.
    session_env_dir = CLAUDE_DIR / "session-env"
    if session_env_dir.exists():
        for f in sorted(session_env_dir.iterdir()):
            if not f.is_file():
                continue
            try:
                env_data = json.loads(f.read_text(encoding="utf-8", errors="replace"))
                for name, cfg in env_data.get("mcpServers", {}).items():
                    if name not in servers:
                        servers[name] = {"config": cfg, "source": str(f)}
            except (json.JSONDecodeError, OSError, PermissionError, TypeError):
                pass

    for name, info in sorted(servers.items()):
        tool_count, confidence = estimate_tool_count(name, info.get("config", {}))
        tokens = tool_count * TOKENS_PER_TOOL
        results.append({
            "name": name,
            "tool_count": tool_count,
            "tokens": tokens,
            "confidence": confidence,
            "source": info.get("source", "unknown"),
        })

    subtotal = sum(r["tokens"] for r in results)
    total_tools = sum(r["tool_count"] for r in results)
    return {
        "items": results,
        "subtotal": subtotal,
        "count": len(results),
        "total_tools": total_tools,
        "note": f"~{TOKENS_PER_TOOL} tokens per tool (name + description + schema)",
    }


# ---------------------------------------------------------------------------
# Section 5: Context store
# ---------------------------------------------------------------------------

def audit_context_store():
    results = []

    if not CONTEXT_DIR.exists():
        return {"items": [], "subtotal": 0, "count": 0}

    # Only .md files at the top level (not subdirs, not lock files)
    md_files = sorted(f for f in CONTEXT_DIR.iterdir()
                      if f.is_file() and f.suffix == ".md" and not f.name.startswith("_"))

    # Private/system files (catalog, manifest, inbox) still count
    system_files = sorted(f for f in CONTEXT_DIR.iterdir()
                          if f.is_file() and f.suffix == ".md" and f.name.startswith("_"))

    all_files = system_files + md_files

    for f in all_files:
        toks, _ = file_tokens(f)
        label = str(f).replace(str(Path.home()), "~")
        results.append({
            "path": str(f),
            "label": label,
            "tokens": toks,
            "system": f.name.startswith("_"),
        })

    subtotal = sum(r["tokens"] for r in results)
    return {
        "items": results,
        "subtotal": subtotal,
        "count": len(results),
        "note": "context store files are read on-demand via tools, not bulk-loaded at session start",
    }


# ---------------------------------------------------------------------------
# Skill-router detection
# ---------------------------------------------------------------------------

def detect_skill_router():
    router_skill = SKILLS_DIR / "skill-router" / "SKILL.md"
    return router_skill.exists()


# ---------------------------------------------------------------------------
# Report formatting
# ---------------------------------------------------------------------------

def fmt_tokens(n):
    return f"~{n:,}"

def pct(part, total):
    if total == 0:
        return 0.0
    return (part / total) * 100

def verdict(total):
    if total < VERDICT_HEALTHY:
        return "Healthy", Colors.GREEN
    if total < VERDICT_MODERATE:
        return "Moderate", Colors.YELLOW
    if total < VERDICT_HEAVY:
        return "Heavy", Colors.YELLOW
    return "Critical", Colors.RED

def bar(value, max_value, width=20):
    if max_value == 0:
        return "[" + " " * width + "]"
    filled = int((value / max_value) * width)
    return "[" + "#" * filled + "-" * (width - filled) + "]"


def print_terminal_report(data):
    skills      = data["skills"]
    claude_mds  = data["claude_mds"]
    memory      = data["memory"]
    mcp         = data["mcp"]
    context     = data["context"]
    total       = data["total"]
    has_router  = data["has_skill_router"]

    verdict_label, verdict_color = verdict(total)
    max_subtotal = max(
        skills["subtotal"], claude_mds["subtotal"],
        memory["subtotal"], mcp["subtotal"], context["subtotal"],
        1,
    )

    # Header
    print()
    print(colorize("╔══════════════════════════════════════════════════════╗", Colors.CYAN))
    print(colorize("║      Claude Code System Prompt Audit                 ║", Colors.CYAN))
    print(colorize("╚══════════════════════════════════════════════════════╝", Colors.CYAN))
    print()

    verdict_str = colorize(f"  Verdict: {verdict_label}", verdict_color + Colors.BOLD)
    total_str   = colorize(f"  Total estimated tokens: {total:,}", Colors.WHITE + Colors.BOLD)
    print(verdict_str)
    print(total_str)
    router_status = colorize("installed", Colors.GREEN) if has_router else colorize("not found", Colors.YELLOW)
    print(f"  skill-router: {router_status}")
    print()

    divider = colorize("  " + "-" * 52, Colors.DIM)

    # --- SKILLS ---
    section_label = colorize("SKILLS  (~/.claude/skills/)", Colors.BOLD + Colors.WHITE)
    section_pct   = f"{pct(skills['subtotal'], total):.0f}%"
    print(f"  {section_label}  {colorize(section_pct, Colors.DIM)}")
    print(divider)
    for s in sorted(skills["items"], key=lambda x: -x["tokens"]):
        name_col  = s["name"][:28].ljust(30)
        tok_col   = fmt_tokens(s["tokens"]).rjust(10)
        color     = token_color(s["tokens"])
        print(f"    {colorize(name_col, Colors.WHITE)}{colorize(tok_col, color)}")
    print(divider)
    sub_color = token_color(skills["subtotal"])
    vault_note = f"  (skill-router catalog: {skills['vault_skill_count']} vault entries)" if skills.get("vault_skill_count") else ""
    print(f"  Subtotal: {colorize(fmt_tokens(skills['subtotal']), sub_color + Colors.BOLD)} tokens  ({skills['count']} slash-command skills){vault_note}")
    print()

    # --- CLAUDE.md ---
    section_label = colorize("CLAUDE.md FILES", Colors.BOLD + Colors.WHITE)
    section_pct   = f"{pct(claude_mds['subtotal'], total):.0f}%"
    print(f"  {section_label}  {colorize(section_pct, Colors.DIM)}")
    print(divider)
    for item in claude_mds["items"]:
        label_col = item["label"][:44].ljust(46)
        tok_col   = fmt_tokens(item["tokens"]).rjust(10)
        color     = token_color(item["tokens"])
        print(f"    {colorize(label_col, Colors.WHITE)}{colorize(tok_col, color)}")
    print(divider)
    sub_color = token_color(claude_mds["subtotal"])
    print(f"  Subtotal: {colorize(fmt_tokens(claude_mds['subtotal']), sub_color + Colors.BOLD)} tokens  ({claude_mds['count']} files, loaded in full)")
    print()

    # --- MEMORY ---
    section_label = colorize("MEMORY FILES", Colors.BOLD + Colors.WHITE)
    section_pct   = f"{pct(memory['subtotal'], total):.0f}%"
    print(f"  {section_label}  {colorize(section_pct, Colors.DIM)}")
    print(colorize(f"  Note: {memory['note']}", Colors.DIM))
    print(divider)
    # Show first 12 items, then summarize
    shown = memory["items"][:12]
    for item in shown:
        label_col = Path(item["label"]).name[:44].ljust(46)
        tok_col   = fmt_tokens(item["tokens"]).rjust(10)
        color     = token_color(item["tokens"])
        print(f"    {colorize(label_col, Colors.WHITE)}{colorize(tok_col, color)}")
    if len(memory["items"]) > 12:
        hidden = len(memory["items"]) - 12
        hidden_tokens = sum(i["tokens"] for i in memory["items"][12:])
        print(f"    {colorize(f'... {hidden} more files', Colors.DIM)}{colorize(fmt_tokens(hidden_tokens).rjust(10), Colors.DIM)}")
    print(divider)
    sub_color = token_color(memory["subtotal"])
    print(f"  Subtotal: {colorize(fmt_tokens(memory['subtotal']), sub_color + Colors.BOLD)} tokens  ({memory['count']} files, estimate)")
    print()

    # --- MCP SERVERS ---
    section_label = colorize("MCP SERVERS", Colors.BOLD + Colors.WHITE)
    section_pct   = f"{pct(mcp['subtotal'], total):.0f}%"
    print(f"  {section_label}  {colorize(section_pct, Colors.DIM)}")
    if mcp["note"]:
        print(colorize(f"  Note: {mcp['note']}", Colors.DIM))
    print(divider)
    if mcp["items"]:
        for item in sorted(mcp["items"], key=lambda x: -x["tokens"]):
            conf_mark = "" if item["confidence"] == "known" else " (est.)"
            name_col  = f"{item['name']} ({item['tool_count']} tools{conf_mark})"[:44].ljust(46)
            tok_col   = fmt_tokens(item["tokens"]).rjust(10)
            color     = token_color(item["tokens"])
            print(f"    {colorize(name_col, Colors.WHITE)}{colorize(tok_col, color)}")
    else:
        print(f"    {colorize('No MCP servers found in settings files', Colors.DIM)}")
    print(divider)
    sub_color = token_color(mcp["subtotal"])
    print(f"  Subtotal: {colorize(fmt_tokens(mcp['subtotal']), sub_color + Colors.BOLD)} tokens  ({mcp['count']} servers, {mcp['total_tools']} tools)")
    print()

    # --- CONTEXT STORE ---
    section_label = colorize("CONTEXT STORE  (~/.claude/context/)", Colors.BOLD + Colors.WHITE)
    print(f"  {section_label}  {colorize('(on-demand reads, not counted in total)', Colors.DIM)}")
    if context.get("note"):
        print(colorize(f"  Note: {context['note']}", Colors.DIM))
    print(divider)
    if context["items"]:
        # Show top 8 by size
        top = sorted(context["items"], key=lambda x: -x["tokens"])[:8]
        for item in top:
            label_col = Path(item["label"]).name[:44].ljust(46)
            tok_col   = fmt_tokens(item["tokens"]).rjust(10)
            color     = token_color(item["tokens"])
            print(f"    {colorize(label_col, Colors.WHITE)}{colorize(tok_col, color)}")
        if len(context["items"]) > 8:
            hidden = len(context["items"]) - 8
            hidden_tokens = sum(i["tokens"] for i in sorted(context["items"], key=lambda x: -x["tokens"])[8:])
            print(f"    {colorize(f'... {hidden} more files', Colors.DIM)}{colorize(fmt_tokens(hidden_tokens).rjust(10), Colors.DIM)}")
    else:
        print(f"    {colorize('No context store found', Colors.DIM)}")
    print(divider)
    sub_color = token_color(context["subtotal"])
    load_note = "(not bulk-loaded at session start)" if context["count"] > 0 else ""
    print(f"  Subtotal: {colorize(fmt_tokens(context['subtotal']), sub_color + Colors.BOLD)} tokens  ({context['count']} files)  {colorize(load_note, Colors.DIM)}")
    print()

    # --- TOTAL ---
    total_color = verdict_color
    print(colorize("  " + "=" * 52, Colors.CYAN))
    print(f"  {colorize('TOTAL ESTIMATED SYSTEM PROMPT:', Colors.BOLD + Colors.WHITE)}  "
          f"{colorize(fmt_tokens(total) + ' tokens', total_color + Colors.BOLD)}")
    print()

    # Breakdown bar chart (context store excluded from total, shown separately)
    categories = [
        ("CLAUDE.md",  claude_mds["subtotal"]),
        ("Memory",     memory["subtotal"]),
        ("MCP",        mcp["subtotal"]),
        ("Skills",     skills["subtotal"]),
    ]
    categories_sorted = sorted(categories, key=lambda x: -x[1])
    max_cat = max(toks for _, toks in categories_sorted) if categories_sorted else 1
    scale   = max(max_cat, total, 1)

    print(colorize("  BREAKDOWN BY CATEGORY  (of counted total)", Colors.BOLD))
    for label, toks in categories_sorted:
        b = bar(toks, scale, width=24)
        pct_str = f"{pct(toks, total):4.0f}%"
        label_col = label.ljust(14)
        print(f"    {colorize(label_col, Colors.WHITE)} {colorize(b, Colors.DIM)} {colorize(pct_str, Colors.DIM)}  {colorize(fmt_tokens(toks), token_color(toks))}")

    if context["count"] > 0:
        ctx_b = bar(context["subtotal"], max(scale, context["subtotal"]), width=24)
        print(f"    {colorize('Context store ', Colors.DIM)} {colorize(ctx_b, Colors.DIM)}  "
              f"{colorize(fmt_tokens(context['subtotal']), Colors.DIM)}"
              f"  {colorize('(on-demand, not in total)', Colors.DIM)}")
    print()

    # --- RECOMMENDATIONS ---
    recs = build_recommendations(data)
    if recs:
        print(colorize("  TOP RECOMMENDATIONS", Colors.BOLD + Colors.CYAN))
        print(divider)
        for i, rec in enumerate(recs, 1):
            icon = colorize(str(i) + ".", Colors.YELLOW)
            print(f"  {icon} {rec}")
        print()


def build_recommendations(data):
    skills     = data["skills"]
    claude_mds = data["claude_mds"]
    memory     = data["memory"]
    mcp        = data["mcp"]
    context    = data["context"]
    total      = data["total"]
    has_router = data["has_skill_router"]

    recs = []

    # Sort categories by token contribution
    categories = sorted([
        ("CLAUDE.md files", claude_mds["subtotal"], claude_mds),
        ("Memory files",    memory["subtotal"],     memory),
        ("MCP servers",     mcp["subtotal"],         mcp),
        ("Skills",          skills["subtotal"],      skills),
        ("Context store",   context["subtotal"],     context),
    ], key=lambda x: -x[1])

    for label, toks, cat in categories:
        p = pct(toks, total)
        if label == "CLAUDE.md files" and toks > 3000:
            recs.append(
                f"CLAUDE.md is your largest contributor ({p:.0f}%, {toks:,} tokens). "
                "Consider moving project-specific rules into project-level CLAUDE.md files "
                "to reduce per-session load."
            )
        elif label == "Memory files" and cat["count"] > 10:
            recs.append(
                f"{cat['count']} memory files loaded ({toks:,} tokens, {p:.0f}% of total). "
                "Prune stale feedback and project files to reduce context overhead."
            )
        elif label == "MCP servers" and cat["count"] > 0:
            recs.append(
                f"{cat['count']} MCP server(s) with {cat['total_tools']} total tools "
                f"({toks:,} tokens, {p:.0f}%). Disconnect servers you are not actively using."
            )
        elif label == "Skills" and cat["count"] > 5 and not has_router:
            recs.append(
                f"{cat['count']} slash-command skills registered ({toks:,} tokens). "
                "Install skill-router to lazy-load skill prompts only when triggered, "
                "reducing always-on overhead."
            )

    if has_router and skills.get("vault_skill_count", 0) > 15:
        recs.append(
            f"skill-router is installed with {skills['vault_skill_count']} vault skills. "
            "Good -- vault prompts are loaded on-demand. Keep the catalog rows concise "
            "to minimize the router's own footprint."
        )
    elif has_router:
        recs.append("skill-router is installed. Vault skill prompts load on-demand, not at session start.")

    if context["count"] > 0 and context["subtotal"] > 5000:
        recs.append(
            f"Context store has {context['count']} files ({context['subtotal']:,} tokens total). "
            "These are read on-demand, not bulk-loaded -- but large individual files can slow "
            "tool responses. Consider archiving stale entries."
        )

    if not recs:
        recs.append("System prompt load looks healthy. No major optimizations needed.")

    return recs[:5]


# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------

def print_json_report(data):
    output = {
        "total_tokens": data["total"],
        "verdict":      verdict(data["total"])[0],
        "has_skill_router": data["has_skill_router"],
        "skills": {
            "subtotal": data["skills"]["subtotal"],
            "count":    data["skills"]["count"],
            "vault_skill_count": data["skills"].get("vault_skill_count", 0),
            "items": data["skills"]["items"],
        },
        "claude_mds": {
            "subtotal": data["claude_mds"]["subtotal"],
            "count":    data["claude_mds"]["count"],
            "items":    data["claude_mds"]["items"],
        },
        "memory": {
            "subtotal": data["memory"]["subtotal"],
            "count":    data["memory"]["count"],
            "note":     data["memory"]["note"],
            "items":    data["memory"]["items"],
        },
        "mcp": {
            "subtotal":     data["mcp"]["subtotal"],
            "count":        data["mcp"]["count"],
            "total_tools":  data["mcp"]["total_tools"],
            "items":        data["mcp"]["items"],
        },
        "context_store": {
            "subtotal": data["context"]["subtotal"],
            "count":    data["context"]["count"],
            "note":     data["context"].get("note", ""),
            "items":    data["context"]["items"],
        },
        "recommendations": build_recommendations(data),
    }
    print(json.dumps(output, indent=2))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Audit Claude Code system prompt token usage."
    )
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument(
        "--path",
        default=os.getcwd(),
        help="Project directory to check for CLAUDE.md (default: cwd)",
    )
    args = parser.parse_args()

    skills     = audit_skills()
    claude_mds = audit_claude_md(args.path)
    memory     = audit_memory()
    mcp        = audit_mcp()
    context    = audit_context_store()

    total = (
        skills["subtotal"]
        + claude_mds["subtotal"]
        + memory["subtotal"]
        + mcp["subtotal"]
        # context store is NOT counted in total because it is not bulk-loaded at session start
    )

    data = {
        "skills":          skills,
        "claude_mds":      claude_mds,
        "memory":          memory,
        "mcp":             mcp,
        "context":         context,
        "total":           total,
        "has_skill_router": detect_skill_router(),
    }

    if args.json:
        print_json_report(data)
    else:
        print_terminal_report(data)


if __name__ == "__main__":
    main()
