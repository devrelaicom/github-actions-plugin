# gha-runtime-pitfalls skill — design

**Date:** 2026-07-15
**Folds in:** [devrelaicom/github-actions-plugin#2](https://github.com/devrelaicom/github-actions-plugin/issues/2)
— "Add a *Pitfalls the check loop won't catch* section to gha-creator agent"

## Problem

The `gha-creator` verification loop (`actionlint` → `zizmor` → `wrkflw`
local-run) catches schema, security, and many logic errors. But a distinct
class of bug **passes all three and only fails on a real GitHub runner** —
e.g. a `pull_request_target` guard that calls `gh pr close` from a job with
no checkout, which fails with `fatal: not a git repository` because `gh` has
no remote to infer the repo from.

The issue proposes documenting these directly inside `agents/gha-creator.md`.
The maintainer's decision instead: extract them into a **reference-knowledge
skill** the agent autoloads (the same way it already reads
`gha-dangerous-patterns`), so the knowledge isn't baked into one agent and can
be shared by the review/audit path too.

## Curation principle (load-bearing)

**Only include pitfalls the local check loop cannot catch.** If
`actionlint`, `zizmor`, or `wrkflw` already flags it, leave it out. This is
what keeps the catalog high-signal and prevents it from bloating into a
general GitHub Actions tutorial.

## What we build

A new reference skill — **not** an executable script-wrapper skill — modeled
on `skills/gha-dangerous-patterns/SKILL.md` (prose catalog, read-and-apply,
no script, no test).

- **Path:** `skills/gha-runtime-pitfalls/SKILL.md`
- **Name:** `gha-runtime-pitfalls`
- **Frontmatter `description`:** written so it triggers when writing/editing
  a workflow AND is discoverable on its own, and states that other gha
  skills/agents should reference it rather than re-derive the knowledge
  (mirrors the dangerous-patterns description's closing sentence).

### Catalog contents

Each entry: one-line symptom → why the check loop misses it → the fix, in the
same clipped style as `gha-dangerous-patterns`. Grouped for scannability:

1. **`gh` CLI in Actions**
   - `gh pr`/`issue`/`release` with **no checkout** needs explicit `--repo
     "$REPO"` (`REPO: ${{ github.repository }}`) or job-level `GH_REPO`;
     otherwise `not a git repository`. (`gh api` is exempt — repo is in the
     path.) *(issue — the originating bug)*
   - `gh` always needs `GH_TOKEN` in env; it is not auto-provided. *(issue)*
   - Fork PRs get a read-only token and no secrets — a plain `pull_request`
     run can't comment on / label / close a fork PR; that's when
     `pull_request_target` (no checkout, no untrusted interpolation) or a
     `workflow_run` follow-up is correct. *(issue)*
   - "Resource not accessible by integration" from `gh pr comment` on org
     repos / fork PRs is the same read-only-token boundary, not a bug.
     *(research)*

2. **Triggers & events**
   - `pull_request_target` runs the workflow from the **base** branch — the
     YAML and default checkout come from the base repo's default branch, not
     the PR. Land workflow changes on the default branch before testing.
     *(issue)*
   - `on.<event>.paths` is a trigger gate, not an in-job filter — it decides
     whether the run *starts*, not what the job sees. Don't re-implement it
     with a `GET /pulls/{n}/files` scan (which caps at 3000 files and can
     *miss* what the paths filter caught) unless the second signal is
     genuinely independent. *(issue)*
   - `branch:` / `tag:` (singular) instead of `branches:` / `tags:` is
     silently ignored — YAML accepts the unknown key and the filter never
     applies. *(research)*

3. **Shell & data flow**
   - The default `bash` runs with `-e` but **not** `pipefail` — a failing
     command mid-pipe (`tests | tee`) is masked by the last command's exit
     code. Set `shell: bash` (which adds `-o pipefail`) for any pipeline
     whose failure matters. *(research)*
   - Multiline values into `$GITHUB_OUTPUT`/`$GITHUB_ENV` need a heredoc
     delimiter (`{name}<<EOF … EOF`), not `key=value`; a bare newline breaks
     parsing and is an injection vector. *(issue)*
   - Step outputs are **strings** — `if: steps.x.outputs.n != '0'` compares
     text; there are no numbers or booleans in output comparisons. *(issue)*
   - `if:` written as a YAML block scalar (`if: |`) or with the `${{ }}`
     wrapped in extra characters becomes a non-empty string → always truthy →
     the step always runs. *(research)*

4. **Checkout & API**
   - `actions/checkout` fetches depth 1 by default — `git describe`, base
     diffs, and `git log` ranges need `fetch-depth: 0`. *(issue)*
   - List endpoints truncate to ~30 items without `--paginate` (`gh api
     .../files` etc.); correctness-critical scans must paginate (and the
     3000-file cap still applies). *(issue)*

5. **Concurrency**
   - A `concurrency` group **cancels** superseded runs by default rather than
     queuing them, and allows at most one running + one pending run per group
     — so `cancel-in-progress: false` still won't give you a full queue.
     *(research)*

## Wiring ("autoload")

1. `agents/gha-creator.md` — "Before writing", add a step to `Read
   ${CLAUDE_PLUGIN_ROOT}/skills/gha-runtime-pitfalls/SKILL.md` and apply it
   while writing (parallel to the existing dangerous-patterns step 1).
2. `agents/gha-auditor.md` — "Process", add the same skill to the reference
   read so the audit flags these in existing workflows.
3. `skills/gha-dangerous-patterns/SKILL.md` — add a short cross-link pointer
   to `gha-runtime-pitfalls` for the security-overlapping pitfalls (fork
   token, heredoc injection), so neither catalog is siloed.

## Out of scope / non-goals

- **No new `/gha:*` command.** This is agent-consumed reference knowledge with
  no user-facing entry point, like `gha-dangerous-patterns`.
- **No script, no test.** Prose reference skill; nothing executable to unit
  test. Verification = agent read-lines resolve to the right path and the
  frontmatter is well-formed (consistent with dangerous-patterns having no
  test).
- **No README command-table change** (README lists commands, not skills).

## Sources (research beyond the issue)

- Default `bash` lacks `pipefail`: actions/runner#1955, runner-images#4459.
- `if:` block-scalar truthiness & `branch:`/`branches:` typo: htek.dev GitHub
  Actions debugging guide.
- `gh` `GH_TOKEN` / "Resource not accessible by integration": cli/cli#9253,
  cli/cli#10464, cli/cli#8374.
- Concurrency cancels-by-default, 1-running-1-pending: GitHub Docs "Control
  the concurrency of workflows and jobs"; community#26566.
