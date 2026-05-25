# claude-deepseek-collab

A minimal, battle-tested architecture for using Claude Code and DeepSeek V4 Pro
together — Claude handles reasoning and audit, DeepSeek handles volume.

**Why**: Claude Opus costs significant tokens per call. DeepSeek V4 Pro has
comparable single-task quality at near-zero marginal cost. Most research/writing
workflow volume (prose drafting, format conversion, template filling) doesn't
need Claude's reasoning depth. This project provides the protocol layer for
delegation: when to delegate, how to brief the task, how to dispatch it, how to
save the result, and how Claude audits it before use.

This project is **not** a model router. Use
[claude-code-router](https://github.com/musistudio/claude-code-router) or a
DeepSeek Anthropic-compatible endpoint for transport/model routing. Keep API
keys and provider configuration in that backend, not in this repo.

## What's here

```
bin/claude-deepseek          # Wrapper: redirects Claude Code CLI to DeepSeek API
config/deepseek.env.example  # API key template
rules/deepseek-delegation.md # Drop into ~/.claude/rules/ — loaded by Claude automatically
hooks/session-start.snippet.json  # Optional: surface pending decisions at session start
.claude/commands/ds.md       # Claude Code /ds delegation workflow
.claude/commands/ds-audit.md # Claude audit checklist for DS output
.claude/hooks/user-prompt-submit.sh  # Cold-start hint for delegation triggers
scripts/ds-dispatch.sh       # Offline-safe dispatch wrapper; CCR optional
scripts/ds-selftest.sh       # No-network self-test for the DS workflow
templates/                   # Task, result, and audit templates
protocols/
  01-routing.md                  # When to use DeepSeek vs Claude
  02-plan-annotation.md          # [DeepSeek]/[Claude] step tagging in Plan mode
  03-programmatic-delegation.md  # --print --bare delegation pattern
  04-async-parallel.md           # Parallel tasks via temp files (~2 min for N tasks)
  05-structured-output.md        # FLAGS-first format to minimize audit token cost
  06-speculative-exec.md         # Multi-path exploration with parallel DeepSeek instances
  07-self-critique-loop.md       # Two-instance quality loop (draft → critique → Claude compact audit)
  08-scdp.md                     # Stateless Chunk-Directive Protocol for large-file tasks
  09-skill-adapter.md            # How other skills stack with /ds
tests/                           # Validity + boundary tests per protocol; timing benchmark
install.sh                       # Automated setup
```

## Quick start (5 minutes)

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- One transport backend configured separately:
  - claude-code-router, or
  - DeepSeek's Anthropic-compatible endpoint

No real API key or network is required for the repo self-test.

### Install

```bash
git clone https://github.com/your-username/claude-deepseek-collab
cd claude-deepseek-collab
bash install.sh
```

This installs `/ds` and `/ds-audit` as global Claude Code commands in
`~/.claude/commands/`, and installs `ds-dispatch` in `~/.local/bin/` so they work
from any project after restarting Claude Code.

Then edit `~/.config/claude-code/deepseek.env` and add your key, if using the
legacy direct DeepSeek wrapper:

```bash
export DEEPSEEK_API_KEY="sk-your-key-here"
```

### Wire up the rules file

Add to `~/.claude/CLAUDE.md`:

```
@~/.claude/rules/deepseek-delegation.md
```

### Configure CCR separately

If using claude-code-router, install and configure it outside this repo. The
transport layer should know about providers, models, API keys, and routing.
This repo should only create task briefs, dispatch them, store results, and
force Claude audit before integration.

Useful CCR checks after separate setup:

```bash
ccr status
ccr start
```

### Test the protocol layer

```bash
bash scripts/ds-selftest.sh
```

The self-test uses `DS_DRY_RUN=1`, creates a fake deterministic DS result, and
does not call the network.

### Use in Claude Code

Use `/ds` when a task is suitable for DeepSeek volume work. Claude should:

1. Create a task brief in `.ds/tasks/`
2. Run `scripts/ds-dispatch.sh <task-file>` or global `ds-dispatch <task-file>`
3. Read the result from `.ds/results/`
4. Audit it with `/ds-audit`
5. Return only Claude-reviewed final output

Direct endpoint smoke test, if you installed the legacy wrapper and configured
DeepSeek credentials:

```bash
claude-deepseek --print --bare -p "Say hello in one sentence."
```

You should see a one-sentence response from DeepSeek. If you see an error about
the API key, check `~/.config/claude-code/deepseek.env`.

## How the architecture works

### Layers

```
Claude Code
   ↓
this repo: trigger / task brief / dispatch wrapper / result storage / audit
   ↓
CCR or DeepSeek Anthropic-compatible endpoint
   ↓
DeepSeek or another configured provider
```

The transport backend decides how model/provider requests are routed. This repo
decides whether work is safe to delegate, makes the prompt explicit, preserves
the DS draft as an artifact, and requires Claude to audit before merging or
answering. Other Claude Code skills can stack with `/ds` by producing a brief
from `templates/ds_task.md`; see `protocols/09-skill-adapter.md`.

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

For CCR-backed setups, use `scripts/ds-dispatch.sh` as the protocol boundary.
It supports dry-run testing offline and fails with setup instructions when CCR
is unavailable or no explicit backend invocation has been configured. If your
local CCR command accepts a prompt with `-p`, set `DS_BACKEND_CMD` to that command
without the prompt text; the dispatcher appends the task brief as the final
argument.

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
TMP=$(mktemp -d)
claude-deepseek --print --bare -p "$P1" > "$TMP/r1.txt" &
claude-deepseek --print --bare -p "$P2" > "$TMP/r2.txt" &
wait
cat "$TMP/r1.txt"
cat "$TMP/r2.txt"
rm -rf "$TMP"
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
| `09-skill-adapter.md` | How any Claude Code skill can use `/ds` for draft work while keeping decisions and audit in Claude. |

## Known limitations

- `--bare` means DeepSeek has no file access — embed context inline for small tasks; for large-file tasks, use SCDP (Protocol 08)
- DeepSeek's self-consistency is weaker than Claude's — always audit before integrating (use self-critique loop, Protocol 07, for prose >300 tokens)
- Rate limit: avoid >5 simultaneous parallel calls
- Tasks requiring iterative file editing or multi-turn refinement remain Claude-only
- `scripts/ds-dispatch.sh` intentionally does not guess CCR invocation details.
  If CCR is installed but no explicit backend command is configured, it exits
  with instructions instead of making an unsafe or credential-bearing call.
- DS output is untrusted draft material. Claude remains responsible for final
  review, factual verification, code safety, and merge decisions.
