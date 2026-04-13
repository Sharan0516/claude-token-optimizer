#!/usr/bin/env bash
# restore.sh - Move all skills back from ~/.claude/skill-vault/ to ~/.claude/skills/
# and remove the skill router installation.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

SKILLS_DIR="${HOME}/.claude/skills"
VAULT_DIR="${HOME}/.claude/skill-vault"
ROUTER_SKILL_DIR="${SKILLS_DIR}/skill-router"

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Preflight ─────────────────────────────────────────────────────────────────

header "claude-token-optimizer: restore"

if [[ ! -d "${VAULT_DIR}" ]]; then
  info "No vault found at ${VAULT_DIR} - nothing to restore."
  exit 0
fi

# ── Move skills back ──────────────────────────────────────────────────────────

header "Restoring skills from vault..."

restored=0
skipped=0

for vault_skill_path in "${VAULT_DIR}"/*/; do
  vault_skill_path="${vault_skill_path%/}"
  [[ -d "${vault_skill_path}" ]] || continue
  skill_name="$(basename "${vault_skill_path}")"
  target="${SKILLS_DIR}/${skill_name}"

  if [[ -d "${target}" ]]; then
    warn "Conflict: ${skill_name} already exists in ~/.claude/skills/ - skipping"
    ((skipped++)) || true
    continue
  fi

  mv "${vault_skill_path}" "${target}"
  ok "Restored: ${skill_name}"
  ((restored++)) || true
done

# ── Remove router ─────────────────────────────────────────────────────────────

header "Removing skill router..."

if [[ -d "${ROUTER_SKILL_DIR}" ]]; then
  rm -rf "${ROUTER_SKILL_DIR}"
  ok "Removed: ${ROUTER_SKILL_DIR}"
else
  info "Router directory not found - nothing to remove"
fi

# ── Remove vault if empty ─────────────────────────────────────────────────────

remaining=$(ls -A "${VAULT_DIR}" 2>/dev/null | wc -l | tr -d ' ')

if [[ "${remaining}" -eq 0 ]]; then
  rmdir "${VAULT_DIR}"
  ok "Removed empty vault: ${VAULT_DIR}"
else
  warn "${remaining} item(s) remain in ${VAULT_DIR} - not removing"
  if [[ "${skipped}" -gt 0 ]]; then
    warn "Manually resolve conflicts above, then delete ${VAULT_DIR} when empty"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

header "Done."
echo ""
echo -e "  Skills restored:    ${GREEN}${restored}${RESET}"
echo -e "  Skipped (conflict): ${YELLOW}${skipped}${RESET}"
echo ""
echo -e "  ${BOLD}Restart Claude Code to apply changes.${RESET}"
echo ""
