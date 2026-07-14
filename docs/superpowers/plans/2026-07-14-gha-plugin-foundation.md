# gha Plugin — Plan 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `gha` plugin's foundation — plugin manifest, the wrapper-script pattern that keeps tool output out of the agent's context, the tooling-doctor capability, the actionlint-based lint capability, and the shared security-knowledge skill — as a working, installable, testable plugin.

**Architecture:** Every external tool (`gh`, `actionlint`, `wrkflw`, `zizmor`, `pinact`, plus `jq` as a scripting dependency) is wrapped by a small shell script in `scripts/`. Each script writes its tool's full raw output to a temp file and prints only a compact summary (one line on the happy path). Skills call scripts via Bash and never invoke the underlying tool directly. Commands are thin wrappers that invoke skills.

**Tech Stack:** Bash (wrapper scripts, POSIX-ish, `set -uo pipefail`), `jq` for JSON parsing, Markdown+YAML frontmatter for commands/skills (Claude Code plugin format).

**Relationship to later plans:** This plan covers the plugin foundation only: scaffolding, `gha-doctor` (script+skill+command), `gha-lint` (script+skill, no command yet), and `gha-dangerous-patterns`. `/gha:review` (lint+security), `/gha:maintain`, `/gha:test`, `/gha:trigger`, `/gha:watch`, the `gha-auditor`/`gha-creator` subagents, and `/gha:brainstorming` are separate plans written after this one lands, so their tasks can reference real paths and patterns instead of guessing ahead.

## Global Constraints

- Plugin name is `gha` (kebab-case), manifest at `.claude-plugin/plugin.json`.
- Public, Claude Code only — no cross-harness packaging (Cursor/Codex/Gemini) in scope.
- No auto-installing tooling, ever. `gha-doctor`/`scripts/doctor.sh` only report gaps and print the install command; they never execute an install.
- Every tool invocation happens inside a `scripts/*.sh` wrapper, never directly in a skill's instructions. Wrapper contract: write full raw output to a file in the OS temp dir, print the file path, and print a compact summary — one line on the happy path (what ran, against what, headline numbers), a capped findings list otherwise.
- `gh` is the only path to the GitHub API; the plugin never handles credentials directly (not exercised until later plans, but no task in this plan should introduce any other auth mechanism).
- License is MIT (existing `LICENSE` file, copyright DevRel AI 2026); repository is `git@github.com:devrelaicom/github-actions-plugin.git`.
- Git identity for commits in this repo: Aaron Bassett.

---

### Task 1: Plugin scaffolding

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Modify: `README.md`

**Interfaces:**
- Produces: a valid plugin manifest at `.claude-plugin/plugin.json` with `name: "gha"` — every later task's commands/skills/agents are discovered relative to this plugin root (`${CLAUDE_PLUGIN_ROOT}`).

- [ ] **Step 1: Create the plugin manifest**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "gha",
  "version": "0.1.0",
  "description": "Create, review, maintain, locally test, trigger, and monitor GitHub Actions workflows from Claude Code",
  "author": {
    "name": "Aaron Bassett",
    "email": "aaronbassett@gmail.com"
  },
  "homepage": "https://github.com/devrelaicom/github-actions-plugin",
  "repository": "https://github.com/devrelaicom/github-actions-plugin",
  "license": "MIT",
  "keywords": [
    "github-actions",
    "ci-cd",
    "workflows",
    "linting",
    "security"
  ]
}
```

- [ ] **Step 2: Create the marketplace listing**

Create `.claude-plugin/marketplace.json` so the repo is self-installable as a single-plugin marketplace:

```json
{
  "name": "gha-marketplace",
  "description": "Marketplace for the gha GitHub Actions plugin",
  "owner": {
    "name": "Aaron Bassett",
    "email": "aaronbassett@gmail.com"
  },
  "plugins": [
    {
      "name": "gha",
      "description": "Create, review, maintain, locally test, trigger, and monitor GitHub Actions workflows from Claude Code",
      "version": "0.1.0",
      "source": "./",
      "author": {
        "name": "Aaron Bassett",
        "email": "aaronbassett@gmail.com"
      }
    }
  ]
}
```

- [ ] **Step 3: Validate both manifests are well-formed JSON**

Run: `jq . .claude-plugin/plugin.json && jq . .claude-plugin/marketplace.json`
Expected: both files print back as formatted JSON with no error. If `jq` isn't available yet on the implementer's machine, substitute `python3 -m json.tool .claude-plugin/plugin.json` (and the same for `marketplace.json`) — either is an acceptable validity check here.

- [ ] **Step 4: Update the README**

Replace the entire contents of `README.md` with:

```markdown
# gha

