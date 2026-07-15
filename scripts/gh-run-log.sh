#!/usr/bin/env bash
# scripts/gh-run-log.sh view <run-id> | history [--workflow <name>] [--limit <n>]
# Wraps the gh calls whose output volume needs compressing: full run logs
# (view) and run-history JSON (history). Set GH_REPO=owner/name to target
# a repo other than the current directory's.
set -uo pipefail

usage() {
  echo "usage: gh-run-log.sh view <run-id> | history [--workflow <name>] [--limit <n>]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
mode="$1"; shift

if ! command -v gh >/dev/null 2>&1; then
  echo "MISSING gh. Run /gha:doctor for install instructions."
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "MISSING jq. Run /gha:doctor for install instructions."
  exit 2
fi

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/gha-run-log.XXXXXX")"

case "$mode" in
  view)
    [ "$#" -eq 1 ] || usage
    run_id="$1"
    if ! summary="$(gh run view "$run_id" --json workflowName,displayTitle,status,conclusion,jobs 2>"$TMP_FILE.err")"; then
      echo "ERROR gh run view failed:"
      sed 's/^/  /' "$TMP_FILE.err"
      exit 2
    fi
    echo "$summary" | jq -r '"\(.workflowName): \(.displayTitle) — \(.status) (\(.conclusion // "in progress"))"'
    echo "$summary" | jq -r '.jobs[] | "  job \(.name): \(.conclusion // .status)"'
    gh run view "$run_id" --log > "$TMP_FILE" 2>/dev/null || true
    failed="$(echo "$summary" | jq '[.jobs[] | select(.conclusion == "failure")] | length')"
    if [ "$failed" -gt 0 ]; then
      echo "  failed-step log excerpt (last 40 lines):"
      gh run view "$run_id" --log-failed 2>/dev/null | tail -40 | sed 's/^/    /'
    fi
    ;;
  history)
    workflow=""
    limit=30
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --workflow) [ "$#" -ge 2 ] || usage; workflow="$2"; shift 2 ;;
        --limit)    [ "$#" -ge 2 ] || usage; limit="$2";    shift 2 ;;
        *) usage ;;
      esac
    done
    if [ -n "$workflow" ]; then
      gh run list --workflow "$workflow" --limit "$limit" \
        --json workflowName,status,conclusion,startedAt,updatedAt,databaseId \
        > "$TMP_FILE" 2>"$TMP_FILE.err"
    else
      gh run list --limit "$limit" \
        --json workflowName,status,conclusion,startedAt,updatedAt,databaseId \
        > "$TMP_FILE" 2>"$TMP_FILE.err"
    fi
    if [ $? -ne 0 ]; then
      echo "ERROR gh run list failed:"
      sed 's/^/  /' "$TMP_FILE.err"
      exit 2
    fi
    count="$(jq 'length' "$TMP_FILE")"
    if [ "$count" -eq 0 ]; then
      echo "history: no runs found"
    else
      echo "history: $count run(s) analyzed"
      jq -r 'group_by(.workflowName)[]
        | . as $runs
        | ($runs | map(select(.conclusion == "success")) | length) as $ok
        | ($runs | map(select(.conclusion == "failure")) | length) as $bad
        | ($runs | map(select(.startedAt != null and .updatedAt != null)
                   | ((.updatedAt | fromdateiso8601) - (.startedAt | fromdateiso8601)))) as $durs
        | "  \($runs[0].workflowName): \($runs | length) runs, \($ok) success, \($bad) failure"
          + ", avg " + (if ($durs | length) > 0 then "\(($durs | add / ($durs | length)) | floor)s" else "n/a" end)' \
        "$TMP_FILE"
    fi
    ;;
  *)
    usage
    ;;
esac

echo "Full output: $TMP_FILE"
exit 0
