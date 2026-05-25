#!/usr/bin/env bash
# 02-plan-annotation-test.sh — static/regex tests for Protocol 02 plan annotation format
set -euo pipefail

FAILS=0; PASSES=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓ $1${NC}"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILS=$((FAILS + 1)); }

echo "═══ Protocol 02 — Plan Annotation Static Tests ═══"

is_valid_step() {
    local line="$1"
    local labels
    labels=$(grep -oE '\[(DeepSeek|Claude)\]' <<< "$line" | wc -l)
    [[ "$labels" -eq 1 && "$line" =~ ^Step[[:space:]]+[0-9]+[[:space:]]+\[(DeepSeek|Claude)\][[:space:]]+[^[]+$ ]]
}

valid='Step 2 [DeepSeek] — draft §Discussion from findings list'
unlabeled='Step 2 — draft §Discussion from findings list'
double='Step 2 [DeepSeek] [Claude] — confused executor'

if is_valid_step "$valid"; then pass "Valid labeled step accepted"; else fail "Valid labeled step rejected"; fi
if is_valid_step "$unlabeled"; then fail "Unlabeled step accepted"; else pass "Unlabeled step rejected"; fi
if is_valid_step "$double"; then fail "Double-labeled step accepted"; else pass "Double-labeled step rejected"; fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if grep -q "Every step in a plan must carry exactly one label" "$REPO_ROOT/protocols/02-plan-annotation.md"; then
    pass "Protocol documents exactly-one-label rule"
else
    fail "Protocol missing exactly-one-label rule"
fi

if grep -q "Spec-completeness requirement" "$REPO_ROOT/protocols/02-plan-annotation.md"; then
    pass "Protocol documents DeepSeek spec-completeness requirement"
else
    fail "Protocol missing DeepSeek spec-completeness requirement"
fi

echo "Protocol 02 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
[[ "$FAILS" -eq 0 ]]
