```bash
#!/usr/bin/env bash
# 03-programmatic-test.sh — VALIDITY + BOUNDARY tests for Protocol 03
#
# Protocol 03: Programmatic Delegation (--print --bare pattern)
#
# TESTS:
#   VALIDITY  — invoke claude-deepseek --print --bare -p "Say: HELLO"
#               and verify output contains "HELLO"
#   BOUNDARY  — empty prompt → verify non-empty error or graceful exit
#               (must not hang)
#
# Exit code: 0 = all pass, 1 = ≥1 failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
PASSES=0

# Colours
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ $1${NC}"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILS=$((FAILS + 1)); }

echo "═══ Protocol 03 — Programmatic Delegation Tests ═══"
echo ""

# ── Helper: invoke claude-deepseek with timeout ────────────────────────
DS_TIMEOUT=120  # seconds — a simple "HELLO" response should be < 30s

invoke_ds() {
    local prompt="$1"
    local outfile="$2"
    timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$prompt" > "$outfile" 2>/tmp/ds_stderr_03.log
}

# ═══════════════════════════════════════════════════════════════════════
# TEST 1 — VALIDITY: basic invocation returns expected output
# ═══════════════════════════════════════════════════════════════════════
echo "── Test 1: VALIDITY — basic --print --bare invocation ──"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

if invoke_ds "Say: HELLO" "$TMP/out.txt"; then
    output=$(cat "$TMP/out.txt")
    if echo "$output" | grep -qi "HELLO"; then
        pass "Output contains HELLO"
        echo "    output (first 120 chars): $(echo "$output" | head -c 120)"
    else
        fail "Output does NOT contain HELLO"
        echo "    output (first 200 chars): $(echo "$output" | head -c 200)"
    fi
else
    fail "claude-deepseek call failed or timed out (${DS_TIMEOUT}s)"
    echo "    stderr: $(cat /tmp/ds_stderr_03.log 2>/dev/null | tail -5 || echo '(none)')"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST 2 — BOUNDARY: empty prompt must not hang
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "── Test 2: BOUNDARY — empty prompt ──"

# Use a tight timeout; an empty prompt should either error or return quickly
EMPTY_TIMEOUT=30

# Run in background with timeout; capture PID so we can check for hang
TMP2=$(mktemp -d)
trap "rm -rf $TMP $TMP2" EXIT

set +e
timeout "$EMPTY_TIMEOUT" claude-deepseek --print --bare -p "" > "$TMP2/empty_out.txt" 2>"$TMP2/empty_err.txt"
empty_rc=$?
set -e

if [[ "$empty_rc" -eq 124 ]]; then
    # timeout(1) returns 124 when the command times out
    fail "Empty prompt TIMED OUT after ${EMPTY_TIMEOUT}s — means the command HUNG"
    echo "    This is a BOUNDARY violation: empty prompt should fail fast, not hang."
elif [[ "$empty_rc" -eq 0 ]]; then
    out=$(cat "$TMP2/empty_out.txt")
    err=$(cat "$TMP2/empty_err.txt" 2>/dev/null || true)
    if [[ -n "$out$err" ]]; then
        # It returned something — acceptable (graceful handling)
        pass "Empty prompt returned gracefully (exit=0, output=$(echo "$out$err" | wc -c) bytes)"
        echo "    output: $(echo "$out$err" | head -c 150)"
    else
        # Returned 0 but with no output — suspicious but not strictly a hang
        pass "Empty prompt returned silently (exit=0, no output) — graceful"
    fi
else
    out=$(cat "$TMP2/empty_out.txt")
    err=$(cat "$TMP2/empty_err.txt" 2>/dev/null || true)
    if [[ -n "$out$err" ]]; then
        # Non-zero exit with output — acceptable error behaviour
        pass "Empty prompt produced error output (exit=$empty_rc) — graceful"
        echo "    stderr+stdout: $(echo "$out$err" | head -c 150)"
    else
        fail "Empty prompt failed silently (exit=$empty_rc, no output)"
    fi
fi

# ── Report ─────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "Protocol 03 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
echo "─────────────────────────────────────────"

if [[ "$FAILS" -gt 0 ]]; then
    exit 1
fi
exit 0
```

---
