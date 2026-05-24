
# Protocol 08 — Stateless Chunk-Directive Protocol (SCDP)

> **Status**: v0.1 — design spec, not yet implemented
> **Scope**: multi-round token-efficient file handoff from Claude (orchestrator) to DeepSeek (`--bare` mode, no file access)
> **Depends on**: Protocol 01 (Claude-DeepSeek Collaborative Architecture, `docs/Claude-DeepSeek Collaborative Architecture.md`)
> **File convention**: English per AGENTS.md (AI-facing instruction text; LLMs follow English more reliably)

---

## Problem

When Claude delegates a coding/research task to DeepSeek via `claude-deepseek --print --bare -p "..."`, DeepSeek has **no file access** — all context must be inline in the prompt. Two existing strategies both fail past moderate scale:

| Strategy | Token cost | Info fidelity | Fragile at |
|---|---|---|---|
| **Inline-embed** (paste entire files into prompt) | Linear in file size | Perfect | ~10K tokens total; files × size blow past context window |
| **Pre-summarize** (Claude summarizes each file into prose) | Low | Medium–low | Irreversible info loss on summarization; no recovery path |

The core tension: DeepSeek doesn't know *which parts* of each file it needs until it starts reasoning — but shipping everything upfront is wasteful and unsafe; shipping only summaries is lossy and unverifiable.

---

## The SCDP Mechanism

**Idea**: Claude pre-processes files into a lightweight **capsule** (chunk index + one-line summaries). DeepSeek receives only the capsule. When DeepSeek needs to read a specific chunk, it emits a structured **expansion directive** in its output. A mediator (Claude, via Bash) intercepts the directive, fetches the chunk from the local filesystem, and re-invokes DeepSeek with the capsule + resolved chunks + prior reasoning trace — all in a fresh, stateless call.

This is **lazy loading for LLM context**: pay tokens only for what the model actually reads, not for what it *might* read.

```
Round 1: Claude → [capsule + task] → DeepSeek → response + <<EXPAND ...>>
Round 2: Claude → [capsule + resolved chunks + R1 trace] → DeepSeek → response + <<EXPAND ...>>
Round 3: Claude → [capsule + resolved chunks + R1+R2 trace] → DeepSeek → final response (no directives)
```

Each round is a **fresh `claude-deepseek --print --bare` invocation** — no session state, no accumulated context drift, fully reproducible.

---

## Capsule Format Spec

A capsule is a YAML-structured block embedded in the prompt. It contains an entry per chunk.

### Per-Chunk Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `chunk_id` | string | ✅ | Unique identifier: `{file-stem}-{zero-padded-N}` (e.g., `gate_alpha-003`) |
| `file_path` | string | ✅ | Relative path to source file from repo root |
| `chunk_index` | int | ✅ | Zero-based ordinal within the file |
| `line_range` | `[start, end]` | ✅ | 1-based inclusive line range in the source file |
| `byte_range` | `[start, end]` | ✅ | 0-based inclusive byte offset range |
| `token_est` | int | ✅ | Estimated token count of this chunk (claude-style tokenizer, ~0.75 × word count as floor) |
| `summary` | string | ✅ | One-line semantic description (≤ 80 chars); answers "what would I miss if I skipped this chunk?" |
| `content_hash` | string | ✅ | SHA256 of chunk content (used by mediator to detect stale capsules) |

### Capsule Block Syntax

```yaml
--- CAPSULE v1 ---
chunks:
  - chunk_id:    gate_alpha-000
    file_path:   notebook/1_spectral_invariants_validation.ipynb
    chunk_index: 0
    line_range:  [1, 45]
    byte_range:  [0, 1847]
    token_est:   420
    summary:     "Notebook metadata, kernel spec, import block — setup boilerplate"
    content_hash: a3f1b9...
  - chunk_id:    gate_alpha-001
    file_path:   notebook/1_spectral_invariants_validation.ipynb
    chunk_index: 1
    line_range:  [46, 180]
    byte_range:  [1848, 9123]
    token_est:   1280
    summary:     "SVD validation logic: constructs Γ matrix, computes σ₂/σ₁, asserts η₁≥0.99"
    content_hash: d92c7e...
  - chunk_id:    gate_beta-000
    file_path:   scripts/gate_beta_pixel_joint_mle_oracle_compare.py
    chunk_index: 0
    line_range:  [1, 60]
    byte_range:  [0, 2341]
    token_est:   510
    summary:     "Imports, argparse, MLE utility functions; no experiment logic"
    content_hash: b71a2f...
  - chunk_id:    gate_beta-001
    file_path:   scripts/gate_beta_pixel_joint_mle_oracle_compare.py
    chunk_index: 1
    line_range:  [61, 210]
    byte_range:  [2342, 8745]
    token_est:   1650
    summary:     "Core MLE loop: per-pixel φ-parameter estimation, convergence checks, oracle comparison"
    content_hash: 4e8f13...
--- END CAPSULE ---
```

