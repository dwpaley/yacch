#!/usr/bin/env bash
# use-project.sh — Switch the active memory slot for the current working directory.
#
# Usage (sourced, never run directly):
#   source use-project.sh [slot]
#
# With no argument, slot defaults to "default".
# Writes autoMemoryDirectory into ./.claude/settings.local.json.
# Requires: jq, CLAUDE_MEMORY_DIR set to an existing absolute directory.

# ---------------------------------------------------------------------------
# Guard: must be sourced, not executed directly
# ---------------------------------------------------------------------------
# We can't detect this perfectly in all shells, but we use `return` throughout
# so that if this is accidentally executed (not sourced), the `return` outside
# a function will cause a non-fatal error rather than killing a shell session.

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
_slot="${1:-default}"

# Guard against path traversal: reject any slot name containing / or ..
if [[ "${_slot}" == */* ]] || [[ "${_slot}" == *..* ]]; then
    echo "yacch-project: error: slot name must not contain '/' or '..': '${_slot}'" >&2
    return 1
fi

# ---------------------------------------------------------------------------
# Validate dependencies
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
    echo "yacch-project: error: jq is required but not found. Install it (e.g. conda install jq) and retry." >&2
    return 1
fi

# ---------------------------------------------------------------------------
# Validate CLAUDE_MEMORY_DIR
# ---------------------------------------------------------------------------
if [[ -z "${CLAUDE_MEMORY_DIR:-}" ]]; then
    echo "yacch-project: error: CLAUDE_MEMORY_DIR is not set. Export it to an absolute path of your memory repo." >&2
    return 1
fi

if [[ ! -d "${CLAUDE_MEMORY_DIR}" ]]; then
    echo "yacch-project: error: CLAUDE_MEMORY_DIR does not exist or is not a directory: '${CLAUDE_MEMORY_DIR}'" >&2
    return 1
fi

# ---------------------------------------------------------------------------
# Compute target directory
# ---------------------------------------------------------------------------
_target="${CLAUDE_MEMORY_DIR}/${_slot}/"

# ---------------------------------------------------------------------------
# Create the slot directory and seed MEMORY.md if missing
# ---------------------------------------------------------------------------
mkdir -p "${_target}"
if [[ ! -f "${_target}/MEMORY.md" ]]; then
    touch "${_target}/MEMORY.md"
fi

# ---------------------------------------------------------------------------
# Upsert autoMemoryDirectory in ./.claude/settings.local.json
# ---------------------------------------------------------------------------
_settings_dir="$(pwd)/.claude"
_settings_file="${_settings_dir}/settings.local.json"

mkdir -p "${_settings_dir}"

if [[ ! -f "${_settings_file}" ]]; then
    echo '{}' > "${_settings_file}"
fi

_tmp="$(mktemp "${TMPDIR:-/tmp}/yacch-settings.XXXXXX")"
jq --arg d "${_target}" '. + {autoMemoryDirectory: $d}' "${_settings_file}" > "${_tmp}" && mv "${_tmp}" "${_settings_file}"

# ---------------------------------------------------------------------------
# Set up agent-memory symlink
# ---------------------------------------------------------------------------
# Create the slot's agent-memory subdir so the symlink target exists.
_target_agent_mem="${CLAUDE_MEMORY_DIR}/${_slot}/agent-memory"
mkdir -p "${_target_agent_mem}"

# The symlink we're managing inside the project's .claude/ dir.
_link="$(pwd)/.claude/agent-memory"

if [[ -L "${_link}" ]]; then
    # Already a symlink — check where it points.
    _current_target="$(readlink "${_link}")"
    if [[ "${_current_target}" == "${_target_agent_mem}" ]]; then
        # Already pointing at the right place; nothing to do.
        :
    else
        # Points somewhere else — update it.
        rm "${_link}"
        ln -s "${_target_agent_mem}" "${_link}"
        echo "yacch-project: updated agent-memory symlink to point to new slot"
    fi
elif [[ ! -e "${_link}" ]]; then
    # Nothing there (includes broken symlinks, since -e returns false for them).
    # rm -f is safe here — it's a no-op on truly absent paths.
    rm -f "${_link}"
    ln -s "${_target_agent_mem}" "${_link}"
    echo "yacch-project: agent-memory symlink → ${_target_agent_mem}"
elif [[ -d "${_link}" ]]; then
    # It's a real directory. Check if empty.
    if [[ -z "$(ls -A "${_link}")" ]]; then
        # Empty — safe to replace.
        rmdir "${_link}"
        ln -s "${_target_agent_mem}" "${_link}"
        echo "yacch-project: agent-memory symlink → ${_target_agent_mem}"
    else
        # Non-empty real directory — do NOT clobber; warn and let user migrate.
        echo "yacch-project: WARNING: ./.claude/agent-memory is a real directory with content:" >&2
        ls -A "${_link}" | sed 's/^/    /' >&2
        echo "yacch-project: symlink NOT created. Manually migrate first:" >&2
        echo "    mv \"${_link}\"/* \"${_target_agent_mem}/\" && rmdir \"${_link}\" && yacch-project ${_slot}" >&2
        # Continue — settings.local.json was already updated; user can re-run after migration.
    fi
else
    # Something else (regular file, etc.) — warn but don't touch it.
    echo "yacch-project: WARNING: ./.claude/agent-memory exists and is not a directory or symlink; symlink NOT created." >&2
fi

# ---------------------------------------------------------------------------
# Confirm
# ---------------------------------------------------------------------------
echo "yacch-project: active slot for $(pwd) → ${_slot} (${_target})"

return 0
