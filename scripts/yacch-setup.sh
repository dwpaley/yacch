#!/usr/bin/env bash
# yacch-setup.sh — Apply recommended Claude Code settings and install yacch agent-rules
# into ~/.claude/CLAUDE.md. Idempotent: safe to run multiple times.
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

# Resolve the plugin root relative to this script so it works regardless of CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SETTINGS_FILE="${HOME}/.claude/settings.json"
CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
SNIPPET_FILE="${CLAUDE_PLUGIN_ROOT}/CLAUDE.md.snippet"
NOW="$(date +%s)"

SETTINGS_BACKUP=""
CLAUDE_MD_BACKUP=""

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || die "jq is required but not found. Install it (e.g. conda install jq) and retry."
[[ -f "${SNIPPET_FILE}" ]] || die "Snippet file not found: ${SNIPPET_FILE}"

# ---------------------------------------------------------------------------
# Action 1 — Patch ~/.claude/settings.json
# ---------------------------------------------------------------------------
echo "=== Action 1: Patching ${SETTINGS_FILE} ==="

# Ensure parent directory exists
mkdir -p "${HOME}/.claude"

# Create settings file if missing
if [[ ! -f "${SETTINGS_FILE}" ]]; then
    echo "  settings.json not found — creating empty file."
    echo '{}' > "${SETTINGS_FILE}"
fi

# Always back up
SETTINGS_BACKUP="${SETTINGS_FILE}.bak.${NOW}"
cp "${SETTINGS_FILE}" "${SETTINGS_BACKUP}"
echo "  Backup: ${SETTINGS_BACKUP}"

# Recommended defaults (existing values in the file will WIN over these)
RECOMMENDED='{
  "sandbox": {"enabled": true},
  "autoDreamEnabled": true,
  "effortLevel": "high"
}'

# Merge: recommended * existing (existing takes precedence — right side wins)
MERGED="$(jq -s '.[0] * .[1]' <(echo "${RECOMMENDED}") "${SETTINGS_FILE}")"

# Compute diff between backup and what we'd write
DIFF_OUTPUT="$(diff -u "${SETTINGS_BACKUP}" <(echo "${MERGED}") || true)"

if [[ -z "${DIFF_OUTPUT}" ]]; then
    echo "  Settings already match recommended values — nothing to change."
    # Remove the backup we just made since we're not modifying the file
    rm "${SETTINGS_BACKUP}"
    SETTINGS_BACKUP=""
else
    echo "  Changes to settings.json:"
    echo "${DIFF_OUTPUT}"
    echo "${MERGED}" > "${SETTINGS_FILE}"
    echo "  settings.json updated."
fi

# ---------------------------------------------------------------------------
# Action 2 — Append/update yacch snippet in ~/.claude/CLAUDE.md
# ---------------------------------------------------------------------------
echo ""
echo "=== Action 2: Installing yacch agent-rules into ${CLAUDE_MD} ==="

# Ensure CLAUDE.md exists
if [[ ! -f "${CLAUDE_MD}" ]]; then
    echo "  CLAUDE.md not found — creating empty file."
    touch "${CLAUDE_MD}"
fi

SNIPPET_CONTENT="$(cat "${SNIPPET_FILE}")"

# Extract the version from the snippet's start marker, e.g. "v1"
SNIPPET_VERSION="$(head -1 "${SNIPPET_FILE}" | grep -oE 'v[0-9]+')"
[[ -n "${SNIPPET_VERSION}" ]] || die "Could not extract version marker from ${SNIPPET_FILE} (expected first line to contain 'v<N>')"

# Check whether an existing yacch block is present
if grep -qF '<!-- yacch:rules:start' "${CLAUDE_MD}"; then
    # Extract the installed version marker
    INSTALLED_VERSION="$(grep -oE '<!-- yacch:rules:start v[0-9]+ -->' "${CLAUDE_MD}" | grep -oE 'v[0-9]+' | head -1)"

    if [[ "${INSTALLED_VERSION}" == "${SNIPPET_VERSION}" ]]; then
        echo "  Agent-rules snippet already installed at this version (${SNIPPET_VERSION}) — nothing to change."
    else
        echo "  Found existing snippet at version ${INSTALLED_VERSION}, upgrading to ${SNIPPET_VERSION}."
        CLAUDE_MD_BACKUP="${CLAUDE_MD}.bak.${NOW}"
        cp "${CLAUDE_MD}" "${CLAUDE_MD_BACKUP}"
        echo "  Backup: ${CLAUDE_MD_BACKUP}"

        # Replace the block from <!-- yacch:rules:start ... to <!-- yacch:rules:end -->
        # Use Python for reliable multi-line replacement (avoids sed portability issues on macOS)
        python3 - "${CLAUDE_MD}" "${SNIPPET_FILE}" <<'PYEOF'