### Capsule Generation Rules

1. **Chunk boundaries**: split on semantic units — function definitions, paragraph breaks, section headers, cell boundaries (for `.ipynb`). Never split mid-function, mid-paragraph, or mid-expression.
2. **Chunk sizing**: target 400–1800 tokens per chunk. Soft cap at 2000 tokens (if a single semantic unit exceeds this, note `⚠️ oversized` in summary).
3. **Hash freshness**: capsule is **invalidated** if `content_hash` doesn't match the current file content — the mediator must regenerate before use.
4. **File exclusion**: skip binary files, images, `*.npy`, `*.pkl`. Skip `.gitignore`-d files. Skip files > 5000 lines unless explicitly requested by the task.
5. **Token estimation**: use `wc -w` × 0.75 as floor estimate; for code-heavy files, use `wc -c` / 4 as rough ASCII-based estimate.

---

## Directive Syntax Spec

DeepSeek emits expansion directives inline within its response text. The mediator parses them, strips them from the visible output, and acts on them.

### Format

```
<<EXPAND chunk_id tokens=N>>
```

| Component | Description |
|---|---|
| `<<EXPAND` | Fixed delimiter; case-sensitive; no whitespace after `<<` |
| `chunk_id` | Must match a `chunk_id` present in the active capsule |
| `tokens=N` | Optional. DeepSeek's estimate of how many tokens it will *actually consume* from this chunk. Used by the mediator to decide whether expansion is safe or the chunk itself needs sub-capsuling |
| `>>` | Fixed closing delimiter |

### Validity Rules

- **One directive per line** (no multiple `<<EXPAND ...>>` on the same line)
- **chunk_id must exist** in the capsule; unmatched chunk_ids → mediator responds with error, does not expand
- **Maximum 8 directives per round** (prevents runaway expansion; if DeepSeek requests > 8, mediator caps and warns)
- **Duplicate chunk_id ignored** (same chunk already resolved in a prior round → skip)
- **N must be > 0** if provided; `tokens=0` is treated as "I don't know" and mediator uses `token_est` from capsule

### Example DeepSeek Response with Directives

```
I need to examine the SVD validation logic more closely to assess whether 
the σ₂/σ₁ threshold is appropriate for Gate α re-verification.

<<EXPAND gate_alpha-001 tokens=800>>

I also need to check the MLE convergence criteria in the Gate β script 
to understand the φ-parameter boundary conditions.

<<EXPAND gate_beta-001 tokens=600>>
```

### Directive-Failure Modes

| Symptom | Mediator Response |
|---|---|
| Directive refers to non-existent chunk_id | Return error message in next round; do not expand any chunk |
| Directive lacks `>>` closer | Treat remainder of line as unclosed → strip, log warning, continue parsing other directives |
| > 8 directives in one response | Expand first 8; insert warning line: `<<MEDIATOR: capped at 8 expansions; remaining directives dropped>>` |
| DeepSeek responds with no directives | Response is final; mediator outputs verbatim |

---

## Mediator Pseudocode

The mediator is Claude itself, orchestrating via Bash. Below is the pseudocode for the core loop.

