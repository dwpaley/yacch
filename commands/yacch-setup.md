---
description: Apply recommended yacch Claude Code settings and install yacch agent-rules into CLAUDE.md.
disable-model-invocation: true
allowed-tools: Bash(bash *)
---

Run the yacch setup script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/yacch-setup.sh"
```

After it finishes, summarize what changed for the user:
- Whether settings.json was updated or already matched recommended values, and which backup was created (if any).
- Whether the agent-rules snippet was newly installed, already up to date, or upgraded to a new version, and which backup was created (if any).