A Claude Code plugin for the full GitHub Actions workflow lifecycle: creating
workflows through a guided brainstorming flow, reviewing them for correctness
and security, running them locally, keeping them current, and triggering and
monitoring runs on GitHub — all from inside Claude Code.

## Install

\`\`\`
/plugin marketplace add devrelaicom/github-actions-plugin
/plugin install gha
\`\`\`

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
```

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "Scaffold gha plugin manifest and marketplace listing"
```

---

### Task 2: Test fixtures

**Files:**
- Create: `tests/fixtures/clean.yml`
- Create: `tests/fixtures/bad-lint.yml`

**Interfaces:**
- Produces: `tests/fixtures/clean.yml` (a workflow `actionlint` reports zero issues for) and `tests/fixtures/bad-lint.yml` (a workflow `actionlint` reports at least one issue for — an undefined job dependency and an undefined step-output reference). Both are consumed by Task 7's `scripts/tests/test-lint.sh`.

- [ ] **Step 1: Create the clean fixture**

Create `tests/fixtures/clean.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Run a script
        run: echo "hello world"
```

- [ ] **Step 2: Create the bad-lint fixture**

Create `tests/fixtures/bad-lint.yml`:

```yaml
name: Bad Lint Example
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: echo "testing ${{ steps.setup.outputs.missing }}"
```

This references a nonexistent `build` job in `needs:` and a nonexistent
`setup` step in `steps.setup.outputs.missing` — both are checks `actionlint`
performs by default, independent of whether `actionlint` is installed on the
machine that authored this fixture.

- [ ] **Step 3: Sanity-check the fixtures are valid YAML**

Run: `python3 -c "import yaml, sys; [yaml.safe_load(open(f)) for f in ['tests/fixtures/clean.yml', 'tests/fixtures/bad-lint.yml']]; print('valid yaml')"`
Expected: `valid yaml` printed, no exception. (If `pyyaml` isn't available, `ruby -ryaml -e "YAML.load_file('tests/fixtures/clean.yml'); YAML.load_file('tests/fixtures/bad-lint.yml'); puts 'valid yaml'"` is an acceptable substitute — the point is confirming both files parse as YAML before they're used as tool input.)

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/clean.yml tests/fixtures/bad-lint.yml
git commit -m "Add clean and bad-lint workflow fixtures"
```

---

### Task 3: `scripts/doctor.sh` and its smoke test

**Files:**
- Create: `scripts/doctor.sh`
- Create: `scripts/tests/test-doctor.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `scripts/doctor.sh` — a script with no required arguments. Contract: prints one `OK <tool> (<version>)` or `MISSING <tool>` line per tool (`gh`, `actionlint`, `wrkflw`, `zizmor`, `pinact`, `jq`, in that order), an `  install: <command>` line under each `MISSING` line, then a `Full log: <path>` line. Exit code `0` if every tool is present, `1` if at least one is missing. This is consumed by `skills/gha-doctor/SKILL.md` (Task 5) and `commands/doctor.md` (Task 6).

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test-doctor.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for scripts/doctor.sh. Run: bash scripts/tests/test-doctor.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$SCRIPT_DIR/../doctor.sh"

output="$("$DOCTOR" 2>&1)"
exit_code=$?

fail=0

if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 1 ]; then
  echo "FAIL: doctor.sh exited with unexpected code $exit_code"
  fail=1
fi

for tool in gh actionlint wrkflw zizmor pinact jq; do
  if ! echo "$output" | grep -q "$tool"; then
    echo "FAIL: doctor.sh output doesn't mention '$tool'"
    fail=1
  fi
done

log_path="$(echo "$output" | grep 'Full log:' | sed 's/Full log: //')"
if [ -z "$log_path" ] || [ ! -s "$log_path" ]; then
  echo "FAIL: doctor.sh didn't produce a non-empty log file (got: '$log_path')"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: doctor.sh smoke test"
fi
exit "$fail"
```