```bash
#!/usr/bin/env bash
# scdp_mediate.sh — Stateless Chunk-Directive Protocol mediator
# Usage: scdp_mediate.sh <capsule_file> <task_prompt_file> [max_rounds=3]

set -euo pipefail

CAPSULE_FILE="${1:?}"
TASK_FILE="${2:?}"
MAX_ROUNDS="${3:-3}"
DEEPSEEK="claude-deepseek --print --bare"
RESOLVED_DIR=$(mktemp -d /tmp/scdp_resolved.XXXXXX)
TRACE_FILE=$(mktemp /tmp/scdp_trace.XXXXXX)
ROUND=0

# --- helpers ---
resolve_chunks() {
    # Parse <<EXPAND ...>> directives from DeepSeek response $1
    # For each unique, valid chunk_id:
    #   1. Look up line_range from CAPSULE
    #   2. sed -n "${start},${end}p" "$file_path" > $RESOLVED_DIR/${chunk_id}.txt
    #   3. Print "RESOLVED: chunk_id (N tokens)" to stderr
    local response_file="$1"
    local chunk_ids=($(grep -oP '<<EXPAND \K[^ >]+' "$response_file" | sort -u))
    
    if [ ${#chunk_ids[@]} -eq 0 ]; then
        return 0  # no directives → final round
    fi
    
    if [ ${#chunk_ids[@]} -gt 8 ]; then
        echo "WARNING: ${#chunk_ids[@]} directives requested, capping at 8" >&2
        chunk_ids=("${chunk_ids[@]:0:8}")
    fi
    
    for cid in "${chunk_ids[@]}"; do
        local line_range=$(yq -r ".chunks[] | select(.chunk_id == \"$cid\") | .line_range | @tsv" "$CAPSULE_FILE")
        if [ -z "$line_range" ]; then
            echo "ERROR: chunk_id '$cid' not found in capsule" >&2
            continue
        fi
        local start=$(echo "$line_range" | cut -f1)
        local end=$(echo "$line_range" | cut -f2)
        local file_path=$(yq -r ".chunks[] | select(.chunk_id == \"$cid\") | .file_path" "$CAPSULE_FILE")
        sed -n "${start},${end}p" "$file_path" > "$RESOLVED_DIR/${cid}.txt"
        echo "RESOLVED: $cid → $file_path L${start}-${end}" >&2
    done
}

build_prompt() {
    # Construct the round-N prompt:
    #   [TASK] + [CAPSULE] + [RESOLVED CHUNKS block] + [PRIOR TRACE]
    local task=$(cat "$TASK_FILE")
    local capsule=$(cat "$CAPSULE_FILE")
    local resolved_block=""
    
    # --- RESOLVED CHUNKS ---
    for f in "$RESOLVED_DIR"/*.txt; do
        [ -f "$f" ] || continue
        local cid=$(basename "$f" .txt)
        resolved_block+="\n--- RESOLVED: $cid ---\n$(cat "$f")\n--- END $cid ---\n"
    done
    
    local trace=""
    if [ -s "$TRACE_FILE" ]; then
        trace="\n--- PRIOR REASONING TRACE ---\n$(cat "$TRACE_FILE")\n--- END TRACE ---"
    fi
    
    echo -e "${task}\n\n--- CAPSULE ---\n${capsule}\n--- END CAPSULE ---\n${resolved_block}${trace}"
}

# --- main loop ---
while [ $ROUND -lt $MAX_ROUNDS ]; do
    ROUND=$((ROUND + 1))
    echo "=== SCDP Round $ROUND/$MAX_ROUNDS ===" >&2
    
    PROMPT=$(build_prompt)
    
    # Invoke DeepSeek (fresh call, no prior session)
    RESPONSE_FILE=$(mktemp /tmp/scdp_response.XXXXXX)
    echo "$PROMPT" | $DEEPSEEK -p - > "$RESPONSE_FILE" 2>/tmp/scdp_stderr.log
    
    # Strip <<EXPAND ...>> lines from visible output and append to trace
    grep -v '<<EXPAND ' "$RESPONSE_FILE" >> "$TRACE_FILE"
    echo "" >> "$TRACE_FILE"
    
    # Check for directives
    if ! grep -q '<<EXPAND ' "$RESPONSE_FILE"; then
        # No directives → final output
        cat "$TRACE_FILE"
        echo "SCDP: converged at round $ROUND" >&2
        rm -rf "$RESOLVED_DIR" "$TRACE_FILE" "$RESPONSE_FILE"
        exit 0
    fi
    
    # Resolve chunks for next round
    resolve_chunks "$RESPONSE_FILE"
    rm -f "$RESPONSE_FILE"
done

# Exceeded max rounds → output partial trace + warning
echo "SCDP: max rounds ($MAX_ROUNDS) reached; output may be incomplete. Consider fallback to inline-embed." >&2
cat "$TRACE_FILE"
rm -rf "$RESOLVED_DIR" "$TRACE_FILE"
exit 1
```

