# /ds-audit

Treat DS output as untrusted draft material. Claude must audit before using it.

## Checklist

- Requirements satisfied
- Factual claims checked or clearly flagged
- Hallucinations removed
- Unsafe code removed
- Missing edge cases identified
- Integration risks identified
- Final answer rewritten by Claude

If the DS result is incomplete or risky, either repair it directly as Claude or
create a narrower follow-up DS task. Never pass along raw DS output as final.
