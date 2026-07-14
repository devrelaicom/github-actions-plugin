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
- A CI pipeline that runs on every push to this repo (see Testing section) —
  the wrapper scripts get their own lightweight local test harness instead.

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

### Scripts (`scripts/`)

Every skill that shells out to an external tool does so through a small
wrapper script, rather than invoking the raw tool directly from the skill's
instructions. This exists purely to protect the agent's context budget:
`actionlint`, `zizmor`, `wrkflw`, `pinact`, and `gh` can all produce output
ranging from nothing (clean pass) to hundreds of lines (many findings, or a
verbose log). Skills should not be the layer that decides how to compress
that.

Each wrapper script:
1. Runs the underlying tool against the given target(s).
2. Writes the full, unfiltered output to a file in the OS temp directory
   (a fresh path per invocation) and prints that path.
3. Parses the same output into a compact result and prints that instead of
   letting the raw output reach the agent.
   - **Happy path** is a single line: what ran, against what, and the
     headline numbers — e.g. `ci.yml: actionlint OK (147 lines, 0 warnings,
     0 errors)`. Enough for the agent to sense-check that linting actually
     happened, against the right file, and the file wasn't empty — without
     paying for a wall of "no issues" output.
   - **Non-happy path** prints a compact findings list (rule, file:line,
     one-line message), capped at a reasonable count, plus a note of how
     many more are in the raw file if truncated.
4. Exits non-zero only for actual execution failure (tool crashed, file not
   found) — findings/warnings are reported in the summary, not via exit code,
   so skills can distinguish "the tool couldn't run" from "the tool ran and
   found problems."

| Script | Wraps | Used by |
|---|---|---|
| `scripts/lint.sh` | `actionlint` | `gha-lint` |
| `scripts/security-audit.sh` | `zizmor` | `gha-security-audit` |
| `scripts/local-run.sh` | `wrkflw` | `gha-local-run` |
| `scripts/maintain.sh` | `pinact` + deprecation/drift checks | `gha-maintain` |
| `scripts/doctor.sh` | presence/version checks for all five tools | `gha-doctor` |
| `scripts/gh-run-log.sh` | `gh run view --log` / `gh run watch` | `gha-monitor` (only where log volume is a concern — simple dispatch/cancel calls in `gha-trigger` don't need wrapping) |

Skills call these scripts via Bash and read only the compact summary; the
temp file path is there for the agent (or the user) to drill in only when
something looks wrong.

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
- Local tools are invoked exclusively through the wrapper scripts described
  above, never directly from a skill — this is what keeps the happy path to
  one line of context per tool call instead of a full dump. Scripts prefer
  structured tool output internally (`actionlint -format '{{json .}}'`,
  zizmor's SARIF) as the thing they parse, but that's an implementation
  detail of the script, not something a skill or the agent ever sees raw.
- Every wrapper script preflights that its tool is present before shelling
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
  action, `pull_request_target` + untrusted checkout). Used by both automated
  and manual checks below.
- The wrapper scripts in `scripts/` are actual code, so they get a
  lightweight automated smoke test each (a plain shell test, run manually
  during implementation and re-run before any script change is considered
  done): run the script against the fixtures and assert the happy-path
  fixture produces the single-line OK summary, and the bad fixtures produce
  the expected compact findings with a valid temp-file path. No CI pipeline
  wired up for this in v1 (see Scope) — it's a local dev-time check.
- Skills and commands themselves (markdown instructions, not code) remain
  manually smoke-tested against the fixtures plus a real scratch repo,
  tracked as a checklist during implementation.
