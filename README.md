# yacch — Yet Another Claude Code Harness

yacch (pronounced "yatch") is a Claude Code plugin that wires an orchestrator-mode subagent workflow into your Claude Code sessions. It ships eight specialized subagents, a lifecycle hook set that injects orchestrator reminders on every prompt, and optional private-memory sync against a user-managed git repo. Everything is installed in one shot via `/yacch-setup`.

---

## What you get

- **Orchestrator-mode enforcement.** A `UserPromptSubmit` hook appends a reminder to every prompt pointing Claude at the orchestrator rules file and listing the available agents. The main session acts as a thin dispatcher; substantive work goes to subagents.
- **Eight subagents** covering the full development loop (see table below).
- **`/yacch-setup`** — a one-shot command that merges recommended settings into `~/.claude/settings.json` and appends the shared agent-rules block to `~/.claude/CLAUDE.md`.
- **Optional memory sync.** `SessionStart` / `SessionEnd` hooks pull and push a private git repo when `CLAUDE_MEMORY_DIR` is set. If unset, the hooks no-op silently.

### Subagents

| Agent | Purpose |
|-------|---------|
| **planner** | Breaks a high-level goal into an implementation plan and task list |
| **junior-dev-worktree** | Implements atomic coding tasks (~100 LOC) in an isolated git worktree |
| **reviewer** | Reviews junior-dev branches for correctness and spec compliance before merging |
| **build-and-test** | Compiles code, runs tests and benchmarks, reports raw results |
| **investigator** | Open-ended debugging, profiling, and feasibility studies; returns findings |
| **refactorer** | Rewrites code for clarity without changing behavior; paired with build-and-test |
| **test-writer** | Writes tests that pin down current behavior as a refactoring safety net |
| **gofer** | Lightweight lookups: check dependencies, search docs, verify env state, simple setup tasks (runs on Haiku) |

The orchestrator rules file (`agents/orchestrator-notes.md`) is not an agent — it is the governing spec read by the main session at the start of every conversation.

---

## Requirements

- **Claude Code** (any recent version with plugin support)
- **`jq`** — used by `/yacch-setup`, the session-start advisory script, and `yacch-project`
- **`git`** — required by worktree-based agents and the memory-sync hooks
- **`python3`** — used by `/yacch-setup` for portable in-place text replacement in `CLAUDE.md`
- **Optional: GitHub CLI (`gh`)** — useful for creating the private memory repo

---

## Install

### 1. Add the plugin

```
/plugin marketplace add github.com/<your-fork>/yacch
/plugin install yacch
```

Replace `<your-fork>/yacch` with the URL of the repo you pushed to.

### 2. Run setup

```
/yacch-setup
```

Setup does the following:

- **Backs up** `~/.claude/settings.json` (timestamped `.bak.*` file) before touching it.
- **Merges recommended settings** into `settings.json`. The merge is right-side-wins, meaning your existing values are never overwritten — only missing keys are added.
- **Backs up** `~/.claude/CLAUDE.md` before modifying it.
- **Appends the agent-rules snippet** to `~/.claude/CLAUDE.md`, wrapped in `<!-- yacch:rules:start v1 -->` / `<!-- yacch:rules:end -->` markers. If the block is already present at the same version, nothing changes. If an older version is found, it is replaced and a backup is created.
- **Installs `~/.claude/yacch-shell-init.sh`** — a shell init file providing the `yacch-project` function.
- **Idempotent** — running `/yacch-setup` again after it has already succeeded is safe.

### 3. Add shell init to your rc file

```bash
# In your ~/.bashrc or ~/.zshrc:
source ~/.claude/yacch-shell-init.sh
```

Then reload your shell (`exec $SHELL` or open a new terminal). This provides the `yacch-project` command and sets the recommended `ANTHROPIC_SMALL_FAST_MODEL` environment variable.

---

## Recommended settings (and why)

`/yacch-setup` applies these defaults if they are not already set:

| Key | Value | Why |
|-----|-------|-----|
| `sandbox.enabled` | `true` | Restricts where Bash commands can write; safer default for agent work |
| `autoDreamEnabled` | `true` | Enables background dream cycles |
| `effortLevel` | `"high"` | The orchestrator (main session) thinks harder; individual subagents carry their own `effort:` overrides in their frontmatter so they don't all inherit max-effort |

These are recommendations, not hard requirements. `/yacch-setup` leaves your existing values intact.

To suppress the session-start advisory that fires when these keys are missing, set:

```bash
export YACCH_QUIET=1   # add to .bashrc or .zshrc
```

