#!/usr/bin/env bash
# memory-router.sh - Compact MEMORY.md files to prevent bulk loading of memory entries
# Transforms linked format ([Title](file.md)) to inline catalog (no links = no auto-load)
# Safe to run multiple times (idempotent)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PROJECTS_DIR="${HOME}/.claude/projects"

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Extract frontmatter field from a memory .md file ─────────────────────────

extract_frontmatter_field() {
  local file="$1"
  local field="$2"
  # Only read the first 30 lines to find frontmatter
  head -30 "$file" 2>/dev/null \
    | awk -v field="$field" '
        /^---/ { if (NR==1) { in_fm=1; next } else { in_fm=0 } }
        in_fm && $0 ~ "^"field":" {
          sub("^"field":[[:space:]]*", "")
          # Strip surrounding quotes if present
          gsub(/^["'"'"']|["'"'"']$/, "")
          print
          exit
        }
      ' \
    || true
}

# ── Parse a single markdown link entry and compact it ─────────────────────────
# Input line formats:
#   - [Title](file.md) - description text
#   - [Title](file.md) — description text    (em dash variant)
#   - **Bold text**: description
#   - plain text
#
# Returns compacted line (no markdown link)

compact_entry() {
  local line="$1"
  local memory_dir="$2"

  # Check if line has a markdown link pattern: [Title](file.md)
  if echo "$line" | grep -qE '^[[:space:]]*-[[:space:]]*\[.+\]\(.+\.md\)'; then
    # Extract the linked filename
    local linked_file
    linked_file=$(echo "$line" | sed -E 's/.*\[.*\]\(([^)]+)\).*/\1/')

    # Extract the display title
    local title
    title=$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*\[([^]]+)\].*/\1/')

    # Extract the description (text after ) - or ) --)
    local description
    description=$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*\[[^]]+\]\([^)]+\)[[:space:]]*[-—][[:space:]]*//')

    # Resolve the file path
    local file_path=""
    local entry_type="unknown"

    # Handle relative paths that go up directories (e.g. ../../../claude-outputs/...)
    if echo "$linked_file" | grep -qE '^\.\./'; then
      # Cross-directory reference -- can't easily resolve type, use description only
      file_path=""
      entry_type="reference"
    else
      file_path="${memory_dir}/${linked_file}"
    fi

    # Try to get type from frontmatter
    if [[ -n "$file_path" && -f "$file_path" ]]; then
      local fm_type
      fm_type=$(extract_frontmatter_field "$file_path" "type")
      if [[ -n "$fm_type" ]]; then
        entry_type="$fm_type"
      fi

      # If description is empty (just a link with no text after), get it from frontmatter
      if [[ -z "$description" || "$description" == "$title" ]]; then
        local fm_desc
        fm_desc=$(extract_frontmatter_field "$file_path" "description")
        if [[ -n "$fm_desc" ]]; then
          description="$fm_desc"
        fi
      fi
    fi

    # Output compact format: - Title -- description [type]
    echo "- ${title} -- ${description} [${entry_type}]"
  else
    # Not a markdown link -- preserve as-is
    echo "$line"
  fi
}

# ── Process a single MEMORY.md file ──────────────────────────────────────────

