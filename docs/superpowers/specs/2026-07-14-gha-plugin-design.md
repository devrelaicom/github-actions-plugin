# gha: A Claude Code Plugin for GitHub Actions

Date: 2026-07-14
Status: Approved

## Purpose

A Claude Code plugin, namespaced `gha`, that covers the full lifecycle of GitHub
Actions workflows: creating them through a guided brainstorming flow, reviewing
them for correctness and security, running them locally, keeping them
up to date, and triggering/monitoring runs on GitHub — all from inside Claude
Code.

This repository (`github-actions-plugin`) *is* the plugin. It will be published
publicly for other Claude Code users (Claude Code only — no cross-harness
packaging for Cursor/Codex/Gemini in v1).

## Scope

**In scope:**
- Creating and modifying GitHub Actions **workflows** (`.github/workflows/*.yml`)
  via a guided command.
- Linting and security-reviewing existing workflows.
- Running workflows locally without pushing.
- Keeping actions pinned/current and flagging deprecated patterns.
- Triggering, watching, and analyzing the health of workflow runs on GitHub.
- Checking that required local tooling is installed, and telling the user
  how to fix gaps.

**Out of scope (v1):**
- Authoring reusable custom actions (composite/JavaScript/Docker `action.yml`)
  meant for publishing/sharing. Only workflow files are covered.
- Auto-installing missing tooling. The doctor skill reports gaps and prints
  the install command; the user runs it themselves.
- Cross-harness packaging (Cursor/Codex/Gemini/etc).
- Automated CI test suite for the plugin itself (skills are instructions, not
  code — see Testing section).

## Tooling this plugin wraps

| Tool | Purpose | Notes |
|---|---|---|
| `gh` | All GitHub API access (auth, PRs, runs, dispatch) | Reuses the user's existing `gh auth login` session. The plugin never handles credentials directly. |
| `actionlint` | Workflow syntax/schema correctness and style | Has a JSON output mode; preferred over scraping text output. |
| `wrkflw` | Local execution of workflows without requiring Docker/Podman | Chosen over `act` specifically to avoid the Docker-running requirement — a nicer default UX. Falls back to container mode if Docker/Podman happen to be available and needed. |
| `zizmor` | Security static analysis (unpinned actions, `pull_request_target` misuse, script injection, overbroad permissions) | Emits SARIF; offline-first. |
| `pinact` | Pin actions/reusable workflows to full-length commit SHAs, verify/update version comments | Used by the maintain skill for SHA pinning and version bumps. |

## Architecture

### Commands (`commands/`)

Each command is a thin, discoverable entry point that invokes one or more
skills. All of them exist as skills too, so Claude can also reach them from
natural language without the user typing the slash command.

| Command | Wraps | Behavior |
|---|---|---|
| `/gha:brainstorming` | orchestrates everything below | Guided creation/modification flow (see below) |
| `/gha:review` | `gha-lint` + `gha-security-audit` | Lint + security findings, consolidated, file:line |
| `/gha:maintain` | `gha-maintain` | Pin/update actions, deprecation/EOL scan, cross-workflow drift audit; proposes a diff, doesn't auto-commit |
| `/gha:test` | `gha-local-run` | Runs a workflow/job locally via `wrkflw` |
| `/gha:trigger` | `gha-trigger` | `gh workflow run` (with input prompting) / `gh run rerun` / `gh run cancel` |
| `/gha:watch` | `gha-monitor` | Live watch of a run (foreground or background via the Monitor tool) or a historical health report |
| `/gha:doctor` | `gha-doctor` | Reports which of `gh`/`actionlint`/`wrkflw`/`zizmor`/`pinact` are missing, with install commands |

### Skills (`skills/`)

