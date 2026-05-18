# {SLUG} — Acceptance Criteria

> Independent judgment document. Designed to be read **without**
> `requirements.md`. If a criterion below references a concept, that
> concept must be expanded inline here, not by pointer to
> `requirements.md` (AP-12).

## 0. How to use this document

- **Who scores**: anyone able to judge whether software / tools / a
  proposal work as advertised. No code-reading required.
- **What to look at**: at least 5 sample outputs / sessions of the
  artifact. Specific sample requirements in §4 below.
- **Scoring summary**: pass all of §1 (binary hard gates); then score
  §2 (five 0–10 dimensions, median across samples). Pass line:
  per-dimension avg ≥ 7 AND no single dimension < 5.

## 1. Hard Gates (HG-XX) — any ❌ = overall fail

| # | Criterion | How to verify | ✅ / ❌ |
|---|---|---|---|
| HG-01 | {{TODO binary criterion}} | {{TODO concrete verification step}} | |
| HG-02 | {{TODO}} | {{TODO}} | |
| HG-03 | {{TODO}} | {{TODO}} | |

## 2. Scored dimensions (each 0–10)

### A. {{Dimension A — TODO name}}

**Criteria**:
- A.1 {{TODO}}
- A.2 {{TODO}}

**Anchors**:

| Score | What you observe (specific files / phrases / signals) |
|---|---|
| **0** | {{TODO concrete failure case}} |
| **5** | {{TODO concrete middling case}} |
| **10** | {{TODO concrete excellence case}} |

### B. {{Dimension B}}

Same structure as A. {{TODO}}.

### C. {{Dimension C}}

Same structure as A. {{TODO}}.

### D. {{Dimension D}}

Same structure as A. {{TODO}}.

### E. {{Dimension E}}

Same structure as A. {{TODO}}.

### Aggregation rule

- Per dimension: take the median over the sample set.
- **Pass**: 5-dim average ≥ 7 AND min(per-dim) ≥ 5.
- **Excellent**: 5-dim average ≥ 8.5 AND min(per-dim) ≥ 7 AND §3
  anti-pattern hits ≤ 2.

## 3. Anti-Patterns (AP-XX) — each hit = −1 in the relevant dimension

- **AP-01** {{TODO concrete failure pattern}}. Dimension: {{X}}. Example
  of the smell: {{TODO}}.
- **AP-02** {{TODO}}. Dimension: {{X}}. Example: {{TODO}}.
- **AP-09** (built-in) Subjective-word presence: any of `should be good`
  / `更好` / `合理` / `优雅` / `挺好` appears in this document or in
  `requirements.md` outside an AP citation. Dimension: D.

## 4. Sample requirements (what to look at)

- N = 5 samples (minimum); N = 8 for an Excellent rating.
- **Must collectively cover**: at least 1 sample from each category
  the artifact claims to serve. {{TODO list the categories explicitly
  here so a scorer can pick samples without reading the requirements
  doc}}.

## 5. Scoring procedure (recommended)

- ~ 20 min / sample + 30 min synthesis = ~ 2.5 hours total.
- 2 scorers independent; if any dimension differs by > 3 points,
  bring in a 3rd scorer for that dimension only; take the median.
- Scorers **must not** read `requirements.md` while scoring — that
  defeats the independence test.

## 6. Output template

```
samples: 5 (slugs)
scorer: {name}
HG result: HG-XX ✅ / ❌
5-dim scores (median): A=X B=X C=X D=X E=X
average: X.X
AP hits: APXX, APXX, ...
adjusted per-dim: A=X B=X C=X D=X E=X
verdict: pass / fail
≤ 300-word summary: one biggest strength + one biggest weakness.
```
