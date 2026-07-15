# gha Plugin — Plan 2: Complete Remainder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the `gha` plugin — every remaining script, skill, command, and agent from the spec — so that after this plan the plugin is feature-complete at v1.0.0 with no further phases.

**Architecture:** Vertical capability slices. Each analysis capability lands as fixture → wrapper script + smoke test → skill + command, so every slice is independently usable and testable. The two subagents and the guided brainstorming flow land after the capabilities they orchestrate. Wrapper scripts keep raw tool output out of the agent's context (full output to a temp file, compact summary to stdout).

**Tech Stack:** Bash (wrapper scripts, `set -uo pipefail`, bash-3.2-compatible — no arrays), `jq` for JSON/SARIF parsing, Markdown + YAML frontmatter for skills/commands/agents (Claude Code plugin format).

**Relationship to Plan 1:** Plan 1 (foundation) is complete: scaffolding, `doctor.sh`, `lint.sh`, `gha-doctor`, `gha-lint`, `gha-dangerous-patterns`, `/gha:doctor`, and the `clean.yml`/`bad-lint.yml` fixtures all exist. The spec back-port (jq in the tooling table, mktemp portability rule, doctor.sh exit-code carve-out, "0 issues" wording, `gha-brainstorming` skill, self-contained plan format, mechanical-only `maintain.sh`) landed in commit `d31c21c` before this plan was written.

## Global Constraints

