# yacch

yacch (pronounced "yatch") is a Claude Code plugin that wires an orchestrator-mode subagent workflow into your Claude Code sessions. It ships eight specialized subagents, a lifecycle hook set that injects orchestrator reminders on every prompt, and optional private memory sync against a user-managed git repo. Everything is installed in one shot via `/yacch-setup`.

## Quickstart

### 1. Install the plugin

```
/plugin marketplace add dwpaley/yacch
/plugin install yacch
/reload-plugins
```

### 2. (Optional but recommended) Set up a private memory repo

If you want agent memory to persist and sync across sessions, create a private git repo now. You can skip this and add it later.

```bash
gh repo create my-claude-memory --private
git clone git@github.com:<you>/my-claude-memory.git ~/claude-memory
export CLAUDE_MEMORY_DIR=~/claude-memory   # add to your ~/.bashrc or ~/.zshrc
```

See [Project memory](#project-memory) for how the slot model works.

### 3. Run /yacch-setup

```
/yacch:yacch-setup
```

This applies recommended settings, installs agent rules into `~/.claude/CLAUDE.md`, installs the shell init scripts, and — if `CLAUDE_MEMORY_DIR` is set — adds it to the sandbox write allowlist. As its final action it hardens the sandbox. See [What /yacch-setup does](#what-yacch-setup-does) for the full list.

### 4. Add shell init to your rc file

```bash
# Add to ~/.bashrc or ~/.zshrc:
source ~/.claude/yacch-shell-init.sh
```

Then reload your shell (`exec $SHELL` or open a new terminal). This provides the `yacch-project` command and exports `ANTHROPIC_SMALL_FAST_MODEL`.

### 5. Restart your Claude Code session

The sandbox and allowlist changes written by `/yacch-setup` take effect only after a session restart. After restarting, orchestrator-mode behavior is active and (if `CLAUDE_MEMORY_DIR` was set) the memory sync hooks are wired up.

### 6. (Optional) Activate a project memory slot

```bash
cd ~/projects/myproject
yacch-project myproject
```

This sets the active memory slot for that directory. See [Project memory](#project-memory) for details.

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Claude Code** | Any recent version with plugin support |
| **`jq`** | Used by `/yacch-setup`, `yacch-project`, and the session-start advisory |
| **`git`** | Required by worktree-based agents and the memory sync hooks |
| **`python3`** | Used by `/yacch-setup` for portable in-place text replacement in `CLAUDE.md` |
| **`gh` CLI** | Optional; useful for creating the private memory repo |

---

## What you get

### Agents

Eight subagents cover the full development loop. Each has explicit `model:` and `effort:` frontmatter so subagents don't inherit the orchestrator's effort level. The orchestrator rules file (`agents/orchestrator-notes.md`) is not an agent — it is the governing spec read by the main session at the start of every conversation.

| Agent | Purpose |
|-------|---------|
| **planner** | Breaks a high-level goal into a detailed implementation plan and task list |
| **junior-dev-worktree** | Implements atomic coding tasks (~100 LOC) in an isolated git worktree |
| **reviewer** | Reviews junior-dev branches for correctness and spec compliance before merging |
| **build-and-test** | Compiles code, runs tests and benchmarks, and reports raw results |
| **investigator** | Open-ended debugging, profiling, and feasibility studies; returns findings |
| **refactorer** | Rewrites code for clarity without changing behavior; paired with build-and-test |
| **test-writer** | Writes tests that pin down current behavior as a refactoring safety net |
| **gofer** | Lightweight lookups, dependency checks, simple setup tasks (runs on Haiku) |

### Hooks

| Hook | Trigger | Behavior | Suppress with |
|------|---------|----------|---------------|
| `UserPromptSubmit` | Every prompt | Appends an orchestrator-mode reminder pointing at `${CLAUDE_PLUGIN_ROOT}/agents/orchestrator-notes.md` and listing available agents | `export ORCHESTRATOR_MODE=off` |
| `SessionStart` (1) | Session open | Runs `git pull --rebase` on `$CLAUDE_MEMORY_DIR` if set and valid | Unset `CLAUDE_MEMORY_DIR` |
| `SessionStart` (2) | Session open | Checks that recommended settings keys are present; warns if any are missing | `export YACCH_QUIET=1` |
| `SessionEnd` | Session close | Stages all changes, commits with ISO timestamp, and pushes `$CLAUDE_MEMORY_DIR`; warns on push failure but does not block exit | Unset `CLAUDE_MEMORY_DIR` |

---

## What /yacch-setup does

`/yacch-setup` runs five actions in order, with backups before every file modification:

**Action 1 — Patch `~/.claude/settings.json` with recommended values.**
Merges `sandbox.enabled: true`, `autoDreamEnabled: true`, and `effortLevel: "high"` into the file. The merge is right-side-wins: your existing values are never overwritten, only missing keys are added.

**Action 2 — Idempotently install the agent-rules snippet into `~/.claude/CLAUDE.md`.**
The block is wrapped in `<!-- yacch:rules:start v1 -->` / `<!-- yacch:rules:end -->` version markers. If the block is already present at the current version, nothing changes. If an older version is found, the block is replaced and a backup is created.

**Action 3 — Install `~/.claude/yacch-use-project.sh` and `~/.claude/yacch-shell-init.sh`.**
These are overwritten on every run (idempotent by design). After setup you must `source ~/.claude/yacch-shell-init.sh` from your shell rc.

**Action 4 — Add `CLAUDE_MEMORY_DIR` (canonical resolved path) to `sandbox.filesystem.allowWrite[]`.**
Required because macOS resolves symlinks to their canonical targets before applying sandbox write rules; without this entry, subagent writes through `./.claude/agent-memory/` would be blocked. Skipped if `CLAUDE_MEMORY_DIR` is not set. Takes effect on next session restart.

**Action 5 — Set `sandbox.allowUnsandboxedCommands: false`.**
Hardens the sandbox so the bypass is disabled. See [Hardening](#hardening-making-the-sandbox-a-real-wall).

`/yacch-setup` is idempotent and safe to re-run, but the preflight check will abort if the sandbox is already hardened (Action 5 from a prior run blocks writes to `~/.claude/settings.json`). See the Hardening section for the unlock procedure.

---

## Project memory

The memory repo is organized into named slots — subdirectories each containing their own `MEMORY.md` and `agent-memory/` directory.

**Layout:**
```
$CLAUDE_MEMORY_DIR/
  default/
    MEMORY.md
    agent-memory/
  myproject/
    MEMORY.md
    agent-memory/
```

When no slot is active for a working directory, the `default/` slot is used.

### Switching the active slot

```bash
cd ~/projects/myproject
yacch-project myproject
```

`yacch-project <slot>` does two things:

1. Writes `autoMemoryDirectory` to `./.claude/settings.local.json` so Claude Code loads memory from `$CLAUDE_MEMORY_DIR/<slot>/` for that directory.
2. Creates `./.claude/agent-memory` as a symlink to `$CLAUDE_MEMORY_DIR/<slot>/agent-memory/`. Subagent memory writes tagged `memory: project` land inside this symlink and flow through to the private memory repo, where they are picked up by the `SessionStart`/`SessionEnd` sync hooks.

With no argument, the slot defaults to `default`:

```bash
yacch-project   # → $CLAUDE_MEMORY_DIR/default/
```

### Notes

- The slot name is independent of the working directory name. Multiple directories can share a slot, or you can repoint a directory to a different slot by re-running `yacch-project <newslot>`.
- `yacch-project` creates the slot subdirectory and a seed `MEMORY.md` if they do not already exist.
- The slot setting is stored in `./.claude/settings.local.json`. Commit it to share the slot with teammates, or add it to `.gitignore` to keep it personal.

### Migrating existing agent-memory content

If `./.claude/agent-memory/` already exists as a real directory with content, `yacch-project` will not overwrite it. It prints a warning and the commands to migrate:

```bash
mv ./.claude/agent-memory/* "$CLAUDE_MEMORY_DIR/<slot>/agent-memory/" \
  && rmdir ./.claude/agent-memory \
  && yacch-project <slot>
```

After the manual move, re-run `yacch-project <slot>` to create the symlink.

---

## Hardening: making the sandbox a real wall

`/yacch-setup` applies one final write that matters for security: it sets `sandbox.allowUnsandboxedCommands: false` in `~/.claude/settings.json`.

### What this does

By default `sandbox.allowUnsandboxedCommands` is `true`, which means Claude Code silently retries any sandbox-blocked command with the sandbox disabled — the sandbox is advisory, not enforced.

Setting it to `false` makes the sandbox authoritative: if a command is blocked by the sandbox rules, it fails with a hard error instead of silently escaping. This matters most when `skipDangerousModePermissionPrompt: true` is also set. Without hardening, that combination means sandbox failures are retried invisibly with no prompt and no log — effectively, the sandbox does nothing.

### The trade-off

Re-running `/yacch-setup` (for example, after a plugin update) requires temporarily reverting the hardening first, because the setup script needs to write to `~/.claude/settings.json` — a path the hardened sandbox blocks.

To re-run `/yacch-setup` after hardening:

```bash
# 1. From a shell outside Claude Code, or via /config / /sandbox in Claude Code:
jq '.sandbox.allowUnsandboxedCommands = true' ~/.claude/settings.json \
  > ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json

# 2. Restart your Claude Code session (so the change takes effect).

# 3. Re-run /yacch-setup — it sets the value back to false at the end.
```

---

## Customizing

- **Agent model and effort**: each agent file under `agents/` has `model:` and `effort:` frontmatter fields you can edit to tune cost and quality per agent.
- **Disable orchestrator mode for a session**: `export ORCHESTRATOR_MODE=off` before starting Claude Code.
- **Silence the settings advisory**: `export YACCH_QUIET=1`.
- **Agent-rules versioning**: the block in `~/.claude/CLAUDE.md` is delimited by `<!-- yacch:rules:start v1 -->` and `<!-- yacch:rules:end -->`. A future `/yacch-setup` run detects the version marker and replaces the block with the canonical version from the plugin. To keep local edits, track them separately.
- **Telemetry**: `~/.claude/yacch-shell-init.sh` contains a commented-out `export DISABLE_TELEMETRY=1` line. Uncomment it to disable Anthropic telemetry.

---

## Uninstall

```
/plugin uninstall yacch
```

Then manually:

1. Remove the agent-rules block from `~/.claude/CLAUDE.md` — everything between (and including) `<!-- yacch:rules:start ... -->` and `<!-- yacch:rules:end -->`.
2. Optionally restore `~/.claude/settings.json` from a timestamped backup:
   ```bash
   cp ~/.claude/settings.json.bak.<timestamp> ~/.claude/settings.json
   ```
3. Optionally restore `~/.claude/CLAUDE.md` from a timestamped backup:
   ```bash
   cp ~/.claude/CLAUDE.md.bak.<timestamp> ~/.claude/CLAUDE.md
   ```

Your memory repo is untouched — you own it.
