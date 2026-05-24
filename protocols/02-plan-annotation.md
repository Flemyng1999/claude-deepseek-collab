# Protocol 02 — Plan-Mode Step Annotation

## Why

Without an explicit labeling step, Claude defaults to handling everything itself
(inertia). Plan-mode annotation creates a structural checkpoint where routing
decisions are made visible and reviewable before any execution begins.

## Annotation format

Every step in a plan must carry exactly one label:

```
Step N [DeepSeek] — <one-line description of task>
Step N [Claude]   — <one-line description of task>
```

No unlabeled steps. No vague labels. The label commits to a specific executor.

## When to use Plan mode

Trigger Plan mode for:
- Tasks with 3+ steps
- Cross-file modifications
- Complex bugs where cause is not yet confirmed
- Any task where step ordering matters

Single-step tasks can route directly without Plan mode (see `01-routing.md`).

## What a good plan looks like

```
## Task: draft and integrate §Discussion

Step 1 [Claude]   — read existing §Results and identify 3 key findings to address
Step 2 [DeepSeek] — draft §Discussion from findings list + provided evidence outline
Step 3 [Claude]   — audit: factual consistency, overclaiming, boundary violations
Step 4 [DeepSeek] — revise based on audit notes
Step 5 [Claude]   — final framing decision and integration into manuscript
```

## Spec-completeness requirement for [DeepSeek] steps

Before executing a `[DeepSeek]` step, the plan must specify:
- What input the step consumes (which files / inline text)
- What output format is expected (see `05-structured-output.md`)
- What constraints apply (word count, tone, forbidden claims)

A `[DeepSeek]` step without a complete spec must be refined before execution.

## Claude audit after governance-boundary steps

If a `[DeepSeek]` step produces output that crosses a governance boundary
(definition changes, claim escalations, structural decisions), a `[Claude]` audit
step must immediately follow — not optionally.