- Plugin name is `gha`; manifest at `.claude-plugin/plugin.json`. Public, Claude Code only.
- **Full toolchain assumed installed before any task starts:** `gh` (authenticated via `gh auth login`), `actionlint`, `wrkflw`, `zizmor`, `pinact`, `jq`. Run `bash scripts/doctor.sh` first; do not begin Task 1 until it reports all six `OK`.
- No auto-installing tooling, ever. Skills report gaps and point to `/gha:doctor`.
- Every external-tool invocation happens inside a `scripts/*.sh` wrapper, never directly in a skill's instructions — **except** `gh` calls whose output is inherently small (dispatch/rerun/cancel/auth-status/watch), per the spec.
- Wrapper contract: (1) run the tool; (2) write full raw output to `mktemp "${TMPDIR:-/tmp}/gha-<name>.XXXXXX"` — never a hardcoded `/tmp` prefix, never a suffix after `XXXXXX` (BSD/macOS mktemp rejects suffixed templates); (3) print a compact summary — one line per target on the happy path, a findings list capped at 20 otherwise; (4) exit non-zero only for execution failure (usage error, missing tool, missing file, tool crash) — findings are reported in the summary and exit `0`. (`doctor.sh`'s exit-1-on-missing-tool carve-out is Plan 1 code; nothing in this plan touches it.)
- `gh` is the only path to the GitHub API. The plugin never handles credentials directly.
- Any action that pushes, opens a PR, triggers/reruns/cancels a run, or merges requires an explicit user confirmation step, stated in the relevant skill itself. Nothing ever merges automatically.
- Self-contained: no gha skill, command, or agent may invoke or require a superpowers (or any other plugin's) skill.
- Bash scripts must stay bash-3.2 compatible (macOS default shell): no arrays, no `${var,,}`, no mapfile.
- License MIT; repository `git@github.com:devrelaicom/github-actions-plugin.git`; git identity for commits: Aaron Bassett.
- New SKILL.md files use frontmatter `version: 0.1.0` (the plugin version, bumped to 1.0.0 in Task 14, is the user-facing version).
- End state after Task 14: plugin version **1.0.0**, feature-complete per the spec. No further phases.

---

### Task 1: Security fixtures — harden `clean.yml`, add `bad-security.yml`

**Files:**
- Modify: `tests/fixtures/clean.yml`
- Create: `tests/fixtures/bad-security.yml`

**Interfaces:**
- Consumes: `pinact` and `zizmor` binaries (toolchain preflight), existing `tests/fixtures/clean.yml`.
- Produces: `tests/fixtures/clean.yml` that is clean for **both** `actionlint` and `zizmor` (SHA-pinned checkout, `persist-credentials: false`, explicit `permissions`), and `tests/fixtures/bad-security.yml` that `zizmor` reports at least two findings for. Both consumed by Task 2's `scripts/tests/test-security-audit.sh`; `clean.yml` also by Task 4's maintain test.

- [ ] **Step 1: Preflight the toolchain**

Run: `bash scripts/doctor.sh`
Expected: `OK` for all six tools, exit code `0`. If anything is `MISSING`, stop — the environment isn't ready for this plan (see Global Constraints).

- [ ] **Step 2: Baseline zizmor against the current clean fixture**

Run: `zizmor --no-exit-codes tests/fixtures/clean.yml`
Expected: findings such as `artipacked` (checkout without `persist-credentials: false`) and/or missing-permissions findings. This confirms why the fixture needs hardening. (If this zizmor version doesn't know `--no-exit-codes`, check `zizmor --help` for the equivalent and adapt Task 2's script accordingly, noting it in that task's commit message.)

- [ ] **Step 3: Pin the checkout action with pinact**

Run: `pinact run tests/fixtures/clean.yml`
Expected: exit 0; `tests/fixtures/clean.yml` now has `uses: actions/checkout@<full-40-char-sha> # v4...` (the SHA and version comment are written by pinact — do not hand-type them). If pinact reports a GitHub API rate limit, run `export GITHUB_TOKEN="$(gh auth token)"` and retry.

- [ ] **Step 4: Harden the rest of clean.yml by hand**

Edit `tests/fixtures/clean.yml` so it reads (keeping the exact `uses:` line pinact wrote in Step 3):

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@<sha-and-comment-written-by-pinact-in-step-3>
        with:
          persist-credentials: false
      - name: Run a script
        run: echo "hello world"
```

- [ ] **Step 5: Verify clean.yml is clean for both tools**

Run: `zizmor --no-exit-codes tests/fixtures/clean.yml && bash scripts/lint.sh tests/fixtures/clean.yml`
Expected: zizmor reports no findings (its "no findings" output, exit 0), and lint.sh prints `tests/fixtures/clean.yml: actionlint OK (... 0 issues)`. If zizmor still reports a finding, treat it as real: fix the fixture until zizmor reports none (do not suppress with config).

- [ ] **Step 6: Create the bad-security fixture**

Create `tests/fixtures/bad-security.yml`:

```yaml
name: Bad Security Example
on: pull_request_target

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - name: Install and build
        run: |
          npm install
          npm run build
      - name: Echo PR title
        run: echo "PR title is ${{ github.event.pull_request.title }}"
      - uses: fakeorg/random-action@v1
```

This deliberately combines: `pull_request_target` + checkout of the PR head (dangerous-triggers), untrusted `${{ github.event.pull_request.title }}` interpolated into `run:` (template-injection), an unpinned third-party action (unpinned-uses), no `permissions:` block, and checkout without `persist-credentials: false` (artipacked) — every section of `gha-dangerous-patterns` that zizmor can detect statically.

- [ ] **Step 7: Verify the bad fixture trips zizmor and parses as YAML**

Run: `zizmor --no-exit-codes tests/fixtures/bad-security.yml`
Expected: at least 2 findings (typically 4-5), exit 0.

Run: `python3 -c "import yaml; yaml.safe_load(open('tests/fixtures/bad-security.yml')); print('valid yaml')"`
Expected: `valid yaml`

- [ ] **Step 8: Confirm the existing lint smoke test still passes**

Run: `bash scripts/tests/test-lint.sh`
Expected: `PASS: lint.sh smoke test` (clean.yml changed shape but is still actionlint-clean).

- [ ] **Step 9: Commit**

```bash
git add tests/fixtures/clean.yml tests/fixtures/bad-security.yml
git commit -m "Harden clean fixture for zizmor and add bad-security fixture"
```

---

### Task 2: `scripts/security-audit.sh` and its smoke test

**Files:**
- Create: `scripts/security-audit.sh`
- Create: `scripts/tests/test-security-audit.sh`

**Interfaces:**
- Consumes: `tests/fixtures/clean.yml` and `tests/fixtures/bad-security.yml` (Task 1).
- Produces: `scripts/security-audit.sh <workflow-file> [<workflow-file> ...]`. Contract: for each clean file prints `<file>: zizmor OK (<N> lines, 0 findings)`; with findings prints `zizmor found <count> finding(s):` then up to 20 `  <level> <ruleId> <file>:<line> <message>` lines (plus `... and N more` if truncated); always prints `Full output: <path>` last. Exit `0` for a successful run with or without findings, `2` for usage/missing-tool/missing-file, zizmor's own exit code if zizmor itself failed. Consumed by `skills/gha-security-audit/SKILL.md` (Task 3), `agents/gha-auditor.md` (Task 11), `agents/gha-creator.md` (Task 12).

- [ ] **Step 1: Verify the zizmor flags this script relies on**

Run: `zizmor --help | grep -E -- '--(format|no-exit-codes|offline)'`
Expected: all three flags listed, with `sarif` among the format choices. If the installed zizmor names any of these differently, adapt the script below to the real flags and say so in the commit message.

- [ ] **Step 2: Write the failing test**

Create `scripts/tests/test-security-audit.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for scripts/security-audit.sh using
# tests/fixtures/{clean,bad-security}.yml.
# Run: bash scripts/tests/test-security-audit.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$SCRIPT_DIR/../security-audit.sh"
FIXTURES="$SCRIPT_DIR/../../tests/fixtures"

if ! command -v zizmor >/dev/null 2>&1; then
  echo "SKIP: zizmor not installed, cannot run security-audit.sh smoke test"
  exit 0
fi

fail=0

clean_output="$("$AUDIT" "$FIXTURES/clean.yml" 2>&1)"
if ! echo "$clean_output" | grep -q "OK (.*0 findings)"; then
  echo "FAIL: clean.yml did not produce a clean OK summary. Got:"
  echo "$clean_output"
  fail=1
fi

bad_output="$("$AUDIT" "$FIXTURES/bad-security.yml" 2>&1)"
if ! echo "$bad_output" | grep -q "found [1-9][0-9]* finding"; then
  echo "FAIL: bad-security.yml did not produce any findings. Got:"
  echo "$bad_output"
  fail=1
fi

log_path="$(echo "$bad_output" | grep 'Full output:' | sed 's/Full output: //')"
if [ -z "$log_path" ] || [ ! -s "$log_path" ]; then
  echo "FAIL: security-audit.sh didn't produce a non-empty SARIF file (got: '$log_path')"
  fail=1
fi

usage_output="$("$AUDIT" 2>&1)"
usage_code=$?
if [ "$usage_code" -ne 2 ]; then
  echo "FAIL: no-args invocation should exit 2, got $usage_code"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: security-audit.sh smoke test"
fi
exit "$fail"
```

Make it executable: `chmod +x scripts/tests/test-security-audit.sh`

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash scripts/tests/test-security-audit.sh`
Expected: FAIL — `scripts/security-audit.sh` doesn't exist yet, so the invocations error with `No such file or directory` and the grep assertions fail.

- [ ] **Step 4: Implement `scripts/security-audit.sh`**

Create `scripts/security-audit.sh`:

```bash
#!/usr/bin/env bash
# scripts/security-audit.sh <workflow-file> [<workflow-file> ...]
# Wraps zizmor. Writes the full SARIF result to a temp file and prints a
# compact summary: one line per clean file, or a capped findings list.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: security-audit.sh <workflow-file> [<workflow-file> ...]" >&2
  exit 2
fi

if ! command -v zizmor >/dev/null 2>&1; then
  echo "MISSING zizmor. Run /gha:doctor for install instructions."
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

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-security-audit.XXXXXX")"

# --no-exit-codes: findings must not drive the exit code (wrapper rule 4).
# --offline: deterministic, no GitHub API dependency for the audit itself.
zizmor --format sarif --no-exit-codes --offline "$@" > "$TMP_FILE" 2>"$TMP_FILE.err"
exit_code=$?

if [ "$exit_code" -ne 0 ]; then
  echo "ERROR zizmor failed to run (exit $exit_code):"
  head -10 "$TMP_FILE.err" | sed 's/^/  /'
  echo "Full output: $TMP_FILE (stderr: $TMP_FILE.err)"
  exit "$exit_code"
fi

count="$(jq '[.runs[].results[]] | length' "$TMP_FILE" 2>/dev/null || echo 0)"

if [ "$count" -eq 0 ]; then
  for f in "$@"; do
    lines="$(wc -l < "$f" | tr -d ' ')"
    echo "$f: zizmor OK ($lines lines, 0 findings)"
  done
else
  echo "zizmor found $count finding(s):"
  jq -r '[.runs[].results[]][:20][]
    | "  \(.level // "note") \(.ruleId) \(.locations[0].physicalLocation.artifactLocation.uri):\(.locations[0].physicalLocation.region.startLine // 0) \(.message.text | split("\n")[0])"' \
    "$TMP_FILE"
  if [ "$count" -gt 20 ]; then
    echo "  ... and $((count - 20)) more (see $TMP_FILE)"
  fi
fi

echo "Full output: $TMP_FILE"
exit 0
```

Make it executable: `chmod +x scripts/security-audit.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/tests/test-security-audit.sh`
Expected: `PASS: security-audit.sh smoke test`, exit code `0`. If the findings line or SARIF paths don't match (zizmor SARIF layout can shift between versions), inspect the temp file the script printed, fix the jq paths, and re-run until PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/security-audit.sh scripts/tests/test-security-audit.sh
git commit -m "Add security-audit.sh zizmor wrapper with smoke test"
```

---

### Task 3: `gha-security-audit` skill and `/gha:review` command

**Files:**
- Create: `skills/gha-security-audit/SKILL.md`
- Create: `commands/review.md`

**Interfaces:**
- Consumes: `scripts/security-audit.sh` (Task 2, contract in Task 2's Interfaces), `scripts/lint.sh` (Plan 1: same shape, `OK (... 0 issues)` / `actionlint found <count> issue(s):`), skills `gha-lint`, `gha-dangerous-patterns`, `gha-doctor` (Plan 1, referenced by name).
- Produces: skill `gha-security-audit` and the `/gha:review` slash command. `gha-auditor` (Task 11) is referenced by name here before it exists — that's fine; the reference activates when Task 11 lands, and until then the instruction's "if the agent is unavailable, run file-by-file" fallback applies.

- [ ] **Step 1: Create the skill**

Create `skills/gha-security-audit/SKILL.md`:

````markdown
---
name: gha-security-audit
description: This skill should be used when the user asks to "security review this workflow", "check this workflow for vulnerabilities", "run zizmor", "is this GitHub Actions file safe", "audit workflow permissions", or when /gha:review needs security findings. Runs zizmor security static analysis against workflow files and reports findings with file:line references.
version: 0.1.0
---

# gha Security Audit

Check GitHub Actions workflow files for security issues using `zizmor`, run
through `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh` rather than
invoking `zizmor` directly.

## Running the check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh <workflow-file> [...]`
via Bash, passing the workflow file(s) relevant to the request — if the
user didn't name one, use Glob to find `.github/workflows/*.yml` and
`*.yaml` in the current repo and pass all of them.

- **Clean files** print one line each: `<file>: zizmor OK (<N> lines,
  0 findings)`. Relay as-is.
- **Findings** print `zizmor found <count> finding(s):` followed by
  `  <level> <ruleId> <file>:<line> <message>` lines. Relay these directly
  and mention the `Full output: <path>` line (full SARIF) for drill-down.
- `MISSING zizmor` → tell the user to run `/gha:doctor` for the install
  command; don't work around it.

## Interpreting findings

Cross-reference the `gha-dangerous-patterns` skill — zizmor's rule ids map
onto its catalog:

| zizmor rule | gha-dangerous-patterns section |
|---|---|
| `dangerous-triggers` | `pull_request_target` with untrusted checkout |
| `template-injection` | Script injection via `${{ }}` in `run:` steps |
| `excessive-permissions` | Overbroad `GITHUB_TOKEN` permissions |
| `unpinned-uses` | Unpinned third-party actions |
| `artipacked`, `cache-poisoning` | Cache and artifact poisoning / credential persistence |

For each finding, explain the risk and give the concrete fix from the
catalog. Read the surrounding workflow context before suggesting a fix —
and never dismiss a finding as a false positive without having read the
workflow lines it points at.

## Scale

If the repo has more than ~5 workflow files, or the user asked for a
full-repo audit, dispatch the `gha-auditor` agent instead of running
file-by-file in the main conversation (it returns a condensed summary).
If that agent isn't available in this installation, fall back to running
the script against all files in one invocation.

## Correctness findings are a separate concern

`zizmor` checks security, not schema/syntax. For correctness (undefined
jobs, bad expressions), that's the `gha-lint` skill; `/gha:review` runs
both and consolidates.
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('skills/gha-security-audit/SKILL.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-security-audit'; assert 'description' in d; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Create the command**

Create `commands/review.md`:

```markdown
---
description: Lint and security-review GitHub Actions workflows (actionlint + zizmor), consolidated
argument-hint: "[workflow files, defaults to .github/workflows/*]"
allowed-tools: Bash, Glob, Read, Task
---

Review GitHub Actions workflow files for correctness and security, using
the gha-lint and gha-security-audit skills together.

1. Determine targets: use $ARGUMENTS if given; otherwise Glob
   `.github/workflows/*.yml` and `.github/workflows/*.yaml`.
2. If there are more than ~5 workflow files, dispatch the `gha-auditor`
   agent with the file list and relay its condensed summary instead of
   steps 3-5.
3. Run `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh <files>` via Bash.
4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh <files>` via Bash.
5. Present one consolidated report: correctness findings first, then
   security findings, each as `file:line — what and why`, with the fix.
   Note both scripts' `Full output:` temp-file paths at the end.

If either script prints `MISSING <tool>`, stop and point the user at
/gha:doctor. Do not install anything.
```

- [ ] **Step 4: Confirm command frontmatter shape**

Run: `head -6 commands/review.md`
Expected: frontmatter with `description:`, `argument-hint:`, and `allowed-tools:` visible.

- [ ] **Step 5: Manually exercise the slice against fixtures**

Run: `bash scripts/lint.sh tests/fixtures/bad-security.yml && bash scripts/security-audit.sh tests/fixtures/bad-security.yml`
Expected: lint likely reports `OK` (the file is schema-valid), security reports findings — demonstrating the two dimensions `/gha:review` consolidates are genuinely independent.

- [ ] **Step 6: Commit**

```bash
git add skills/gha-security-audit/SKILL.md commands/review.md
git commit -m "Add gha-security-audit skill and /gha:review command"
```

---

### Task 4: `scripts/maintain.sh` and its smoke test

**Files:**
- Create: `scripts/maintain.sh`
- Create: `scripts/tests/test-maintain.sh`

**Interfaces:**
- Consumes: `tests/fixtures/clean.yml` (Task 1: fully SHA-pinned) and `tests/fixtures/bad-lint.yml` (Plan 1: contains unpinned `actions/checkout@v4`).
- Produces: `scripts/maintain.sh check|pin <workflow-file> [...]`. Contract: `check` prints either `pinact check: all action refs pinned (<n> file(s))` or `pinact check: issues found (pinact exit <n>):` plus up to 20 indented pinact output lines; `pin` runs pinact for real (edits the given files in the working tree) and prints `pinact pin: updated refs in place. Review with: git diff -- <files>`. Both modes then print a mechanical `Inventory:` block (`uses:` refs grouped and counted, `runs-on:` labels grouped and counted) and `Full output: <path>` last. Exit `0` for successful runs including check-mode findings, `2` for usage/missing-tool/missing-file, pinact's exit code if pin-mode pinact failed. Consumed by `skills/gha-maintain/SKILL.md` (Task 5) and `agents/gha-auditor.md` (Task 11). **The script never commits; committing is always the caller's (user's) decision.**

- [ ] **Step 1: Verify the pinact CLI surface**

Run: `pinact run --help`
Expected: help text confirming `pinact run [files...]` accepts file arguments and a `--check` flag. If the installed pinact differs (e.g. `--check` renamed), adapt the script below and note it in the commit message.

- [ ] **Step 2: Write the failing test**

Create `scripts/tests/test-maintain.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for scripts/maintain.sh using tests/fixtures/{clean,bad-lint}.yml.
# pin mode needs network access to the GitHub API (pinact resolves tags to
# SHAs). If rate-limited: export GITHUB_TOKEN="$(gh auth token)" and re-run.
# Run: bash scripts/tests/test-maintain.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINTAIN="$SCRIPT_DIR/../maintain.sh"
FIXTURES="$SCRIPT_DIR/../../tests/fixtures"

if ! command -v pinact >/dev/null 2>&1; then
  echo "SKIP: pinact not installed, cannot run maintain.sh smoke test"
  exit 0
fi

fail=0

clean_output="$("$MAINTAIN" check "$FIXTURES/clean.yml" 2>&1)"
if ! echo "$clean_output" | grep -q "all action refs pinned"; then
  echo "FAIL: check on pinned clean.yml did not report all-pinned. Got:"
  echo "$clean_output"
  fail=1
fi
if ! echo "$clean_output" | grep -q "Inventory:"; then
  echo "FAIL: check output has no Inventory block. Got:"
  echo "$clean_output"
  fail=1
fi

bad_output="$("$MAINTAIN" check "$FIXTURES/bad-lint.yml" 2>&1)"
if ! echo "$bad_output" | grep -q "issues found"; then
  echo "FAIL: check on unpinned bad-lint.yml did not report issues. Got:"
  echo "$bad_output"
  fail=1
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/gha-maintain-test.XXXXXX")"
cp "$FIXTURES/bad-lint.yml" "$workdir/"
pin_output="$("$MAINTAIN" pin "$workdir/bad-lint.yml" 2>&1)"
pin_code=$?
if [ "$pin_code" -ne 0 ]; then
  echo "FAIL: pin mode exited $pin_code. Got:"
  echo "$pin_output"
  fail=1
elif ! grep -qE '@[0-9a-f]{40}' "$workdir/bad-lint.yml"; then
  echo "FAIL: pin mode did not write a full-length SHA into the copy. File now:"
  cat "$workdir/bad-lint.yml"
  fail=1
fi

usage_output="$("$MAINTAIN" check 2>&1)"
usage_code=$?
if [ "$usage_code" -ne 2 ]; then
  echo "FAIL: mode-without-files invocation should exit 2, got $usage_code"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: maintain.sh smoke test"
fi
exit "$fail"
```

Make it executable: `chmod +x scripts/tests/test-maintain.sh`

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash scripts/tests/test-maintain.sh`
Expected: FAIL — `scripts/maintain.sh` doesn't exist yet (`No such file or directory`).

- [ ] **Step 4: Implement `scripts/maintain.sh`**

Create `scripts/maintain.sh`:

```bash
#!/usr/bin/env bash
# scripts/maintain.sh check|pin <workflow-file> [<workflow-file> ...]
# Wraps pinact plus a mechanical inventory (uses: refs, runner labels).
# check: report-only. pin: pinact edits the given files in the working
# tree; committing (or not) is the caller's decision, never this script's.
# Judgment calls (what's deprecated, what's drift) belong to the
# gha-maintain skill, not here.
set -uo pipefail

usage() {
  echo "usage: maintain.sh check|pin <workflow-file> [<workflow-file> ...]" >&2
  exit 2
}

[ "$#" -ge 2 ] || usage
mode="$1"; shift
case "$mode" in
  check|pin) ;;
  *) usage ;;
esac

if ! command -v pinact >/dev/null 2>&1; then
  echo "MISSING pinact. Run /gha:doctor for install instructions."
  exit 2
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "ERROR $f: file not found"
    exit 2
  fi
done

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-maintain.XXXXXX")"

if [ "$mode" = "check" ]; then
  pinact run --check "$@" > "$TMP_FILE" 2>&1
  pinact_exit=$?
  if [ "$pinact_exit" -eq 0 ]; then
    echo "pinact check: all action refs pinned ($# file(s))"
  else
    # pinact --check exits non-zero when refs are unpinned/outdated.
    # That's a finding, not a failure (wrapper rule 4): report, exit 0.
    # A genuine pinact crash surfaces in these same relayed lines.
    echo "pinact check: issues found (pinact exit $pinact_exit):"
    head -20 "$TMP_FILE" | sed 's/^/  /'
    total="$(wc -l < "$TMP_FILE" | tr -d ' ')"
    if [ "$total" -gt 20 ]; then
      echo "  ... and $((total - 20)) more lines (see $TMP_FILE)"
    fi
  fi
else
  pinact run "$@" > "$TMP_FILE" 2>&1
  pinact_exit=$?
  if [ "$pinact_exit" -ne 0 ]; then
    echo "ERROR pinact failed to pin (exit $pinact_exit):"
    head -20 "$TMP_FILE" | sed 's/^/  /'
    echo "Full output: $TMP_FILE"
    exit "$pinact_exit"
  fi
  echo "pinact pin: updated refs in place. Review with: git diff -- $*"
fi

{
  echo "Inventory:"
  echo "  uses:"
  grep -hE '^[[:space:]]*(-[[:space:]]+)?uses:' "$@" \
    | sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//; s/[[:space:]]*#.*$//' \
    | sort | uniq -c | sort -rn | sed 's/^/    /'
  echo "  runs-on:"
  grep -hE '^[[:space:]]*runs-on:' "$@" \
    | sed -E 's/^[[:space:]]*runs-on:[[:space:]]*//' \
    | sort | uniq -c | sort -rn | sed 's/^/    /'
} | tee -a "$TMP_FILE"

echo "Full output: $TMP_FILE"
exit 0
```

Make it executable: `chmod +x scripts/maintain.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/tests/test-maintain.sh`
Expected: `PASS: maintain.sh smoke test`, exit `0`. If pinact's actual `--check` behavior differs (e.g. it exits 0 and only logs), inspect the temp file, adjust the summary branch to match reality, and re-run until PASS — the *contract lines* in this task's Interfaces block are what the test asserts, so keep the script conforming to them.

- [ ] **Step 6: Commit**

```bash
git add scripts/maintain.sh scripts/tests/test-maintain.sh
git commit -m "Add maintain.sh pinact wrapper with inventory and smoke test"
```

---

### Task 5: `gha-maintain` skill and `/gha:maintain` command

**Files:**
- Create: `skills/gha-maintain/SKILL.md`
- Create: `commands/maintain.md`

**Interfaces:**
- Consumes: `scripts/maintain.sh` (Task 4, contract in Task 4's Interfaces); skills `gha-dangerous-patterns`, `gha-doctor` (Plan 1) by name.
- Produces: skill `gha-maintain` and the `/gha:maintain` slash command. Referenced by `agents/gha-auditor.md` (Task 11).

- [ ] **Step 1: Create the skill**

Create `skills/gha-maintain/SKILL.md`:

````markdown
---
name: gha-maintain
description: This skill should be used when the user asks to "pin my actions", "SHA-pin this workflow", "update action versions", "are my workflows using deprecated actions or runners", "check for outdated actions", or "audit my workflows for drift". Runs pinact through a wrapper for SHA pinning and version checks, then interprets the mechanical inventory for deprecations, EOL toolchains, and cross-workflow drift. Proposes diffs; never commits.
version: 0.1.0
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

## Applying pins

Only after the user has seen the check-mode report and agreed: run
`${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh pin <files>`. This edits the
working tree. Immediately show the user `git diff -- <files>` and stop —
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
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('skills/gha-maintain/SKILL.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-maintain'; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Create the command**

Create `commands/maintain.md`:

```markdown
---
description: Pin/update GitHub Actions, flag deprecations and cross-workflow drift; proposes a diff, never commits
argument-hint: "[workflow files, defaults to .github/workflows/*]"
allowed-tools: Bash, Glob, Read, Task, WebSearch
---

Use the gha-maintain skill to audit and maintain GitHub Actions workflows.

1. Determine targets: use $ARGUMENTS if given; otherwise Glob
   `.github/workflows/*.yml` and `.github/workflows/*.yaml`.
2. If there are more than ~5 workflow files, dispatch the `gha-auditor`
   agent for the read-only audit and relay its condensed summary; apply
   pins afterward (with confirmation) in the main conversation.
3. Otherwise run `${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh check <files>`
   and interpret per the gha-maintain skill (deprecations, drift,
   duplicated logic, unpinned actions).
4. If the user agrees to pin/update, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh pin <files>`, show
   `git diff -- <files>`, and stop. Never commit.

If the script prints `MISSING pinact`, point the user at /gha:doctor.
```

- [ ] **Step 4: Confirm command frontmatter shape**

Run: `head -6 commands/maintain.md`
Expected: frontmatter with `description:`, `argument-hint:`, `allowed-tools:` visible.

- [ ] **Step 5: Commit**

```bash
git add skills/gha-maintain/SKILL.md commands/maintain.md
git commit -m "Add gha-maintain skill and /gha:maintain command"
```

---

### Task 6: Local-run fixture, `scripts/local-run.sh`, and its smoke test

**Files:**
- Create: `tests/fixtures/local-run.yml`
- Create: `scripts/local-run.sh`
- Create: `scripts/tests/test-local-run.sh`

**Interfaces:**
- Consumes: `tests/fixtures/bad-lint.yml` (Plan 1) as the failure-case input.
- Produces: `tests/fixtures/local-run.yml` (a workflow with no `uses:` steps, so it runs deterministically in wrkflw's emulation mode) and `scripts/local-run.sh <workflow-file> [extra wrkflw args...]`. Contract: prints `<file>: wrkflw run PASSED (<runtime>)` or `<file>: wrkflw run FAILED (exit <n>). Last 40 lines:` plus the indented log tail; always prints `Full output: <path>` last; defaults to `--runtime emulation` unless the caller passes `--runtime`; exit `0` whether the workflow passed or failed (the run itself happened), `2` for usage/missing-tool/missing-file. Consumed by `skills/gha-local-run/SKILL.md` (Task 7) and `agents/gha-creator.md` (Task 12).

- [ ] **Step 1: Verify the wrkflw CLI surface**

Run: `wrkflw --help && wrkflw run --help`
Expected: a `run` subcommand accepting a workflow file path, and a `--runtime` option that includes an `emulation` mode. **If the real flags differ** (different option name, different mode spelling), adapt the script and test below to reality and record the deviation in the commit message — the *contract* (summary lines, exit codes) must stay as specified in Interfaces.

- [ ] **Step 2: Create the local-run fixture**

Create `tests/fixtures/local-run.yml`:

```yaml
name: Local Run Example
on:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - name: Say hello
        run: echo "hello from wrkflw"
      - name: Do math
        run: test "$((2 + 2))" = "4"
```

No `uses:` steps on purpose — action resolution is the least portable part
of local execution, and this fixture exists to prove the wrapper works,
not to exercise wrkflw's action emulation.

Run: `python3 -c "import yaml; yaml.safe_load(open('tests/fixtures/local-run.yml')); print('valid yaml')"`
Expected: `valid yaml`

- [ ] **Step 3: Write the failing test**

Create `scripts/tests/test-local-run.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for scripts/local-run.sh using tests/fixtures/local-run.yml
# (pass case) and tests/fixtures/bad-lint.yml (fail case: undefined
# `needs:` dependency, which wrkflw cannot resolve).
# Run: bash scripts/tests/test-local-run.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCALRUN="$SCRIPT_DIR/../local-run.sh"
FIXTURES="$SCRIPT_DIR/../../tests/fixtures"

if ! command -v wrkflw >/dev/null 2>&1; then
  echo "SKIP: wrkflw not installed, cannot run local-run.sh smoke test"
  exit 0
fi

fail=0

pass_output="$("$LOCALRUN" "$FIXTURES/local-run.yml" 2>&1)"
pass_code=$?
if [ "$pass_code" -ne 0 ] || ! echo "$pass_output" | grep -q "PASSED"; then
  echo "FAIL: local-run.yml did not PASS (exit $pass_code). Got:"
  echo "$pass_output"
  fail=1
fi

bad_output="$("$LOCALRUN" "$FIXTURES/bad-lint.yml" 2>&1)"
bad_code=$?
if [ "$bad_code" -ne 0 ] || ! echo "$bad_output" | grep -q "FAILED"; then
  echo "FAIL: bad-lint.yml should report FAILED with exit 0 (got exit $bad_code). Got:"
  echo "$bad_output"
  fail=1
fi

usage_output="$("$LOCALRUN" 2>&1)"
usage_code=$?
if [ "$usage_code" -ne 2 ]; then
  echo "FAIL: no-args invocation should exit 2, got $usage_code"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: local-run.sh smoke test"
fi
exit "$fail"
```

Make it executable: `chmod +x scripts/tests/test-local-run.sh`

- [ ] **Step 4: Run the test to verify it fails**

Run: `bash scripts/tests/test-local-run.sh`
Expected: FAIL — `scripts/local-run.sh` doesn't exist yet.

- [ ] **Step 5: Implement `scripts/local-run.sh`**

Create `scripts/local-run.sh`:

```bash
#!/usr/bin/env bash
# scripts/local-run.sh <workflow-file> [extra wrkflw args...]
# Wraps wrkflw. Defaults to emulation mode (no Docker requirement) unless
# the caller passes --runtime explicitly. Writes the full run log to a
# temp file and prints a compact pass/fail summary. A failing workflow is
# a result, not a script failure: the script still exits 0.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: local-run.sh <workflow-file> [extra wrkflw args...]" >&2
  exit 2
fi

if ! command -v wrkflw >/dev/null 2>&1; then
  echo "MISSING wrkflw. Run /gha:doctor for install instructions."
  exit 2
fi

workflow="$1"; shift
if [ ! -f "$workflow" ]; then
  echo "ERROR $workflow: file not found"
  exit 2
fi

runtime_flag="--runtime emulation"
case " $* " in
  *" --runtime"*) runtime_flag="" ;;
esac

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-local-run.XXXXXX")"

# shellcheck disable=SC2086  # runtime_flag is deliberately word-split
wrkflw run $runtime_flag "$@" "$workflow" > "$TMP_FILE" 2>&1
exit_code=$?

if [ "$exit_code" -eq 0 ]; then
  echo "$workflow: wrkflw run PASSED (${runtime_flag:-caller-specified runtime})"
else
  echo "$workflow: wrkflw run FAILED (exit $exit_code). Last 40 lines:"
  tail -40 "$TMP_FILE" | sed 's/^/  /'
fi

echo "Full output: $TMP_FILE"
exit 0
```

Make it executable: `chmod +x scripts/local-run.sh`

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash scripts/tests/test-local-run.sh`
Expected: `PASS: local-run.sh smoke test`. Two known wrinkles to check if it doesn't: (a) if wrkflw runs `bad-lint.yml` successfully despite the undefined `needs:` (i.e. it doesn't validate dependencies), swap the fail-case fixture for one with a step `run: exit 1` added to a copy in the test's own temp dir; (b) if wrkflw tries to open a TUI even with redirected output, look for a `--no-tui`/CLI flag in `wrkflw run --help` and add it to the script's invocation.

- [ ] **Step 7: Commit**

```bash
git add tests/fixtures/local-run.yml scripts/local-run.sh scripts/tests/test-local-run.sh
git commit -m "Add local-run.sh wrkflw wrapper with fixture and smoke test"
```

---

### Task 7: `gha-local-run` skill and `/gha:test` command

**Files:**
- Create: `skills/gha-local-run/SKILL.md`
- Create: `commands/test.md`

**Interfaces:**
- Consumes: `scripts/local-run.sh` (Task 6, contract in Task 6's Interfaces); skill `gha-doctor` (Plan 1) by name.
- Produces: skill `gha-local-run` and the `/gha:test` slash command. Referenced by `agents/gha-creator.md` (Task 12) — including its troubleshooting matrix, which gha-creator consults on local-run failures.

- [ ] **Step 1: Create the skill**

Create `skills/gha-local-run/SKILL.md`:

````markdown
---
name: gha-local-run
description: This skill should be used when the user asks to "run this workflow locally", "test my GitHub Actions without pushing", "run wrkflw", "dry-run this workflow", or "check if this workflow works before I push". Executes a workflow locally via wrkflw (emulation mode by default, container mode optional) and interprets failures with a troubleshooting matrix.
version: 0.1.0
---

# gha Local Run

Run a GitHub Actions workflow locally without pushing, using `wrkflw`
through `${CLAUDE_PLUGIN_ROOT}/scripts/local-run.sh` rather than invoking
`wrkflw` directly.

## Running a workflow

Run `${CLAUDE_PLUGIN_ROOT}/scripts/local-run.sh <workflow-file>` via Bash.
The script defaults to wrkflw's **emulation mode** (no Docker/Podman
required). To use container mode instead (needed for workflows that
depend on a real container environment), pass it through:
`local-run.sh <file> --runtime docker` (or `podman`).

- `PASSED` → relay the one-line summary as-is.
- `FAILED` → the summary includes the last 40 log lines; diagnose with
  the matrix below before showing the user a wall of log text. The
  `Full output: <path>` line has the complete log for drill-down.
- `MISSING wrkflw` → point the user to `/gha:doctor`.

## Troubleshooting matrix

| Symptom in the log | Likely cause | What to do |
|---|---|---|
| Empty value where `${{ secrets.X }}` is used, or "secret not found" | wrkflw has no access to repo secrets | Provide the value as a plain env var in a local copy of the workflow for the test run, or export it in the environment if wrkflw supports env passthrough (`wrkflw run --help`). Never paste real production secrets into the workflow file. |
| An expression (`${{ }}`) evaluates differently than on GitHub, or errors | wrkflw's expression evaluator doesn't cover every GitHub function/context | Simplify the expression, or accept that this particular check needs a real run on GitHub (`/gha:trigger` after push). |
| A `uses:` action fails to resolve, or behaves oddly | Emulation mode doesn't fully replicate the action runtime (Node version, container features) | Retry with `--runtime docker` if Docker/Podman is available; otherwise note the emulation limitation and validate that step on GitHub. |
| `services:`, `container:`, or Docker-dependent steps fail | Emulation mode has no container engine | This workflow genuinely needs container mode: `--runtime docker`. If no container engine exists on this machine, the workflow can't be fully tested locally — say so plainly. |
| Workflow fails immediately on a `needs:`/structure error | The workflow is invalid, not the runner | Run the `gha-lint` skill first; fix correctness before re-running locally. |

## What local success means

A local PASS is strong evidence, not proof — secrets, GitHub-hosted
runner images, and marketplace action behavior can still differ. The
full confidence chain is lint → security-audit → local run → first real
run on GitHub (via `gha-trigger`/`gha-monitor`).
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('skills/gha-local-run/SKILL.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-local-run'; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Create the command**

Create `commands/test.md`:

```markdown
---
description: Run a GitHub Actions workflow locally via wrkflw (no push needed)
argument-hint: "<workflow-file> [--runtime docker|podman]"
allowed-tools: Bash, Glob, Read
---

Use the gha-local-run skill to run a workflow locally.

1. Target: $ARGUMENTS if given. If not given and the repo has exactly one
   workflow file, use it; if several, list them and ask which to run.
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/local-run.sh <file>` (append any
   extra args the user provided, e.g. `--runtime docker`).
3. Relay PASSED one-liners as-is. For FAILED, diagnose using the
   gha-local-run skill's troubleshooting matrix before dumping log lines.

If the script prints `MISSING wrkflw`, point the user at /gha:doctor.
```

- [ ] **Step 4: Confirm command frontmatter shape**

Run: `head -6 commands/test.md`
Expected: frontmatter with `description:`, `argument-hint:`, `allowed-tools:` visible.

- [ ] **Step 5: Commit**

```bash
git add skills/gha-local-run/SKILL.md commands/test.md
git commit -m "Add gha-local-run skill and /gha:test command"
```

---

### Task 8: `gha-trigger` skill and `/gha:trigger` command

**Files:**
- Create: `skills/gha-trigger/SKILL.md`
- Create: `commands/trigger.md`

**Interfaces:**
- Consumes: the `gh` CLI directly (per the spec, dispatch/rerun/cancel output is inherently small — no wrapper script); skill `gha-doctor` (Plan 1) by name.
- Produces: skill `gha-trigger` and the `/gha:trigger` slash command. Referenced by `skills/gha-brainstorming/SKILL.md` (Task 13) for triggering the first real run.

- [ ] **Step 1: Create the skill**

Create `skills/gha-trigger/SKILL.md`:

````markdown
---
name: gha-trigger
description: This skill should be used when the user asks to "trigger this workflow", "run the deploy workflow on GitHub", "dispatch a workflow", "rerun that failed run", "rerun failed jobs", or "cancel that run". Dispatches, reruns, and cancels GitHub Actions runs via gh, with input prompting for workflow_dispatch and an explicit confirmation before every mutating call.
version: 0.1.0
---

# gha Trigger

Dispatch, rerun, and cancel GitHub Actions runs via `gh`. These calls
produce a handful of lines at most, so they run directly through Bash —
no wrapper script (the spec's context-budget concern doesn't apply).

## Preflight

Run `gh auth status` first (Bash). If it fails, tell the user to run
`gh auth login` themselves and stop — this plugin never handles
credentials. If `gh` isn't installed, point to `/gha:doctor`.

## Confirmation is not optional

**Every mutating call below — dispatch, rerun, cancel — needs the user's
explicit confirmation immediately before it runs**, stating exactly what
will be executed (the full `gh` command and what it affects). This holds
even when this skill is reached from another flow (e.g. gha-brainstorming)
that already got a broad go-ahead: confirm the specific run action anyway.
For cancel/rerun of a run the user didn't start (someone else's run on a
shared repo), point that out during confirmation.

## Dispatching a workflow (`workflow_dispatch`)

1. Identify the workflow file. Read its `on.workflow_dispatch.inputs`
   block (Read tool). If the workflow has no `workflow_dispatch` trigger,
   say so — `gh workflow run` can't dispatch it; offer to add the trigger
   instead (that's a workflow edit → gha-brainstorming / gha-creator
   territory).
2. For each defined input, collect a value from the user (AskUserQuestion
   works well: required inputs first, defaults shown). Skip prompting for
   inputs the user already gave.
3. Confirm, then run:
   `gh workflow run <workflow-file-name> [--ref <branch>] -f key=value ...`
4. Find the new run's id (dispatch is async; retry once after a few
   seconds if empty):
   `gh run list --workflow <workflow-file-name> --limit 1 --json databaseId,status --jq '.[0]'`
5. Offer to watch it via the `gha-monitor` skill (`/gha:watch`).

## Rerunning

- Whole run: `gh run rerun <run-id>`
- Only failed jobs: `gh run rerun <run-id> --failed`
Confirm first, showing which run (fetch its title with
`gh run view <run-id> --json displayTitle,workflowName,conclusion --jq
'"\(.workflowName): \(.displayTitle) (\(.conclusion))"'`).

## Cancelling

`gh run cancel <run-id>` — confirm first, same identification as above.
A completed run can't be cancelled; check `status` and say so instead of
running a command that will error.
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('skills/gha-trigger/SKILL.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-trigger'; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Create the command**

Create `commands/trigger.md`:

```markdown
---
description: Trigger, rerun, or cancel a GitHub Actions run (with confirmation)
argument-hint: "<workflow-file | run-id> [inputs...]"
allowed-tools: Bash, Read, Glob, AskUserQuestion
---

Use the gha-trigger skill to dispatch, rerun, or cancel GitHub Actions
runs via gh.

1. Preflight `gh auth status`; on failure tell the user to run
   `gh auth login` and stop.
2. Work out the intent from $ARGUMENTS: a workflow file (or name) means
   dispatch; a run id plus "rerun"/"cancel" wording means that operation.
   Ambiguous → ask.
3. For dispatch, read the workflow's `workflow_dispatch` inputs and
   prompt for values per the gha-trigger skill.
4. **Confirm the exact gh command with the user before running it.**
5. After a dispatch, report the new run id and offer /gha:watch.
```

- [ ] **Step 4: Confirm command frontmatter shape**

Run: `head -6 commands/trigger.md`
Expected: frontmatter with `description:`, `argument-hint:`, `allowed-tools:` visible.

- [ ] **Step 5: Verify the gh subcommands used actually exist**

Run: `gh workflow run --help >/dev/null && gh run rerun --help >/dev/null && gh run cancel --help >/dev/null && echo "gh surface ok"`
Expected: `gh surface ok`

- [ ] **Step 6: Commit**

```bash
git add skills/gha-trigger/SKILL.md commands/trigger.md
git commit -m "Add gha-trigger skill and /gha:trigger command"
```

---

### Task 9: `scripts/gh-run-log.sh` and its smoke test

**Files:**
- Create: `scripts/gh-run-log.sh`
- Create: `scripts/tests/test-gh-run-log.sh`

**Interfaces:**
- Consumes: authenticated `gh` CLI; `jq`.
- Produces: `scripts/gh-run-log.sh view <run-id> | history [--workflow <name>] [--limit <n>]`. Contract — `view`: prints `<workflowName>: <displayTitle> — <status> (<conclusion>)`, one `  job <name>: <conclusion>` line per job, and (only if a job failed) `  failed-step log excerpt (last 40 lines):` with indented log lines; the run's full log is written to the temp file. `history`: prints `history: <count> run(s) analyzed` then one `  <workflowName>: <n> runs, <n> success, <n> failure, avg <n>s` line per workflow; the raw JSON is the temp file. Both modes print `Full output: <path>` last and exit `0`; usage errors/missing tools exit `2`. Honors the `GH_REPO` env var to target a repo other than the cwd's. Consumed by `skills/gha-monitor/SKILL.md` (Task 10).

- [ ] **Step 1: Verify the gh JSON fields this script relies on**

Run: `gh run list --help | grep -A2 -- '--json' ; gh run view --help | grep -E -- '--(json|log|log-failed)'`
Expected: `--json` supported on both, `--log` and `--log-failed` on view. Then sanity-check field names against a real public repo:
`GH_REPO=cli/cli gh run list --limit 2 --json workflowName,status,conclusion,startedAt,updatedAt,databaseId`
Expected: a JSON array with those exact keys. If any field name is rejected, `gh run list --json ''` (empty) lists the valid fields — adapt and note in the commit message.

- [ ] **Step 2: Write the failing test**

Create `scripts/tests/test-gh-run-log.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for scripts/gh-run-log.sh. Usage/arg checks always run; the
# live checks run against the public cli/cli repo and need an
# authenticated gh (read-only calls only).
# Run: bash scripts/tests/test-gh-run-log.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNLOG="$SCRIPT_DIR/../gh-run-log.sh"

if ! command -v gh >/dev/null 2>&1; then
  echo "SKIP: gh not installed, cannot run gh-run-log.sh smoke test"
  exit 0
fi

fail=0

usage_output="$("$RUNLOG" 2>&1)"
usage_code=$?
if [ "$usage_code" -ne 2 ]; then
  echo "FAIL: no-args invocation should exit 2, got $usage_code"
  fail=1
fi

badmode_output="$("$RUNLOG" frobnicate 123 2>&1)"
badmode_code=$?
if [ "$badmode_code" -ne 2 ]; then
  echo "FAIL: unknown mode should exit 2, got $badmode_code"
  fail=1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "SKIP (live checks): gh not authenticated — run 'gh auth login', then re-run"
  echo "PARTIAL PASS: gh-run-log.sh arg handling"
  exit "$fail"
fi

hist_output="$(GH_REPO=cli/cli "$RUNLOG" history --limit 5 2>&1)"
if ! echo "$hist_output" | grep -q "run(s) analyzed"; then
  echo "FAIL: history mode produced no analysis line. Got:"
  echo "$hist_output"
  fail=1
fi

run_id="$(GH_REPO=cli/cli gh run list --limit 1 --status completed --json databaseId --jq '.[0].databaseId')"
if [ -n "$run_id" ]; then
  view_output="$(GH_REPO=cli/cli "$RUNLOG" view "$run_id" 2>&1)"
  if ! echo "$view_output" | grep -q "  job "; then
    echo "FAIL: view mode printed no job lines for run $run_id. Got:"
    echo "$view_output" | head -20
    fail=1
  fi
else
  echo "WARN: couldn't find a completed run in cli/cli; view-mode live check skipped"
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: gh-run-log.sh smoke test"
fi
exit "$fail"
```

Make it executable: `chmod +x scripts/tests/test-gh-run-log.sh`

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash scripts/tests/test-gh-run-log.sh`
Expected: FAIL — `scripts/gh-run-log.sh` doesn't exist yet.

- [ ] **Step 4: Implement `scripts/gh-run-log.sh`**

Create `scripts/gh-run-log.sh`:

```bash
#!/usr/bin/env bash
# scripts/gh-run-log.sh view <run-id> | history [--workflow <name>] [--limit <n>]
# Wraps the gh calls whose output volume needs compressing: full run logs
# (view) and run-history JSON (history). Set GH_REPO=owner/name to target
# a repo other than the current directory's.
set -uo pipefail

usage() {
  echo "usage: gh-run-log.sh view <run-id> | history [--workflow <name>] [--limit <n>]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
mode="$1"; shift

if ! command -v gh >/dev/null 2>&1; then
  echo "MISSING gh. Run /gha:doctor for install instructions."
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING jq. Run /gha:doctor for install instructions."
  exit 2
fi

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-run-log.XXXXXX")"

case "$mode" in
  view)
    [ "$#" -eq 1 ] || usage
    run_id="$1"
    if ! summary="$(gh run view "$run_id" --json workflowName,displayTitle,status,conclusion,jobs 2>"$TMP_FILE.err")"; then
      echo "ERROR gh run view failed:"
      sed 's/^/  /' "$TMP_FILE.err"
      exit 2
    fi
    echo "$summary" | jq -r '"\(.workflowName): \(.displayTitle) — \(.status) (\(.conclusion // "in progress"))"'
    echo "$summary" | jq -r '.jobs[] | "  job \(.name): \(.conclusion // .status)"'
    gh run view "$run_id" --log > "$TMP_FILE" 2>/dev/null || true
    failed="$(echo "$summary" | jq '[.jobs[] | select(.conclusion == "failure")] | length')"
    if [ "$failed" -gt 0 ]; then
      echo "  failed-step log excerpt (last 40 lines):"
      gh run view "$run_id" --log-failed 2>/dev/null | tail -40 | sed 's/^/    /'
    fi
    ;;
  history)
    workflow=""
    limit=30
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --workflow) [ "$#" -ge 2 ] || usage; workflow="$2"; shift 2 ;;
        --limit)    [ "$#" -ge 2 ] || usage; limit="$2";    shift 2 ;;
        *) usage ;;
      esac
    done
    if [ -n "$workflow" ]; then
      gh run list --workflow "$workflow" --limit "$limit" \
        --json workflowName,status,conclusion,startedAt,updatedAt,databaseId \
        > "$TMP_FILE" 2>"$TMP_FILE.err"
    else
      gh run list --limit "$limit" \
        --json workflowName,status,conclusion,startedAt,updatedAt,databaseId \
        > "$TMP_FILE" 2>"$TMP_FILE.err"
    fi
    if [ $? -ne 0 ]; then
      echo "ERROR gh run list failed:"
      sed 's/^/  /' "$TMP_FILE.err"
      exit 2
    fi
    count="$(jq 'length' "$TMP_FILE")"
    if [ "$count" -eq 0 ]; then
      echo "history: no runs found"
    else
      echo "history: $count run(s) analyzed"
      jq -r 'group_by(.workflowName)[]
        | . as $runs
        | ($runs | map(select(.conclusion == "success")) | length) as $ok
        | ($runs | map(select(.conclusion == "failure")) | length) as $bad
        | ($runs | map(select(.startedAt != null and .updatedAt != null)
                   | ((.updatedAt | fromdateiso8601) - (.startedAt | fromdateiso8601)))) as $durs
        | "  \($runs[0].workflowName): \($runs | length) runs, \($ok) success, \($bad) failure"
          + (if ($durs | length) > 0 then ", avg \(($durs | add / ($durs | length)) | floor)s" else "" end)' \
        "$TMP_FILE"
    fi
    ;;
  *)
    usage
    ;;
