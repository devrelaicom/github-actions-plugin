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
