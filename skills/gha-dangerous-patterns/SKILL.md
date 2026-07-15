---
name: gha-dangerous-patterns
description: This skill should be used when writing, editing, or reviewing GitHub Actions workflow files, or when asked to "check for security issues in this workflow", "is this workflow safe", "review this action for vulnerabilities", or "what's wrong with this workflow's permissions". Provides a catalog of known GitHub Actions security anti-patterns to check for. Other gha skills and agents that touch workflow content should reference this skill rather than re-deriving this knowledge.
---

# GitHub Actions Security Anti-Patterns

Check workflow content against the anti-patterns below whenever creating,
editing, or reviewing a `.github/workflows/*.yml` file. This is reference
knowledge, not an executable check — the `gha-security-audit` skill runs
`zizmor` for automated detection; this skill exists so the same knowledge
is available even when `zizmor` isn't run, e.g. while `gha-creator` is
drafting a new workflow.

The companion `gha-runtime-pitfalls` skill covers failure modes that pass
every static check and only surface on a live runner. Some of them carry a
security dimension this catalog also cares about — a fork PR's read-only
token (which pushes people toward `pull_request_target`, governed by the
untrusted-checkout pattern below) and `$GITHUB_OUTPUT`/`$GITHUB_ENV` heredoc
handling (a `${{ }}`-adjacent injection surface). Read that skill too when
writing or auditing a workflow.

## `pull_request_target` with untrusted checkout

`pull_request_target` runs with the base repo's permissions and secrets,
even for PRs from forks. If a step then checks out the PR's head ref
(`actions/checkout@vX` with `ref: ${{ github.event.pull_request.head.sha }}`
or similar) and later runs code from that checkout, a malicious fork PR can
execute arbitrary code with access to the base repo's secrets.

Flag: `on: pull_request_target` combined with any checkout of
`github.event.pull_request.head.*` followed by running that checked-out
code (build scripts, `npm install` with lifecycle scripts, etc).

Prefer `pull_request` (safe by default, runs with fork permissions) unless
there's a specific need for base-repo secrets — and if there is, avoid
checking out or executing untrusted head content at all.

## Script injection via `${{ }}` in `run:` steps

Interpolating untrusted context values directly into a `run:` shell script
lets an attacker inject shell commands. Untrusted values include
`github.event.issue.title`, `github.event.pull_request.title`,
`github.event.comment.body`, `github.head_ref`, and similar user-controlled
fields.

Flag: any `run:` step with `${{ github.event.* }}` or `${{ github.head_ref }}`
interpolated directly into the script body.

Fix: pass the value through an environment variable instead, so the shell
never sees it as literal script text:

```yaml
- run: echo "$TITLE"
  env:
    TITLE: ${{ github.event.issue.title }}
```

## Overbroad `GITHUB_TOKEN` permissions

The default `GITHUB_TOKEN` permissions vary by repo setting, and a workflow
that doesn't declare `permissions:` explicitly can end up with far more
access than it needs (e.g. write access to contents, issues, and PRs for a
job that only needs to read).

Flag: a workflow or job with no `permissions:` block, or a `permissions:`
block broader than the job actually uses.

Fix: set `permissions: {}` at the workflow level and grant only what each
job needs at the job level, e.g. `permissions: { contents: read }`.

## Unpinned third-party actions

An action referenced by a mutable tag (`uses: some/action@v1` or `@main`)
can change behavior — maliciously or accidentally — without the workflow
file changing. Only a full-length commit SHA is immutable.

Flag: any `uses:` referencing a non-SHA ref for a third-party (non-`actions/*`,
non same-org) action.

Fix: pin to the full commit SHA with the human-readable version as a
trailing comment (`uses: some/action@<40-char-sha> # v1.2.3`) — this is
what the `pinact` tool (via `gha-maintain`) automates.

## Cache and artifact poisoning

Build caches and uploaded artifacts are sometimes restored or consumed by
later, more-privileged jobs or workflows (e.g. a `pull_request` job uploads
an artifact that a privileged `workflow_run` job later downloads and
executes). If the producing job runs untrusted code, the artifact/cache can
carry a payload into the privileged context.

Flag: a workflow that downloads an artifact or restores a cache produced by
a job triggered from a less-trusted context (fork PRs) and then executes
its contents (runs a script from it, `source`s it, installs it) in a more
privileged context.

Fix: treat artifacts/caches crossing a trust boundary as untrusted input —
validate or re-verify before executing anything from them, or avoid the
cross-boundary handoff entirely.
