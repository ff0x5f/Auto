#!/usr/bin/env bash
# Watch the latest GitHub Actions run to completion and dump the startup-diagnosis
# job's emulator log so the app's FATAL EXCEPTION stack (or the "process alive"
# verdict) lands in the terminal. Run once after pushing; it exits when the run
# finishes — no need to babysit.
#
# Usage:
#   scripts/watch-ci.sh                 # watch the latest run on the current branch
#   scripts/watch-ci.sh <run-id>        # watch a specific run id
#
# Env:
#   HTTPS_PROXY / HTTP_PROXY            # e.g. http://127.0.0.1:7897 (read by gh)
#   GH_RUN_ID                           # alternative way to pass a run id
#
# Requires: gh (authenticated via `gh auth login`).
# Note: parsing uses gh's built-in `--jq`, so no standalone `jq` binary is
# required.

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repo" >&2
  exit 1
}

command -v gh  >/dev/null || { echo "error: gh not installed" >&2; exit 1; }

RUN_ID="${1:-${GH_RUN_ID:-}}"

if [ -z "$RUN_ID" ]; then
  echo "Resolving latest CI run for current commit..."
  SHA="$(git rev-parse HEAD)"
  RUN_ID="$(gh run list --limit 30 --json databaseId,headSha --jq \
    '.[] | select(.headSha == "'"${SHA}"'") | .databaseId' 2>/dev/null | head -1)"
  if [ -z "$RUN_ID" ]; then
    # Fall back to the most recent run regardless of sha.
    RUN_ID="$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)"
  fi
fi

if [ -z "${RUN_ID:-}" ]; then
  echo "error: could not resolve a CI run id (push first?)" >&2
  exit 1
fi

echo "Watching run ${RUN_ID} ..."
echo "(polling every 25s; Ctrl+C to stop)"

# --- Wait for the whole run to finish --------------------------------------
last_status=""
while :; do
  status="$(gh run view "${RUN_ID}" --json status --jq '.status' 2>/dev/null)"
  if [ "$status" != "$last_status" ]; then
    last_status="$status"
    echo "  run status => ${status}"
  fi
  [ "$status" = "completed" ] && break
  sleep 25
done

echo
echo "=== Run ${RUN_ID} completed ==="
gh run view "${RUN_ID}" --json conclusion,jobs \
  --jq '"conclusion: \(.conclusion)", (.jobs[] | "  \(.name): \(.conclusion // .status)")' 2>/dev/null
echo

# --- Dump per-job conclusions + the startup-diagnosis log ------------------
JOB_ID="$(gh run view "${RUN_ID}" --json jobs \
  --jq '.jobs[] | select(.name=="startup-diagnosis") | .databaseId' 2>/dev/null)"

if [ -z "${JOB_ID:-}" ]; then
  echo "No startup-diagnosis job in this run. Listing jobs and latest step logs:"
  gh run view "${RUN_ID}" --log 2>/dev/null | tail -40
  exit 0
fi

echo "=== startup-diagnosis job ${JOB_ID} log (key lines) ==="
gh run view --job="${JOB_ID}" --log 2>/dev/null \
  | grep -aE 'Resolved APK|adb install rc=|::error|::notice|::warning|pidof com\.simple\.process|process is (ALIVE|GONE)|FATAL EXCEPTION|AndroidRuntime|Caused by|at org\.autojs|at com\.simple|Process: com\.simple|Saving snapshot' \
  | tail -60
echo
echo "=== end ==="
