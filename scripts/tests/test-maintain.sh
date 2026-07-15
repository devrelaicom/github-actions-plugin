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
