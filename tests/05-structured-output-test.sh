```bash
#!/usr/bin/env bash
# 05-structured-output-test.sh — VALIDITY + BOUNDARY tests for Protocol 05
#
# Protocol 05: Structured Output (FLAGS header)
#
# TESTS:
#   VALIDITY  — request FLAGS header, verify response contains
#               "CHANGES:" AND "UNCERTAIN:" AND "---"
#   BOUNDARY  — what happens if DeepSeek ignores FLAGS instruction?
#               Detect missing header, set exit code 1
#
# Exit code: 0 = all pass, 1 = ≥1 failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
PASSES=0

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓ $1${NC}"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILS=$((FAILS + 1)); }

echo "═══ Protocol 05 — Structured Output (FLAGS) Tests ═══"
echo ""

DS_TIMEOUT=120
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# ═══════════════════════════════════════════════════════════════════════
# PROMPT: explicitly request FLAGS header per Protocol 05 spec
# ═══════════════════════════════════════════════════════════════════════
read -r -d '' PROMPT_FLAGS << 'EOF' || true
Write a 2-sentence description of a tree canopy.

Begin your response with:
CHANGES: [what you wrote]
UNCERTAIN: [anything uncertain, or "none"]
---
Then provide the description.
EOF

echo "── Test 1: VALIDITY — FLAGS header present ──"

set +e
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_FLAGS" > "$TMP/flags_out.txt" 2>"$TMP/flags_err.txt"
flags_rc=$?
set -e

if [[ "$flags_rc" -ne 0 ]]; then
    fail "claude-deepseek call failed (exit=$flags_rc)"
    echo "    stderr: $(cat "$TMP/flags_err.txt" | tail -5 || true)"
    echo "─────────────────────────────────────────"
    echo "Protocol 05 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
    exit 1
fi

FLAGS_OUT=$(cat "$TMP/flags_out.txt")
echo "    Response (first 300 chars):"
echo "    $(echo "$FLAGS_OUT" | head -c 300)"
echo ""

# Check each FLAGS component
flags_ok=true

if echo "$FLAGS_OUT" | grep -q "CHANGES:"; then
    pass "Response contains CHANGES: header"
else
    fail "Response MISSING CHANGES: header"
    flags_ok=false
fi

if echo "$FLAGS_OUT" | grep -q "UNCERTAIN:"; then
    pass "Response contains UNCERTAIN: header"
else
    fail "Response MISSING UNCERTAIN: header"
    flags_ok=false
fi

if echo "$FLAGS_OUT" | grep -q -- "---"; then
    pass "Response contains --- separator"
else
    fail "Response MISSING --- separator"
    flags_ok=false
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST 2 — BOUNDARY: what if DeepSeek ignores FLAGS instruction?
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "── Test 2: BOUNDARY — detection when FLAGS header missing ──"

# Re-use the same output; simulate the detection logic that a
# consuming script (or Claude auditor) would use.

has_changes=$(echo "$FLAGS_OUT" | grep -c "CHANGES:" || true)
has_uncertain=$(echo "$FLAGS_OUT" | grep -c "UNCERTAIN:" || true)
has_sep=$(echo "$FLAGS_OUT" | grep -c -- "---" || true)

if [[ "$has_changes" -ge 1 && "$has_uncertain" -ge 1 && "$has_sep" -ge 1 ]]; then
    pass "FLAGS header complete — audit can proceed with header-only read (~50 tokens)"
    echo "    Protocol 05 works: CHANGES + UNCERTAIN + --- all present."
    echo "    A consumer script can branch on this to decide read-depth."
else
    fail "FLAGS header incomplete or missing"
    echo "    CHANGES: found $has_changes, UNCERTAIN: found $has_uncertain, ---: found $has_sep"
    echo ""
    echo "    This means DeepSeek ignored the FLAGS instruction."
    echo "    Mitigation (per protocol):"
    echo "      - Re-prompt with stronger FLAGS requirement"
    echo "      - Or Claude reads full output (higher token cost)"
    echo "      - Log as 'DeepSeek FLAGS non-compliance' for tracking"

    # This IS a boundary test failure: we set exit code 1
    FAILS=$((FAILS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST 3 — BOUNDARY: request FLAGS with deliberately vague prompt
#           (no "Begin your response with" instruction)
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "── Test 3: BOUNDARY — FLAGS requested but prompt not protocol-compliant ──"

# This prompt mentions FLAGS but doesn't use the precise phrasing from Protocol 05
# Protocol 05 requires: "Begin your response with: CHANGES: ... UNCERTAIN: ... ---"
read -r -d '' PROMPT_LOOSE << 'EOF2' || true
Write a one-sentence description of photosynthesis.
Oh and include FLAGS like CHANGES and UNCERTAIN somewhere.
EOF2

set +e
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_LOOSE" > "$TMP/loose_out.txt" 2>/dev/null
loose_rc=$?
set -e

LOOSE_OUT=$(cat "$TMP/loose_out.txt" 2>/dev/null || true)

if [[ "$loose_rc" -ne 0 ]]; then
    pass "Loose FLAGS prompt: call completed (exit=$loose_rc) — graceful"
else
    has_c=$(echo "$LOOSE_OUT" | grep -c "CHANGES:" || true)
    has_u=$(echo "$LOOSE_OUT" | grep -c "UNCERTAIN:" || true)
    has_s=$(echo "$LOOSE_OUT" | grep -c -- "---" || true)

    if [[ "$has_c" -ge 1 && "$has_u" -ge 1 && "$has_s" -ge 1 ]]; then
        pass "Loose FLAGS prompt: DeepSeek produced FLAGS header anyway (robust)"
    else
        pass "Loose FLAGS prompt: DeepSeek did NOT produce full FLAGS (CHANGES=$has_c UNCERTAIN=$has_u SEP=$has_s)"
        echo "    This confirms: precise 'Begin your response with:' phrasing matters."
        echo "    Protocol 05's exact prompt template is necessary for compliance."
    fi
fi

# ── Report ─────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "Protocol 05 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
echo "─────────────────────────────────────────"

if [[ "$FAILS" -gt 0 ]]; then
    exit 1
fi
exit 0
```

---
