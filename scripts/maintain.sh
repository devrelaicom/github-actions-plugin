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