### System Prompt Appendix (injected into every DeepSeek call)

```text
You are operating under the Stateless Chunk-Directive Protocol (SCDP v1).

You have been given a CAPSULE — an index of available file chunks with one-line
summaries. You do NOT have the full file contents.

When you need to read a specific chunk to reason accurately:
- Emit exactly: <<EXPAND chunk_id tokens=N>>
- One directive per line. No more than 8 directives per response.
- chunk_id must match an entry in the CAPSULE. Do not invent chunk_ids.

When your reasoning is complete and you need no more chunks:
- Produce your final answer. Do not emit any <<EXPAND directives.

Do not guess file content from summaries alone if the answer depends on exact
code/derivation/values. When in doubt, EXPAND.

Do not write <<EXPAND in any context other than requesting a chunk expansion.
Do not simulate chunk content — you will receive it in the next round.
```

---

## Decision Matrix: When to Use SCDP

### Quantitative Thresholds

| Condition | Recommended Strategy |
|---|---|
| 1 file, ≤ 3K tokens total | **Inline-embed** — simpler, zero overhead, no round-trip latency |
| 1–3 files, 3K–10K tokens total | **Inline-embed** — still safe in bare mode; SCDP overhead not justified |
| 4–7 files, OR 10K–25K tokens total | **SCDP** — capsule keeps initial prompt compact; selective expansion saves tokens |
| 8+ files, OR > 25K tokens total | **SCDP** — inline-embed risks context truncation; pre-summarize loses critical detail |
| Task requires *scanning* entire files (e.g., find all occurrences of X) | **Inline-embed** (if fits) or **grep pre-filter** → SCDP on filtered results |
| Task is simple mechanical (formatting, translation, table-reorg) | **Pre-summarize** — full detail not needed; SCDP is overkill |

### Conceptual Decision Flow

```
Can the whole corpus fit safely in one prompt (≤ 10K tokens)?
├── YES → inline-embed
└── NO  → Does the task require per-chunk exact reasoning
          or is it bulk mechanical?
          ├── Exact reasoning needed → SCDP
          └── Bulk mechanical → pre-summarize (loss acceptable)
```

---

## Comparison: Inline-Embed vs Pre-Summarize vs SCDP

| Dimension | Inline-Embed | Pre-Summarize | SCDP |
|---|---|---|---|
| **Token cost (initial)** | High (all files) | Low (summaries only) | Low (capsule only, ~50 tokens/chunk) |
| **Token cost (total)** | Fixed; paid upfront | Fixed; paid upfront | Variable; pay-as-you-go per expanded chunk |
| **Info fidelity** | Perfect (verbatim) | Medium–low (lossy summarization) | Perfect for expanded chunks; one-line summaries for skipped chunks |
| **Round trips** | 1 | 1 | 2–4 (typical); hard cap at 3 |
| **Latency** | ~5–30s (single call) | ~5–30s (single call) | ~15–120s (multiple calls) |
| **Context window risk** | High above 10K tokens | Low | Low (capsule is tiny; expanded chunks are bounded) |
| **Recovery from wrong summarization** | N/A | Impossible (summary is the only source) | Directives can request any chunk; no info is permanently lost |
| **DeepSeek can verify capsule accuracy** | N/A (no capsule) | No | Yes — by requesting the chunk and comparing to its summary |
| **Best for** | Small codebases; single-file tasks | Bulk mechanical ops (formatting, translation) | Large multi-file analysis; selective deep-reading |
| **Worst for** | Large repos; token-budget-sensitive tasks | Tasks requiring exact code/values/derivations | Single-file simple tasks; latency-sensitive workflows |
| **Capsule maintenance cost** | Zero | Zero | Non-zero (must regenerate when files change; hash check is O(n) per chunk) |

---

## Failure Modes and Mitigations

### FM1: Chunk Boundary Splits Semantic Atom

**What**: A chunk cut falls mid-function, mid-derivation, or mid-paragraph. DeepSeek reads the chunk and encounters a broken context — missing the opening definition or the closing return.

**Detection**: DeepSeek emits `<<EXPAND {adjacent_chunk}>>` immediately after receiving a resolved chunk (adjacent-chunk cascade).

