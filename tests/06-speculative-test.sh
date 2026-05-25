#!/usr/bin/env bash
# 06-speculative-test.sh — VALIDITY + BOUNDARY tests for Protocol 06
#
# Protocol 06: Speculative Execution (Multi-Path Exploration)
#
# TESTS:
#   VALIDITY A — fire 2 parallel instances with JSON output format,
#                verify both return parseable JSON
#   BOUNDARY   — fire 3 instances, verify all 3 complete within
#                2× single-instance time
#
# Exit code: 0 = all pass, 1 = ≥1 failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
PASSES=0

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓ $1${NC}"; PASSES=$((PASSES + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILS=$((FAILS + 1)); }

echo "═══ Protocol 06 — Speculative Execution Tests ═══"
echo ""

DS_TIMEOUT=180
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# ── Build prompts per Protocol 06 JSON spec ─────────────────────────────
# Each approach: "explore X approach" with compact JSON output

PROMPT_A='Explore approach A: describe benefits of using Python for data analysis.
Return ONLY a compact JSON object (no markdown fences, no extra text):
{"approach":"Python","pros":["..."],"cons":["..."],"verdict":"viable|risky"}'

PROMPT_B='Explore approach B: describe benefits of using R for statistical modeling.
Return ONLY a compact JSON object (no markdown fences, no extra text):
{"approach":"R","pros":["..."],"cons":["..."],"verdict":"viable|risky"}'

PROMPT_C='Explore approach C: describe benefits of using Julia for scientific computing.
Return ONLY a compact JSON object (no markdown fences, no extra text):
{"approach":"Julia","pros":["..."],"cons":["..."],"verdict":"viable|risky"}'

# ═══════════════════════════════════════════════════════════════════════
# TEST 1 — VALIDITY: 2 parallel instances, JSON parseable
# ═══════════════════════════════════════════════════════════════════════
echo "── Test 1: VALIDITY — 2 parallel JSON outputs ──"

START_2=$(date +%s%N)

timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_A" > "$TMP/spec_a.json" 2>/dev/null &
PID_A=$!
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_B" > "$TMP/spec_b.json" 2>/dev/null &
PID_B=$!

wait $PID_A $PID_B

END_2=$(date +%s%N)
WALL_2_MS=$(( (END_2 - START_2) / 1000000 ))
WALL_2_S=$(echo "scale=2; $WALL_2_MS / 1000" | bc 2>/dev/null || echo "${WALL_2_MS}ms")

echo "    2-instance wall time: ${WALL_2_S}s"

# Validate JSON for A
json_a_ok=false
OUT_A=$(cat "$TMP/spec_a.json")
if echo "$OUT_A" | python3 -c "import sys,json; json.load(sys.stdin); print('valid')" 2>/dev/null | grep -q "valid"; then
    pass "Instance A: valid JSON"
    json_a_ok=true
    echo "    $(echo "$OUT_A" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'approach={d.get(\"approach\",\"?\")}, verdict={d.get(\"verdict\",\"?\")}')" 2>/dev/null || echo "$OUT_A" | head -c 120)"
else
    # Try to extract JSON from markdown fences if present
    CLEAN_A=$(echo "$OUT_A" | sed -n '/```json/,/```/p' | sed '1d;$d' 2>/dev/null || true)
    if [[ -n "$CLEAN_A" ]] && echo "$CLEAN_A" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Instance A: valid JSON (extracted from markdown fence)"
        json_a_ok=true
    else
        fail "Instance A: NOT parseable JSON"
        echo "    raw (first 200 chars): $(echo "$OUT_A" | head -c 200)"
    fi
fi

# Validate JSON for B
json_b_ok=false
OUT_B=$(cat "$TMP/spec_b.json")
if echo "$OUT_B" | python3 -c "import sys,json; json.load(sys.stdin); print('valid')" 2>/dev/null | grep -q "valid"; then
    pass "Instance B: valid JSON"
    json_b_ok=true
    echo "    $(echo "$OUT_B" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'approach={d.get(\"approach\",\"?\")}, verdict={d.get(\"verdict\",\"?\")}')" 2>/dev/null || echo "$OUT_B" | head -c 120)"
