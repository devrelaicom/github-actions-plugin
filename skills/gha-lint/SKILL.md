---
name: gha-lint
description: This skill should be used when the user asks to "lint this workflow", "check this GitHub Actions file for errors", "validate my workflow syntax", "run actionlint", or is editing a file under .github/workflows/. Runs actionlint against one or more workflow files and reports correctness/schema findings.
version: 0.1.0
---

# gha Lint

Check GitHub Actions workflow files for syntax and schema correctness using
`actionlint`, run through `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh` rather than
invoking `actionlint` directly.

## Running the check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh <workflow-file> [<workflow-file> ...]`
via Bash, passing the specific workflow file(s) relevant to the request — if
the user didn't name one, use `Glob` to find `.github/workflows/*.yml` and
`*.yaml` in the current repo and pass all of them.

The script's own summary is already the right level of detail to relay:

- **Clean files** print one line each: `<file>: actionlint OK (<N> lines, 0 issues)`.
  Relay this as-is — there's no need to say more for a clean pass.
- **Files with findings** produce a `actionlint found <count> issue(s):`
  header followed by `  <filepath>:<line>:<column> <message>` lines. Relay
  these findings directly (they're already file:line, no reformatting
  needed), and mention the `Full output: <path>` line so the user can open
  the raw JSON if they want more than the capped list.
- If the script prints `MISSING actionlint`, don't try to work around it —
  tell the user to run `/gha:doctor` (or invoke the `gha-doctor` skill) for
  the install command.

## Security findings are a separate concern

`actionlint` checks correctness and schema, not security. If the user's
request is really about security (unpinned actions, `pull_request_target`
misuse, script injection, permissions), that's the `gha-security-audit`
skill's job (a later plan) — cross-reference the `gha-dangerous-patterns`
skill's catalog in the meantime if `gha-security-audit` isn't available yet
in this installation.
