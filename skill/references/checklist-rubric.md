# Reference — Convergence Checklist (C-01 .. C-07)

> Load this file when updating `checklist-status.md` or deciding whether
> to propose convergence (F-23, F-24). Source: `requirements.md §8`.

Maintain `.local/pensees/{date}-{slug}/checklist-status.md` with exactly 7
rows. After every agent turn, update each row's status (`✅` / `⚠️` /
`❌`) plus a one-sentence evidence pointer (`turn #N: ...`). Do not
propose convergence (F-24) unless all 7 rows are `✅`.

## C-01 — Key terms have explicit definitions

- **Evidence sample (✅)**: `ontology.yaml` lists every recognized slot
  with a non-empty `definition:` field of ≥ 5 chars.
- **If ❌ or ⚠️**: trigger F-13 fuzzy-term sharpening on the slot whose
  definition is missing or shortest. Do not advance to C-02.

## C-02 — Scope boundary explicit (what we will NOT do)

- **Evidence sample (✅)**: the running draft of `requirements.md` has
  ≥ 5 anti-requirement rows in §5.
- **If ❌ or ⚠️**: ask `To prevent scope blow-up, what would we
  explicitly NOT do?` Aim for ≥ 5 items.

## C-03 — Acceptance criteria are independently verifiable

- **Evidence sample (✅)**: draft of `acceptance-criteria.md` contains
  zero matches of the subjective-word regex (see §9 below).
- **If ❌ or ⚠️**: scan the draft; for every match, ask `How would we
  measure "{match}"? Who judges?` and rewrite to a concrete criterion.

## C-04 — At least 2–3 alternatives considered, with explicit trade-offs

- **Evidence sample (✅)**: at least one demo emit group exists in
  `demos/` (≥ 2 variant files) AND transcript contains the user's
  preference statement.
- **If ❌ or ⚠️**: trigger a demo emit (use F-18 condition (d) — slot
  has ≥ 2 interpretations).

## C-05 — Who, how, and what-not-for are explicit

- **Evidence sample (✅)**: draft `requirements.md` §1 has ≥ 1 sentence
  each for: target user, typical usage, and explicitly-out-of-scope
  audience.
- **If ❌ or ⚠️**: ask each missing one as a binary confirm.

## C-06 — ≥ 1 HTML demo seen by user with specific feedback

- **Evidence sample (✅)**: transcript contains a user message comparing
  variants (e.g. `prefer A because ...`, `B's X should change to Y`),
  not a generic `looks good`.
- **If ❌ or ⚠️**: ask `Comparing A and B, on the {axis} dimension,
  which is closer?` — pin the axis explicitly.

## C-07 — Known risks / assumptions listed

- **Evidence sample (✅)**: draft `requirements.md` has a section that
  contains the keywords `risk` / `assumption` / `dependency` (or zh
  equivalents `风险` / `假设` / `依赖`) with ≥ 2 items.
- **If ❌ or ⚠️**: ask `If assumption {X} turns out to be false, where
  does the plan first break?`

## Propose timing (F-24)

When all 7 rows hit `✅`, your next agent turn proposes:

> 7 rows of the convergence checklist look ✅ (see `checklist-status.md`).
> Should I draft the final `requirements.md` + `acceptance-criteria.md`
> now? Reply `可以` / `go` / `yes` to proceed, or `还没` to keep going.

If the user vetoes (`还没` / `not yet` / `再想想 X`), stay silent on
convergence for the next 3 agent turns (F-25). Keep dialoguing on whatever
the user surfaced.

## Subjective-word regex (used for C-03 self-check)

Forbidden in `acceptance-criteria.md` unless inside an AP-09 citation
block:

```
should be good | 更好 | 合理 | 优雅 | 挺好 | nice to have | feels right
```

Each match in the draft must be rewritten to a concrete observable, or
moved into an AP-09 anti-example with `AP-09` label.

## checklist-status.md skeleton

```markdown
# Convergence Status — {slug}

| # | Item | Status | Evidence |
|---|---|:-:|---|
| C-01 | Key terms defined | ❌ |  |
| C-02 | Scope boundary | ❌ |  |
| C-03 | Independently verifiable AC | ❌ |  |
| C-04 | Alternatives + trade-off | ❌ |  |
| C-05 | Who / how / not-for | ❌ |  |
| C-06 | Demo + specific feedback | ❌ |  |
| C-07 | Risks / assumptions | ❌ |  |
```
