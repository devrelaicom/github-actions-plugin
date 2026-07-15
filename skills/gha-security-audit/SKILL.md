---
name: gha-security-audit
description: This skill should be used when the user asks to "security review this workflow", "check this workflow for vulnerabilities", "run zizmor", "is this GitHub Actions file safe", "audit workflow permissions", or when /gha:review needs security findings. Runs zizmor security static analysis against workflow files and reports findings with file:line references.
version: 0.1.0
---

# gha Security Audit

Check GitHub Actions workflow files for security issues using `zizmor`, run
through `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh` rather than
invoking `zizmor` directly.

## Running the check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh <workflow-file> [...]`
via Bash, passing the workflow file(s) relevant to the request — if the
user didn't name one, use Glob to find `.github/workflows/*.yml` and
`*.yaml` in the current repo and pass all of them.

- **Clean files** print one line each: `<file>: zizmor OK (<N> lines,
  0 findings)`. Relay as-is.
- **Findings** print `zizmor found <count> finding(s):` followed by
  `  <level> <ruleId> <file>:<line> <message>` lines. Relay these directly
  and mention the `Full output: <path>` line (full SARIF) for drill-down.
- `MISSING zizmor` → tell the user to run `/gha:doctor` for the install
  command; don't work around it.

## Interpreting findings

Cross-reference the `gha-dangerous-patterns` skill — zizmor's rule ids map
onto its catalog:

| zizmor rule | gha-dangerous-patterns section |
|---|---|
| `dangerous-triggers` | `pull_request_target` with untrusted checkout |
| `template-injection` | Script injection via `${{ }}` in `run:` steps |
| `excessive-permissions` | Overbroad `GITHUB_TOKEN` permissions |
| `unpinned-uses` | Unpinned third-party actions |
| `artipacked`, `cache-poisoning` | Cache and artifact poisoning / credential persistence |

For each finding, explain the risk and give the concrete fix from the
catalog. Read the surrounding workflow context before suggesting a fix —
and never dismiss a finding as a false positive without having read the
workflow lines it points at.

## Scale

If the repo has more than ~5 workflow files, or the user asked for a
full-repo audit, dispatch the `gha-auditor` agent instead of running
file-by-file in the main conversation (it returns a condensed summary).
If that agent isn't available in this installation, fall back to running
the script against all files in one invocation.

## Correctness findings are a separate concern

`zizmor` checks security, not schema/syntax. For correctness (undefined
jobs, bad expressions), that's the `gha-lint` skill; `/gha:review` runs
both and consolidates.
