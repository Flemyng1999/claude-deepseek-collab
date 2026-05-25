```bash
#!/usr/bin/env bash
# run_all.sh — claude-deepseek-collab test suite orchestrator
#
# Runs all test scripts matching tests/??-*.sh (excluding benchmark-timing.sh),
# collects pass/fail per script, prints a summary table.
#
# Does NOT abort on first failure — runs every script and reports all results.
#
# Usage:
#   cd /path/to/claude-deepseek-collab
#   bash tests/run_all.sh
#
# Exit code:
#   0 — all tests passed
#   1 — one or more tests failed

set -uo pipefail  # no -e: we want to run all tests

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

declare -a TEST_FILES=()
declare -a TEST_NAMES=()
declare -a TEST_RESULTS=()
declare -a TEST_EXIT_CODES=()
declare -a TEST_DURATIONS=()

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  claude-deepseek-collab  TEST SUITE${NC}"
echo -e "${CYAN}  started: $TIMESTAMP${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# ── Discover test scripts ──────────────────────────────────────────────
if [[ ! -d "$TESTS_DIR" ]]; then
    echo -e "${RED}FATAL: tests/ directory not found at $TESTS_DIR${NC}"
    exit 2
fi

shopt -s nullglob
for f in "$TESTS_DIR"/??-*.sh; do
    base="$(basename "$f")"
    # Skip ourselves
    if [[ "$base" == "run_all.sh" ]]; then
        continue
    fi
    # Skip benchmark (run separately)
    if [[ "$base" == "benchmark-timing.sh" ]]; then
        continue
    fi
    TEST_FILES+=("$f")
    TEST_NAMES+=("$base")
done
shopt -u nullglob

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No test scripts found in $TESTS_DIR${NC}"
    exit 0
fi

echo "Found ${#TEST_FILES[@]} test script(s)"
echo ""

# ── Quick self-check: ensure claude-deepseek is reachable ──────────────
echo -n "Checking claude-deepseek availability ... "
if command -v claude-deepseek &>/dev/null; then
    echo -e "${GREEN}OK${NC} ($(which claude-deepseek))"
else
    echo -e "${RED}NOT FOUND${NC}"
    echo "  Install with: bash install.sh"
    echo "  Then add ~/.local/bin to PATH"
    exit 2
fi

if [[ ! -f "$HOME/.config/claude-code/deepseek.env" ]]; then
    echo -e "${RED}API key config missing: $HOME/.config/claude-code/deepseek.env${NC}"
    echo "  Create from: config/deepseek.env.example"
    exit 2
fi

echo ""

# ── Run each test ──────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

for i in "${!TEST_FILES[@]}"; do
    test_file="${TEST_FILES[$i]}"
    test_name="${TEST_NAMES[$i]}"

    if [[ ! -x "$test_file" ]]; then
        chmod +x "$test_file"
    fi

    echo -n "▶  $test_name ... "

    START_NS=$(date +%s%N)

    # Run in a subshell to isolate side effects
    if (cd "$REPO_ROOT" && bash "$test_file" >/tmp/test_stdout.log 2>/tmp/test_stderr.log); then
        exit_code=$?
    else
        exit_code=$?
    fi

    END_NS=$(date +%s%N)
    DURATION_MS=$(( (END_NS - START_NS) / 1000000 ))

    TEST_EXIT_CODES+=("$exit_code")
    DURATION_MS_STR=$(printf "%.1fs" "$(echo "scale=1; $DURATION_MS / 1000" | bc 2>/dev/null || echo "$((DURATION_MS / 1000))")")
    TEST_DURATIONS+=("$DURATION_MS_STR")

    if [[ "$exit_code" -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}  (${DURATION_MS_STR})"
        TEST_RESULTS+=("PASS")
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}FAIL${NC}  (exit=$exit_code, ${DURATION_MS_STR})"
        TEST_RESULTS+=("FAIL")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        # Print last 10 lines of stderr for diagnostics
        echo -e "  ${YELLOW}last stderr:${NC}"
        tail -10 /tmp/test_stderr.log | sed 's/^/    /' || true
    fi
done

# ── Summary table ──────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  RESULTS SUMMARY${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# Table header
printf "  %-45s %-8s %-5s %s\n" "TEST" "RESULT" "EXIT" "DURATION"
printf "  %-45s %-8s %-5s %s\n" "$(printf '%0.s─' {1..45})" "$(printf '%0.s─' {1..8})" "$(printf '%0.s─' {1..5})" "$(printf '%0.s─' {1..10})"

for i in "${!TEST_NAMES[@]}"; do
    name="${TEST_NAMES[$i]}"
    result="${TEST_RESULTS[$i]}"
    exit_code="${TEST_EXIT_CODES[$i]}"
    duration="${TEST_DURATIONS[$i]}"

    if [[ "$result" == "PASS" ]]; then
        result_coloured="${GREEN}PASS${NC}"
    else
        result_coloured="${RED}FAIL${NC}"
    fi

    printf "  %-45s " "$name"
    echo -ne "$result_coloured"
    printf "   %-3s   %s\n" "$exit_code" "$duration"
done

echo ""
echo -e "  Total: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}, $((PASS_COUNT + FAIL_COUNT)) ran"
echo ""

# ── Exit code ──────────────────────────────────────────────────────────
if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo -e "${GREEN}All tests passed.${NC}"
    exit 0
else
    echo -e "${RED}${FAIL_COUNT} test(s) failed.${NC}"
    exit 1
fi
```

---
