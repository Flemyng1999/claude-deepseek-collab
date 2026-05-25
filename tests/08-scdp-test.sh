#!/usr/bin/env bash
# 08-scdp-test.sh — static consistency tests for Protocol 08 design spec
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P08="$REPO_ROOT/protocols/08-scdp.md"
FAILS=0; PASSES=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓ $1${NC}"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILS=$((FAILS + 1)); }

echo "═══ Protocol 08 — SCDP Static Tests ═══"

require() {
    local pattern="$1" label="$2"
    if grep -qF "$pattern" "$P08"; then
        pass "$label"
    else
        fail "$label missing: expected '$pattern'"
    fi
}

require "design spec, not yet implemented (roadmap only" "Status is explicit roadmap-only design spec"
require "external-project examples, not files shipped" "Example file paths are marked external"
require 'does not currently ship `scripts/scdp_mediate.sh`' 'Mediator pseudocode is marked non-shipped'
require 'not a shipped `scripts/gen_capsule.py` file' 'Generator signature is marked non-shipped'
require "(?=(\s+tokens=[0-9]+)?>>)" "Directive parser requires closing >>"
require "no chunks expanded this round" "Invalid chunk id uses all-or-none expansion"
require "sha256sum" "Pseudocode verifies content_hash"
require "Claude's audit gate for DeepSeek output" "Integration reference avoids dead Protocol 01 anchor"

if [[ -e "$REPO_ROOT/scripts/gen_capsule.py" || -e "$REPO_ROOT/scripts/scdp_mediate.sh" ]]; then
    fail "Roadmap-only SCDP unexpectedly has shipped scripts"
else
    pass "Roadmap-only SCDP has no shipped scripts"
fi

echo "Protocol 08 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
[[ "$FAILS" -eq 0 ]]