**Mitigation**:
- **Semantic-aware chunking**: always split on function/class/method boundaries, section headers (`## `, `### `), paragraph breaks (`\n\n`), or notebook cell boundaries. Never split mid-token-stream.
- **Adjacency hint in capsule**: the capsule entry includes `line_range`; the mediator can pre-expand adjacent chunks when the requested chunk's range is < 10 lines from a boundary.

**Fallback**: if DeepSeek requests 3+ adjacent chunks from the same file in one round, the mediator promotes to inline-embed the entire file on the next round.

---

### FM2: Task Requires Full-File Scan (All Chunks Requested)

**What**: The task inherently needs every chunk (e.g., "audit all imports across the codebase", "find every place variable X is mutated"). DeepSeek requests 80%+ of chunks across rounds.

**Detection**: After round 2, mediator tracks cumulative chunk-coverage. If `resolved_chunks / total_chunks > 0.8`, the SCDP overhead exceeds inline-embed cost.

**Mitigation**: Mediator aborts SCDP, re-runs with full inline-embed of all files. Wastes 1–2 DeepSeek calls but avoids paying per-round latency × N rounds.

**Decision rule**: If `coverage > 0.8 AND round ≤ 2`, fall back to inline-embed; warn: "SCDP aborted — task is full-scan; switching to inline-embed."

---

### FM3: > 3 Expand Rounds (Runaway Iteration)

**What**: DeepSeek requests chunks incrementally (one per round, or small batches), extending beyond the hard cap.

**Detection**: Round counter exceeds `MAX_ROUNDS` (default 3).

**Mitigation**:
- **Hard cap at 3 rounds**. At round 4, mediator stops and outputs partial trace + warning.
- **Encourage batching**: system prompt instructs DeepSeek to request all needed chunks in round 1, not drip-feed.
- **After cap**: mediator offers the user two options: (a) manually expand remaining chunks and re-run, (b) fall back to inline-embed.

**Why 3 rounds**: Empirically, well-constructed capsules elicit 60–80% of needed expansions in round 1. Two additional rounds cover edge cases. Beyond 3, the task is likely misclassified (should have been inline-embed) or the capsule is poorly structured.

---

### FM4: DeepSeek Ignores Directive Syntax

**What**: DeepSeek produces reasoning without emitting `<<EXPAND ...>>`, but the output is vague, wrong, or hallucinated because it relied on capsule summaries alone.

**Detection**: No `<<EXPAND` directives in any round; output quality is low (hedging language, nonspecific claims, "based on the summary...").

**Mitigation**:
- System prompt uses strong framing: "Do not guess file content from summaries alone if the answer depends on exact code/derivation/values. When in doubt, EXPAND."
- Mediator checks: if round 1 response has zero directives AND contains phrases like "likely", "probably", "appears to", "based on the summary", flag as low-confidence and add a prompt suffix in round 2: "Your previous response relied on capsule summaries without expanding any chunks. If your answer depends on exact content, request the relevant chunks now."

---

### FM5: Token Estimate in Directive Is Wrong

**What**: DeepSeek's `tokens=N` in `<<EXPAND gate_alpha-001 tokens=300>>` is a severe underestimate (chunk is actually 1800 tokens). This doesn't break expansion, but misleads human operators about cost.

**Impact**: Low — the mediator always uses the actual chunk content, not the estimate. The `tokens=N` field is advisory (for human monitoring and for future auto-budgeting).

**Mitigation**: Mediator logs `expected=N actual=M` for each expansion; if discrepancy exceeds 2×, the mediator notes it in the trace for human review.

---

### FM6: Stale Capsule (Files Changed Between Capsule Generation and Chunk Resolution)

**What**: Claude generates a capsule; a human or another process modifies a file; DeepSeek requests a chunk; the mediator fetches different content than what the capsule described.

**Detection**: Mediator computes SHA256 of fetched chunk content and compares to `content_hash` in capsule on every expansion. Mismatch → capsule is stale.

**Mitigation**: On hash mismatch, mediator regenerates the capsule entry for the affected file only (partial re-index), appends a `<<MEDIATOR: capsule entry for {chunk_id} was stale; content refreshed>>` note to the prompt, and continues.

---

### FM7: DeepSeek Hallucinates chunk_ids

**What**: DeepSeek emits `<<EXPAND nonexistent_chunk tokens=200>>` — a chunk_id not present in the capsule.

**Detection**: Mediator grep-validates each chunk_id against capsule before fetching.

