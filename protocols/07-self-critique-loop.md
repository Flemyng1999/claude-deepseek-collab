# Protocol 07 — Self-Critique Loop

> **Dependency chain**: Protocol 03 (programmatic delegation) → Protocol 04 (async parallel) → Protocol 05 (FLAGS structured output) → **Protocol 07 (self-critique loop)**
>
> **Problem**: DeepSeek V4 Pro generates fluent, structurally correct output but **does not self-audit**. Report summaries and artifact content can contradict; factual assertions may be inconsistent with provided evidence; structural commitments made in FLAGS headers may mismatch the body text. Without review, these errors propagate into downstream Claude audit — but Claude audit cost scales with output length.
>
> **Solution**: Insert a second DeepSeek instance as an adversarial reviewer between draft and Claude. Claude reads only the compact critique (~50–100 tokens) + FLAGS header, not the full output, for pass-verdict cases. For needs-revision cases, Claude reads the critique ISSUES list (~100–200 tokens) — still far less than the full draft.

---

## 1. Pattern Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    SELF-CRITIQUE LOOP                            │
│                                                                  │
│  ┌──────────┐     draft      ┌──────────┐                       │
│  │ Instance │ ──────────────→ │ Instance │                       │
│  │    1     │   (Protocol 05) │    2     │                       │
│  │ Draft    │                 │ Critique │                       │
│  └──────────┘                 └────┬─────┘                       │
│                                    │                             │
│                  ISSUES + VERDICT  │                             │
│                                    ▼                             │
│                           ┌──────────────┐                       │
│                           │    Claude     │                      │
│                           │   Auditor     │                      │
│                           └──┬───┬───┬───┘                      │
│                              │   │   │                           │
│              pass ──────────┘   │   └── needs_revision          │
│              (~60 tokens)       │       (~200 tokens)            │
│                                 │                                │
│            ┌────────────────────┘                                │
│            ▼                                                     │
│   ┌─────────────────┐       ┌──────────────────┐                │
│   │ SPOT-CHECK       │       │ DECIDE            │               │
│   │ FLAGS + VERDICT  │       │ re-prompt / fix   │               │
│   │ → ACCEPT draft   │       │ manually          │               │
│   └─────────────────┘       └──────────────────┘                │
│                                                                  │
│   Optional batch-2: re-run Instance 1 with critique as           │
│   additional constraint → second draft → Instance 2 again        │
└─────────────────────────────────────────────────────────────────┘
```

## 2. Step-by-Step

### Step 1 — Instance 1: Draft with FLAGS header

Instance 1 produces a draft following **Protocol 05**: the output begins with a FLAGS header block:

```
CHANGES: [list of files/sections modified or created]
UNCERTAIN: [any claims the model is uncertain about, or "none"]
---
[body content — prose, code, tables, etc.]
```

The FLAGS header is critical: it is the first thing Claude reads during audit. A well-written FLAGS block lets Claude know at a glance what was changed and where doubt exists. Instance 1 must be prompted to write honest UNCERTAIN entries — not polite placeholders.

**Invocation** (per Protocol 03):

```bash
claude-deepseek --print --bare -p "$(cat task_spec.md)" > draft.md
```

`task_spec.md` must include:
- The FLAGS-header requirement (reference Protocol 05)
- The complete task specification with acceptance criteria
- File paths, evidence anchors, output format
- Length cap if applicable

### Step 2 — Instance 2: Adversarial Review

Instance 2 receives the full draft and critiques it using the **Critique Prompt Template** (§3 below). Instance 2 is a fresh, independent DeepSeek call — no shared context with Instance 1.

**Invocation** (per Protocol 04 — async parallel):

```bash
# Step 1 and Step 2 can run in parallel if Instance 2 is fed
# a different draft from a previous iteration. For the first
# pass, they must be sequential:

