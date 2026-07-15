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