**Mitigation**: Mediator strips the invalid directive, appends a correction notice to the next round: `<<MEDIATOR: chunk_id 'nonexistent_chunk' not found in capsule. Available IDs: [list of 5 closest matches by edit distance]>>`.

---

## Integration with Existing Workflow

### Ticket-Generation Integration

When Claude (as manager) generates a DeepSeek worker ticket per Protocol 01, it should:

1. **Decide strategy**: run the decision matrix (§5) against the ticket's file-scope.
2. **If SCDP**: generate capsule alongside the ticket; embed both in the DeepSeek invocation.
3. **If inline-embed**: proceed as today (paste files into ticket).
4. **If pre-summarize**: Claude summarizes each relevant file into the ticket body.

### Delivery Report Integration

When DeepSeek returns (with or without SCDP), Claude's review checklist (Protocol 01 §"Claude Review Prompt") adds one item:

> 8. **SCDP audit (if used)**: total rounds, chunks expanded vs capsule total, any stale-capsule detections, any directive syntax violations, token-cost estimate vs inline-embed baseline.

### Token Cost Tracking

SCDP's primary value is token economy. Every SCDP-mediated task should log:

```yaml
scdp_log:
  task_id: "ticket-2026-05-24-gate-beta-review"
  file_count: 5
  total_chunks: 23
  rounds: 2
  chunks_expanded: 7
  chunks_coverage: 0.304
  token_estimate:
    capsule: 1150        # 23 chunks × ~50 tokens
    expanded_chunks: 8400   # 7 chunks × ~1200 tokens avg
    trace_carry: 2100    # prior reasoning trace
    total: 11650
  baseline_inline: 28750   # all 5 files verbatim
  savings: "59%"
```

---

## Implementation Roadmap

| Phase | Deliverable | Effort |
|---|---|---|
| **P0 — Capsule Generator** | Python script: `scripts/gen_capsule.py <file...> → capsule.yaml`. Semantic chunking, token estimation, SHA256 hashing. | 2–3 hours |
| **P1 — Bash Mediator** | `scripts/scdp_mediate.sh` implementing the pseudocode loop above. | 2–3 hours |
| **P2 — Claude Integration** | Ticket-generation pipeline (Protocol 01) auto-selects strategy and calls mediator when SCDP-eligible. | 1–2 hours |
| **P3 — Logging & Audit** | Token-cost tracking, SCDP-log YAML output, integration with `WORKING.md` / vault journal. | 1 hour |
| **P4 — Sub-Capsuling** | If a single chunk is > 2000 tokens, the mediator can auto-sub-capsule it (recursive SCDP within a chunk). | Deferred to v0.2 |

---

## Appendix A: Capsule Generator Python Signature

```python
# scripts/gen_capsule.py (stub)

def generate_capsule(
    file_paths: list[str],
    max_chunk_tokens: int = 1800,
    semantic_boundaries: bool = True
) -> dict:
    """
    Returns a capsule dict conforming to CAPSULE v1 spec.

    Semantic boundaries (default True):
      - .py: split on 'def ', 'class ', '# ====' section markers
      - .md: split on '## ', '### ', '\n\n'
      - .ipynb: split on cell boundaries (preserve cell type metadata)
      - fallback: split on '\n\n' (paragraph breaks)

    Each chunk gets:
      - chunk_id: {file_stem}-{zero_padded_index}
      - line_range: [start, end] (1-based inclusive)
      - byte_range: [start, end] (0-based inclusive)
      - token_est: estimated token count
      - summary: one-line semantic description
      - content_hash: SHA256 of chunk content
    """
    ...


def estimate_tokens(text: str) -> int:
    """
    Token estimation: max of:
      - wc -w × 0.75
      - wc -c / 4  (ASCII byte-based floor)
    Returns integer token count.
    """
    ...
```

## Appendix B: Minimum Viable Test

Before full integration, validate SCDP with a controlled test:

1. **Input**: 5 Python files totaling ~15K tokens (too large for safe inline-embed).
2. **Task**: "Identify all hardcoded threshold values (numeric constants in comparisons) across these files and assess whether each should be a named constant."
3. **Expected**: 2–3 rounds; 6–10 chunks expanded; coverage 30–50%; token savings ≥ 40%.
4. **Pass criteria**: DeepSeek correctly identifies all thresholds; no false positives; no missed thresholds traceable to un-expanded capsule summaries.