esac

echo "Full output: $TMP_FILE"
exit 0
```

Make it executable: `chmod +x scripts/gh-run-log.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/tests/test-gh-run-log.sh`
Expected: `PASS: gh-run-log.sh smoke test` (needs authenticated gh; the live checks hit the public cli/cli repo read-only). The view-mode log download can take ~30s on a big run — that's normal.

- [ ] **Step 6: Commit**

```bash
git add scripts/gh-run-log.sh scripts/tests/test-gh-run-log.sh
git commit -m "Add gh-run-log.sh wrapper (run logs + history aggregation) with smoke test"
```

---

### Task 10: `gha-monitor` skill and `/gha:watch` command

**Files:**
- Create: `skills/gha-monitor/SKILL.md`
- Create: `commands/watch.md`

**Interfaces:**
- Consumes: `scripts/gh-run-log.sh` (Task 9, contract in Task 9's Interfaces); `gh run watch` directly (streaming, deliberately unwrapped per the spec); skills `gha-trigger`, `gha-doctor` by name.
- Produces: skill `gha-monitor` and the `/gha:watch` slash command. Referenced by `skills/gha-brainstorming/SKILL.md` (Task 13) for watching the first real run.

- [ ] **Step 1: Create the skill**

Create `skills/gha-monitor/SKILL.md`:

````markdown
---
name: gha-monitor
description: This skill should be used when the user asks to "watch this workflow run", "is my CI passing", "monitor the deploy", "why did that run fail", "show me the run logs", "which workflows are flaky", or "how healthy is our CI". Watches GitHub Actions runs live (foreground or background) and produces run-history health reports via gh.
version: 0.1.0
---

# gha Monitor

Watch GitHub Actions runs and analyze run history via `gh`. Three modes:
live watch, single-run log analysis, and history/health reporting. Set
`GH_REPO=owner/name` in the Bash environment to target a repo other than
the current directory's.

## Preflight

`gh auth status` must pass; otherwise tell the user to run
`gh auth login` and stop. `gh` missing → `/gha:doctor`.

## Live watch

- **Foreground** (user wants to follow along now):
  `gh run watch <run-id> --exit-status` via Bash. This streams compact
  status updates by design — it's the one gh call this plugin runs
  unwrapped despite being long-running, because buffering a live stream
  into a temp file would defeat watching. Exit code 0 = run succeeded,
  non-zero = run failed; report which.
- **Background** (user wants to keep working): if this harness provides a
  Monitor tool (or background Bash), run the same command in the
  background and report when it completes. Don't poll in a loop in the
  foreground — that burns context for no benefit.
- Watching mutates nothing, so no confirmation is needed. But if the user
  asks to *do* something to the run (cancel, rerun), that's the
  `gha-trigger` skill, with its confirmation rule.

## Analyzing a finished run

Run `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh view <run-id>` via Bash.
It prints the run's headline, one line per job, and — only when a job
failed — the last 40 lines of the failed steps' logs. Diagnose from the
excerpt; the `Full output: <path>` file has the complete log if the
excerpt isn't enough. Don't paste the full log into the conversation.

## Health report

Run `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh history [--workflow <name>] [--limit <n>]`
(default limit 30). It prints one aggregate line per workflow: run count,
successes, failures, average duration. Interpret, don't just relay:

- **Flaky**: a workflow with both successes and failures in the window,
  with no correlated change (check whether failures cluster before a fix
  landed vs alternate randomly — drill into specific runs with view mode).
- **Chronically red**: all/mostly failures — CI rot; propose fixing or
  removing the workflow.
- **Slow or degrading**: compare average durations across workflows and
  against what the team expects; for trends over time, run history twice
  with different limits and compare.

For anything suspicious, drill down: `view <run-id>` on a representative
failure, then propose the concrete fix (often a `gha-lint` /
`gha-security-audit` / `gha-maintain` follow-up).
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('skills/gha-monitor/SKILL.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-monitor'; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Create the command**

Create `commands/watch.md`:

```markdown
---
description: Watch a GitHub Actions run live, analyze a finished run, or report CI health
argument-hint: "[run-id | 'health' | workflow name]"
allowed-tools: Bash, Read, Glob
---

