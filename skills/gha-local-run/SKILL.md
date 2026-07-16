---
name: gha-local-run
description: This skill should be used when the user asks to "run this workflow locally", "test my GitHub Actions without pushing", "run wrkflw", "dry-run this workflow", or "check if this workflow works before I push". Executes a workflow locally via wrkflw (emulation mode by default, container mode optional) and interprets failures with a troubleshooting matrix.
---

# gha Local Run

Run a GitHub Actions workflow locally without pushing, using `wrkflw`
through `${CLAUDE_PLUGIN_ROOT}/scripts/local-run.sh` rather than invoking
`wrkflw` directly.

## Running a workflow

Pick the target first: use the workflow file the user named. If they didn't
name one, `Glob` `.github/workflows/*.yml` and `*.yaml` — if there's exactly
one, use it; if there are several, list them and ask which to run rather than
guessing.

Run `${CLAUDE_PLUGIN_ROOT}/scripts/local-run.sh <workflow-file>` via Bash.
The script defaults to wrkflw's **emulation mode** (no Docker/Podman
required). To use container mode instead (needed for workflows that
depend on a real container environment), pass it through:
`local-run.sh <file> --runtime docker` (or `podman`).

- `PASSED` → relay the one-line summary as-is.
- `FAILED` → the summary includes the last 40 log lines; diagnose with
  the matrix below before showing the user a wall of log text. The
  `Full output: <path>` line has the complete log for drill-down.
- `MISSING wrkflw` → point the user to `/gha:doctor`.

The wrapper always exits `0` once the run has happened — a FAILED workflow
is a result, not a script error — so read PASSED vs FAILED from the summary
text, not from the exit code.

## Troubleshooting matrix

| Symptom in the log | Likely cause | What to do |
|---|---|---|
| Empty value where `${{ secrets.X }}` is used, or "secret not found" | wrkflw has no access to repo secrets | Provide the value as a plain env var in a local copy of the workflow for the test run, or export it in the environment if wrkflw supports env passthrough (`wrkflw run --help`). Never paste real production secrets into the workflow file. |
| An expression (`${{ }}`) evaluates differently than on GitHub, or errors | wrkflw's expression evaluator doesn't cover every GitHub function/context | Simplify the expression, or accept that this particular check needs a real run on GitHub (`/gha:trigger` after push). |
| A `uses:` action fails to resolve, or behaves oddly | Emulation mode doesn't fully replicate the action runtime (Node version, container features) | Retry with `--runtime docker` if Docker/Podman is available; otherwise note the emulation limitation and validate that step on GitHub. |
| `services:`, `container:`, or Docker-dependent steps fail | Emulation mode has no container engine | This workflow genuinely needs container mode: `--runtime docker`. If no container engine exists on this machine, the workflow can't be fully tested locally — say so plainly. |
| Workflow fails immediately on a `needs:`/structure error | The workflow is invalid, not the runner | Run the `gha-lint` skill first; fix correctness before re-running locally. |

## What local success means

A local PASS is strong evidence, not proof — secrets, GitHub-hosted
runner images, and marketplace action behavior can still differ. The
full confidence chain is lint → security-audit → local run → first real
run on GitHub (via `gha-trigger`/`gha-monitor`).
