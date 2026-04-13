#!/usr/bin/env bash
# memory-restore.sh - Restore all MEMORY.md files from their .backup copies
# Reverts the compaction done by memory-router.sh

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

# ── Main ──────────────────────────────────────────────────────────────────────

header "claude-skill-router: memory-restore"

if [[ ! -d "$PROJECTS_DIR" ]]; then
  error "Projects directory not found: ${PROJECTS_DIR}"
  exit 1
fi

header "Restoring MEMORY.md files from backups..."

restored=0
skipped=0
no_backup=0

for memory_dir in "${PROJECTS_DIR}"/*/memory/; do
  memory_dir="${memory_dir%/}"
  [[ -d "$memory_dir" ]] || continue

  memory_file="${memory_dir}/MEMORY.md"
  backup_file="${memory_dir}/MEMORY.md.backup"
  dir_label="$(basename "$(dirname "$memory_dir")")/memory"

  if [[ ! -f "$backup_file" ]]; then
    info "No backup found: ${dir_label} -- skipping"
    ((no_backup++)) || true
    continue
  fi

  # Check if MEMORY.md is currently compacted
  if [[ -f "$memory_file" ]] && ! grep -q "MEMORY ROUTER:" "$memory_file" 2>/dev/null; then
    warn "MEMORY.md in ${dir_label} does not appear to be compacted -- restoring anyway"
  fi

  # Restore from backup
  cp "$backup_file" "$memory_file"
  rm "$backup_file"
  ok "Restored: ${dir_label}/MEMORY.md"
  ((restored++)) || true
done

# ── Summary ───────────────────────────────────────────────────────────────────

header "Done."
echo ""
echo -e "  Files restored:      ${GREEN}${restored}${RESET}"
echo -e "  No backup found:     ${YELLOW}${no_backup}${RESET}"
echo -e "  Skipped:             ${YELLOW}${skipped}${RESET}"
echo ""

if [[ "$restored" -gt 0 ]]; then
  echo -e "  MEMORY.md files are back to their original linked format."
  echo -e "  Backup files (.backup) have been removed."
fi

echo ""
echo -e "  ${BOLD}Restart Claude Code to apply changes.${RESET}"
echo ""
