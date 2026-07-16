---
description: Pin/update GitHub Actions, flag deprecations and cross-workflow drift; proposes a diff, never commits
argument-hint: "[workflow files, defaults to .github/workflows/*]"
allowed-tools: Bash, Glob, Read, Task, WebSearch
---

Use the gha-maintain skill to audit and maintain GitHub Actions workflows.

1. Determine targets: use $ARGUMENTS if given; otherwise Glob
   `.github/workflows/*.yml` and `.github/workflows/*.yaml`.
2. If there are more than ~5 workflow files, dispatch the `gha-auditor`
   agent for the read-only audit and relay its condensed summary; apply
   pins afterward (with confirmation) in the main conversation.
3. Otherwise run `${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh check <files>`
   and interpret per the gha-maintain skill (deprecations, drift,
   duplicated logic, unpinned actions).
4. If the user agrees to pin/update, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh pin <files>`, show
   `git diff -- <files>`, and stop. Never commit.

If the script prints `MISSING pinact`, point the user at /gha:doctor.
