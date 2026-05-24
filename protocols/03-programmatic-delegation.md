# Protocol 03 — Programmatic Delegation

## The pattern

```bash
claude-deepseek --print --bare -p "fully self-contained prompt"
```

- `--print`: non-interactive; output goes to stdout, no spinner, no session files
- `--bare`: skips project CLAUDE.md, hooks, and memory — DeepSeek sees only the prompt
- `-p "..."`: the complete prompt; must embed all context inline (no file references)

Claude invokes this via the Bash tool and receives output synchronously.
No user relay, no copy-paste, no manual handoff.

## Prompt construction rules

Because `--bare` strips all project context, the prompt must be fully self-contained:

1. **Embed all relevant content inline** — paste the section, table, or data directly
2. **State the output format explicitly** — see `05-structured-output.md`
3. **State constraints** — word limit, forbidden claims, required structure
4. **No file path references** — DeepSeek cannot read files

Example prompt skeleton:

```
You are drafting §Discussion for a scientific paper.

EVIDENCE:
<paste structured evidence here>

CONSTRAINTS:
- ~400 words
- Do not claim causation, only correlation
- Follow the structure: finding → mechanism → implication

OUTPUT FORMAT:
CHANGES: [what you drafted / key choices made]
UNCERTAIN: [anything you are unsure about]
---
[§Discussion prose]
```

## Capturing output

```bash
RESULT=$(claude-deepseek --print --bare -p "$PROMPT")
echo "$RESULT"
```

Claude then audits `$RESULT` before integrating (see `01-routing.md` audit gate).

## Handling tasks that need file content

Read the file content into a shell variable first, then embed it:

```bash
CONTENT=$(cat path/to/file.md)
RESULT=$(claude-deepseek --print --bare -p "Rewrite the following: $CONTENT

OUTPUT FORMAT:
CHANGES: [...]
UNCERTAIN: [...]
---
[rewritten content]")
```

Keep embedded content under ~10k tokens to stay within practical limits.
