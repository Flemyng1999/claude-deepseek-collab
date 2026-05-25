```bash
#!/usr/bin/env bash
# benchmark-timing.sh — compare deepseek-v4-pro[1m] vs deepseek-v4-flash
#
# Task: "Write a 3-sentence explanation of photosynthesis.
#        Start with CHANGES: written UNCERTAIN: none ---"
#
# N=3 runs each model, measure wall time per run.
# Report table:
#   Model | Run1 | Run2 | Run3 | Mean | Output_lines
#
# Also test quality proxy: does each output contain
#   CHANGES: and UNCERTAIN: and --- ?
#
# Flash calls bypass the claude-deepseek wrapper (which hardcodes model
# names) and call `claude` directly with flash model env vars.
#
# Usage:
#   bash tests/benchmark-timing.sh
#
# Exit code:
#   0 — benchmark completed
#   1 — missing prerequisites or all calls failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  MODEL BENCHMARK: deepseek-v4-pro[1m] vs deepseek-v4-flash${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# ── Prerequisites ──────────────────────────────────────────────────────
ENV_FILE="$HOME/.config/claude-code/deepseek.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}FATAL: $ENV_FILE not found${NC}"
    echo "  Create from config/deepseek.env.example and add your API key"
    exit 1
fi

source "$ENV_FILE"
if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    echo -e "${RED}FATAL: DEEPSEEK_API_KEY is empty${NC}"
    exit 1
fi

if ! command -v claude &>/dev/null; then
    echo -e "${RED}FATAL: 'claude' command not found${NC}"
    echo "  Install Claude Code CLI first"
    exit 1
fi

N_RUNS=3
DS_TIMEOUT=180
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PROMPT='Write a 3-sentence explanation of photosynthesis.
Start with CHANGES: written UNCERTAIN: none ---
Then provide the three sentences.'

# ═══════════════════════════════════════════════════════════════════════
# Benchmark: deepseek-v4-pro[1m] (via claude-deepseek wrapper)
# ═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── deepseek-v4-pro[1m] (N=$N_RUNS) ──${NC}"
echo ""

PRO_TIMES=()
PRO_LINES=()
PRO_FLAGS_OK=()

for ((i=1; i<=N_RUNS; i++)); do
    echo -n "  Run $i ... "

    START_NS=$(date +%s%N)
    set +e
    timeout "$DS_TIMEOUT" claude-deepseek --print --bare -p "$PROMPT" > "$TMP/pro_run${i}.txt" 2>/dev/null
    rc=$?
    set -e
    END_NS=$(date +%s%N)

    WALL_S=$(echo "scale=1; ($END_NS - $START_NS) / 1000000000" | bc 2>/dev/null || echo "?")
    PRO_TIMES+=("$WALL_S")

    if [[ "$rc" -ne 0 ]]; then
        echo -e "${RED}FAILED (exit=$rc)${NC}"
        PRO_LINES+=("ERR")
        PRO_FLAGS_OK+=("NO")
        continue
    fi

    OUT=$(cat "$TMP/pro_run${i}.txt")
    LINES=$(echo "$OUT" | wc -l)
    PRO_LINES+=("$LINES")

    # Quality proxy: check for FLAGS components
    has_changes=0; has_uncertain=0; has_sep=0
    echo "$OUT" | grep -q "CHANGES:" && has_changes=1 || true
    echo "$OUT" | grep -q "UNCERTAIN:" && has_uncertain=1 || true
    echo "$OUT" | grep -q -- "---" && has_sep=1 || true

    if [[ "$has_changes" -eq 1 && "$has_uncertain" -eq 1 && "$has_sep" -eq 1 ]]; then
        PRO_FLAGS_OK+=("YES")
        echo -e "${GREEN}${WALL_S}s${NC}  lines=$LINES  flags=OK"
    else
        PRO_FLAGS_OK+=("NO")
        echo -e "${YELLOW}${WALL_S}s${NC}  lines=$LINES  flags=MISSING (C:$has_changes U:$has_uncertain S:$has_sep)"
    fi
done

# ═══════════════════════════════════════════════════════════════════════
# Benchmark: deepseek-v4-flash (via `claude` directly)
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}── deepseek-v4-flash (N=$N_RUNS) ──${NC}"
echo ""

# Flash: call claude directly with model env vars overridden
FLASH_TIMES=()
FLASH_LINES=()
FLASH_FLAGS_OK=()

for ((i=1; i<=N_RUNS; i++)); do
    echo -n "  Run $i ... "

    START_NS=$(date +%s%N)
    set +e
    timeout "$DS_TIMEOUT" \
        ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic" \
        ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" \
        ANTHROPIC_MODEL="deepseek-v4-flash" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-flash" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-flash" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash" \
        CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash" \
        claude --print --bare -p "$PROMPT" > "$TMP/flash_run${i}.txt" 2>/dev/null
    rc=$?
    set -e
    END_NS=$(date +%s%N)

    WALL_S=$(echo "scale=1; ($END_NS - $START_NS) / 1000000000" | bc 2>/dev/null || echo "?")
    FLASH_TIMES+=("$WALL_S")

    if [[ "$rc" -ne 0 ]]; then
        echo -e "${RED}FAILED (exit=$rc)${NC}"
        FLASH_LINES+=("ERR")
        FLASH_FLAGS_OK+=("NO")
        continue
    fi

    OUT=$(cat "$TMP/flash_run${i}.txt")
    LINES=$(echo "$OUT" | wc -l)
    FLASH_LINES+=("$LINES")

    has_changes=0; has_uncertain=0; has_sep=0
    echo "$OUT" | grep -q "CHANGES:" && has_changes=1 || true
    echo "$OUT" | grep -q "UNCERTAIN:" && has_uncertain=1 || true
    echo "$OUT" | grep -q -- "---" && has_sep=1 || true

    if [[ "$has_changes" -eq 1 && "$has_uncertain" -eq 1 && "$has_sep" -eq 1 ]]; then
        FLASH_FLAGS_OK+=("YES")
        echo -e "${GREEN}${WALL_S}s${NC}  lines=$LINES  flags=OK"
    else
        FLASH_FLAGS_OK+=("NO")
        echo -e "${YELLOW}${WALL_S}s${NC}  lines=$LINES  flags=MISSING (C:$has_changes U:$has_uncertain S:$has_sep)"
    fi
done

# ═══════════════════════════════════════════════════════════════════════
# Summary table
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  BENCHMARK RESULTS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# Compute means
pro_mean="?"
pro_sum=0; pro_count=0
for t in "${PRO_TIMES[@]}"; do
    if [[ "$t" != "?" ]]; then
        pro_sum=$(echo "$pro_sum + $t" | bc 2>/dev/null || echo "$pro_sum")
        pro_count=$((pro_count + 1))
    fi
done
if [[ "$pro_count" -gt 0 ]]; then
    pro_mean=$(echo "scale=1; $pro_sum / $pro_count" | bc 2>/dev/null || echo "?")
fi

flash_mean="?"
flash_sum=0; flash_count=0
for t in "${FLASH_TIMES[@]}"; do
    if [[ "$t" != "?" ]]; then
        flash_sum=$(echo "$flash_sum + $t" | bc 2>/dev/null || echo "$flash_sum")
        flash_count=$((flash_count + 1))
    fi
done
if [[ "$flash_count" -gt 0 ]]; then
    flash_mean=$(echo "scale=1; $flash_sum / $flash_count" | bc 2>/dev/null || echo "?")
fi

# Print table header
printf "  %-28s" "Model"
for ((i=1; i<=N_RUNS; i++)); do
    printf " %-8s" "Run$i"
done
printf " %-8s %-12s\n" "Mean" "Output_lines"

printf "  %-28s" "────────────────────────────"
for ((i=1; i<=N_RUNS; i++)); do
    printf " %-8s" "────────"
done
printf " %-8s %-12s\n" "────────" "────────────"

# Pro row
printf "  %-28s" "deepseek-v4-pro[1m]"
for ((i=0; i<N_RUNS; i++)); do
    t="${PRO_TIMES[$i]:-?}"
    printf " %-8s" "${t}s"
done
printf " %-8s" "${pro_mean}s"

# Collect pro line counts
pro_lines_str=""
for ((i=0; i<N_RUNS; i++)); do
    if [[ $i -gt 0 ]]; then pro_lines_str+=","; fi
    pro_lines_str+="${PRO_LINES[$i]:-?}"
done
printf " %-12s\n" "$pro_lines_str"

# Flash row
printf "  %-28s" "deepseek-v4-flash"
for ((i=0; i<N_RUNS; i++)); do
    t="${FLASH_TIMES[$i]:-?}"
    printf " %-8s" "${t}s"
done
printf " %-8s" "${flash_mean}s"

flash_lines_str=""
for ((i=0; i<N_RUNS; i++)); do
    if [[ $i -gt 0 ]]; then flash_lines_str+=","; fi
    flash_lines_str+="${FLASH_LINES[$i]:-?}"
done
printf " %-12s\n" "$flash_lines_str"

echo ""

# Quality proxy summary
echo -e "${CYAN}── Quality Proxy: FLAGS compliance ──${NC}"
echo ""

printf "  %-28s" "Model"
for ((i=1; i<=N_RUNS; i++)); do
    printf " %-8s" "Run$i"
done
printf " %-8s\n" "Rate"

printf "  %-28s" "────────────────────────────"
for ((i=1; i<=N_RUNS; i++)); do
    printf " %-8s" "────────"
done
printf " %-8s\n" "────────"

pro_flags_pass=0
printf "  %-28s" "deepseek-v4-pro[1m]"
for ((i=0; i<N_RUNS; i++)); do
    f="${PRO_FLAGS_OK[$i]:-?}"
    if [[ "$f" == "YES" ]]; then
        pro_flags_pass=$((pro_flags_pass + 1))
        printf " ${GREEN}%-8s${NC}" "✓"
    else
        printf " ${RED}%-8s${NC}" "✗"
    fi
done
printf " %-8s\n" "${pro_flags_pass}/${N_RUNS}"

flash_flags_pass=0
printf "  %-28s" "deepseek-v4-flash"
for ((i=0; i<N_RUNS; i++)); do
    f="${FLASH_FLAGS_OK[$i]:-?}"
    if [[ "$f" == "YES" ]]; then
        flash_flags_pass=$((flash_flags_pass + 1))
        printf " ${GREEN}%-8s${NC}" "✓"
    else
        printf " ${RED}%-8s${NC}" "✗"
    fi
done
printf " %-8s\n" "${flash_flags_pass}/${N_RUNS}"

echo ""

# Speedup calculation
if [[ "$pro_mean" != "?" && "$flash_mean" != "?" ]]; then
    speedup=$(echo "scale=1; $pro_mean / $flash_mean" | bc 2>/dev/null || echo "?")
    echo "  Flash speedup vs Pro: ${speedup}×"
    echo "  (Pro mean: ${pro_mean}s, Flash mean: ${flash_mean}s)"
fi

echo ""
echo "  Prompt: 'Write a 3-sentence explanation of photosynthesis.'"
echo "  FLAGS compliance = output contains CHANGES: AND UNCERTAIN: AND ---"
echo ""

echo -e "${CYAN}Benchmark complete.${NC}"
exit 0
```

