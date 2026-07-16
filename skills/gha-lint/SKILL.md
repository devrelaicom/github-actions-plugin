---
name: gha-lint
description: This skill should be used when the user asks to "lint this workflow", "check this GitHub Actions file for errors", "validate my workflow syntax", or "run actionlint". Runs actionlint against one or more workflow files and reports correctness/schema findings.
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
  needed).
- The script always prints a `Full output: <path>` line last, whether or
  not any issues were found — mention it as where to look for more detail
  than the capped list, but it's not itself a sign something went wrong on
  a clean pass.
- If the script prints `MISSING <tool>` (e.g. `MISSING actionlint` or
  `MISSING jq`), don't try to work around it — tell the user to run
  `/gha:doctor` (or invoke the `gha-doctor` skill) for the install command.
- If the script prints an `ERROR ...` line (a named file that doesn't
  exist, or actionlint itself failing to run), relay that line directly
  and stop — don't retry or improvise a workaround.

## Scale

If the repo has more than ~5 workflow files, or the user asked for a
full-repo pass, dispatch the `gha-auditor` agent instead of running
file-by-file in the main conversation (it runs lint/security/maintain
across every file and returns a condensed summary). If that agent isn't
available in this installation, fall back to running the script against
all files in one invocation.

## Security findings are a separate concern

`actionlint` checks correctness and schema, not security. If the user's
request is really about security (unpinned actions, `pull_request_target`
misuse, script injection, permissions), that's the `gha-security-audit`
skill's job (or `/gha:review`, which runs both lint and security together).
