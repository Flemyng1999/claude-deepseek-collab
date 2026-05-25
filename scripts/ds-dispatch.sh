#!/usr/bin/env bash
# Dispatch a self-contained DS task brief and save the result artifact.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: scripts/ds-dispatch.sh <task-file.md>" >&2
  echo "Set DS_DRY_RUN=1 for offline tests." >&2
  exit 2
fi

task_file="$1"
[[ -f "$task_file" ]] || { echo "ERROR: Task file not found: $task_file" >&2; exit 1; }

mkdir -p .ds/results
task_base=$(basename "$task_file")
task_slug=${task_base%.*}
task_slug=$(printf '%s' "$task_slug" | tr -c 'A-Za-z0-9._-' '-')
timestamp=$(date '+%Y%m%d-%H%M%S')
result_file=".ds/results/${timestamp}-${task_slug}.md"
suffix=0
while [[ -e "$result_file" ]]; do
  suffix=$((suffix + 1))
  result_file=".ds/results/${timestamp}-${task_slug}-${suffix}.md"
done

if [[ "${DS_DRY_RUN:-0}" == "1" ]]; then
  cat > "$result_file" <<EOF
# DS Dry Run Result

SUMMARY: deterministic offline result for dispatcher self-test.
OUTPUT:
- Task file: $task_file
- Backend: dry-run
- No network, credentials, or provider calls were used.

ASSUMPTIONS:
- Claude will audit this draft before using it.

UNCERTAINTY:
- This is not real DeepSeek output.

FILES CHANGED:
- None
EOF
  echo "RESULT_FILE=$result_file"
  exit 0
fi

if [[ -n "${DS_BACKEND_CMD:-}" ]]; then
  task_content=$(<"$task_file")
  # DS_BACKEND_CMD is local config; it receives task text as final argument.
  # shellcheck disable=SC2086
  if $DS_BACKEND_CMD "$task_content" > "$result_file"; then
    [[ -s "$result_file" ]] || { echo "ERROR: backend produced an empty result" >&2; exit 1; }
    echo "RESULT_FILE=$result_file"
    exit 0
  fi
  rm -f "$result_file"
  echo "ERROR: backend command failed: $DS_BACKEND_CMD" >&2
  exit 1
fi

if command -v ccr >/dev/null 2>&1; then
  note="CCR was detected, but DS_BACKEND_CMD is not configured."
else
  note="No DS backend was detected."
fi

cat >&2 <<EOF
ERROR: $note

Configure claude-code-router or a DeepSeek Anthropic-compatible endpoint outside
this repo. This repo is the protocol/audit layer and must not store API keys.

Optional bridge:
  export DS_BACKEND_CMD='your-ccr-backed-command --print --bare -p'
  scripts/ds-dispatch.sh .ds/tasks/example.md

CCR checks: ccr status; ccr start
Offline: DS_DRY_RUN=1 scripts/ds-dispatch.sh .ds/tasks/example.md
EOF
exit 1
