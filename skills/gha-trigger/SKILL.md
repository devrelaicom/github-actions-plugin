---
name: gha-trigger
description: This skill should be used when the user asks to "trigger this workflow", "run the deploy workflow on GitHub", "dispatch a workflow", "rerun that failed run", "rerun failed jobs", or "cancel that run". Dispatches, reruns, and cancels GitHub Actions runs via gh, with input prompting for workflow_dispatch and an explicit confirmation before every mutating call.
version: 0.1.0
---

# gha Trigger

Dispatch, rerun, and cancel GitHub Actions runs via `gh`. These calls
produce a handful of lines at most, so they run directly through Bash —
no wrapper script (the spec's context-budget concern doesn't apply).

## Preflight

Run `gh auth status` first (Bash). If it fails, tell the user to run
`gh auth login` themselves and stop — this plugin never handles
credentials. If `gh` isn't installed, point to `/gha:doctor`.

## Confirmation is not optional

**Every mutating call below — dispatch, rerun, cancel — needs the user's
explicit confirmation immediately before it runs**, stating exactly what
will be executed (the full `gh` command and what it affects). This holds
even when this skill is reached from another flow (e.g. gha-brainstorming)
that already got a broad go-ahead: confirm the specific run action anyway.
For cancel/rerun of a run the user didn't start (someone else's run on a
shared repo), point that out during confirmation.

## Dispatching a workflow (`workflow_dispatch`)

1. Identify the workflow file. Read its `on.workflow_dispatch.inputs`
   block (Read tool). If the workflow has no `workflow_dispatch` trigger,
   say so — `gh workflow run` can't dispatch it; offer to add the trigger
   instead (that's a workflow edit → gha-brainstorming / gha-creator
   territory).
2. For each defined input, collect a value from the user (AskUserQuestion
   works well: required inputs first, defaults shown). Skip prompting for
   inputs the user already gave.
3. Confirm, then run:
   `gh workflow run <workflow-file-name> [--ref <branch>] -f key=value ...`
4. Find the new run's id (dispatch is async; retry once after a few
   seconds if empty):
   `gh run list --workflow <workflow-file-name> --limit 1 --json databaseId,status --jq '.[0]'`
5. Offer to watch it via the `gha-monitor` skill (`/gha:watch`).

## Rerunning

- Whole run: `gh run rerun <run-id>`
- Only failed jobs: `gh run rerun <run-id> --failed`
Confirm first, showing which run (fetch its title with
`gh run view <run-id> --json displayTitle,workflowName,conclusion --jq
'"\(.workflowName): \(.displayTitle) (\(.conclusion))"'`).

## Cancelling

`gh run cancel <run-id>` — confirm first, same identification as above.
A completed run can't be cancelled; check `status` and say so instead of
running a command that will error.