| Skill | Type | Responsibility |
|---|---|---|
| `gha-lint` | action | Run `actionlint`, parse JSON output into findings |
| `gha-security-audit` | action | Run `zizmor`, parse SARIF into findings, cross-reference `gha-dangerous-patterns` |
| `gha-maintain` | action | Run `pinact` for SHA pinning/version bumps; scan for deprecated runners/actions/EOL toolchains; audit multiple workflow files for drift (inconsistent versions, duplicated logic that should be a reusable workflow) |
| `gha-local-run` | action | Run a workflow/job via `wrkflw`; troubleshooting matrix for common failures |
| `gha-trigger` | action | Dispatch/rerun/cancel runs via `gh` |
| `gha-monitor` | action | Live watch (incl. Monitor-tool-backed background tracking) + run history/health trends (flaky jobs, rising durations) |
| `gha-doctor` | action | Presence/version checks for the five tools above; never installs anything itself |
| `gha-dangerous-patterns` | knowledge | Catalog of GH Actions security anti-patterns: `pull_request_target` combined with untrusted PR-head checkout, script injection via `${{ }}` interpolation in `run:` steps, overbroad `GITHUB_TOKEN` permissions, unpinned third-party actions, cache/artifact poisoning. No standalone action — every skill that touches workflow content (`gha-security-audit`, `gha-maintain`, `gha-creator`, `gha-auditor`) cross-references it, so the same knowledge applies whether or not a subagent is involved. |

### Subagents (`agents/`)

| Subagent | Dispatched by | Purpose |
|---|---|---|
| `gha-creator` | `/gha:brainstorming`, once the implementation plan is approved | Writes/edits workflow YAML, loops `gha-lint` → `gha-security-audit` → `gha-local-run` until clean. Auto-loads `gha-dangerous-patterns`. Keeps the iterative fix loop out of the main conversation. |
| `gha-auditor` | `/gha:review` and `/gha:maintain`, when a repo has many workflow files or a full-repo audit is requested | Runs lint/security/maintain checks across all workflow files, returns a condensed findings summary rather than raw per-file output. Auto-loads `gha-dangerous-patterns`. |

## `/gha:brainstorming` flow

Adapted from `superpowers:brainstorming`, simplified because a workflow is
much smaller in scope than a typical software project — no separate formal
spec-doc stage.

1. Explore repo context: existing workflows, project language/tooling, CI
   conventions already in use.
2. Ask clarifying questions one at a time: trigger events, what should
   pass/fail the workflow, secrets/environments needed, runner choice.
3. Research current best practices (e.g. current major version of a relevant
   marketplace action) via WebSearch/Rover.
4. Propose 2-3 approaches with trade-offs and a recommendation.
5. Present a short inline design summary (trigger, jobs, key decisions) in
   chat — not a committed spec file — and get approval.
6. Invoke `writing-plans` for an implementation plan.
7. On plan approval, dispatch to `gha-creator`: writes the workflow YAML,
   loops lint → security → local-run (`wrkflw`) until clean.
8. **Stop and get explicit user confirmation before push, PR creation, or
   triggering any run.** Nothing is pushed automatically once the local loop
   is clean.
9. Once confirmed: push, open a PR, trigger/watch the first real run via
   `gha-trigger`/`gha-monitor`, report pass/fail.
10. Stop again and get explicit confirmation before merging. The plugin never
    merges on its own.

## Data flow

- `gh` is the only path to the GitHub API; it reuses the user's existing
  `gh auth login` session.
- Local tools are invoked via Bash, preferring structured output
  (`actionlint -format '{{json .}}'`, zizmor's SARIF) over text-scraping.
- Every tool-using skill preflights that its tool is present before shelling
  out. On failure, it names the missing tool and points to `/gha:doctor`
  rather than surfacing a raw "command not found."

## Error handling & safety

- Missing tool → name it, point to `/gha:doctor` (which prints but never runs
  the install command).
- `gh` not authenticated → detected via `gh auth status`; user is told to run
  `gh auth login`. The plugin never touches tokens directly.
- `wrkflw` failures get a small known-issues matrix (missing secrets/env
  values, expression-evaluation edge cases, emulation-mode limitations for
  actions that assume a full container environment).
- Any action that pushes, opens a PR, triggers a run, cancels/reruns a run
  that isn't the user's own, or merges requires an explicit confirmation
  step. This is stated in the relevant skill itself (not left to default
  harness behavior alone), so it holds even when a skill is invoked directly
  rather than through `/gha:brainstorming`.

## Testing (of the plugin itself)

- Structural validation via the existing `plugin-dev:plugin-validator` agent
  (manifest correctness, frontmatter on every skill/command/agent).
- A `tests/fixtures/` directory with sample workflow files: one clean, one
  with known `actionlint` errors, one with known `zizmor` findings (unpinned
  action, `pull_request_target` + untrusted checkout). Used to manually
  verify each skill produces the expected findings during development.
- No automated CI test suite in v1 — skills are instructions, not code.
  Verification is manual smoke-testing against the fixtures plus a real
  scratch repo, tracked as a checklist during implementation.
