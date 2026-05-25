# Protocol 06 — Speculative Execution (Multi-Path Exploration)

## When to use

When facing a decision with N plausible approaches and insufficient information
to choose upfront, fire N parallel DeepSeek instances — each exploring one approach
— and have Claude read compact summaries to decide.

Cost: ~2 min wall-clock (parallel) + ~30 tokens per summary to read.
Alternative: Claude reasons through all approaches sequentially at full token cost.

## Pattern

```bash
PROMPT_A="Explore approach A: [description]. Return a compact JSON summary:
{\"approach\": \"A\", \"pros\": [...], \"cons\": [...], \"blockers\": [...], \"verdict\": \"viable|risky|blocked\"}"

PROMPT_B="Explore approach B: [description]. Return a compact JSON summary:
{\"approach\": \"B\", \"pros\": [...], \"cons\": [...], \"blockers\": [...], \"verdict\": \"viable|risky|blocked\"}"

TMP=$(mktemp -d)
claude-deepseek --print --bare -p "$PROMPT_A" > "$TMP/a.txt" &
claude-deepseek --print --bare -p "$PROMPT_B" > "$TMP/b.txt" &
wait

cat "$TMP/a.txt"
cat "$TMP/b.txt"
rm -rf "$TMP"
# Claude reads ~60 tokens total and makes the routing decision
```

## Output format for exploration tasks

Request compact JSON so Claude can audit all summaries with minimal tokens:

```json
{
  "approach": "name",
  "pros": ["..."],
  "cons": ["..."],
  "blockers": ["... or none"],
  "verdict": "viable | risky | blocked",
  "recommendation": "one sentence"
}
```

## Example use cases

- **Architecture decision**: explore two data pipeline designs in parallel
- **Bug diagnosis**: explore two hypothesized root causes simultaneously  
- **Section structure**: explore two narrative framings for a paper section
- **Algorithm choice**: benchmark two candidate algorithms conceptually before coding

## Decision after exploration

Claude reads the summaries and:
1. If one approach is clearly viable and others blocked → proceed with that approach
2. If multiple approaches viable → present tradeoffs to user, ask for decision
3. If all approaches blocked → surface the blockers to user

Do not proceed autonomously past a genuine fork without user confirmation.

## Two-level tree

For very large decision spaces, Claude can run a first-level exploration to narrow
to 2–3 candidates, then a second-level exploration to go deeper on those candidates.
Each level takes ~2 min. Two levels = ~4 min to map a complex decision space.
