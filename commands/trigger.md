---
description: Trigger, rerun, or cancel a GitHub Actions run (with confirmation)
argument-hint: "<workflow-file | run-id> [inputs...]"
allowed-tools: Bash, Read, Glob, AskUserQuestion
---

Use the gha-trigger skill to dispatch, rerun, or cancel GitHub Actions
runs via gh.

1. Preflight `gh auth status`; on failure tell the user to run
   `gh auth login` and stop.
2. Work out the intent from $ARGUMENTS: a workflow file (or name) means
   dispatch; a run id plus "rerun"/"cancel" wording means that operation.
   Ambiguous → ask.
3. For dispatch, read the workflow's `workflow_dispatch` inputs and
   prompt for values per the gha-trigger skill.
4. **Confirm the exact gh command with the user before running it.**
5. After a dispatch, report the new run id and offer /gha:watch.
