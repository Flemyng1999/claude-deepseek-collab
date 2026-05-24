# Protocol 05 — Structured Output for Low-Cost Audit

## The problem

If DeepSeek returns raw content, Claude must read the entire output to audit it.
For a 500-token output, that costs ~500 tokens of audit work.

## The solution: FLAGS header first

Request a structured header before the content:

```
CHANGES: [bullet list of what was changed / key decisions made]
UNCERTAIN: [anything DeepSeek flagged as uncertain or needing verification]
---
[actual content]
```

Claude reads the FLAGS header (~30–80 tokens) and decides:
- **No flags, expected changes** → integrate directly
- **UNCERTAIN items** → inspect only those sections
- **Unexpected changes** → reject and re-prompt

Audit cost drops from ~500 tokens (full read) to ~50 tokens (header only) in the
common case where the output is clean.

## Required prompt instruction

Add this to every DeepSeek delegation prompt:

```
Begin your response with:
CHANGES: [bullet list of what you changed or key choices you made]
UNCERTAIN: [list anything you are unsure about, or write "none"]
---
Then provide the [output type].
```

## Interpreting FLAGS

| UNCERTAIN value | Action |
|---|---|
| `none` | Proceed to spot-check only |
| Specific item listed | Read that section carefully before integrating |
| Many items listed | Consider re-prompting with more constraints |

| CHANGES value | Action |
|---|---|
| Matches expected scope | Integrate after spot-check |
| Broader than expected | Read full output; may need to trim |
| Narrower than expected | Check if prompt was underspecified |

## Example exchange

Prompt includes: `Begin your response with CHANGES: [...] UNCERTAIN: [...]`

DeepSeek response:
```
CHANGES:
- Drafted §Discussion (~380 words)
- Framed finding 1 as correlation (not causation) per constraint
- Omitted mechanism for finding 3 (insufficient evidence in provided material)

UNCERTAIN:
- Finding 2 implication paragraph — not sure if "downstream application" framing
  matches the paper's scope; verify against §Introduction

---
The vegetation canopy re-illumination results demonstrate...
```

Claude audit: Read CHANGES (expected scope ✓), check finding 2 implication paragraph
(~30 tokens), done. Total audit: ~60 tokens instead of ~400.