Make it executable: `chmod +x scripts/tests/test-doctor.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test-doctor.sh`
Expected: FAIL — `scripts/doctor.sh` doesn't exist yet, so the shell reports something like `.../doctor.sh: No such file or directory` and the script exits non-zero (not `0` or `1`), tripping the first assertion.

- [ ] **Step 3: Implement `scripts/doctor.sh`**

Create `scripts/doctor.sh`:

```bash
#!/usr/bin/env bash
# scripts/doctor.sh
# Checks that the tools gha's other scripts depend on are installed.
# Never installs anything - only reports gaps and prints the install
# command the user would run themselves.
set -uo pipefail

TMP_FILE="$(mktemp /tmp/gha-doctor.XXXXXX.log)"
echo "gha doctor run: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMP_FILE"

have_brew=0; have_cargo=0; have_go=0; have_pip=0
command -v brew  >/dev/null 2>&1 && have_brew=1
command -v cargo >/dev/null 2>&1 && have_cargo=1
command -v go    >/dev/null 2>&1 && have_go=1
{ command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; } && have_pip=1

# check_tool <binary> <version-flag...>
check_tool() {
  local name="$1"; shift
  if command -v "$name" >/dev/null 2>&1; then
    local version
    version="$("$name" "$@" 2>&1 | head -1)"
    echo "OK      $name ($version)"
    echo "OK      $name ($version)" >> "$TMP_FILE"
    return 0
  fi
  echo "MISSING $name"
  echo "MISSING $name" >> "$TMP_FILE"
  return 1
}

# install_hint <label> <brew-pkg> <cargo-pkg> <go-module> <pip-pkg>
install_hint() {
  local label="$1" brew_pkg="$2" cargo_pkg="$3" go_mod="$4" pip_pkg="$5"
  local hint=""
  if   [ "$have_brew"  -eq 1 ] && [ -n "$brew_pkg" ];  then hint="brew install $brew_pkg"
  elif [ "$have_cargo" -eq 1 ] && [ -n "$cargo_pkg" ]; then hint="cargo install $cargo_pkg"
  elif [ "$have_go"    -eq 1 ] && [ -n "$go_mod" ];    then hint="go install ${go_mod}@latest"
  elif [ "$have_pip"   -eq 1 ] && [ -n "$pip_pkg" ];   then hint="pip install $pip_pkg"
  else hint="no supported package manager detected on this machine — see the $label project's install docs"
  fi
  echo "  install: $hint"
  echo "  install: $hint" >> "$TMP_FILE"
}

missing=0

check_tool gh --version                || { install_hint gh gh "" "" "";                                                                                  missing=1; }
check_tool actionlint -version         || { install_hint actionlint actionlint github.com/rhysd/actionlint/cmd/actionlint github.com/rhysd/actionlint/cmd/actionlint ""; missing=1; }
check_tool wrkflw --version            || { install_hint wrkflw wrkflw wrkflw "" "";                                                                       missing=1; }
check_tool zizmor --version            || { install_hint zizmor zizmor zizmor "" zizmor;                                                                   missing=1; }
check_tool pinact --version            || { install_hint pinact pinact pinact github.com/suzuki-shunsuke/pinact/cmd/pinact "";                            missing=1; }
check_tool jq --version                || { install_hint jq jq "" "" "";                                                                                   missing=1; }

echo
echo "Full log: $TMP_FILE"

exit "$missing"
```

