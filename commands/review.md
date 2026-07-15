---
description: Lint and security-review GitHub Actions workflows (actionlint + zizmor), consolidated
argument-hint: "[workflow files, defaults to .github/workflows/*]"
allowed-tools: Bash, Glob, Read, Task
---

Review GitHub Actions workflow files for correctness and security, using
the gha-lint and gha-security-audit skills together.

1. Determine targets: use $ARGUMENTS if given; otherwise Glob
   `.github/workflows/*.yml` and `.github/workflows/*.yaml`.
2. If there are more than ~5 workflow files, dispatch the `gha-auditor`
   agent with the file list and relay its condensed summary instead of
   steps 3-5.
3. Run `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh <files>` via Bash.
4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh <files>` via Bash.
5. Present one consolidated report: correctness findings first, then
   security findings, each as `file:line — what and why`, with the fix.
   Note both scripts' `Full output:` temp-file paths at the end.

If either script prints `MISSING <tool>`, stop and point the user at
/gha:doctor. Do not install anything.
