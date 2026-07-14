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