claude-deepseek --print --bare -p "$(cat critique_spec.md)" > critique.md
```

`critique_spec.md` = the critique prompt template (§3) with the draft text substituted into the TEXT field.

**Instance 2 context**: provide a **one-sentence task brief + key constraint list** only.
The full task specification is withheld to prevent anchoring — but Instance 2 must
see enough constraints to detect spec violations (scope, format, naming conventions,
excluded cases). Without any spec context, Instance 2 cannot flag that the draft
violates the task's requirements.

Example brief:
> *Task*: Draft §3 Methods prose for a canopy reflectance manuscript.
> *Constraints*: Use notation R_dif1 (not R_dir1); SZA=80° is explicitly excluded;
> output must include FLAGS header per Protocol 05.

### Step 3 — Claude: Compact Audit

Claude reads only what is necessary:

| VERDICT | What Claude reads | Approx. tokens |
|---|---|---|
| `pass` | FLAGS header + VERDICT line | ~60 |
| `needs_revision` | FLAGS + full ISSUES list + VERDICT + one-sentence summary | ~200 |

Claude does **not** read the full draft body for a `pass` verdict. This is the cost-saving mechanism — the critique IS the compressed audit.

**Claude's decision tree**:

1. **If VERDICT = pass**: spot-check FLAGS header for obvious red flags (e.g., UNCERTAIN lists a critical item). If FLAGS looks clean, ACCEPT draft. Claude may optionally sample 2–3 random sentences from the draft body as a sanity check — this should be rare and explicitly noted.

2. **If VERDICT = needs_revision**: read the full ISSUES list. Decide:
   - **Re-prompt**: issues are systematic/spec-violating → write a corrected task spec incorporating the critique as constraints, re-run Instance 1 (Step 5 batch-2)
   - **Handle manually**: issues are minor/localized → Claude fixes directly (cost: Claude reads draft body once)
   - **Escalate**: issues touch governance boundary (scope, framing, core claims) → flag for PI

### Step 4 — Gate Decision

Claude produces a final verdict in one of four states:

| State | Meaning | Next action |
|---|---|---|
| `ACCEPT` | Draft passes with no or cosmetic issues | Merge into working copy |
| `ACCEPT_WITH_NOTES` | Passes but has non-blocking issues | Merge; file issues as follow-up ticket |
| `REVISE` | Needs revision via Instance 1 re-run | Execute Step 5 (batch-2) |
| `REJECT` | Fundamentally wrong; Claude must rewrite | Claude handles; log as loop failure for post-mortem |

### Step 5 — Batch-2 (Optional): Re-run with Critique

If Claude decides REVISE, re-run Instance 1 with the critique as an additional constraint:

```bash
# Construct a revised task spec by appending the critique
cat task_spec.md > task_spec_v2.md
echo "" >> task_spec_v2.md
echo "## Revision constraints (from reviewer)" >> task_spec_v2.md
cat critique.md >> task_spec_v2.md

claude-deepseek --print --bare -p "$(cat task_spec_v2.md)" > draft_v2.md
```

Then re-run Instance 2 on the new draft. **Maximum 2 batch-2 iterations** — if the third draft still fails, the task is likely mis-specified or exceeds DeepSeek's capability for the given domain. Claude takes over.

## 3. Critique Prompt Template

The prompt for Instance 2 is the core of this protocol. It must be **fixed in structure** to produce parsable, comparable output.

```
Adversarial reviewer. Your sole task: find every flaw in the text below.
Be specific, numbered, and adversarial. Assume nothing is correct until proven.

TEXT:
```
[draft text — full body including FLAGS header]
```

Examine for:
1. **Factual errors** — claims that contradict provided evidence, wrong numbers, wrong citations
2. **Logical gaps** — missing steps in reasoning, unstated assumptions, non-sequiturs
3. **Structural violations** — FLAGS header content that mismatches the body (e.g., CHANGES lists a file not actually modified, UNCERTAIN claims "none" when the body contains hedging language)
4. **Specification violations** — output that exceeds scope, modifies files not authorized, changes definitions or thresholds
5. **Internal inconsistencies** — two parts of the text that contradict each other
6. **Over-claiming** — stronger conclusions than the evidence supports, missing caveats

