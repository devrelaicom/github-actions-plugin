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

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-lint.XXXXXX")"

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
