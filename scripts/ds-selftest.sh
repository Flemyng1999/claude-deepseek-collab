#!/usr/bin/env bash
# Offline self-test for the /ds protocol layer.
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

REQUIRED_FILES=(
  "CLAUDE.md"
  ".claude/commands/ds.md"
  ".claude/commands/ds-audit.md"
  ".claude/hooks/user-prompt-submit.sh"
  "scripts/ds-dispatch.sh"
  "templates/ds_task.md"
  "templates/ds_result.md"
  "templates/claude_audit.md"
  "protocols/09-skill-adapter.md"
)

for file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$file" ]] || fail "missing required file: $file"
done
pass "required files exist"

[[ -x ".claude/hooks/user-prompt-submit.sh" ]] || fail "hook is not executable"
[[ -x "scripts/ds-dispatch.sh" ]] || fail "scripts/ds-dispatch.sh is not executable"
pass "hook and dispatcher are executable"

mkdir -p .ds/tasks
task_file=".ds/tasks/selftest-$(date '+%Y%m%d-%H%M%S')-$$.md"
{
  echo "# Self-test DS Task"
  echo
  echo "Objective: produce deterministic dry-run output."
} > "$task_file"

dispatch_output=$(DS_DRY_RUN=1 scripts/ds-dispatch.sh "$task_file")
case "$dispatch_output" in
  RESULT_FILE=*) result_file=${dispatch_output#RESULT_FILE=} ;;
  *) fail "dispatch did not print RESULT_FILE=<path>: $dispatch_output" ;;
esac

[[ -f "$result_file" ]] || fail "result file was not created: $result_file"
[[ -s "$result_file" ]] || fail "result file is empty: $result_file"
pass "dry-run dispatch creates a non-empty result"

hint=$(printf '%s\n' "批量 初稿 DeepSeek" | .claude/hooks/user-prompt-submit.sh)
[[ -n "$hint" ]] || fail "hook did not print hint for DS trigger prompt"

daily_hint=$(printf '%s\n' "请写晚间结项草稿" | .claude/hooks/user-prompt-submit.sh)
[[ -n "$daily_hint" ]] || fail "hook did not print hint for daily draft trigger"

neutral=$(printf '%s\n' "请做晚间结项，总结今天进展" | .claude/hooks/user-prompt-submit.sh)
[[ -z "$neutral" ]] || fail "hook printed output for neutral daily prompt: $neutral"
pass "hook trigger behavior is correct"

if ! grep -qF "Any Claude Code skill" protocols/09-skill-adapter.md; then
  fail "skill adapter protocol does not describe cross-skill use"
fi
pass "skill adapter contract is documented"

if ! grep -qF "ds-dispatch <task-file>" .claude/commands/ds.md; then
  fail "/ds command does not document global dispatcher fallback"
fi
if ! grep -qF 'COMMANDS_DIR/ds.md' install.sh; then
  fail "installer does not install global /ds command"
fi
pass "global command install path is documented"

if command -v ccr >/dev/null 2>&1; then
  echo "CCR: detected ($(command -v ccr))"
else
  echo "CCR: not detected"
fi

pass "ds self-test complete"