Return ONLY:
ISSUES: [numbered list, one issue per line. If no issues found, write "none"]
VERDICT: pass | pass_with_notes | needs_revision
---
[one sentence: the single most critical issue, or "no critical issues found"]
```

`pass_with_notes` = draft passes core acceptance criteria but reviewer flagged
non-blocking items. Claude treats this as `ACCEPT_WITH_NOTES` — merge and file
the flagged items as follow-up tasks rather than blocking the pipeline.

**Why this template works**:
- The adversarial framing ("assume nothing is correct until proven") counters DeepSeek's known sycophancy bias
- The six examination categories form a checklist — Instance 2 won't forget to check structural violations if it's in the list
- Three-level verdict (pass | pass_with_notes | needs_revision) gives Claude granularity: accept clean, accept with tracked follow-ups, or block for revision
- The output format is strict: ISSUES / VERDICT / `---` / one-sentence — easy for Claude to parse in ~200 tokens
- "Return ONLY" prevents Instance 2 from adding disclaimers, hedging, or verbose explanations

## 4. When to Use (Triage Matrix)

| Scenario | Use loop? | Reason |
|---|---|---|
| Long prose output (>300 tokens) from DeepSeek | ✅ **YES** | Primary use case. Claude audit of full text would be expensive; critique amortizes well |
| Scientific/technical text with factual claims | ✅ **YES** | Factual accuracy matters; Instance 2 adversarial review catches hallucinated numbers, wrong units, misattributed evidence |
| Multi-section paper drafts (≥2 sections) | ✅ **YES** | Structural errors (e.g., §Results says X, §Discussion says Y) are hard to spot in a single read; adversarial review surfaces them |
| Code generation with FLAGS header | ⚠️ **CONDITIONAL** | Use if output >200 lines and correctness matters. Skip for obvious boilerplate |
| Template filling / schema generation | ❌ **NO** | Errors are obvious (wrong field names, missing columns); Claude spot-check is sufficient |
| Boilerplate / repetitive formatting | ❌ **NO** | No factual content to audit; Instance 2 would find only style nits, not worth the overhead |
| Single-paragraph answers (<100 tokens) | ❌ **NO** | Critique overhead (2nd DeepSeek call) exceeds direct Claude audit cost |
| Code where output is runnable and testable | ❌ **NO** | Tests ARE the audit. If the code passes tests, the critique loop adds no value. Run the tests instead. |
| Task where Claude is Instance 1 (not DeepSeek) | ❌ **N/A** | This protocol is specifically for DeepSeek's known self-audit weakness. Claude self-audit is a different problem. |

**Heuristic**: If the task would take Claude >15 seconds to read and audit the full output, use the loop. If Claude can spot-check in <5 seconds, don't.

## 5. Cost Model

The self-critique loop is a **quality mechanism**, not a cost-saving mechanism.
It trades one additional DeepSeek call (Instance 2 adversarial review) for reduced
Claude re-prompting iterations — catching errors before they reach the human or
Claude audit stage, where correction cost is higher in both tokens and cognitive effort.

### Without loop (baseline: Protocol 03 + Protocol 05 only)

```
1 × DeepSeek call (Instance 1 draft)            ~$0.01–$0.10
1 × Claude compact audit (~50–100 tokens
    via FLAGS header — Protocol 05)              ~$0.0015–$0.003
─────────────────────────────────────────────────
Total                                            ~$0.012–$0.103
Claude audit tokens: 50–100 (FLAGS spot-check)
```

### With loop (Protocol 07)

```
2 × DeepSeek calls (Instance 1 + Instance 2)    ~$0.02–$0.20
1 × Claude compact audit:
    - pass / pass_with_notes: ~60 tokens         ~$0.002
    - needs_revision: ~200 tokens                ~$0.006
