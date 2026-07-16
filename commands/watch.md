---
description: Watch a GitHub Actions run live, analyze a finished run, or report CI health
argument-hint: "[run-id | 'health' | workflow name]"
allowed-tools: Bash, Read, Glob
---

Use the gha-monitor skill.

1. Preflight `gh auth status`; on failure tell the user to run
   `gh auth login` and stop.
2. Route by $ARGUMENTS:
   - a run id → if the run is in progress, live watch
     (`gh run watch <id> --exit-status`); if finished, analyze it via
     `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh view <id>`.
   - "health" (optionally plus a workflow name) → health report via
     `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh history [--workflow <name>]`.
   - nothing → show recent runs (`gh run list --limit 10`) and ask which
     to watch or analyze.
3. Interpret findings per the gha-monitor skill (flaky/chronically
   red/slow), don't just relay raw lines.
