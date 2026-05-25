#!/usr/bin/env bash
# 01-routing-test.sh — static consistency tests for Protocol 01 routing claims
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0; PASSES=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓ $1${NC}"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILS=$((FAILS + 1)); }

echo "═══ Protocol 01 — Routing Static Tests ═══"

require_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -qF "$pattern" "$REPO_ROOT/$file"; then
        pass "$label"
    else
        fail "$label missing: $file must contain '$pattern'"
    fi
}

require_contains "protocols/01-routing.md" "expected output > ~50 tokens" "Protocol 01 threshold is > ~50 tokens"
require_contains "README.md" "Expected output > ~50 tokens" "README threshold is > ~50 tokens"
require_contains "rules/deepseek-delegation.md" "expected output > ~50 tokens" "Rules threshold is > ~50 tokens"

if grep -RIn "Expected output > ~150 tokens\|expected output > ~150 tokens\|≥3 files" \
    "$REPO_ROOT/protocols/01-routing.md" "$REPO_ROOT/README.md" "$REPO_ROOT/rules/deepseek-delegation.md" >/tmp/routing_bad_thresholds.log; then
    fail "Stale routing threshold found"
    cat /tmp/routing_bad_thresholds.log
else
    pass "No stale ~150-token or ≥3-files routing threshold"
fi

require_contains "rules/deepseek-delegation.md" "Protocol 04 async parallel" "Rules mention Protocol 04 trigger"
require_contains "rules/deepseek-delegation.md" "Protocol 06 speculative execution" "Rules mention Protocol 06 trigger"
require_contains "rules/deepseek-delegation.md" "Protocol 07 self-critique loop" "Rules mention Protocol 07 trigger"
require_contains "rules/deepseek-delegation.md" "Protocol 08 SCDP" "Rules mention Protocol 08 trigger"

echo "Protocol 01 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
[[ "$FAILS" -eq 0 ]]