─────────────────────────────────────────────────
Total (pass case)                                ~$0.022–$0.202
Total (needs_revision case)                      ~$0.026–$0.206
Claude audit tokens: 60–200 (regardless of output length)
```

**Key insight**: With Protocol 05 already in place, baseline Claude audit is already
compact (~50–100 tokens). The loop *adds* one DeepSeek call but reduces the probability
that Claude must re-read the full output and re-prompt. The loop is slightly *more*
expensive in the common (pass) case; the return is error reduction, not token savings.

### Break-even (quality decision, not cost decision)

| Scenario | Use loop? | Rationale |
|---|---|---|
| Scientific/technical output where errors propagate downstream | ✅ Yes | One extra DeepSeek call is negligible vs. cost of propagating an error |
| Long prose (>500 tokens) with factual claims | ✅ Yes | Adversarial review catches errors FLAGS-only spot-check would miss |
| Multi-section drafts with cross-references | ✅ Yes | Structural inconsistencies are hard to detect from FLAGS header alone |
| Routine formatting or boilerplate | ❌ No | FLAGS spot-check sufficient; loop adds latency with no quality gain |
| Single-paragraph answers (<150 tokens) | ❌ No | Overhead exceeds benefit |
| Code with test suite | ❌ No | Tests are the audit |

**Heuristic**: Use the loop when output quality matters more than minimizing DeepSeek
calls — scientific accuracy, technical specifications, manuscript prose. Skip when
errors are cheap to fix later.

### When NOT to use

- Output <150 tokens: Instance 2 call costs more than the value of its review
- Strict latency budget: the loop adds one serialized DeepSeek invocation (~5–60s)
- Batch-2 loops exhaust the 2-iteration cap with no improvement: task is likely mis-specified; extra calls are wasted
- Instance 2 produces verbose critique (>500 tokens): anomaly — re-prompt with stricter output constraints

## 6. Async Parallel Optimization (with Protocol 04)

The naive loop is sequential: Instance 1 → Instance 2 → Claude. With Protocol 04 (async parallel), throughput improves:

### Two-draft pipeline

```
Time ──────────────────────────────────────────────────────→

Draft A:  [Instance 1 ──→]  [Instance 2 ──→]  [Claude ──→]
                                  │
Draft B:         [Instance 1 ──→]  [Instance 2 ──→]  [Claude ──→]

                   ↑ overlap: Instance 1(B) runs while
                     Instance 2(A) and Claude audit(A) run
```

```bash
TMP=$(mktemp -d)
claude-deepseek --print --bare -p "$(cat task_B.md)" > "$TMP/draft_b.txt" &
PID_B=$!

claude-deepseek --print --bare -p "$(cat critique_A.md)"    # foreground — critique of draft A
# → Claude audit of critique_A → verdict