process_memory_file() {
  local memory_file="$1"
  local memory_dir
  memory_dir="$(dirname "$memory_file")"
  local dir_label
  dir_label="$(basename "$(dirname "$memory_dir")")/memory"

  header "Processing: ${dir_label}/MEMORY.md"

  # Check if already compacted (idempotent)
  if grep -q "MEMORY ROUTER:" "$memory_file" 2>/dev/null; then
    info "Already compacted -- skipping (run memory-restore.sh first to re-process)"
    return 0
  fi

  # Back up the original
  local backup_file="${memory_file}.backup"
  if [[ -f "$backup_file" ]]; then
    info "Backup already exists: $(basename "$backup_file")"
  else
    cp "$memory_file" "$backup_file"
    ok "Backed up to: $(basename "$backup_file")"
  fi

  # Count entries before compaction
  local link_count
  link_count=$(grep -cE '^[[:space:]]*-[[:space:]]*\[.+\]\(.+\.md\)' "$memory_file" 2>/dev/null || echo 0)

  # Build compacted content
  local output=""
  local in_header=0
  local current_section=""
  local entries_processed=0
  local entries_preserved=0

  # Write the router header comment
  output="<!-- MEMORY ROUTER: This is a compact index. Memory files are NOT linked to prevent
     bulk loading. To access a memory, read the file directly from this directory.
     Run \`memory-restore.sh\` to revert to the original linked format. -->
"

  # Process line by line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Section headers (## or #) -- pass through unchanged
    if echo "$line" | grep -qE '^#{1,3}\s'; then
      output="${output}
${line}"
      current_section="$line"
      continue
    fi

    # Empty lines -- pass through
    if [[ -z "$line" ]]; then
      output="${output}
"
      continue
    fi

    # HTML comments -- skip (don't include old router comments if re-running)
    if echo "$line" | grep -qE '^<!--'; then
      continue
    fi

    # Lines starting with - that contain a markdown link
    if echo "$line" | grep -qE '^[[:space:]]*-[[:space:]]*\[.+\]\(.+\.md\)'; then
      local compacted
      compacted=$(compact_entry "$line" "$memory_dir")
      output="${output}
${compacted}"
      ((entries_processed++)) || true
      continue
    fi

    # All other lines (plain bullet points, bold rules, backtick references) -- pass through
    output="${output}
${line}"
    ((entries_preserved++)) || true
  done < "$memory_file"

  # Write the compacted file
  printf '%s\n' "$output" > "$memory_file"

  ok "Compacted: ${entries_processed} linked entries converted, ${entries_preserved} plain entries preserved"
  echo "$entries_processed"
}

# ── Main ──────────────────────────────────────────────────────────────────────

header "claude-token-optimizer: memory-router"
echo ""
echo -e "  Scans all memory directories under ${BOLD}${PROJECTS_DIR}${RESET}"
echo -e "  Compacts MEMORY.md files to prevent bulk loading of linked memory files"
echo ""

if [[ ! -d "$PROJECTS_DIR" ]]; then
  error "Projects directory not found: ${PROJECTS_DIR}"
  exit 1
fi

total_dirs=0
total_converted=0
total_skipped=0

for memory_dir in "${PROJECTS_DIR}"/*/memory/; do
  # Strip trailing slash
  memory_dir="${memory_dir%/}"
  [[ -d "$memory_dir" ]] || continue

  memory_file="${memory_dir}/MEMORY.md"

  if [[ ! -f "$memory_file" ]]; then
    info "No MEMORY.md in $(basename "$(dirname "$memory_dir")")/memory/ -- skipping"
    ((total_skipped++)) || true
    continue
  fi

  ((total_dirs++)) || true

  result=$(process_memory_file "$memory_file" 2>&1)
  echo "$result"

  # Count converted entries from the last numeric line in output
  converted=$(echo "$result" | grep -oE '^[0-9]+$' | tail -1 || echo 0)
  total_converted=$((total_converted + converted))
done

# ── Token estimate ─────────────────────────────────────────────────────────────

header "Done."
echo ""
echo -e "  Memory directories processed: ${GREEN}${total_dirs}${RESET}"
echo -e "  Directories skipped:          ${YELLOW}${total_skipped}${RESET}"
echo -e "  Linked entries compacted:     ${BOLD}${total_converted}${RESET}"
echo ""

if [[ "$total_converted" -gt 0 ]]; then
  # Rough token estimates: each linked file averages ~400 tokens when loaded
  # Compact index entry averages ~15 tokens
  est_before=$(( total_converted * 400 ))
  est_after=$(( total_converted * 15 ))
  est_saved=$(( est_before - est_after ))
  echo -e "  Estimated token reduction (memory files no longer auto-loaded):"
  echo -e "    Before: ~${est_before} tokens  (${total_converted} files x ~400 tokens avg)"
  echo -e "    After:  ~${est_after} tokens   (inline descriptions only)"
  echo -e "    ${GREEN}Saved:  ~${est_saved} tokens per conversation${RESET}"
  echo ""
  echo -e "  Memory files remain on disk. Claude reads them on-demand when relevant."
  echo -e "  Run ${BOLD}./memory-restore.sh${RESET} to revert to the original linked format."
fi

echo ""
echo -e "  ${BOLD}Restart Claude Code to apply changes.${RESET}"
echo ""
