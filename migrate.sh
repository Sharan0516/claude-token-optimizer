#!/usr/bin/env bash
# migrate.sh - Move skills to ~/.claude/skill-vault/ and install the skill router
# Safe to run multiple times (idempotent)

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Extract trigger keywords from a SKILL.md ─────────────────────────────────
# Looks for: "trigger:", "triggers:", or the first non-heading sentence after #
# Falls back to the skill name if nothing useful is found.

extract_triggers() {
  local skill_md="$1"
  local triggers=""

  # Try: frontmatter trigger/triggers field (e.g. "triggers: foo, bar")
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

  # Fall back to skill name as trigger phrase
  if [[ -z "${triggers}" ]]; then
    local skill_name
    skill_name="$(basename "$(dirname "${skill_md}")")"
    triggers="${skill_name}"
  fi

  # Truncate to keep table readable
  echo "${triggers}" | cut -c1-100
}

# ── Preflight checks ──────────────────────────────────────────────────────────

header "claude-token-optimizer: migrate"

if [[ ! -d "${SKILLS_DIR}" ]]; then
  error "~/.claude/skills/ does not exist. Nothing to migrate."
  exit 1
fi

router_template="${SCRIPT_DIR}/skill-router/SKILL.md"
if [[ ! -f "${router_template}" ]]; then
  error "Template not found: ${router_template}"
  error "Run this script from the claude-token-optimizer repo directory."
  exit 1
fi

# ── Create vault ──────────────────────────────────────────────────────────────

if [[ ! -d "${VAULT_DIR}" ]]; then
  mkdir -p "${VAULT_DIR}"
  ok "Created ${VAULT_DIR}"
else
  info "Vault already exists at ${VAULT_DIR}"
fi

# ── Scan skills directory and move to vault ───────────────────────────────────

header "Scanning ${SKILLS_DIR}..."

moved=0
skipped=0
already_vaulted=0

for skill_path in "${SKILLS_DIR}"/*/; do
  # Strip trailing slash
  skill_path="${skill_path%/}"
  skill_name="$(basename "${skill_path}")"

  # Skip non-directories
  [[ -d "${skill_path}" ]] || continue

  # Skip directories starting with _ (e.g. _shared, _archived)
  if [[ "${skill_name}" == _* ]]; then
    info "Skipping reserved directory: ${skill_name}"
    ((skipped++)) || true
    continue
  fi

  # Skip the router itself
  if [[ "${skill_name}" == "skill-router" ]]; then
    info "Skipping skill-router (will reinstall)"
    continue
  fi

  # Skip if no SKILL.md present (not a skill directory)
  if [[ ! -L "${skill_path}" && ! -f "${skill_path}/SKILL.md" ]]; then
    info "Skipping ${skill_name} (no SKILL.md)"
    ((skipped++)) || true
    continue
  fi

  # Handle symlinks
  if [[ -L "${skill_path}" ]]; then
    link_target="$(readlink -f "${skill_path}" 2>/dev/null || readlink "${skill_path}")"
    if [[ "${link_target}" == "${VAULT_DIR}"/* ]]; then
      info "Already vaulted (symlink): ${skill_name}"
      ((already_vaulted++)) || true
      continue
    else
      warn "Removing external symlink: ${skill_name} -> ${link_target} (target not moved)"
      rm "${skill_path}"
      ((skipped++)) || true
      continue
    fi
  fi

  vault_target="${VAULT_DIR}/${skill_name}"

  # Already in vault (idempotent)
  if [[ -d "${vault_target}" ]]; then
    info "Already in vault: ${skill_name}"
    ((already_vaulted++)) || true
    continue
  fi

  # Move to vault
  mv "${skill_path}" "${vault_target}"
  ok "Moved to vault: ${skill_name}"
  ((moved++)) || true
done

# ── Build catalog from everything now in the vault ───────────────────────────

header "Building catalog..."

catalog_rows=""
skill_count=0

for vault_skill_path in "${VAULT_DIR}"/*/; do
  vault_skill_path="${vault_skill_path%/}"
  [[ -d "${vault_skill_path}" ]] || continue
  vault_skill_name="$(basename "${vault_skill_path}")"

  skill_md="${vault_skill_path}/SKILL.md"
  if [[ ! -f "${skill_md}" ]]; then
    warn "No SKILL.md in vault/${vault_skill_name} - skipping catalog entry"
    continue
  fi

  triggers="$(extract_triggers "${skill_md}")"
  new_row="| ${vault_skill_name} | ${triggers} | ~/.claude/skill-vault/${vault_skill_name}/ |"
  catalog_rows="${catalog_rows}
${new_row}"
  ((skill_count++)) || true
  info "Cataloged: ${vault_skill_name}"
done

# ── Install router with generated catalog ─────────────────────────────────────

header "Installing skill router..."

mkdir -p "${ROUTER_SKILL_DIR}"

# Build the full catalog table string
catalog_table="| Skill | Triggers | Vault Path |
|-------|----------|------------|${catalog_rows}"

# Write router SKILL.md: copy template header/instructions, replace catalog section
{
  # Output everything from template up to (and including) the catalog section comment
  awk '
    /^<!-- HOW TO CUSTOMIZE/ { in_comment=1 }
    in_comment && /-->/ { print; in_comment=0; found_end=1; next }
    found_end { next }
    { print }
  ' "${router_template}"

  # Inject generated catalog
  echo ""
  echo "${catalog_table}"
  echo ""
  echo "<!-- ADD YOUR SKILLS BELOW THIS LINE"
  echo "     Example row format:"
  echo "     | skill-name | trigger phrase one, trigger phrase two | ~/.claude/skill-vault/skill-name/ |"
  echo "-->"

} > "${ROUTER_SKILL_DIR}/SKILL.md"

ok "Router installed: ${ROUTER_SKILL_DIR}/SKILL.md"

# ── Summary ───────────────────────────────────────────────────────────────────

header "Done."
echo ""
echo -e "  Skills moved to vault this run:   ${GREEN}${moved}${RESET}"
echo -e "  Already in vault (skipped):       ${CYAN}${already_vaulted}${RESET}"
echo -e "  Skipped (not a skill dir):        ${YELLOW}${skipped}${RESET}"
echo -e "  Total catalog entries:            ${BOLD}${skill_count}${RESET}"
echo ""

if [[ "${skill_count}" -gt 0 ]]; then
  est_before=$(( skill_count * 40 ))
  est_after=200
  est_saved=$(( est_before - est_after ))
  echo -e "  Estimated system prompt reduction (skill descriptions only):"
  echo -e "    Before: ~${est_before} tokens  (${skill_count} skills x ~40 tokens avg)"
  echo -e "    After:  ~${est_after} tokens   (router catalog only)"
  echo -e "    ${GREEN}Saved:  ~${est_saved} tokens per conversation${RESET}"
  echo ""
  echo -e "  Note: Skills are one part of system prompt overhead. CLAUDE.md, memory,"
  echo -e "  MCP plugins, and tool registrations also contribute. See README for details."
fi

echo ""
echo -e "  ${BOLD}Restart Claude Code to apply changes.${RESET}"
echo ""
