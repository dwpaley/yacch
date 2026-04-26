#!/usr/bin/env bash
# session-start-advisory.sh — warn if recommended settings.json keys are missing.
# Exits 0 always; never fails the session.

# Silence mode
if [ "${YACCH_QUIET}" = "1" ]; then
  exit 0
fi

SETTINGS="${HOME}/.claude/settings.json"

# No settings file — nothing to check
if [ ! -f "$SETTINGS" ]; then
  exit 0
fi

# jq required for inspection; degrade gracefully if absent
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Check that settings.json is valid JSON before proceeding
if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  exit 0
fi

missing=()

if [ "$(jq '.sandbox.enabled // false' "$SETTINGS")" != "true" ]; then
  missing+=("sandbox.enabled")
fi

if [ "$(jq '.autoDreamEnabled // false' "$SETTINGS")" != "true" ]; then
  missing+=("autoDreamEnabled")
fi

if [ "$(jq -r '.effortLevel // ""' "$SETTINGS")" != "high" ]; then
  missing+=("effortLevel")
fi

if [ ${#missing[@]} -gt 0 ]; then
  # Build comma-separated list
  list=$(IFS=, ; echo "${missing[*]}")
  echo "yacch: recommended settings not configured (${list}) — run /yacch-setup, or set YACCH_QUIET=1 to silence." >&2
fi

exit 0
