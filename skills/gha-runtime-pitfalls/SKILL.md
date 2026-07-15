---
name: gha-runtime-pitfalls
description: This skill should be used when writing, editing, or reviewing GitHub Actions workflow files, especially before pushing one to a real runner for the first time. Provides a catalog of failure modes that pass local checks (actionlint, zizmor, wrkflw) and only surface on a live GitHub runner — gh CLI repo/token requirements, fork-PR token limits, pull_request_target evaluation, shell pipefail defaults, $GITHUB_OUTPUT and if-expression string semantics, checkout depth, API pagination, and concurrency cancellation. Other gha skills and agents that write or audit workflow content should reference this skill rather than re-deriving this knowledge.
---

# GitHub Actions Runtime Pitfalls

Failure modes that the local check loop — `actionlint`, `zizmor`, and
`wrkflw` local-run — **cannot** catch, because they depend on a real GitHub
runner's environment, tokens, or event context. A workflow can pass all three
checks and still die on its first live run.

**Curation principle:** only pitfalls the check loop cannot catch belong here.
If `actionlint` / `zizmor` / `wrkflw` already flags it, leave it out — this
catalog stays high-signal precisely because it does not repeat what the tools
already report. When creating or editing a workflow, check the content against
these while writing, not after the run fails.

## `gh` CLI in Actions

### No checkout → `gh` needs an explicit repo

`gh pr`, `gh issue`, `gh release`, etc. infer the target repo from the local
git remote. A job with **no checkout** — common and correct for
`pull_request_target` guards, which must never check out PR code — has no
remote, so the command fails with `fatal: not a git repository`.

Fix: pass `--repo "$REPO"` with `REPO: ${{ github.repository }}` in env, or set
a job-level `GH_REPO`. (`gh api` is exempt — the repo is already in its path.)

```yaml
- run: gh pr close "$PR" --repo "$REPO" --comment "…"
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    REPO: ${{ github.repository }}
    PR: ${{ github.event.pull_request.number }}
```

### `gh` always needs `GH_TOKEN`

`gh` is not auto-authenticated in Actions. Without a token it fails with
`To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment
variable`. Set `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` (or `${{ github.token }}`)
on the step or job.

### Fork PRs get a read-only token and no secrets

On a plain `pull_request` run triggered by a fork, `GITHUB_TOKEN` is read-only
and repository secrets are unavailable — so the run **cannot** comment on,
label, or close the PR. The "Resource not accessible by integration" error from
`gh pr comment` on org repos and fork PRs is this same boundary, not a bug or a
missing permission.

That — not carelessness — is when `pull_request_target` (with the no-checkout /
no-untrusted-interpolation discipline; see `gha-dangerous-patterns`) or a
`workflow_run` follow-up is the right trigger.

## Triggers & events

### `pull_request_target` runs from the base branch

The workflow YAML and any default checkout come from the **base** repo's
default branch, not from the PR. Editing the workflow inside a PR does not
change how that PR is evaluated — land the change on the default branch first,
then test.

### `on.<event>.paths` is a trigger gate, not an in-job filter

A `paths:` filter only decides whether the run *starts*; it does not restrict
what the job then sees. Don't reimplement it with an in-job "did any changed
file match" check unless that second signal is genuinely independent —
re-reading the same changed-file list via `GET /pulls/{n}/files` isn't defense
in depth, and that endpoint caps at 3000 files, so it can *miss* what the paths
filter already caught.

### `branch:` / `tag:` (singular) is silently ignored

The trigger keys are `branches:` and `tags:`. Writing `branch:` or `tag:`
(singular) is accepted as an unknown YAML key and the filter simply never
applies — the workflow triggers on everything. There is no error.

## Shell & data flow

### Default `bash` has `-e` but not `pipefail`

The default non-Windows shell runs as `bash -e {0}` — it does **not** enable
`pipefail`. A command that fails mid-pipe (`run_tests | tee log`) is masked by
the exit code of the *last* command in the pipe, so the step passes green while
the real work failed. Set `shell: bash` — GitHub then runs it as
`bash --noprofile --norc -eo pipefail {0}` — for any pipeline whose failure
matters.

### Multiline values into `$GITHUB_OUTPUT` / `$GITHUB_ENV` need a heredoc

A bare `key=value` write breaks on the first newline and is an injection
vector. Use a heredoc delimiter:

```bash
{
  echo "body<<EOF"
  echo "$MULTILINE"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
```

### Step outputs are strings

`if: steps.x.outputs.count != '0'` is a **string** comparison — there are no
numbers or booleans in output comparisons. Compare against the quoted string
form you actually emit.

### `if:` as a block scalar is always truthy

An `if:` written as a YAML block scalar (`if: |`) or with the `${{ }}` wrapped
in surrounding characters evaluates to a non-empty **string**, which is always
truthy — the step runs unconditionally regardless of the expression inside.
Keep `if:` as a plain scalar: `if: github.event_name == 'push'` (the `${{ }}`
is optional and, when present, must be the whole value).

## Checkout & API

### `actions/checkout` is depth-1 by default

The default fetch depth is 1 — a single commit, no tags, no history. Anything
needing history or tags (`git describe`, diffing against a base, `git log`
ranges) needs `fetch-depth: 0`.

### List endpoints truncate without `--paginate`

`gh api .../files` and similar list endpoints return ~30 items per page. For a
correctness-critical scan, always `--paginate` (and note the 3000-file cap on
`GET /pulls/{n}/files` still applies on top of pagination).

## Concurrency

### A `concurrency` group cancels by default, and queues at most one

By default a `concurrency` group **cancels** the superseded run rather than
queuing it. Even with `cancel-in-progress: false`, a group holds at most one
running plus one pending run — a third arrival evicts the pending one. If you
need every run to complete in order, a `concurrency` group is the wrong tool.
