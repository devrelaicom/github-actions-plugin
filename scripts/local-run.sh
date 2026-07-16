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
runtime_label="emulation"
prev=""
for arg in "$@"; do
  case "$arg" in
    --runtime) runtime_flag="" ;;
    --runtime=*) runtime_flag=""; runtime_label="${arg#--runtime=}" ;;
  esac
  if [ "$prev" = "--runtime" ]; then
    runtime_label="$arg"
  fi
  prev="$arg"
done

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-local-run.XXXXXX")"

# shellcheck disable=SC2086  # runtime_flag is deliberately word-split
wrkflw run $runtime_flag "$@" "$workflow" > "$TMP_FILE" 2>&1
exit_code=$?

if [ "$exit_code" -eq 0 ]; then
  echo "$workflow: wrkflw run PASSED ($runtime_label)"
else
  echo "$workflow: wrkflw run FAILED (exit $exit_code). Last 40 lines:"
  tail -40 "$TMP_FILE" | sed 's/^/  /'
fi

echo "Full output: $TMP_FILE"
exit 0
