---
name: gha-maintain
description: This skill should be used when the user asks to "pin my actions", "SHA-pin this workflow", "update action versions", "are my workflows using deprecated actions or runners", "check for outdated actions", or "audit my workflows for drift". Runs pinact through a wrapper for SHA pinning and version checks, then interprets the mechanical inventory for deprecations, EOL toolchains, and cross-workflow drift. Proposes diffs; never commits.
---

# gha Maintain

Keep GitHub Actions workflows current: pin actions to full-length commit
SHAs, propose version updates, flag deprecated runners/actions/EOL
toolchains, and audit multiple workflows for drift. The mechanical work
happens in `${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh`; every judgment
call happens here.

## Running the check

Start read-only: run
`${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh check <workflow-file> [...]`
via Bash — if the user didn't name files, Glob `.github/workflows/*.yml`
and `*.yaml` and pass all of them. The output has three parts to relay:

- `pinact check:` — either all refs pinned, or the unpinned/outdated refs.
- `Inventory:` — every `uses:` ref grouped with counts, every `runs-on:`
  label grouped with counts. This is raw material for interpretation, not
  findings by itself.
- `Full output: <path>` — the raw pinact log for drill-down.

`MISSING pinact` → point the user to `/gha:doctor`; don't work around it.

## Scale

If the repo has more than ~5 workflow files, or the user asked for a
full-repo maintenance sweep, dispatch the `gha-auditor` agent instead of
working file-by-file in the main conversation (it runs the same
check-mode inventory across every file and returns a condensed drift
summary). Pin mode still happens here, on the user's go-ahead. If that
agent isn't available in this installation, fall back to running
`maintain.sh check` against all files in one invocation.

## Applying pins

Only after the user has seen the check-mode report and agreed: run
`${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh pin <files>`. This edits the
working tree. On success the script confirms with
`pinact pin: updated refs in place. Review with: git diff -- <files>`;
if it instead prints `ERROR pinact failed to pin (exit <n>):`, relay that
and stop rather than proceeding. Immediately show the user
`git diff -- <files>` and stop —
**never commit, and never offer to commit "while you're at it."** The
user decides what happens to the diff.

## Interpreting the inventory

Work through these judgments, citing `file:line` where possible:

1. **Deprecated/EOL**: compare runner labels and action versions against
   the quick reference below. The list rots — when unsure whether
   something is deprecated *today*, verify with WebSearch before
   asserting it to the user.
2. **Version drift**: the same action appearing at different versions
   across workflows (visible in the grouped `uses:` inventory). Propose
   converging on one version — usually the newest already in use.
3. **Duplicated logic**: near-identical job/step blocks across workflows
   (read the files to confirm). Suggest extracting a reusable workflow;
   sketch what it would look like, but don't create it unasked.
4. **Unpinned third-party actions**: cross-reference the
   `gha-dangerous-patterns` skill's "Unpinned third-party actions"
   section for why this matters; pin mode is the fix.

## Deprecation quick reference (written 2026-07 — verify before asserting)

- `ubuntu-20.04` runners: retired (mid-2025).
- `macos-11` / `macos-12` runners: retired.
- Actions running on Node 12 or Node 16: deprecated; runs emit warnings.
- `set-output` / `save-state` workflow commands: removed; use `$GITHUB_OUTPUT` / `$GITHUB_STATE`.
- `actions/upload-artifact@v3` and `actions/download-artifact@v3` (and older): shut off January 2025; require v4.

## Safety

This skill proposes diffs. It never commits, never pushes, and never
opens PRs. Those need the user's explicit go-ahead and happen outside
this skill.
