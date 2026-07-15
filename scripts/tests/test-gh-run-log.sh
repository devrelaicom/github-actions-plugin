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
