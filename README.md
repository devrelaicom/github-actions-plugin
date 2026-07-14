# gha

A Claude Code plugin for the full GitHub Actions workflow lifecycle: creating
workflows through a guided brainstorming flow, reviewing them for correctness
and security, running them locally, keeping them current, and triggering and
monitoring runs on GitHub — all from inside Claude Code.

## Install

```
/plugin marketplace add devrelaicom/github-actions-plugin
/plugin install gha
```

## What's here (so far)

- `/gha:doctor` — checks that `gh`, `actionlint`, `wrkflw`, `zizmor`, `pinact`,
  and `jq` are installed, and prints the install command for anything
  missing. Never installs anything itself.
- `gha-lint` — lints workflow files with `actionlint` (triggered by natural
  language, e.g. "lint this workflow" — no slash command yet).
- `gha-dangerous-patterns` — a knowledge skill cataloguing GitHub Actions
  security anti-patterns, referenced by every skill that touches workflow
  content.

More commands and skills (`/gha:review`, `/gha:maintain`, `/gha:test`,
`/gha:trigger`, `/gha:watch`, `/gha:brainstorming`) are on the way — see
`docs/superpowers/specs/2026-07-14-gha-plugin-design.md` for the full design.

## Design & plans

- Design: `docs/superpowers/specs/2026-07-14-gha-plugin-design.md`
- Implementation plans: `docs/superpowers/plans/`