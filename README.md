# gha

A Claude Code plugin for the full GitHub Actions workflow lifecycle:
creating workflows through a guided brainstorming flow, reviewing them
for correctness and security, running them locally, keeping them
current, and triggering and monitoring runs on GitHub — all from inside
Claude Code.

## Install

```
/plugin marketplace add devrelaicom/github-actions-plugin
/plugin install gha
```

## Commands

| Command | What it does |
|---|---|
| `/gha:brainstorming` | Guided workflow creation/modification: clarify → design → verify locally → (with your confirmation) push, run, watch |
| `/gha:review` | Lint (`actionlint`) + security review (`zizmor`), consolidated with file:line findings |
| `/gha:maintain` | SHA-pin and update actions (`pinact`), flag deprecated runners/actions, audit cross-workflow drift; proposes a diff, never commits |
| `/gha:test` | Run a workflow locally via `wrkflw` — no push, no Docker required |
| `/gha:trigger` | Dispatch, rerun, or cancel runs on GitHub (always confirms first) |
| `/gha:watch` | Watch a run live, analyze a failed run's logs, or get a CI health report |
| `/gha:doctor` | Check that all required tools are installed; prints install commands, never installs |

Every command also works from natural language ("lint this workflow",
"is my CI flaky", "pin my actions") — the commands are thin entry points
over skills.

## Required tooling

`gh` (authenticated), `actionlint`, `wrkflw`, `zizmor`, `pinact`, and
`jq`. Run `/gha:doctor` to see what's missing and how to install it —
the plugin never installs anything itself, and `gh` is its only path to
the GitHub API (your existing `gh auth login` session; no credentials
are ever handled directly).

## Safety model

Anything that leaves your machine — push, PR, triggering/cancelling
runs, merge — requires your explicit confirmation at the moment it
happens. Analysis tools write their full output to temp files and
surface compact summaries, so you can always drill into the raw output.

## Design & plans

- Design: `docs/superpowers/specs/2026-07-14-gha-plugin-design.md`
- Implementation plans: `docs/superpowers/plans/`
