# /ds

Use DeepSeek as a draft worker for token-heavy, low-risk, self-contained work.
Claude owns the task decomposition, final audit, and final answer.

## Workflow

1. Turn the user request into a complete DS task brief.
2. Save it as `.ds/tasks/YYYYMMDD-HHMMSS-task.md` in the active project.
3. Dispatch with the first available command:
   - `scripts/ds-dispatch.sh <task-file>` if this project has it
   - `ds-dispatch <task-file>` if installed globally
4. Read the printed `RESULT_FILE=<path>`.
5. Read the result file.
6. Audit the result with `/ds-audit`.
7. Return only Claude-audited final output to the user.

Do not expose raw DS output as final. Do not merge code, overwrite files, or
trust factual claims until Claude has reviewed them.

## Task brief shape

Use `templates/ds_task.md` when present, otherwise use this shape:

- Objective
- Context
- Inputs
- Constraints
- Output format
- Things not to do

Make the brief self-contained. If DS needs file content, paste the relevant
content or a compact Claude-written summary into the brief.

## Skill stacking

When another skill is active, let that skill decide scope and constraints. Use
`/ds` only for the delegatable draft subtask, following
`protocols/09-skill-adapter.md`.

## Good examples

- Batch drafting several variants of the same section
- Translation or bilingual polishing
- Repetitive edits across similar snippets
- Multi-version generation for titles, abstracts, emails, docs, or prompts
- Long summary from provided notes
- Boilerplate scaffolding from a clear pattern
- First-pass code that Claude will inspect, test, and adapt