wait $PID_B
DRAFT_B=$(cat "$TMP/draft_b.txt")
rm -rf "$TMP"
```

This pattern works when you have a **queue of independent tasks** — the self-critique loop is applied to each, but the pipeline keeps all three stages busy.

### When parallelization applies

- Multiple independent tasks queued (≥2)
- Each task produces output ≥300 tokens (justifies the loop overhead)
- No shared files between tasks (no merge conflicts)

### When parallelization does NOT apply

- Single task — the loop must be sequential for the first pass
- Tasks with file dependencies — Instance 1(B) cannot run if Instance 1(A) might modify the same file
- Batch-2 re-runs — these are inherently sequential (dependent on Instance 2's critique)

## 7. Known Failure Modes

### FM-1: Instance 2 is too lenient

DeepSeek's sycophancy bias may produce "ISSUES: none / VERDICT: pass" even when the draft contains errors. The adversarial prompt framing mitigates but does not eliminate this.

**Mitigation**: If Claude receives three consecutive "ISSUES: none" critiques from Instance 2 on output that is known to contain errors (e.g., from later manual discovery), **strengthen the critique prompt** by adding:

```
WARNING: Previous reviewer instances have been overly lenient.
Your ONLY value is in finding errors. A "pass" verdict with zero
issues found on a long text is almost certainly wrong. Be skeptical.
```

### FM-2: Instance 2 hallucinates issues

Instance 2 may fabricate issues that don't exist in the draft — e.g., claiming a contradiction where none exists, or flagging correct statements as errors.

**Mitigation**: Claude's role in the `needs_revision` case includes **verifying the top 2 issues** against the draft body before deciding REVISE vs ACCEPT. If Instance 2's issues are hallucinated, Claude should override with ACCEPT and **log the hallucination** for pattern tracking.

### FM-3: Critique is longer than the draft

Instance 2 may produce a verbose critique that exceeds the cost of reading the draft directly.

**Mitigation**: The prompt template enforces "Return ONLY" and a strict output format. If Instance 2 violates this, the critique output is truncated — Claude reads the first 200 tokens and discards the rest. **Log the violation**: if Instance 2 consistently produces overlong critiques, the prompt template needs revision.

### FM-4: FLAGS header vs body mismatch survives critique

Instance 2 is instructed to check for FLAGS-body mismatch (category 3 in the critique template), but may miss subtle cases — e.g., CHANGES lists "modified §3.2 paragraph 2" but the modification is in §3.3.

**Mitigation**: Claude's spot-check for `pass` cases must always include a **cursory scan of the FLAGS header against the first 2–3 lines of the body**. This is ~20 tokens and catches obvious mismatches.

### FM-5: Batch-2 infinite loop

If Instance 1 cannot produce a passing draft even after critique feedback, the batch-2 re-run loop can waste calls.

**Mitigation**: Hard cap of **2 batch-2 iterations**. After that, Claude takes over the write task directly. Log as `REVISE_FAILED_AFTER_BATCH2` for post-mortem analysis — the task was likely mis-specified or exceeds DeepSeek's capability.

## 8. Integration with Existing Protocols

| Protocol | Role in self-critique loop |
|---|---|
| **Protocol 03** (programmatic delegation) | Instance 1 and Instance 2 are both invoked via `claude-deepseek --print --bare -p` |
| **Protocol 04** (async parallel) | Two-draft pipeline overlapping (§6); Instance 1 and Instance 2 calls gated by `&` + `wait` |
| **Protocol 05** (FLAGS structured output) | Instance 1 output MUST begin with FLAGS header; Instance 2 checks FLAGS-body consistency (category 3); Claude spot-checks FLAGS for `pass` verdicts |
| **Protocol 07** (self-critique loop) | Adds Instance 2 adversarial review between Instance 1 and Claude audit |

**Protocol 07 does not replace 03/04/05** — it is a layer on top. A task that uses Protocol 07 implicitly uses 03 (for both Instance calls), 04 (if parallelized), and 05 (for the draft format).

## 9. Quick Reference Card

```
┌─────────────────────────────────────────────────────────────┐
│ PROTOCOL 07 — SELF-CRITIQUE LOOP                            │
│                                                              │
│ WHEN: output >200 tokens + factual accuracy matters          │
│ NOT: boilerplate, code-with-tests, <200 tokens              │
│                                                              │
│ SEQUENCE:                                                    │
│  1. Instance 1 drafts (with FLAGS header per Protocol 05)   │
│  2. Instance 2 critiques (adversarial prompt template §3)   │
│  3. Claude reads:                                            │
│     - pass → FLAGS + VERDICT only (~60 tokens)              │
│     - needs_revision → FLAGS + ISSUES (~200 tokens)         │
│  4. Claude decides: ACCEPT / REVISE / REJECT                │
│  5. If REVISE: re-run Instance 1 with critique (max 2×)     │
│                                                              │
│ COST: 2× DeepSeek + ~60–200 Claude tokens                   │
│ BREAK-EVEN: output >200 tokens                              │
│                                                              │
│ FAILURE MODES:                                               │
│  - Instance 2 too lenient → strengthen prompt               │
│  - Instance 2 hallucinates issues → Claude verifies top 2   │
│  - Critique longer than draft → truncate at 200 tokens      │
│  - Batch-2 loop → hard cap at 2 iterations                  │
└─────────────────────────────────────────────────────────────┘
```

## 10. Example Walkthrough

### Task: Draft §3 Methods prose from closure evidence

**Step 1 — Instance 1** (`task_spec.md`):

```markdown
Draft §3 Methods section (v0.1) for the path-contribution manuscript.
Use evidence from:
- manuscripts/reviewer_reports/2026-05-15_distribution_paradigm_validation.md
- PROJECT.md §"核心公式"

