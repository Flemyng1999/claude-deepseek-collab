---
name: Delegate token-heavy low-IQ tasks to DeepSeek
description: Plan-mode [DeepSeek]/[Claude] step annotation drives routing; token-heavy low-IQ tasks → programmatic DeepSeek delegation, Claude reserves critical audit
type: feedback
---

Token-heavy, low-IQ tasks (prose synthesis / format conversion / template filling) should
be delegated to DeepSeek programmatically. Claude reserves capacity for critical audit,
physics derivation, multi-step planning, and novel insight extraction.

**Routing table**

| Task type | → DeepSeek | → Claude |
|---|---|---|
| Long-form prose drafting from existing structured material | ✅ | |
| Format conversion (md ↔ LaTeX / bullets ↔ prose / table ↔ narrative) | ✅ | |
| Bibliographic record formatting / DOI lookup batches | ✅ | |
| Schema-pattern / template filling / repetitive boilerplate | ✅ | |
| Translation / language polishing of already-decided content | ✅ | |
| §M&M / §Results / §Discussion drafting from structured evidence | ✅ | |
| Critical audit / framing decisions / physics derivation | | ✅ |
| First-principles derivation / multi-step planning / governance | | ✅ |
| Cold-start prompt engineering (contamination prevention) | | ✅ |
| Novel insight extraction from raw data | | ✅ |

**Routing trigger**

Plan-mode step annotation `[DeepSeek]` / `[Claude]` is the primary routing point.
Large tasks → Plan mode, each step explicitly labeled.
Simple single-step tasks → decide directly from routing table.

**Programmatic delegation**

```bash
claude-deepseek --print --bare -p "fully self-contained prompt"
```

`--bare` skips project CLAUDE.md and hooks — embed all needed context inline.
`--print` produces non-interactive output suitable for piping or capture.

**Audit gate**

DeepSeek output → Claude consistency + boundary check → user confirmation → execute.

Known DeepSeek weakness: weak self-consistency — understands rules but does not self-audit
after writing. Claude must verify before integrating any DeepSeek output.

**Structured output**

Request DeepSeek to begin its response with a FLAGS header for low-cost audit:

```
CHANGES: [bullet list of what was changed]
UNCERTAIN: [anything DeepSeek is unsure about]
---
[actual content]
```

This lets Claude audit intent in ~50 tokens before reading the full output.
