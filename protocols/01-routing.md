# Protocol 01 — Routing: DeepSeek vs Claude

## The cost model

Claude Opus is expensive per token and has high reasoning capacity.
DeepSeek V4 Pro has ~unlimited tokens at near-zero marginal cost and single-task
intelligence comparable to Claude Sonnet.

The architecture exploits this asymmetry: Claude handles decisions, audits, and
novel derivations; DeepSeek handles volume.

## Decision threshold

Delegate to DeepSeek when **all three** conditions hold:

1. **Token-heavy**: expected output > ~50 tokens
2. **Low-IQ**: the task is synthesis / conversion / formatting, not novel reasoning
3. **Self-contained**: the task can be fully specified in a single prompt (no file access needed, or all relevant content can be embedded inline)

If any condition fails → Claude handles it.

## Routing table (quick reference)

| Task type | Route |
|---|---|
| Prose drafting from structured existing material | DeepSeek |
| Format conversion (md ↔ LaTeX, bullets ↔ prose) | DeepSeek |
| Bibliographic formatting / DOI batches | DeepSeek |
| Template / boilerplate filling | DeepSeek |
| Translation / language polishing of decided content | DeepSeek |
| Paper section drafting (M&M / Results / Discussion) from evidence | DeepSeek |
| Critical audit of DeepSeek output | Claude |
| Physics derivation / first-principles reasoning | Claude |
| Multi-step planning / governance decisions | Claude |
| Prompt engineering (cold-start, contamination-sensitive) | Claude |
| Novel insight extraction from raw data | Claude |

## Primary routing mechanism: Plan-mode step annotation

For any task that spans multiple steps, enter Plan mode first.
Tag each step explicitly before executing anything:

```
Step 1 [DeepSeek] — draft §Results from closure.md evidence
Step 2 [Claude]   — audit factual consistency + physics boundary
Step 3 [DeepSeek] — rewrite §Discussion based on audit notes
Step 4 [Claude]   — final framing decision
```

This creates a forced pause for routing decisions and prevents Claude inertia
(the tendency to execute DeepSeek-appropriate tasks without delegating).

## Fallback: single-step routing

For simple one-step tasks, apply the routing table directly without Plan mode.