Make it executable: `chmod +x scripts/doctor.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/tests/test-doctor.sh`
Expected: `PASS: doctor.sh smoke test`, exit code `0`. This holds regardless of how many of the six tools happen to be installed on the machine running the test — the test only checks that every tool is *mentioned* and that a valid log file was produced, not that all tools are present.

- [ ] **Step 5: Commit**

```bash
git add scripts/doctor.sh scripts/tests/test-doctor.sh
git commit -m "Add doctor.sh wrapper script with smoke test"
```

---

### Task 4: `gha-dangerous-patterns` knowledge skill

**Files:**
- Create: `skills/gha-dangerous-patterns/SKILL.md`

**Interfaces:**
- Produces: a knowledge-only skill named `gha-dangerous-patterns` with no scripts of its own. Referenced by name from `skills/gha-lint/SKILL.md` (Task 7) and, in later plans, from `gha-security-audit`, `gha-maintain`, `gha-creator`, and `gha-auditor`.

- [ ] **Step 1: Create the skill directory and SKILL.md**

Create `skills/gha-dangerous-patterns/SKILL.md`:

```markdown
---
name: gha-dangerous-patterns
description: This skill should be used when writing, editing, or reviewing GitHub Actions workflow files, or when asked to "check for security issues in this workflow", "is this workflow safe", "review this action for vulnerabilities", or "what's wrong with this workflow's permissions". Provides a catalog of known GitHub Actions security anti-patterns to check for. Other gha skills and agents that touch workflow content should reference this skill rather than re-deriving this knowledge.
version: 0.1.0
---

# GitHub Actions Security Anti-Patterns

Check workflow content against the anti-patterns below whenever creating,
editing, or reviewing a `.github/workflows/*.yml` file. This is reference
knowledge, not an executable check — the `gha-security-audit` skill (a
later plan) runs `zizmor` for automated detection; this skill exists so the
same knowledge is available even when `zizmor` isn't run, e.g. while
`gha-creator` is drafting a new workflow.

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
what the `pinact` tool (via `gha-maintain`, a later plan) automates.

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
```

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; f = open('skills/gha-dangerous-patterns/SKILL.md'); content = f.read(); fm = content.split('---')[1]; d = yaml.safe_load(fm); assert d['name'] == 'gha-dangerous-patterns'; assert 'description' in d; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Commit**

```bash
git add skills/gha-dangerous-patterns/SKILL.md
git commit -m "Add gha-dangerous-patterns knowledge skill"
```

---

### Task 5: `gha-doctor` skill

**Files:**
- Create: `skills/gha-doctor/SKILL.md`

**Interfaces:**
- Consumes: `scripts/doctor.sh` (Task 3) — no arguments, contract as described in Task 3's Interfaces.
- Produces: a skill named `gha-doctor`, invoked by `commands/doctor.md` (Task 6) and referenced by name from other skills' preflight instructions in later plans (e.g. "point to `/gha:doctor`" or "point to the `gha-doctor` skill").

- [ ] **Step 1: Create the skill directory and SKILL.md**

Create `skills/gha-doctor/SKILL.md`:

```markdown
---
name: gha-doctor
description: This skill should be used when the user asks to "check my GitHub Actions tooling", "is act/wrkflw/actionlint installed", "what do I need for gha", "run gha doctor", or when another gha skill reports a missing tool and needs to point the user somewhere for install instructions. Checks whether gh, actionlint, wrkflw, zizmor, pinact, and jq are installed and reports install commands for anything missing. Never installs anything itself.
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
| `wrkflw` | Local workflow execution without requiring Docker (a later plan's `gha-local-run`) |
| `zizmor` | Security static analysis (a later plan's `gha-security-audit`) |
| `pinact` | SHA-pinning and version updates for actions (a later plan's `gha-maintain`) |
| `jq` | JSON parsing used internally by gha's own wrapper scripts — not a GitHub Actions tool itself, but required for the others to work |

## When another skill reports a missing tool

If `gha-lint` (or, in later plans, `gha-security-audit`, `gha-local-run`,
`gha-maintain`) reports that its required tool is missing, don't
re-implement a presence check inline — run this skill's check instead and
relay its output, so the user gets one consistent doctor report rather than
several slightly different ad-hoc messages.
```

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; f = open('skills/gha-doctor/SKILL.md'); content = f.read(); fm = content.split('---')[1]; d = yaml.safe_load(fm); assert d['name'] == 'gha-doctor'; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Commit**

```bash
git add skills/gha-doctor/SKILL.md
git commit -m "Add gha-doctor skill"
```

---

### Task 6: `/gha:doctor` command

**Files:**
- Create: `commands/doctor.md`

**Interfaces:**
- Consumes: `gha-doctor` skill (Task 5).
- Produces: the `/gha:doctor` slash command.

- [ ] **Step 1: Create the command**

Create `commands/doctor.md`:

```markdown
---
description: Check that gh, actionlint, wrkflw, zizmor, pinact, and jq are installed
allowed-tools: Bash
---

Use the gha-doctor skill to check whether gh, actionlint, wrkflw, zizmor,
pinact, and jq are installed, by running
`${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh`.

Report the result plainly: if everything is installed, say so in one line.
If anything is missing, list each missing tool with the exact install
command the script printed for it. Do not run any install command — only
report what the user would need to run themselves.
```

- [ ] **Step 2: Confirm the command is discovered**

Run: `ls commands/doctor.md && head -5 commands/doctor.md`
Expected: file exists, frontmatter visible with `description:` and
`allowed-tools:` fields. (Full end-to-end discovery — the command actually
appearing in Claude Code's `/help` — is verified in Task 9's manual
checklist, once the plugin is installed locally.)

- [ ] **Step 3: Commit**

```bash
git add commands/doctor.md
git commit -m "Add /gha:doctor command"
```

---

### Task 7: `scripts/lint.sh` and its smoke test

**Files:**
- Create: `scripts/lint.sh`
- Create: `scripts/tests/test-lint.sh`

**Interfaces:**
- Consumes: `tests/fixtures/clean.yml` and `tests/fixtures/bad-lint.yml` (Task 2).
- Produces: `scripts/lint.sh <workflow-file> [<workflow-file> ...]`. Contract: for each clean file, prints `<file>: actionlint OK (<N> lines, 0 issues)`; if any file has findings, prints `actionlint found <count> issue(s):` followed by up to 20 `  <filepath>:<line>:<column> <message>` lines (and a `... and N more` line if truncated), then always prints `Full output: <path>` last. Exit code `0` for a successful run (whether or not issues were found), `2` for a usage/missing-tool/missing-file error, and whatever `actionlint` itself returned if that's `>1` (a real crash, not just findings). Consumed by `skills/gha-lint/SKILL.md` (Task 8).

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test-lint.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for scripts/lint.sh using tests/fixtures/{clean,bad-lint}.yml.
# Run: bash scripts/tests/test-lint.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/../lint.sh"
FIXTURES="$SCRIPT_DIR/../../tests/fixtures"

if ! command -v actionlint >/dev/null 2>&1; then
  echo "SKIP: actionlint not installed, cannot run lint.sh smoke test"
  exit 0
fi

fail=0

clean_output="$("$LINT" "$FIXTURES/clean.yml" 2>&1)"
if ! echo "$clean_output" | grep -q "OK (.*0 issues)"; then
  echo "FAIL: clean.yml did not produce a clean OK summary. Got:"
  echo "$clean_output"
  fail=1
fi

bad_output="$("$LINT" "$FIXTURES/bad-lint.yml" 2>&1)"
if ! echo "$bad_output" | grep -q "found [1-9][0-9]* issue"; then
  echo "FAIL: bad-lint.yml did not produce any findings. Got:"
  echo "$bad_output"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: lint.sh smoke test"
fi
exit "$fail"
```

Make it executable: `chmod +x scripts/tests/test-lint.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test-lint.sh`
Expected: if `actionlint` is installed on this machine, FAIL — `scripts/lint.sh`
doesn't exist yet, so `"$LINT" ...` errors with `No such file or directory`
and the grep checks fail. If `actionlint` is **not** installed on this
machine, the test prints `SKIP: actionlint not installed...` and exits `0`
— in that case, the real verification of this test happens in Step 4
instead, on whichever machine (this one or CI) has `actionlint` available;
proceed to Step 3 regardless.

- [ ] **Step 3: Implement `scripts/lint.sh`**

Create `scripts/lint.sh`:

```bash
#!/usr/bin/env bash
# scripts/lint.sh <workflow-file> [<workflow-file> ...]
# Wraps actionlint. Writes the full JSON result to a temp file and prints
# a compact summary: one line per clean file, or a capped findings list.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: lint.sh <workflow-file> [<workflow-file> ...]" >&2
  exit 2
fi

if ! command -v actionlint >/dev/null 2>&1; then
  echo "MISSING actionlint. Run /gha:doctor for install instructions."
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING jq. Run /gha:doctor for install instructions."
  exit 2
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "ERROR $f: file not found"
    exit 2
  fi
done

TMP_FILE="$(mktemp /tmp/gha-lint.XXXXXX.json)"

actionlint -format '{{json .}}' "$@" > "$TMP_FILE" 2>/dev/null
exit_code=$?

# actionlint: 0 = clean, 1 = found issues, >1 = it couldn't run at all
if [ "$exit_code" -gt 1 ]; then
  echo "ERROR actionlint failed to run (exit $exit_code). Raw output: $TMP_FILE"
  exit "$exit_code"
fi

count="$(jq 'length' "$TMP_FILE" 2>/dev/null || echo 0)"

if [ "$count" -eq 0 ]; then
  for f in "$@"; do
    lines="$(wc -l < "$f" | tr -d ' ')"
    echo "$f: actionlint OK ($lines lines, 0 issues)"
  done
else
  echo "actionlint found $count issue(s):"
  jq -r '.[:20][] | "  \(.filepath):\(.line):\(.column) \(.message)"' "$TMP_FILE"
  if [ "$count" -gt 20 ]; then
    echo "  ... and $((count - 20)) more (see $TMP_FILE)"
  fi
fi

echo "Full output: $TMP_FILE"
exit 0
```

Make it executable: `chmod +x scripts/lint.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/tests/test-lint.sh`
Expected: `PASS: lint.sh smoke test` if `actionlint` is installed; if it
reports `SKIP`, install `actionlint` (per `/gha:doctor`'s printed command)
and re-run before considering this task done — the SKIP path exists for
environments genuinely without `actionlint`, not as a way to avoid ever
running this test for real.

- [ ] **Step 5: Commit**

```bash
git add scripts/lint.sh scripts/tests/test-lint.sh
git commit -m "Add lint.sh wrapper script with smoke test"
```

---

### Task 8: `gha-lint` skill

**Files:**
- Create: `skills/gha-lint/SKILL.md`

**Interfaces:**
- Consumes: `scripts/lint.sh` (Task 7) — contract as described in Task 7's Interfaces. References `gha-dangerous-patterns` (Task 4) and `gha-doctor` (Task 5) by name.
- Produces: a skill named `gha-lint`. This is the last task of Plan 1 that adds plugin functionality; Task 9 is validation only.

- [ ] **Step 1: Create the skill directory and SKILL.md**

Create `skills/gha-lint/SKILL.md`:

```markdown
---
name: gha-lint
description: This skill should be used when the user asks to "lint this workflow", "check this GitHub Actions file for errors", "validate my workflow syntax", "run actionlint", or is editing a file under .github/workflows/. Runs actionlint against one or more workflow files and reports correctness/schema findings.
version: 0.1.0
---

# gha Lint

Check GitHub Actions workflow files for syntax and schema correctness using
`actionlint`, run through `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh` rather than
invoking `actionlint` directly.

## Running the check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh <workflow-file> [<workflow-file> ...]`
via Bash, passing the specific workflow file(s) relevant to the request — if
the user didn't name one, use `Glob` to find `.github/workflows/*.yml` and
`*.yaml` in the current repo and pass all of them.

The script's own summary is already the right level of detail to relay:

- **Clean files** print one line each: `<file>: actionlint OK (<N> lines, 0 issues)`.
  Relay this as-is — there's no need to say more for a clean pass.
- **Files with findings** produce a `actionlint found <count> issue(s):`
  header followed by `  <filepath>:<line>:<column> <message>` lines. Relay
  these findings directly (they're already file:line, no reformatting
  needed), and mention the `Full output: <path>` line so the user can open
  the raw JSON if they want more than the capped list.
- If the script prints `MISSING actionlint`, don't try to work around it —
  tell the user to run `/gha:doctor` (or invoke the `gha-doctor` skill) for
  the install command.

## Security findings are a separate concern

`actionlint` checks correctness and schema, not security. If the user's
request is really about security (unpinned actions, `pull_request_target`
misuse, script injection, permissions), that's the `gha-security-audit`
skill's job (a later plan) — cross-reference the `gha-dangerous-patterns`
skill's catalog in the meantime if `gha-security-audit` isn't available yet
in this installation.
```

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; f = open('skills/gha-lint/SKILL.md'); content = f.read(); fm = content.split('---')[1]; d = yaml.safe_load(fm); assert d['name'] == 'gha-lint'; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Commit**

```bash
git add skills/gha-lint/SKILL.md
git commit -m "Add gha-lint skill"
```

---

### Task 9: Plugin validation and manual smoke test

**Files:** none created or modified — this task verifies the work of Tasks 1-8.

**Interfaces:**
- Consumes: the entire plugin tree produced by Tasks 1-8.

- [ ] **Step 1: Run structural validation**

Dispatch the `plugin-dev:plugin-validator` agent (or invoke it however this
harness exposes agents) against this repo. Confirm it reports no errors for:
`.claude-plugin/plugin.json` schema, `.claude-plugin/marketplace.json`
schema, frontmatter on `commands/doctor.md`, and frontmatter on all three
`SKILL.md` files. Fix anything it flags before proceeding.

- [ ] **Step 2: Run every smoke test together**

Run:
```bash
bash scripts/tests/test-doctor.sh
bash scripts/tests/test-lint.sh
```
Expected: both `PASS` (or `test-lint.sh` prints `SKIP` only if `actionlint`
truly isn't installed — resolve that per Task 7 Step 4 before calling this
task done).

- [ ] **Step 3: Manual install smoke test**

Install the plugin locally and confirm real end-to-end discovery (not just
file presence):

```bash
cc --plugin-dir "$(pwd)"
```

In the resulting session:
1. Run `/gha:doctor` — confirm it prints a line for each of the six tools
   and, for any missing ones, an install command (and confirm no install
   command is ever executed automatically).
2. Ask "lint tests/fixtures/clean.yml" in natural language (no slash
   command) — confirm the `gha-lint` skill triggers and reports a clean
   `OK` summary, not a wall of raw JSON.
3. Ask "lint tests/fixtures/bad-lint.yml" — confirm `gha-lint` reports the
   findings with file:line references and a path to the full output.

- [ ] **Step 4: Update Plan 1 status**

Add a line to the top of this plan file noting completion and the date, then commit:

```bash
git add docs/superpowers/plans/2026-07-14-gha-plugin-foundation.md
git commit -m "Mark gha plugin Plan 1 (foundation) complete"
```
