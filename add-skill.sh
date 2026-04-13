#!/usr/bin/env bash
# add-skill.sh - Add a single skill to the vault and update the router catalog.
#
# Usage: ./add-skill.sh <path-to-skill-directory>
# Example: ./add-skill.sh ~/.claude/skills/my-new-skill

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

VAULT_DIR="${HOME}/.claude/skill-vault"
ROUTER_SKILL_DIR="${HOME}/.claude/skills/skill-router"
ROUTER_SKILL_MD="${ROUTER_SKILL_DIR}/SKILL.md"

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Extract trigger keywords from a SKILL.md ─────────────────────────────────

extract_triggers() {
  local skill_md="$1"
  local triggers=""

  # Try: frontmatter trigger/triggers field
  triggers=$(grep -i '^\s*triggers\?\s*:' "${skill_md}" 2>/dev/null \
    | head -1 \
    | sed 's/^[^:]*://;s/^[[:space:]]*//;s/[[:space:]]*$//' \
    || true)

  # Try: "Trigger when:" or "Use when:" lines
  if [[ -z "${triggers}" ]]; then
    triggers=$(grep -i 'trigger when\|use when\|TRIGGER when' "${skill_md}" 2>/dev/null \
      | head -1 \
      | sed 's/.*when[[:space:]]*:*[[:space:]]*//' \
      | sed 's/\*\*//g;s/^[[:space:]]*//;s/[[:space:]]*$//' \
      | cut -c1-120 \
      || true)
  fi

  if [[ -z "${triggers}" ]]; then
    local skill_name
    skill_name="$(basename "$(dirname "${skill_md}")")"
    triggers="${skill_name}"
  fi

  echo "${triggers}" | cut -c1-100
}

# ── Input validation ──────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  echo -e "${BOLD}Usage:${RESET} ./add-skill.sh <path-to-skill-directory>"
  echo ""
  echo "  Moves a skill directory to ~/.claude/skill-vault/ and adds it to the router catalog."
  echo ""
  echo -e "${BOLD}Examples:${RESET}"
  echo "  ./add-skill.sh ~/.claude/skills/my-new-skill"
  echo "  ./add-skill.sh /absolute/path/to/any-skill"
  exit 1
fi

skill_path="$(cd "${1}" 2>/dev/null && pwd || echo "")"

if [[ -z "${skill_path}" || ! -d "${skill_path}" ]]; then
  error "Directory not found: ${1}"
  exit 1
fi

skill_name="$(basename "${skill_path}")"
skill_md="${skill_path}/SKILL.md"

header "claude-token-optimizer: add-skill"
info "Skill: ${skill_name}"
info "Source: ${skill_path}"

# ── Validate skill ────────────────────────────────────────────────────────────

if [[ ! -f "${skill_md}" ]]; then
  error "No SKILL.md found in ${skill_path}"
  error "This does not look like a valid skill directory."
  exit 1
fi

if [[ "${skill_name}" == _* ]]; then
  error "Skill name starts with _ - reserved directory prefix. Aborting."
  exit 1
fi

if [[ "${skill_name}" == "skill-router" ]]; then
  error "Cannot vault the skill-router itself."
  exit 1
fi

# ── Check router is installed ─────────────────────────────────────────────────

if [[ ! -f "${ROUTER_SKILL_MD}" ]]; then
  error "Router not installed. Run ./migrate.sh first."
  exit 1
fi

# ── Create vault if needed ────────────────────────────────────────────────────

if [[ ! -d "${VAULT_DIR}" ]]; then
  mkdir -p "${VAULT_DIR}"
  ok "Created ${VAULT_DIR}"
fi

# ── Move skill to vault ───────────────────────────────────────────────────────

vault_target="${VAULT_DIR}/${skill_name}"

if [[ -d "${vault_target}" ]]; then
  warn "Skill already in vault: ${vault_target}"
  warn "Skipping move - will still update catalog entry."
else
  mv "${skill_path}" "${vault_target}"
  ok "Moved to vault: ${vault_target}"
fi

# ── Extract triggers ──────────────────────────────────────────────────────────

triggers="$(extract_triggers "${vault_target}/SKILL.md")"
new_row="| ${skill_name} | ${triggers} | ~/.claude/skill-vault/${skill_name}/ |"

info "Triggers: ${triggers}"

# ── Update catalog ────────────────────────────────────────────────────────────

# Check if this skill already has a row in the catalog
if grep -q "| ${skill_name} |" "${ROUTER_SKILL_MD}" 2>/dev/null; then
  warn "Catalog already has an entry for '${skill_name}' - skipping duplicate"
else
  # Append before the closing "ADD YOUR SKILLS BELOW" comment if it exists,
  # otherwise append before the end-of-file comment block.
  # Strategy: insert after the last data row in the catalog table.
  if grep -q "^<!-- ADD YOUR SKILLS BELOW" "${ROUTER_SKILL_MD}"; then
    # Insert the new row just before the trailing comment
    tmp_file="$(mktemp)"
    awk -v row="${new_row}" '
      /^<!-- ADD YOUR SKILLS BELOW/ { print row; print ""; }
      { print }
    ' "${ROUTER_SKILL_MD}" > "${tmp_file}"
    mv "${tmp_file}" "${ROUTER_SKILL_MD}"
  else
    # Append to the end of the catalog table (last | line)
    tmp_file="$(mktemp)"
    awk -v row="${new_row}" '
      { lines[NR] = $0 }
      END {
        last_table_row = 0
        for (i = NR; i >= 1; i--) {
          if (lines[i] ~ /^\|/) { last_table_row = i; break }
        }
        for (i = 1; i <= NR; i++) {
          print lines[i]
          if (i == last_table_row) print row
        }
      }
    ' "${ROUTER_SKILL_MD}" > "${tmp_file}"
    mv "${tmp_file}" "${ROUTER_SKILL_MD}"
  fi
  ok "Catalog updated: added ${skill_name}"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

header "Done."
echo ""
echo -e "  Skill vaulted:  ${GREEN}${skill_name}${RESET}"
echo -e "  Triggers:       ${triggers}"
echo -e "  Router catalog: ${ROUTER_SKILL_MD}"
echo ""
echo "  To customize trigger keywords, edit the router catalog directly:"
echo "  ${ROUTER_SKILL_MD}"
echo ""
echo -e "  ${BOLD}Restart Claude Code to apply changes.${RESET}"
echo ""
