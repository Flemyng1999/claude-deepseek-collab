# Protocol 04 — Async Parallel Delegation

## Why

Sequential delegation: N tasks × ~2 min each = N×2 min wall-clock time.
Parallel delegation: N tasks run concurrently = ~2 min total.

For independent tasks, always prefer parallel.

## Basic pattern

```bash
RESULT1=$(claude-deepseek --print --bare -p "$PROMPT1") &
PID1=$!
RESULT2=$(claude-deepseek --print --bare -p "$PROMPT2") &
PID2=$!

wait $PID1 $PID2

echo "--- Task 1 ---"
echo "$RESULT1"
echo "--- Task 2 ---"
echo "$RESULT2"
```

Tested: 2 tasks completed in ~9 seconds vs ~4+ minutes sequential.

## When tasks are independent

Tasks are independent when:
- They do not consume each other's output
- They do not modify the same file
- Their order of completion does not matter

Examples of parallelizable tasks:
- Draft two different paper sections simultaneously
- Format-convert multiple bibliography entries
- Explore multiple implementation approaches (see `06-speculative-exec.md`)
- Write multiple memory / documentation entries

## Collecting output safely

Shell variable subshell capture (`VAR=$(...)  &`) works correctly in bash.
The variable is populated when the background subshell completes.
`wait` blocks until all background jobs finish before proceeding.

## Error handling

```bash
RESULT=$(claude-deepseek --print --bare -p "$PROMPT") || {
  echo "DeepSeek call failed"
  exit 1
}
```

Check for empty output before integrating:

```bash
if [[ -z "$RESULT" ]]; then
  echo "Empty output — re-run or handle manually"
fi
```

## Limit

Avoid launching more than ~5 parallel instances simultaneously.
DeepSeek has rate limits; beyond ~5 concurrent calls you may hit 429 errors.