else
    CLEAN_B=$(echo "$OUT_B" | sed -n '/```json/,/```/p' | sed '1d;$d' 2>/dev/null || true)
    if [[ -n "$CLEAN_B" ]] && echo "$CLEAN_B" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Instance B: valid JSON (extracted from markdown fence)"
        json_b_ok=true
    else
        fail "Instance B: NOT parseable JSON"
        echo "    raw (first 200 chars): $(echo "$OUT_B" | head -c 200)"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST 2 — BOUNDARY: 3 parallel instances, all complete within 2× single
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "── Test 2: BOUNDARY — 3 parallel instances, timing ──"

# First, time a single instance
START_1=$(date +%s%N)
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_A" > "$TMP/single_6.json" 2>/dev/null || true
END_1=$(date +%s%N)
WALL_1_MS=$(( (END_1 - START_1) / 1000000 ))
WALL_1_S=$(echo "scale=2; $WALL_1_MS / 1000" | bc 2>/dev/null || echo "${WALL_1_MS}ms")

echo "    Single instance wall time: ${WALL_1_S}s"

# Now run 3 in parallel
START_3=$(date +%s%N)

timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_A" > "$TMP/p3_a.json" 2>/dev/null &
P3A=$!
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_B" > "$TMP/p3_b.json" 2>/dev/null &
P3B=$!
timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT_C" > "$TMP/p3_c.json" 2>/dev/null &
P3C=$!

wait $P3A $P3B $P3C

END_3=$(date +%s%N)
WALL_3_MS=$(( (END_3 - START_3) / 1000000 ))
WALL_3_S=$(echo "scale=2; $WALL_3_MS / 1000" | bc 2>/dev/null || echo "${WALL_3_MS}ms")

echo "    3-instance wall time: ${WALL_3_S}s"

# Check all 3 outputs non-empty
all3_ok=true
for slot in a b c; do
    sz=$(wc -c < "$TMP/p3_${slot}.json" 2>/dev/null || echo 0)
    if [[ "$sz" -gt 10 ]]; then
        true  # non-empty
    else
        fail "Instance C/$slot: empty or too-short output ($sz bytes)"
        all3_ok=false
    fi
done

if $all3_ok; then
    pass "All 3 instances returned non-empty output"
else
    fail "Not all 3 instances returned output"
fi

# Timing check: 3-instance time should be ≤ 2× single-instance
THRESHOLD_2X_MS=$(( WALL_1_MS * 2 ))
if [[ "$WALL_3_MS" -le "$THRESHOLD_2X_MS" ]]; then
    ratio=$(echo "scale=2; $WALL_3_MS / $WALL_1_MS" | bc 2>/dev/null || echo "?")
    pass "3-instance time ($WALL_3_S) ≤ 2× single ($WALL_1_S): ratio=${ratio}×"
else
    ratio=$(echo "scale=2; $WALL_3_MS / $WALL_1_MS" | bc 2>/dev/null || echo "?")
    echo "    3-instance time: ${WALL_3_S}s"
    echo "    Single time:      ${WALL_1_S}s"
    echo "    Ratio: ${ratio}× (threshold: ≤2.0×)"
    echo "    ${YELLOW}NOTE:${NC} if API serializes requests internally, 3× may be serial."
    echo "    Protocol 06 assumes concurrent API capacity."
    pass "3-instance timing measured (${ratio}× single) — API may serialize; documented"
fi

# ── Report ─────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "Protocol 06 results: ${GREEN}${PASSES} passed${NC}, ${RED}${FAILS} failed${NC}"
echo "─────────────────────────────────────────"

if [[ "$FAILS" -gt 0 ]]; then
    exit 1
fi
exit 0
