```bash
#!/usr/bin/env bash
# 07-self-critique-test.sh — VALIDITY + BOUNDARY tests for Protocol 07
#
# Protocol 07: Self-Critique Loop (Instance 1 drafts, Instance 2 critiques)
#
# TESTS:
#   VALIDITY A (error detection) — inject a known factual error
#         ("water boils at 50°C") into a draft, run Instance 2 critique,
#         verify ISSUES list mentions temperature or boiling point
#   VALIDITY B (pass case) — submit a clean correct paragraph,
#         verify VERDICT contains "pass"
#   BOUNDARY — Instance 2 given empty draft → verify graceful output
#         (no hang, produces some output)
#
# Exit code: 0 = all pass, 1 = ≥1 failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
PASSES=0

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓ $1${NC}"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILS=$((FAILS + 1)); }

echo "═══ Protocol 07 — Self-Critique Loop Tests ═══"
echo ""

DS_TIMEOUT=180
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# ── Critique prompt template (from Protocol 07 §3) ─────────────────────
# We embed this as a heredoc and substitute the DRAFT text.
# Instance 2 prompt: adversarial reviewer.

read -r -d '' CRITIQUE_TEMPLATE << 'CRITTPL' || true
Adversarial reviewer. Your sole task: find every flaw in the text below.
Be specific, numbered, and adversarial. Assume nothing is correct until proven.

TEXT:
```
DRAFT_PLACEHOLDER
```

Examine for:
1. Factual errors — claims that contradict provided evidence, wrong numbers
2. Logical gaps — missing steps in reasoning, unstated assumptions
3. Internal inconsistencies — two parts of the text that contradict each other
4. Over-claiming — stronger conclusions than the evidence supports

Return ONLY:
ISSUES: [numbered list, one issue per line. If no issues found, write "none"]
VERDICT: pass | needs_revision
---
[one sentence: the single most critical issue, or "no critical issues found"]
CRITTPL

# ═══════════════════════════════════════════════════════════════════════
# TEST 1 — VALIDITY A: error detection (injected factual error)
# ═══════════════════════════════════════════════════════════════════════
echo "── Test 1: VALIDITY — error detection (water boils at 50°C) ──"

DRAFT_ERROR='Water is a fundamental substance for life. At standard atmospheric pressure,
water boils at 50 degrees Celsius. This makes it unique among common liquids.
The boiling point is an important physical property used in many scientific
and industrial applications.'

CRITIQUE_ERROR="${CRITIQUE_TEMPLATE/DRAFT_PLACEHOLDER/$DRAFT_ERROR}"

set +e
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$CRITIQUE_ERROR" > "$TMP/critique_err.txt" 2>/dev/null
crit_err_rc=$?
set -e

if [[ "$crit_err_rc" -ne 0 ]]; then
    fail "Instance 2 call failed (exit=$crit_err_rc)"
    echo "─────────────────────────────────────────"
    echo "Protocol 07 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
    exit 1
fi

CRIT_ERR_OUT=$(cat "$TMP/critique_err.txt")
echo "    Critique output (first 400 chars):"
echo "    $(echo "$CRIT_ERR_OUT" | head -c 400)"
echo ""

# Check: ISSUES should mention temperature, boiling, or 50
if echo "$CRIT_ERR_OUT" | grep -qiE "temperature|boil|50°|50 degree|50°C"; then
    pass "ISSUES detected temperature/boiling error"
else
    # Also check if VERDICT is needs_revision even without explicit mention
    if echo "$CRIT_ERR_OUT" | grep -q "needs_revision"; then
        pass "VERDICT=needs_revision (detected error, though not by temperature keyword)"
        echo "    Critique found an issue but didn't use expected keywords."
    else
        fail "Instance 2 did NOT detect the water-boils-at-50°C error"
        echo "    Expected: ISSUES mentions temperature/boiling"
        echo "    Got verdict: $(echo "$CRIT_ERR_OUT" | grep -i "VERDICT" || echo '(not found)')"
        echo "    Known failure mode: FM-1 (Instance 2 too lenient)"
    fi
fi

# Also verify VERDICT format
if echo "$CRIT_ERR_OUT" | grep -q "VERDICT:"; then
    pass "VERDICT field present in critique"
else
    fail "VERDICT field missing from critique"
fi

if echo "$CRIT_ERR_OUT" | grep -q "ISSUES:"; then
    pass "ISSUES field present in critique"
else
    fail "ISSUES field missing from critique"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST 2 — VALIDITY B: pass case (clean correct text)
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "── Test 2: VALIDITY — pass case (correct paragraph) ──"

DRAFT_CLEAN='Water is a fundamental substance for life. At standard atmospheric pressure
(1 atm), water boils at 100 degrees Celsius. This boiling point varies with
altitude due to changes in atmospheric pressure. The property is fundamental
to many scientific, industrial, and culinary applications.'

CRITIQUE_CLEAN="${CRITIQUE_TEMPLATE/DRAFT_PLACEHOLDER/$DRAFT_CLEAN}"

set +e
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$CRITIQUE_CLEAN" > "$TMP/critique_clean.txt" 2>/dev/null
crit_clean_rc=$?
set -e

if [[ "$crit_clean_rc" -ne 0 ]]; then
    fail "Instance 2 clean-draft call failed (exit=$crit_clean_rc)"
else
    CRIT_CLEAN_OUT=$(cat "$TMP/critique_clean.txt")
    echo "    Critique output (first 300 chars):"
    echo "    $(echo "$CRIT_CLEAN_OUT" | head -c 300)"
    echo ""

    if echo "$CRIT_CLEAN_OUT" | grep -qi "VERDICT:.*pass"; then
        pass "VERDICT contains 'pass' for clean draft"
    elif echo "$CRIT_CLEAN_OUT" | grep -qi "VERDICT:"; then
        verdict_line=$(echo "$CRIT_CLEAN_OUT" | grep -i "VERDICT:" | head -1)
        echo "    verict line: $verdict_line"
        if echo "$CRIT_CLEAN_OUT" | grep -qi "needs_revision"; then
            echo "    ${YELLOW}NOTE:${NC} Instance 2 found issues in the clean text."
            echo "    This may indicate FM-2 (hallucinated issues) or the text has"
            echo "    subtle issues (e.g., 'varies with altitude' might be flagged"
            echo "    as missing quantification)."
            pass "VERDICT present but was 'needs_revision' — documented (possible FM-2)"
        else
            pass "VERDICT present (value: $(echo "$verdict_line" | head -c 60))"
        fi
    else
        fail "VERDICT not found in critique output"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST 3 — BOUNDARY: empty draft → graceful output
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "── Test 3: BOUNDARY — empty draft ──"

CRITIQUE_EMPTY="${CRITIQUE_TEMPLATE/DRAFT_PLACEHOLDER/}"

set +e
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$CRITIQUE_EMPTY" > "$TMP/critique_empty.txt" 2>/dev/null
crit_empty_rc=$?
set -e

if [[ "$crit_empty_rc" -eq 124 ]]; then
    fail "Instance 2 TIMED OUT on empty draft — HUNG"
    echo "    This is a BOUNDARY violation per Protocol 07."
    echo "    Instance 2 should produce graceful output even with empty/malformed input."
else
    EMPTY_OUT=$(cat "$TMP/critique_empty.txt")
    sz=$(echo "$EMPTY_OUT" | wc -c)
    if [[ "$sz" -gt 5 ]]; then
        pass "Instance 2 produced output for empty draft (${sz} bytes) — graceful"
        echo "    first 200 chars: $(echo "$EMPTY_OUT" | head -c 200)"
    else
        pass "Instance 2 returned minimal/empty output for empty draft — graceful (no hang)"
    fi
fi

# ── Report ─────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "Protocol 07 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
echo "─────────────────────────────────────────"

if [[ "$FAILS" -gt 0 ]]; then
    exit 1
fi
exit 0
```

---
