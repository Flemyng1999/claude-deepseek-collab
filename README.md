# claude-deepseek-collab

A minimal, battle-tested architecture for using Claude Code and DeepSeek V4 Pro
together — Claude handles reasoning and audit, DeepSeek handles volume.

**Why**: Claude Opus costs significant tokens per call. DeepSeek V4 Pro has
comparable single-task quality at near-zero marginal cost. Most research/writing
workflow volume (prose drafting, format conversion, template filling) doesn't
need Claude's reasoning depth. This architecture routes each step to the right model.

## What's here

```
bin/claude-deepseek          # Wrapper: redirects Claude Code CLI to DeepSeek API
config/deepseek.env.example  # API key template
rules/deepseek-delegation.md # Drop into ~/.claude/rules/ — loaded by Claude automatically
hooks/session-start.snippet.json  # Optional: surface pending decisions at session start
protocols/
  01-routing.md                  # When to use DeepSeek vs Claude
  02-plan-annotation.md          # [DeepSeek]/[Claude] step tagging in Plan mode
  03-programmatic-delegation.md  # --print --bare delegation pattern
  04-async-parallel.md           # Parallel tasks via temp files (~2 min for N tasks)
  05-structured-output.md        # FLAGS-first format to minimize audit token cost
  06-speculative-exec.md         # Multi-path exploration with parallel DeepSeek instances
  07-self-critique-loop.md       # Two-instance quality loop (draft → critique → Claude compact audit)
  08-scdp.md                     # Stateless Chunk-Directive Protocol for large-file tasks
tests/                           # Validity + boundary tests per protocol; timing benchmark
install.sh                       # Automated setup
```

## Quick start (5 minutes)

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- DeepSeek API key from [platform.deepseek.com](https://platform.deepseek.com/api-keys)

### Install

```bash
git clone https://github.com/your-username/claude-deepseek-collab
cd claude-deepseek-collab
bash install.sh
```

Then edit `~/.config/claude-code/deepseek.env` and add your key:

```bash
export DEEPSEEK_API_KEY="sk-your-key-here"
```

### Wire up the rules file

Add to `~/.claude/CLAUDE.md`:

```
@~/.claude/rules/deepseek-delegation.md
```

### Test

```bash
claude-deepseek --print --bare -p "Say hello in one sentence."
```

You should see a one-sentence response from DeepSeek. If you see an error about
the API key, check `~/.config/claude-code/deepseek.env`.

## How the architecture works

### Two models, one workflow

```
User → Claude Code (Claude Opus)
              ↓ [Bash tool]
       claude-deepseek --print --bare -p "..."
              ↓
       DeepSeek V4 Pro (via Anthropic-compatible API)
              ↓ stdout
       Claude audits output
              ↓
       User confirms → integrate
```

`claude-deepseek` is a thin bash wrapper that sets environment variables to
redirect Claude Code's API calls to DeepSeek's Anthropic-compatible endpoint.
See [DeepSeek official docs](https://api-docs.deepseek.com/zh-cn/quick_start/agent_integrations/claude_code)
for the canonical configuration reference.

### The routing principle

Delegate to DeepSeek when:
1. Expected output > ~50 tokens
2. Task is synthesis / conversion / formatting (not novel reasoning)
3. Task can be fully specified in a single self-contained prompt

Everything else stays with Claude.

### The core patterns

**Programmatic delegation** (Protocol 03):
```bash
RESULT=$(claude-deepseek --print --bare -p "$PROMPT")
```
No user relay. Claude invokes this via Bash and receives output synchronously.

**Parallel async** (Protocol 04):
```bash
R1=$(claude-deepseek --print --bare -p "$P1") &
R2=$(claude-deepseek --print --bare -p "$P2") &
wait
```
N independent tasks complete in ~2 min regardless of N (vs N×2 min sequential).

**Structured output** (Protocol 05):
Request a FLAGS header to minimize audit cost:
```
CHANGES: [what was changed]
UNCERTAIN: [anything uncertain]
---
[content]
```
Audit cost: ~50 tokens (header only) instead of full-read.

**Plan-mode annotation** (Protocol 02):
```
Step 1 [Claude]   — identify key findings from data
Step 2 [DeepSeek] — draft §Discussion from findings
Step 3 [Claude]   — audit factual consistency
```
Forces routing decisions before execution. Prevents Claude inertia.

## Model reference

| Variable | Value | Notes |
|---|---|---|
| Primary model | `deepseek-v4-pro[1m]` | 1M context window |
| Subagent model | `deepseek-v4-flash` | Faster/cheaper for subagents |
| API endpoint | `https://api.deepseek.com/anthropic` | Anthropic-compatible |

See [DeepSeek API docs](https://api-docs.deepseek.com/zh-cn/quick_start/agent_integrations/claude_code)
for the authoritative model list and any updates.

## Protocols index

| File | What it covers |
|---|---|
| `01-routing.md` | The decision threshold and routing table |
| `02-plan-annotation.md` | Plan-mode `[DeepSeek]`/`[Claude]` step labeling |
| `03-programmatic-delegation.md` | The `--print --bare` delegation pattern + prompt construction |
| `04-async-parallel.md` | Parallel delegation, error handling, rate limit guidance |
| `05-structured-output.md` | FLAGS-first format, audit interpretation, example exchange |
| `06-speculative-exec.md` | Multi-path parallel exploration for uncertain decisions |
| `07-self-critique-loop.md` | Two-instance loop — Instance 1 drafts, Instance 2 critiques; Claude reads only the critique (~50-100 tokens). Use for prose >300 tokens where accuracy matters. |
| `08-scdp.md` | Stateless Chunk-Directive Protocol — DeepSeek receives a compact capsule of file summaries, requests chunks on demand via `<<EXPAND>>` directives; enables large-file tasks without inline-embedding. |

## Known limitations

- `--bare` means DeepSeek has no file access — embed context inline for small tasks; for large-file tasks, use SCDP (Protocol 08)
- DeepSeek's self-consistency is weaker than Claude's — always audit before integrating (use self-critique loop, Protocol 07, for prose >300 tokens)
- Rate limit: avoid >5 simultaneous parallel calls
- Tasks requiring iterative file editing or multi-turn refinement remain Claude-only
