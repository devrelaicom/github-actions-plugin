---
description: Run a GitHub Actions workflow locally via wrkflw (no push needed)
argument-hint: "<workflow-file> [--runtime docker|podman]"
allowed-tools: Bash, Glob, Read
---

Use the gha-local-run skill to run a workflow locally.

1. Target: $ARGUMENTS if given. If not given and the repo has exactly one
   workflow file, use it; if several, list them and ask which to run.
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/local-run.sh <file>` (append any
   extra args the user provided, e.g. `--runtime docker`).
3. Relay PASSED one-liners as-is. For FAILED, diagnose using the
   gha-local-run skill's troubleshooting matrix before dumping log lines.

If the script prints `MISSING wrkflw`, point the user at /gha:doctor.