Use the gha-monitor skill.

1. Preflight `gh auth status`; on failure tell the user to run
   `gh auth login` and stop.
2. Route by $ARGUMENTS:
   - a run id → if the run is in progress, live watch
     (`gh run watch <id> --exit-status`); if finished, analyze it via
     `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh view <id>`.
   - "health" (optionally plus a workflow name) → health report via
     `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-log.sh history [--workflow <name>]`.
   - nothing → show recent runs (`gh run list --limit 10`) and ask which
     to watch or analyze.
3. Interpret findings per the gha-monitor skill (flaky/chronically
   red/slow), don't just relay raw lines.
```

- [ ] **Step 4: Confirm command frontmatter shape**

Run: `head -6 commands/watch.md`
Expected: frontmatter with `description:`, `argument-hint:`, `allowed-tools:` visible.

- [ ] **Step 5: Commit**

```bash
git add skills/gha-monitor/SKILL.md commands/watch.md
git commit -m "Add gha-monitor skill and /gha:watch command"
```

---

### Task 11: `gha-auditor` agent

**Files:**
- Create: `agents/gha-auditor.md`

**Interfaces:**
- Consumes: `scripts/lint.sh` (Plan 1), `scripts/security-audit.sh` (Task 2), `scripts/maintain.sh` (Task 4) — all via Bash with the contracts in their tasks' Interfaces blocks; `skills/gha-dangerous-patterns/SKILL.md` (Plan 1) read directly as reference content.
- Produces: the `gha-auditor` agent, dispatched by name from `commands/review.md` (Task 3), `commands/maintain.md` (Task 5), and natural-language full-repo audit requests.

- [ ] **Step 1: Create the agent**

Create `agents/gha-auditor.md`:

````markdown
---
name: gha-auditor
description: Use this agent when a full-repo GitHub Actions audit is requested, or when /gha:review or /gha:maintain targets a repo with many workflow files (more than ~5). It runs lint, security, and maintenance checks across all workflow files and returns a condensed findings summary instead of raw per-file output. Examples:

<example>
Context: A repo with 12 workflow files, user asks for a review.
user: "Review all our GitHub Actions workflows"
assistant: "This repo has 12 workflow files, so I'll dispatch the gha-auditor agent to audit them all and bring back a consolidated summary."
<commentary>
Per-file tool output for 12 files would flood the main conversation's context; the auditor runs everything and condenses.
</commentary>
</example>

<example>
Context: User wants a maintenance sweep of a monorepo.
user: "Are any of our workflows using deprecated actions?"
assistant: "I'll dispatch the gha-auditor agent to inventory every workflow and flag deprecated runners and actions."
<commentary>
Cross-workflow deprecation/drift analysis needs every file's inventory in one place — a subagent keeps that bulk out of the main thread.
</commentary>
</example>
tools: Read, Grep, Glob, Bash
---

You are a GitHub Actions workflow auditor. You audit every workflow file
in a repository for correctness, security, and maintenance issues, and
return a **condensed** summary — never raw tool output.

## Process

1. Find targets: Glob `.github/workflows/*.yml` and `.github/workflows/*.yaml`
   (use the file list you were given if the dispatching conversation
   provided one).
2. Run each check via the gha wrapper scripts (never the underlying tools
   directly), passing **all** files to each single invocation:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh <files...>` — correctness
   - `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh <files...>` — security
   - `${CLAUDE_PLUGIN_ROOT}/scripts/maintain.sh check <files...>` — pinning + inventory
3. Read `${CLAUDE_PLUGIN_ROOT}/skills/gha-dangerous-patterns/SKILL.md`
   and check the workflows for its anti-patterns that static tools can
   miss (cache/artifact poisoning across trust boundaries especially) —
   read the actual workflow files for anything the scripts flagged or
   that pattern-matching suggests.
4. If any script prints `MISSING <tool>`, record that category as
   "skipped: <tool> not installed (run /gha:doctor)" and continue with
   the others.

## Report format (your final message)

- **Headline:** file count, findings count per category (correctness /
  security / maintenance), and the single most important thing to fix.
- **Findings:** grouped by severity (security findings that are
  exploitable first), each as `file:line — issue — fix`, deduplicated
  across tools (zizmor and the patterns catalog overlap; report once).
- **Drift table:** actions used at inconsistent versions across files,
  from maintain.sh's inventory.
- **Skipped/uncertain:** anything you couldn't check and why.
- Include each script's `Full output:` temp-file path so the main
  conversation can drill in without re-running.

Never dump raw SARIF/JSON or more than ~3 log lines per finding. You are
read-only: never edit files, never run maintain.sh in pin mode, never
commit, and never call gh with a mutating subcommand.
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('agents/gha-auditor.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-auditor'; assert 'tools' in d; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Commit**

```bash
git add agents/gha-auditor.md
git commit -m "Add gha-auditor agent for condensed full-repo audits"
```

---

### Task 12: `gha-creator` agent

**Files:**
- Create: `agents/gha-creator.md`

**Interfaces:**
- Consumes: `scripts/lint.sh` (Plan 1), `scripts/security-audit.sh` (Task 2), `scripts/local-run.sh` (Task 6) via Bash; `skills/gha-dangerous-patterns/SKILL.md` and `skills/gha-local-run/SKILL.md` (troubleshooting matrix) read as reference content.
- Produces: the `gha-creator` agent, dispatched by `skills/gha-brainstorming/SKILL.md` (Task 13) after plan approval, or directly for well-specified workflow-writing requests.

- [ ] **Step 1: Create the agent**

Create `agents/gha-creator.md`:

````markdown
---
name: gha-creator
description: Use this agent to write or modify a GitHub Actions workflow file from an approved plan and iterate until lint, security, and local-run checks all pass. Dispatched by the gha-brainstorming flow after plan approval, or directly when the user has already specified exactly what the workflow should do. Examples:

<example>
Context: The gha-brainstorming flow has an approved plan for a test workflow.
user: "Plan approved, build it"
assistant: "I'll dispatch the gha-creator agent to write the workflow and loop lint → security → local-run until it's clean."
<commentary>
The iterative fix loop (write, check, fix, re-check) is noisy; the subagent keeps it out of the main conversation and returns one summary.
</commentary>
</example>

<example>
Context: User gives a complete, unambiguous spec inline.
user: "Create a workflow that runs 'make test' on every push to main on ubuntu-latest, nothing else"
assistant: "That's fully specified, so I'll dispatch the gha-creator agent directly to write and verify it."
<commentary>
No brainstorming needed when requirements are already exact; the creator still runs the full verification loop.
</commentary>
</example>
tools: Read, Write, Edit, Grep, Glob, Bash, WebSearch
---

You write and edit GitHub Actions workflow YAML, and you do not stop at
"looks right" — you verify with the gha check loop until it's clean.

## Before writing

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/gha-dangerous-patterns/SKILL.md`
   and apply it **while writing** — explicit least-privilege
   `permissions:`, no untrusted `${{ }}` interpolation in `run:` steps,
   `persist-credentials: false` on checkouts unless credentials are
   genuinely needed downstream.
2. Look at existing workflows in the repo (Glob `.github/workflows/*`)
   and match their conventions (naming, runner choices, indentation).
3. For marketplace actions: verify the current major version with
   WebSearch if you're not certain, and pin third-party (non-`actions/*`)
   actions to a full-length commit SHA with the version as a trailing
   comment.

## The verification loop

Write the workflow per the plan you were given, then loop (max 5
iterations; all scripts via Bash):

1. `${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh <file>` — fix every finding.
2. `${CLAUDE_PLUGIN_ROOT}/scripts/security-audit.sh <file>` — fix every
   finding (the dangerous-patterns catalog explains the why and the fix).
3. `${CLAUDE_PLUGIN_ROOT}/scripts/local-run.sh <file>` — on FAILED,
   diagnose with the troubleshooting matrix in
   `${CLAUDE_PLUGIN_ROOT}/skills/gha-local-run/SKILL.md`. A failure
   caused by a genuine local-execution limitation (secrets, emulation
   gaps) is acceptable to carry as a caveat; a failure in workflow logic
   is not.

If any script prints `MISSING <tool>`, skip that check, and say so in
your report rather than silently passing.

## Hard boundaries

- **Never** run `git push`, `gh pr create`, `gh workflow run`, `gh run
  rerun`/`cancel`, or `git commit`. Your job ends at a verified file in
  the working tree — the main conversation owns every confirmation gate.
- Don't create files other than the workflow file(s) in the plan.

## Report format (your final message)

- The workflow file path(s) and a 2-3 sentence description of behavior.
- Check results: lint / security / local-run, each "clean", "clean with
  caveat: <what>", or "skipped: <why>".
- Iterations used and what the loop caught (one line each — this tells
  the user what reviewing already happened).
- Any decision you made that the plan didn't specify.
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('agents/gha-creator.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-creator'; assert 'tools' in d; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Commit**

```bash
git add agents/gha-creator.md
git commit -m "Add gha-creator agent with lint/security/local-run verification loop"
```

---

### Task 13: `gha-brainstorming` skill and `/gha:brainstorming` command

**Files:**
- Create: `skills/gha-brainstorming/SKILL.md`
- Create: `commands/brainstorming.md`

**Interfaces:**
- Consumes: agents `gha-creator` (Task 12) and skills `gha-lint`, `gha-security-audit`, `gha-local-run`, `gha-trigger`, `gha-monitor`, `gha-dangerous-patterns` — all by name; no wrapper scripts directly.
- Produces: skill `gha-brainstorming` and the `/gha:brainstorming` slash command. This is the flow that ties every other component together; nothing later depends on it (Task 14 is validation only).

- [ ] **Step 1: Create the skill**

Create `skills/gha-brainstorming/SKILL.md`:

````markdown
---
name: gha-brainstorming
description: This skill should be used when the user asks to "create a workflow", "add CI to this repo", "set up a deploy pipeline", "add a GitHub Action for X", or wants to significantly modify an existing workflow's behavior. Guides workflow creation/modification through clarifying questions, best-practice research, a short approved design, then dispatches gha-creator to build and verify it. Self-contained — requires no other plugins.
version: 0.1.0
---

# gha Brainstorming

Guide the user from "I want a workflow that does X" to a verified,
running workflow. Follow the steps in order; the two **GATE** steps are
hard stops that require the user's explicit go-ahead.

Small tweaks (bump a version, fix one step) don't need this ceremony —
edit directly and run the `gha-lint`/`gha-security-audit` skills. This
flow is for new workflows or behavior-changing modifications.

## The flow

1. **Explore context.** Existing workflows (Glob `.github/workflows/*`),
   project language/tooling (manifests, lockfiles), CI conventions
   already in use. Don't ask the user things the repo already answers.
2. **Clarify, one question at a time:** trigger events; what makes the
   workflow pass vs fail; secrets/environments needed; runner choice
   (default `ubuntu-latest` unless there's a reason). Prefer multiple
   choice (AskUserQuestion). Stop when you could write the workflow
   without guessing.
3. **Research current best practice** for the specific actions involved
   (WebSearch/web fetch): current major versions, known deprecations.
   Don't trust memorized versions — they rot.
4. **Propose 2-3 approaches** with trade-offs and a recommendation
   (e.g. matrix vs single job; marketplace action vs plain `run:` steps).
5. **Present a short inline design summary** — trigger, jobs, key
   decisions — in chat (not a committed spec file). Get approval.
6. **Write the inline plan** (this flow's own format, in chat):

   ```
   Workflow: .github/workflows/<name>.yml (create | modify)
   Trigger:  <events + filters>
   Jobs:
     - <job>: <runner> — <key steps, one line each>
   Secrets/permissions: <what and why, or "none">
   Verification: lint → security-audit → local run → first real run
   ```

   Get approval on the plan. (Self-contained on purpose: this flow never
   invokes another plugin's planning skills.)
7. **Dispatch the `gha-creator` agent** with the approved plan. It
   writes the YAML and loops lint → security-audit → local-run until
   clean, then reports back. Relay its report, including caveats.
8. **GATE: nothing leaves the machine without explicit confirmation.**
   Present the finished workflow and ask the user explicitly before ANY
   of: committing+pushing, opening a PR, or triggering a run. "The local
   loop is clean" is not consent to push.
9. **On confirmation:** push / open the PR as agreed, then trigger the
   first real run via the `gha-trigger` skill and watch it via
   `gha-monitor`. Report pass/fail; on failure, diagnose (gha-monitor's
   view mode) and loop back to gha-creator with the fix.
10. **GATE: never merge without being told.** When the run is green, stop
    and ask. Merging is always the user's explicit call — even if they
    said "handle everything" earlier.
````

- [ ] **Step 2: Verify the frontmatter parses**

Run: `python3 -c "import yaml; content = open('skills/gha-brainstorming/SKILL.md').read(); d = yaml.safe_load(content.split('---')[1]); assert d['name'] == 'gha-brainstorming'; print('frontmatter ok')"`
Expected: `frontmatter ok`

- [ ] **Step 3: Create the command**

Create `commands/brainstorming.md`:

```markdown
---
description: Guided creation or modification of a GitHub Actions workflow (design → verify → run)
argument-hint: "[what the workflow should do]"
allowed-tools: Bash, Read, Glob, Grep, WebSearch, WebFetch, Task, AskUserQuestion
---

Use the gha-brainstorming skill to guide workflow creation or
modification, starting from $ARGUMENTS if the user provided a
description.

Follow the skill's flow exactly, including both GATE steps: explicit
user confirmation before anything is pushed/PR'd/triggered, and again
before any merge. The gha-creator agent does the writing and
verification; this conversation owns the questions, approvals, and
gates.
```

- [ ] **Step 4: Confirm command frontmatter shape**

Run: `head -6 commands/brainstorming.md`
Expected: frontmatter with `description:`, `argument-hint:`, `allowed-tools:` visible.

- [ ] **Step 5: Commit**

```bash
git add skills/gha-brainstorming/SKILL.md commands/brainstorming.md
git commit -m "Add gha-brainstorming skill and /gha:brainstorming command"
```

---

### Task 14: Final polish, validation, and v1.0.0

**Files:**
- Modify: `skills/gha-doctor/SKILL.md` (lines 35-37, 42), `skills/gha-dangerous-patterns/SKILL.md` (lines 12, 76), `skills/gha-lint/SKILL.md` (line 44)
- Modify: `README.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- Modify: `docs/superpowers/plans/2026-07-15-gha-plugin-complete.md` (status note)

**Interfaces:**
- Consumes: everything from Tasks 1-13 plus all of Plan 1.
- Produces: the released plugin, v1.0.0. Nothing after this.

- [ ] **Step 1: Sweep stale "(a later plan)" references from Plan 1 files**

Everything those phrases promised now exists. Run `grep -rn "later plan" skills/ commands/` to locate them (7 hits expected), then make these edits:

In `skills/gha-doctor/SKILL.md`:
- `Local workflow execution without requiring Docker (a later plan's \`gha-local-run\`).` → `Local workflow execution without requiring Docker (used by \`gha-local-run\`).`
- `Security static analysis (a later plan's \`gha-security-audit\`)` → `Security static analysis (used by \`gha-security-audit\`)`
- `SHA-pinning and version updates for actions (a later plan's \`gha-maintain\`)` → `SHA-pinning and version updates for actions (used by \`gha-maintain\`)`
- `If \`gha-lint\` (or, in later plans, \`gha-security-audit\`, \`gha-local-run\`,` → `If \`gha-lint\` (or \`gha-security-audit\`, \`gha-local-run\`,`

In `skills/gha-dangerous-patterns/SKILL.md`:
- `the \`gha-security-audit\` skill (a\nlater plan) runs \`zizmor\`` → `the \`gha-security-audit\` skill runs \`zizmor\`` (rewrap the paragraph)
- `what the \`pinact\` tool (via \`gha-maintain\`, a later plan) automates.` → `what the \`pinact\` tool (via \`gha-maintain\`) automates.`

In `skills/gha-lint/SKILL.md`:
- `that's the \`gha-security-audit\`\nskill's job (a later plan) — cross-reference the \`gha-dangerous-patterns\`\nskill's catalog in the meantime if \`gha-security-audit\` isn't available yet\nin this installation.` → `that's the \`gha-security-audit\` skill's job (or \`/gha:review\`, which runs both lint and security together).` (rewrap the paragraph)

Then re-run: `grep -rn "later plan" skills/ commands/`
Expected: no matches.

- [ ] **Step 2: Rewrite the README to final form**

Replace the entire contents of `README.md` with:

```markdown
# gha

A Claude Code plugin for the full GitHub Actions workflow lifecycle:
creating workflows through a guided brainstorming flow, reviewing them
for correctness and security, running them locally, keeping them
current, and triggering and monitoring runs on GitHub — all from inside
Claude Code.

## Install

\`\`\`
/plugin marketplace add devrelaicom/github-actions-plugin
/plugin install gha
\`\`\`

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
```

(The two `\`\`\`` sequences inside the Install section above are escaped so this plan renders; write them as literal triple-backtick fences in the real README. The file ends after the plans line.)

- [ ] **Step 3: Bump the version to 1.0.0**

In `.claude-plugin/plugin.json`: change `"version": "0.1.0"` to `"version": "1.0.0"`.
In `.claude-plugin/marketplace.json`: change the plugin entry's `"version": "0.1.0"` to `"version": "1.0.0"`.

Run: `jq -r .version .claude-plugin/plugin.json && jq -r '.plugins[0].version' .claude-plugin/marketplace.json`
Expected: `1.0.0` twice.

- [ ] **Step 4: Run every smoke test**

```bash
bash scripts/tests/test-doctor.sh
bash scripts/tests/test-lint.sh
bash scripts/tests/test-security-audit.sh
bash scripts/tests/test-maintain.sh
bash scripts/tests/test-local-run.sh
bash scripts/tests/test-gh-run-log.sh
```

Expected: six `PASS` lines, no `SKIP` (the toolchain is a precondition of this plan — a SKIP means the environment regressed; fix that before proceeding).

- [ ] **Step 5: Structural validation**

Dispatch the `plugin-dev:plugin-validator` agent against this repo. Confirm no errors for: both manifests, frontmatter on all 7 commands, all 9 skills, both agents. Fix anything it flags before proceeding.

- [ ] **Step 6: Manual end-to-end smoke test (real scratch repo)**

Install the plugin into a live session (`cc --plugin-dir "$(pwd)"`) and work through this checklist. For the GitHub-touching items, use a scratch repo (create one: `gh repo create gha-plugin-scratch --private --clone`).

Local (this repo):
1. `/gha:doctor` — six OK lines.
2. `/gha:review tests/fixtures/bad-security.yml` — consolidated report; security findings with file:line; no raw SARIF in the conversation.
3. `/gha:maintain tests/fixtures/bad-lint.yml` — check-mode report + inventory; agree to pin; verify it shows `git diff` and does NOT commit; then `git checkout -- tests/fixtures/bad-lint.yml` to restore.
4. `/gha:test tests/fixtures/local-run.yml` — PASSED one-liner.
5. Natural language: "is tests/fixtures/bad-security.yml safe?" — `gha-security-audit` triggers without the slash command.

Scratch repo (E2E):
6. `/gha:brainstorming` — ask for a trivial CI workflow (echo + a real checkout). Verify: questions come one at a time, design + plan approvals happen, `gha-creator` runs its loop, and the flow **stops for confirmation before pushing** (GATE 1).
7. Confirm the push; verify it triggers the first run via `gha-trigger` (with its own confirmation) and watches via `gha-monitor`, reporting pass/fail.
8. `/gha:trigger` the workflow again with `workflow_dispatch` — verify input prompting (add an input to the workflow first if needed) and the confirmation gate.
9. `/gha:watch health` in the scratch repo — aggregate line(s) appear.
10. Verify GATE 2: ask the flow to "finish up" — it must ask before any merge, not merge on its own.
11. Delete the scratch repo: `gh repo delete gha-plugin-scratch --yes` (requires the `delete_repo` scope — or delete via the web UI).

- [ ] **Step 7: Mark this plan complete and commit**

Add a status note at the top of this plan file (below the title):
`> **Status: Complete (<date>).** All 14 tasks implemented. <One line on any deviations discovered during implementation — CLI flag adaptations, test adjustments — or "no deviations".>`

```bash
git add -A
git commit -m "Finalize gha plugin v1.0.0: README, version bump, stale-reference sweep"
```
