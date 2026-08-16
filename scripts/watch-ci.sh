#!/usr/bin/env bash
# Watch a GitHub Actions run until it is TRULY finished, then dump the
# startup-diagnosis job's emulator log so the app's FATAL EXCEPTION stack
# (or the "process alive" verdict) lands in the terminal.
#
# Run once after pushing; it will NOT exit until the run is completed and all
# jobs have a terminal conclusion. No need to babysit.
#
# Usage:
#   scripts/watch-ci.sh                 # watch the latest run for current commit
#   scripts/watch-ci.sh <run-id>        # watch a specific run id
#
# Env:
#   HTTPS_PROXY / HTTP_PROXY            # e.g. http://127.0.0.1:7897 (read by gh)
#   GH_RUN_ID                           # alternative way to pass a run id
#   WATCH_CI_MAX_MINS                   # hard cap, default 60 (minutes)
#
# Requires: gh (authenticated via `gh auth login`).
# Parsing uses gh's built-in `--jq`, so no standalone `jq` binary is required.
#
# Exit codes:
#   0  run completed, logs dumped (success OR app crash — review the output)
#   1  setup error (not a repo, gh missing, no run id, etc.)
#   2  run did not finish within WATCH_CI_MAX_MINS
#   3  run completed but no startup-diagnosis job was found

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repo" >&2
  exit 1
}

command -v gh >/dev/null || { echo "error: gh not installed (run 'gh auth login')" >&2; exit 1; }

MAX_MINS="${WATCH_CI_MAX_MINS:-60}"
POLL_SECS=20

RUN_ID="${1:-${GH_RUN_ID:-}}"

if [ -z "$RUN_ID" ]; then
  echo "Resolving latest CI run for current commit $(git rev-parse --short HEAD 2>/dev/null)..."
  SHA="$(git rev-parse HEAD)"
  RUN_ID="$(gh run list --limit 30 --json databaseId,headSha --jq \
    '.[] | select(.headSha == "'"${SHA}"'") | .databaseId' 2>/dev/null | head -1)"
  if [ -z "${RUN_ID:-}" ]; then
    RUN_ID="$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)"
  fi
fi

if [ -z "${RUN_ID:-}" ]; then
  echo "error: could not resolve a CI run id (push first?)" >&2
  exit 1
fi

echo "Watching run ${RUN_ID} (poll every ${POLL_SECS}s, hard cap ${MAX_MINS}m)..."
echo "Will NOT exit until the run is completed AND every job is terminal."
echo

# --- Wait until the run is truly finished -----------------------------------
# `gh` over a flaky proxy can return transient empty output; treat empty as
# "unknown" and keep polling rather than risking a false `completed`.
deadline=$(( $(date +%s) + MAX_MINS * 60 ))
last_status=""
completed=false
while :; do
  now=$(date +%s)
  if [ "$now" -ge "$deadline" ]; then
    echo "error: run ${RUN_ID} not finished within ${MAX_MINS}m" >&2
    gh run view "${RUN_ID}" --json status,conclusion,jobs \
      --jq '"  status=\(.status) conclusion=\(.conclusion//\"-\")", (.jobs[]|"  \(.name): \(.conclusion // .status)")' 2>/dev/null >&2
    exit 2
  fi

  status="$(gh run view "${RUN_ID}" --json status --jq '.status' 2>/dev/null)"
  if [ -z "$status" ]; then
    # transient network/gh failure — keep going, do not compare against empty
    sleep "$POLL_SECS"
    continue
  fi
  if [ "$status" != "$last_status" ]; then
    last_status="$status"
    printf '  [%s] run status => %s\n' "$(date +%H:%M:%S)" "$status"
  fi

  if [ "$status" = "completed" ]; then
    # Double-confirm: require every job to also be terminal, because GitHub
    # occasionally marks the run completed a tick before the last job settles.
    pending="$(gh run view "${RUN_ID}" --json jobs \
      --jq '[.jobs[] | select(.status != "completed")] | length' 2>/dev/null)"
    if [ -z "$pending" ]; then
      # could not read jobs (transient) — keep polling this iteration
      sleep "$POLL_SECS"
      continue
    fi
    if [ "$pending" -eq 0 ]; then
      completed=true
      break
    fi
    printf '  [%s] run completed but %s job(s) still non-terminal; waiting\n' \
      "$(date +%H:%M:%S)" "$pending"
  fi
  sleep "$POLL_SECS"
done

echo
echo "=== Run ${RUN_ID} is truly completed ==="
gh run view "${RUN_ID}" --json conclusion,jobs \
  --jq '"conclusion: \(.conclusion)", (.jobs[] | "  \(.name): \(.conclusion // .status)")' 2>/dev/null
echo

# --- Dump the startup-diagnosis log ----------------------------------------
JOB_ID="$(gh run view "${RUN_ID}" --json jobs \
  --jq '.jobs[] | select(.name=="startup-diagnosis") | .databaseId' 2>/dev/null)"

if [ -z "${JOB_ID:-}" ]; then
  echo "No startup-diagnosis job in this run. Tail of full run log:"
  gh run view "${RUN_ID}" --log 2>/dev/null | tail -40
  exit 3
fi

echo "=== startup-diagnosis job ${JOB_ID} — key lines ==="
gh run view --job="${JOB_ID}" --log 2>/dev/null \
  | grep -aE 'Resolved APK|adb install rc=|::error|::notice|::warning|pidof com\.simple\.process|process is (ALIVE|GONE)|FATAL EXCEPTION|AndroidRuntime|Caused by|at org\.autojs|at com\.simple|Process: com\.simple' \
  | tail -60
echo
echo "  Tip: download full emulator logs via"
echo "    gh run download ${RUN_ID} -n startup-diagnosis-logs"
echo "=== end ==="
exit 0