import sys, re

claude_md_path = sys.argv[1]
snippet_path   = sys.argv[2]

with open(claude_md_path, 'r') as f:
    content = f.read()

with open(snippet_path, 'r') as f:
    snippet = f.read()

# Replace everything from <!-- yacch:rules:start (any version) to <!-- yacch:rules:end -->
pattern = r'<!-- yacch:rules:start[^\n]*\n.*?<!-- yacch:rules:end -->'
updated = re.sub(pattern, snippet.rstrip('\n'), content, flags=re.DOTALL)

with open(claude_md_path, 'w') as f:
    f.write(updated)
PYEOF
        echo "  CLAUDE.md updated with new snippet version."
    fi
else
    echo "  No existing yacch block found — appending snippet."
    CLAUDE_MD_BACKUP="${CLAUDE_MD}.bak.${NOW}"
    cp "${CLAUDE_MD}" "${CLAUDE_MD_BACKUP}"
    echo "  Backup: ${CLAUDE_MD_BACKUP}"

    # Append blank line + snippet
    printf '\n%s\n' "${SNIPPET_CONTENT}" >> "${CLAUDE_MD}"
    echo "  Snippet appended to CLAUDE.md."
fi

# ---------------------------------------------------------------------------
# Action 3 — Install yacch shell init files
# ---------------------------------------------------------------------------
echo ""
echo "=== Action 3: Installing yacch shell init ==="

YACCH_USE_PROJECT_DEST="${HOME}/.claude/yacch-use-project.sh"
YACCH_SHELL_INIT_DEST="${HOME}/.claude/yacch-shell-init.sh"

# Copy use-project.sh into ~/.claude/ for use by the shell function
cp "${SCRIPT_DIR}/use-project.sh" "${YACCH_USE_PROJECT_DEST}"
echo "  Installed: ${YACCH_USE_PROJECT_DEST}"

# Write the shell init file (overwrite on every run — idempotent by design)
cat > "${YACCH_SHELL_INIT_DEST}" <<'SHELLINIT'
# yacch shell init — source this from your ~/.bashrc or ~/.zshrc
#
# Refresh after plugin update by re-running /yacch-setup.

# Recommended fast model for haiku-tagged subagents (lower cost).
export ANTHROPIC_SMALL_FAST_MODEL=claude-haiku-4-5

# Uncomment to disable Anthropic telemetry:
# export DISABLE_TELEMETRY=1

# Project memory switcher.
#   yacch-project myslot   # → $CLAUDE_MEMORY_DIR/myslot/
#   yacch-project          # → $CLAUDE_MEMORY_DIR/default/
yacch-project() {
  source "$HOME/.claude/yacch-use-project.sh" "$@"
}
SHELLINIT
echo "  Installed: ${YACCH_SHELL_INIT_DEST}"

echo ""
echo "  yacch shell init installed at ${YACCH_SHELL_INIT_DEST}"
echo "  Add this line to your ~/.bashrc or ~/.zshrc:"
echo "      source ~/.claude/yacch-shell-init.sh"
echo "  Then reload your shell. After that, \`yacch-project <slot>\` will be available."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "  Settings file     : ${SETTINGS_FILE}"
echo "  CLAUDE.md         : ${CLAUDE_MD}"
echo "  Shell init        : ${YACCH_SHELL_INIT_DEST}"
echo "  use-project.sh    : ${YACCH_USE_PROJECT_DEST}"
if [[ -n "${SETTINGS_BACKUP}" ]]; then
    echo "  Settings backup: ${SETTINGS_BACKUP}"
fi
if [[ -n "${CLAUDE_MD_BACKUP}" ]]; then
    echo "  CLAUDE.md backup: ${CLAUDE_MD_BACKUP}"
fi
echo "Done."