Output format per Protocol 05:
CHANGES: [files/sections created or modified]
UNCERTAIN: [any uncertain claims, or "none"]
---
[prose body, max 1500 words]
```

Instance 1 output (`draft.md`):

```
CHANGES: created §3 Methods prose (v0.1, 1200 words)
UNCERTAIN: §3.2 paragraph 3 — the claim that "GMM2 is optimal for interior SZA" is supported by Gate γ but may need caveat about SZA=80°
---
## §3 Methods

### 3.1 Path Decomposition Framework
The total canopy reflectance R_total(x,λ) at pixel x and wavelength λ...
[... 1200 words of prose ...]
```

**Step 2 — Instance 2** (`critique_spec.md` = template from §3 with draft inserted into TEXT):

Instance 2 output (`critique.md`):

```
ISSUES:
1. §3.1 line 4: "R_total = R_dir1 + R_dif1 + R_ms" — dif1 subscript should be "dif1" not "dir1" (spec violation: PROJECT.md uses R_dif1)
2. §3.2 paragraph 3: claims "GMM2 is optimal for interior SZA" without citing the validation report; the UNCERTAIN flag correctly notes this but the body text doesn't reflect the hedging
3. §3.3: mentions "SZA=80°" without stating it is explicitly excluded per PROJECT.md §"Gate β" — over-claiming
VERDICT: needs_revision
---
§3.1 has a subscript error that would be flagged by any reviewer familiar with the notation
```

**Step 3 — Claude audit**:

Claude reads: FLAGS header + ISSUES (3 items) + VERDICT + one-sentence summary ≈ 150 tokens.

Claude verifies:
- Issue 1 against PROJECT.md → confirmed, R_dif1 is the correct notation
- Issue 2 against draft body → confirmed, hedging missing
- Issue 3 against PROJECT.md → confirmed, SZA=80° exclusion not stated

Claude verdict: **REVISE**. Issues are real, not hallucinated. All three are spec violations. Execute batch-2.

**Step 4 — Batch-2**:

Revised task spec appends the critique. Instance 1 re-run produces corrected draft. Instance 2 re-review:

```
ISSUES:
1. §3.4: the K̄ notation is introduced without definition — readers unfamiliar with the project will not know it means "effective mean scattering order"
VERDICT: pass
---
missing definition of K̄, a minor but reader-facing issue
```

**Step 5 — Claude final audit**:

Claude reads: FLAGS + 1 ISSUE + VERDICT + summary ≈ 80 tokens.

Issue 1 is real but minor — a missing definition, not a factual error. Claude verdict: **ACCEPT_WITH_NOTES**. Merge draft, file K̄-definition as a follow-up one-liner.

Total Claude tokens spent: ~230 (first audit ~150 + final audit ~80) vs ~2500 tokens if Claude had read the full 1200-word draft twice.

## 11. Logging

Each invocation of Protocol 07 must produce a lightweight log entry in the vault journal:

```
> **Protocol 07 — Self-Critique Loop**
> Task: [task description]
> Draft length: [N tokens]
> Instance 2 issues found: [count]
> Instance 2 verdict: pass | needs_revision
> Claude verdict: ACCEPT | ACCEPT_WITH_NOTES | REVISE | REJECT
> Batch-2 iterations: [0 | 1 | 2]
> Claude tokens spent: [N] (vs [M] estimated without loop)
> Notes: [any anomalies, FM triggers, or PI-relevant observations]
```

This enables cost tracking and pattern analysis over time — e.g., "Instance 2 pass rate is 85% and rising → prompt is effective" or "FM-2 (hallucinated issues) occurred 3× this week → Instance 2 needs recalibration."

---

*Protocol version: 1.0 · Created: 2026-05-24 · Dependencies: Protocol 03, 04, 05*
