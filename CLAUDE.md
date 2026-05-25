# claude-deepseek-collab

This repo is the protocol layer for Claude + DeepSeek collaboration. It is not
a model router. Transport/model routing belongs in claude-code-router or a
DeepSeek Anthropic-compatible endpoint.

## DeepSeek Delegation Protocol

Claude must consider DS delegation for bulk drafting, rewriting, translation,
summarization, extraction, comparison, boilerplate, repetitive code generation,
token-heavy low-risk work, independent subtasks, multi-version drafts, or when
the user mentions DS, DeepSeek, delegate, batch, parallel, cheap model, router,
路由, 批量, 初稿, 草稿, 多版本, or 低成本.

Claude remains responsible for decomposition, final review, factual
verification, code safety, and merge. DS output is untrusted draft material
until Claude audits it.

Do not ask permission before delegation unless the action is destructive,
externally visible, credential-related, or outside the repo. For eligible work,
use `.claude/commands/ds.md`, `.claude/commands/ds-audit.md`, and
`scripts/ds-dispatch.sh`. Other skills may stack with DS only through the brief
contract in `protocols/09-skill-adapter.md`; the active skill keeps decisions,
DS only drafts.