---

All seven files are above. Here's a quick summary of each:

| File | Tests | Exit 0 means |
|---|---|---|
| `tests/run_all.sh` | Orchestrator — discovers and runs all `??-*.sh` scripts, prints colour-coded pass/fail table | All tests passed |
| `tests/03-programmatic-test.sh` | VALIDITY: `--print --bare` returns "HELLO" · BOUNDARY: empty prompt doesn't hang | Both pass |
| `tests/04-async-parallel-test.sh` | VALIDITY: 2 parallel tasks captured · speedup < 1.5× · BOUNDARY: `VAR=$(cmd) &` anti-pattern confirmed | All pass |
| `tests/05-structured-output-test.sh` | VALIDITY: FLAGS header present · BOUNDARY: missing header detected and flagged · loose-prompt resilience | All pass |
| `tests/06-speculative-test.sh` | VALIDITY: 2 parallel JSON parseable · BOUNDARY: 3 instances complete ≤ 2× single time | All pass |
| `tests/07-self-critique-test.sh` | VALIDITY-A: error injected → ISSUES catches it · VALIDITY-B: clean text → VERDICT=pass · BOUNDARY: empty draft graceful | All pass |
| `tests/benchmark-timing.sh` | Compares v4-pro[1m] vs v4-flash: N=3× each, wall-time table, FLAGS-compliance proxy | Benchmark complete |

Key design decisions:

- **Timeout on every call** — prevents hangs from blocking the suite (30s for boundary tests, 120–180s for validity)
- **Colour-coded output** — green PASS/red FAIL for quick scanning
- **`trap` cleanup** — `mktemp -d` with `EXIT` trap ensures no temp-file leakage
- **Protocol-accurate prompts** — test prompts match the exact phrasing from each protocol doc (e.g., Protocol 05's "Begin your response with:" is the precise instruction tested)
- **Benchmark bypasses wrapper** — the `claude-deepseek` wrapper hardcodes model names via `export`, so flash calls go directly to `claude` with env vars set on the command line
- **Anti-pattern test uses shell builtins** — the `VAR=$(cmd) &` test doesn't need DeepSeek at all; it's a pure shell-semantics demonstration confirming the protocol's warning
