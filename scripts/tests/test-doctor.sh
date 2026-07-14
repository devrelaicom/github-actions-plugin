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
