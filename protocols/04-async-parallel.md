# Protocol 04 — Async Parallel Delegation

## Why

Sequential delegation: N tasks × ~2 min each = N×2 min wall-clock time.
Parallel delegation: N tasks run concurrently = ~2 min total.

For independent tasks, always prefer parallel.

## Basic pattern

```bash
TMP=$(mktemp -d)

claude-deepseek --print --bare -p "$PROMPT1" > "$TMP/r1.txt" &
PID1=$!
claude-deepseek --print --bare -p "$PROMPT2" > "$TMP/r2.txt" &
PID2=$!

wait $PID1 $PID2

echo "--- Task 1 ---"
cat "$TMP/r1.txt"
echo "--- Task 2 ---"
cat "$TMP/r2.txt"
rm -rf "$TMP"
```

Tested: 2 tasks completed in ~9 seconds vs ~4+ minutes sequential.

> **Why temp files, not variables**: `VAR=$(cmd) &` runs the assignment in a
> background subshell — the variable is never set in the parent shell.
> Always redirect to temp files and `cat` after `wait`.

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

Redirect each background job to a temp file; read after `wait`:

```bash
TMP=$(mktemp -d)
claude-deepseek --print --bare -p "$PROMPT" > "$TMP/result.txt" &
wait
RESULT=$(cat "$TMP/result.txt")
rm -rf "$TMP"
```

`VAR=$(cmd) &` does **not** work — the assignment runs in a background subshell
and the variable is never set in the parent shell. `wait` blocks until all
background jobs finish before proceeding.

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
