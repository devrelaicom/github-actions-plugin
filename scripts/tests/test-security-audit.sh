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
