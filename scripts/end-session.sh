#!/bin/bash
# end-session.sh — auto-commit and push memory updates at end of Claude session.
# Operates against $CLAUDE_MEMORY_DIR; no-ops gracefully if unset or invalid.

# Guard: CLAUDE_MEMORY_DIR must be set and non-empty.
if [ -z "$CLAUDE_MEMORY_DIR" ]; then
  exit 0
fi

# Guard: directory must exist.
if [ ! -d "$CLAUDE_MEMORY_DIR" ]; then
  echo "yacch: CLAUDE_MEMORY_DIR=$CLAUDE_MEMORY_DIR does not exist" >&2
  exit 0
fi

# Guard: must be a git repo.
if ! git -C "$CLAUDE_MEMORY_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  echo "yacch: CLAUDE_MEMORY_DIR=$CLAUDE_MEMORY_DIR is not a git repository" >&2
  exit 0
fi

# Stage all changes.
git -C "$CLAUDE_MEMORY_DIR" add -A

# Skip commit if nothing is staged.
if git -C "$CLAUDE_MEMORY_DIR" diff --cached --quiet; then
  exit 0
fi

# Commit with ISO timestamp.
git -C "$CLAUDE_MEMORY_DIR" commit --quiet -m "memory: auto-update $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Push; warn on failure but do not propagate error.
if ! git -C "$CLAUDE_MEMORY_DIR" push --quiet 2>/dev/null; then
  echo "yacch: push to memory remote failed (continuing)" >&2
fi

exit 0