---

## Optional — private memory repo

The harness ships optional hooks for syncing agent memory across sessions against a private git repo.

### Setup

```bash
gh repo create my-claude-memory --private
git clone git@github.com:<you>/my-claude-memory.git ~/claude-memory
export CLAUDE_MEMORY_DIR=~/claude-memory   # add to .bashrc or .zshrc
```

### Behavior

Once `CLAUDE_MEMORY_DIR` points to a valid git repo:

- **SessionStart** — runs `git pull --rebase` to pull the latest memory before the session begins.
- **SessionEnd** — stages all changes (`git add -A`), commits with an ISO timestamp message, and pushes. If the push fails, a warning is printed but the session exit is unaffected.

If `CLAUDE_MEMORY_DIR` is unset or does not point to a git repo, both hooks exit silently. Memory files are plain markdown, keyed by topic. The agent-rules block installed by `/yacch-setup` describes the expected schema for agents that write memory.

When no project slot is active for a working directory, memory is loaded from the `default/` slot (`$CLAUDE_MEMORY_DIR/default/`). See "Project memory: per-slot loading" below for how to switch slots.

---

## Project memory: per-slot loading

The memory repo can be sliced into named slots — subdirectories each with their own `MEMORY.md`. This lets different projects (or working contexts) load independent memory without interfering with each other.

### Switching the active slot

```bash
cd ~/projects/api
yacch-project api
```

This writes `autoMemoryDirectory` to `./.claude/settings.local.json`. Subsequent Claude Code sessions launched from that directory will automatically load memory from `$CLAUDE_MEMORY_DIR/api/`.

### No argument — global default

```bash
yacch-project   # → $CLAUDE_MEMORY_DIR/default/
```

Useful for working directories that don't need their own slot, or to reset a directory back to the shared default context.

### Notes

- The slot name is independent of the working directory name. Multiple working dirs can share a slot (`yacch-project api` in both `~/projects/api` and `~/projects/api-v2`), or you can repoint a directory to a different slot later by re-running `yacch-project <newslot>`.
- `yacch-project` creates the slot subdirectory and a seed `MEMORY.md` if they do not already exist.
- The slot setting is stored in `./.claude/settings.local.json` — a project-local file. Commit it to your project repo if you want the slot to be shared with teammates, or add it to `.gitignore` if it's personal.
- The `yacch-project` shell function is provided by `~/.claude/yacch-shell-init.sh`, installed by `/yacch-setup`. Add `source ~/.claude/yacch-shell-init.sh` to your `.bashrc` or `.zshrc`.

### Migration tip

If you have existing memory in `~/.claude/memory/<project>/` from a prior setup, move those subdirectories into your private memory repo:

```bash
mv ~/.claude/memory/api/ ~/claude-memory/api/
```

Then run `yacch-project api` in your project directory to activate the slot.

---

## Hooks reference

| Hook | Count | Behavior | Suppress |
|------|-------|----------|---------|
| `UserPromptSubmit` | 1 | Injects orchestrator-mode reminder into every prompt | `export ORCHESTRATOR_MODE=off` |
| `SessionStart` | 2 | (1) Pull memory repo if `CLAUDE_MEMORY_DIR` set; (2) Check recommended settings, warn if any are missing | `YACCH_QUIET=1` suppresses the advisory |
| `SessionEnd` | 1 | Commit and push memory repo if `CLAUDE_MEMORY_DIR` set | Unset `CLAUDE_MEMORY_DIR` |

---

## Customizing

- **Agent model and effort**: each agent file under `agents/` has `model:` and `effort:` frontmatter fields you can edit to tune cost and quality per agent type.
- **Disable orchestrator mode for a session**: `export ORCHESTRATOR_MODE=off` before starting Claude Code.
- **Agent-rules versioning**: the block in `~/.claude/CLAUDE.md` is delimited by `<!-- yacch:rules:start v1 -->` and `<!-- yacch:rules:end -->`. If you edit your local copy, a future `/yacch-setup` run will detect the version marker, back up the file, and replace the block with the canonical version from the plugin. To keep local edits, track them separately.

---

## Uninstall

```
/plugin uninstall yacch
```

Then manually:

1. Remove the agent-rules block from `~/.claude/CLAUDE.md` — everything between (and including) `<!-- yacch:rules:start ... -->` and `<!-- yacch:rules:end -->`.
2. If you want to revert settings changes, restore one of the timestamped backups created by `/yacch-setup`:
   ```bash
   cp ~/.claude/settings.json.bak.<timestamp> ~/.claude/settings.json
   ```
