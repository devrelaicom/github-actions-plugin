---
name: gha-doctor
description: This skill should be used when the user asks to "check my GitHub Actions tooling", "is wrkflw/actionlint installed", "what do I need for gha", "run gha doctor", or when another gha skill reports a missing tool and needs to point the user somewhere for install instructions. Checks whether gh, actionlint, wrkflw, zizmor, pinact, and jq are installed and reports install commands for anything missing. Never installs anything itself.
version: 0.1.0
---

# gha Doctor

Check whether the tools the `gha` plugin depends on are installed, and
report exactly what's missing with the command to install it. Never run an
install command automatically — only the user runs it, on their own
machine, in their own time.

## Running the check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` via Bash. The script prints
one line per tool (`OK <tool> (<version>)` or `MISSING <tool>`, followed by
an `install:` line for anything missing), then a `Full log: <path>` line
pointing to the complete run log.

Relay the script's summary lines to the user directly — that summary is
already the right level of detail; there's no need to re-derive or
re-format it. If every tool reports `OK`, say so plainly (e.g. "All gha
tooling is installed: gh, actionlint, wrkflw, zizmor, pinact, jq"). If
anything is `MISSING`, list exactly which tools and the install command
printed for each, and stop there — do not run the install command, and do
not offer to run it "just this once."

## The six tools

| Tool | What it's for |
|---|---|
| `gh` | All GitHub API access (auth, PRs, runs, dispatch) |
| `actionlint` | Workflow syntax/schema correctness (used by `gha-lint`) |
| `wrkflw` | Local workflow execution without requiring Docker (a later plan's `gha-local-run`). If a user asks about `act` specifically, note that `gha` uses `wrkflw` instead — `doctor.sh` does not check for `act`. |
| `zizmor` | Security static analysis (a later plan's `gha-security-audit`) |
| `pinact` | SHA-pinning and version updates for actions (a later plan's `gha-maintain`) |
| `jq` | JSON parsing used internally by gha's own wrapper scripts — not a GitHub Actions tool itself, but required for the others to work |

## When another skill reports a missing tool

If `gha-lint` (or, in later plans, `gha-security-audit`, `gha-local-run`,
`gha-maintain`) reports that its required tool is missing, don't
re-implement a presence check inline — run this skill's check instead and
relay its output, so the user gets one consistent doctor report rather than
several slightly different ad-hoc messages.
