# Protocol 09 — Skill Adapter

`/ds` is a horizontal draft worker, not a domain skill. Any Claude Code skill
may use it after that skill has done its own task understanding and boundary
checks.

## Contract for any skill

1. Decide which subtask is delegatable.
2. Keep domain decisions in Claude or the active skill.
3. Write a self-contained brief with `templates/ds_task.md`.
4. Dispatch with `scripts/ds-dispatch.sh <task-file>`.
5. Audit with `.claude/commands/ds-audit.md`.
6. Return only Claude-reviewed final output.

## Good delegations

- Drafts, rewrites, translations, summaries, extraction, comparisons
- Multi-version options
- Repetitive boilerplate
- Low-risk first-pass code or tests
- Long daily notes condensed into a draft summary

## Never delegate

- Final decisions, commitments, or priorities
- Secrets, credentials, private raw logs, or hidden chain-of-thought
- Destructive, externally visible, or out-of-repo actions
- Unreviewed code merge, factual claims, or security-sensitive changes

## Stable trigger rule

Prefer explicit triggers: `/ds`, `DeepSeek`, `delegate`, `批量`, `初稿`, `草稿`,
`多版本`, or `低成本`. Hooks may remind Claude, but must not dispatch or modify
files. The active skill remains in charge; DS only drafts.
