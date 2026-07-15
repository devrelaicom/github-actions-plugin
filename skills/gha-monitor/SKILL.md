---
name: gha-monitor
description: This skill should be used when the user asks to "watch this workflow run", "is my CI passing", "monitor the deploy", "why did that run fail", "show me the run logs", "which workflows are flaky", or "how healthy is our CI". Watches GitHub Actions runs live (foreground or background) and produces run-history health reports via gh.
version: 0.1.0
---

# gha Monitor

Watch GitHub Actions runs and analyze run history via `gh`. Three modes:
live watch, single-run log analysis, and history/health reporting. Set
`GH_REPO=owner/name` in the Bash environment to target a repo other than
the current directory's.

## Preflight

`gh auth status` must pass; otherwise tell the user to run
`gh auth login` and stop. `gh` missing → `/gha:doctor`.

## Live watch

- **Foreground** (user wants to follow along now):
  `gh run watch <run-id> --exit-status` via Bash. This streams compact
  status updates by design — it's the one gh call this plugin runs
  unwrapped despite being long-running, because buffering a live stream
  into a temp file would defeat watching. Exit code 0 = run succeeded,
  non-zero = run failed; report which.
- **Background** (user wants to keep working): if this harness provides a
  Monitor tool (or background Bash), run the same command in the
  background and report when it completes. Don't poll in a loop in the
  foreground — that burns context for no benefit.
- Watching mutates nothing, so no confirmation is needed. But if the user
  asks to *do* something to the run (cancel, rerun), that's the
  `gha-trigger` skill, with its confirmation rule.

## Analyzing a finished run

Run `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh view <run-id>` via Bash.
It prints the run's headline, one line per job, and — only when a job
failed — the last 40 lines of the failed steps' logs. Diagnose from the
excerpt; the `Full output: <path>` file has the complete log if the
excerpt isn't enough. Don't paste the full log into the conversation.

## Health report

Run `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh history [--workflow <name>] [--limit <n>]`
(default limit 30). It prints one aggregate line per workflow: run count,
successes, failures, average duration. Interpret, don't just relay:

- **Flaky**: a workflow with both successes and failures in the window,
  with no correlated change (check whether failures cluster before a fix
  landed vs alternate randomly — drill into specific runs with view mode).
- **Chronically red**: all/mostly failures — CI rot; propose fixing or
  removing the workflow.
- **Slow or degrading**: compare average durations across workflows and
  against what the team expects; for trends over time, run history twice
  with different limits and compare.

For anything suspicious, drill down: `view <run-id>` on a representative
failure, then propose the concrete fix (often a `gha-lint` /
`gha-security-audit` / `gha-maintain` follow-up).
