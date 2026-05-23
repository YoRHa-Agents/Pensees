# Reference — Composite Signals (v0.3.2 Lite Scorer)

> Load this file when authoring or reviewing the Lite scorer that
> turns each per-turn record (see `intermediate-result-schema.md`)
> into the two `composite_premature` and `composite_dead_end` floats
> it carries. This file owns HOW those numbers are computed; the
> schema doc owns WHERE they live on disk.

## When to Load

Read to compute, audit, or reproduce the two composite scores in
`turns.jsonl`; tune thresholds via `.local/pensees/.config.yaml`;
implement or review the in-skill guardrail (F-33..F-36, separate
wave); or build the offline reviewer's "Top contributing signals"
table. Lite-only — Standard / Heavy variants will add signals behind
a bumped `schema_version`.

## Signal definitions

Seven base signals — three for premature-detail, four for dead-end.
Each is a deterministic function of records `1..N` (`N` = the planned
current turn), returns a float in `[0, 1]`, and contributes `0` below
its explicit firing threshold. "Inputs" lines reference fields from
`intermediate-result-schema.md`, `ontology-schema.md`, and
`checklist-rubric.md`. Pseudocode is normative.

### slot_focus_imbalance

Group: premature-detail. Surfaces F-10 (drive questions from `open`
slots — one slot monopolizing turns while siblings remain `open` is
the anti-pattern). Inputs: `slots_touched` from every agent turn;
per-slot `status` from `ontology.yaml`.

```
agent_turns = [t for t in turns_1_to_N if t.agent_or_user == "agent"]
if len(agent_turns) < 3: return 0.0
focal       = argmax_slot(count_of_turns_touching(slot, agent_turns))
focal_count = count_of_turns_touching(focal, agent_turns)
other_open  = count_of_open_slots_in_ontology(exclude=focal)
if focal_count < 3 or other_open < 3: return 0.0
return min(1.0, focal_count / len(agent_turns))
```

Fires at `focal_count >= 3 AND other_open >= 3`; value is the ratio
of agent turns touching the most-touched slot.

### e_probe_over_use

Group: premature-detail. Surfaces F-31 (the `(e)` detail probe;
repeated probing of one still-open slot is the anti-pattern). Inputs:
`e_probe_target` from every agent turn; focal slot's `status` in
`ontology.yaml`.

```
agent_turns = [t for t in turns_1_to_N if t.agent_or_user == "agent"]
consec = max trailing run of agent_turns with same non-null
         e_probe_target whose slot is still status="open"
if consec < 2: return 0.0
return min(1.0, (consec - 1) / 2.0)
```

Fires at `consec >= 2`; linear ramp `consec=2 → 0.5`, `consec=3 →
1.0` (saturates). A single `(e)` is a normal probe.

### question_form_jump

Group: premature-detail. Surfaces F-17 (high-res forms
`decision-matrix` / `forced-choice` should land after enough
frame-setting) and F-10. Inputs: planned `question_form` of turn N
(a later guardrail rewrite does NOT retroactively change this
signal — see "Threshold semantics"); per-aspect filled-count from
`ontology.yaml`.

```
HIGH_RES = {"decision-matrix", "forced-choice"}
PEAK     = 0.95          # 5% headroom for legit drilling
if planned_form_of_turn_N not in HIGH_RES: return 0.0
filled_aspects = count(aspect for aspect in ontology
                       if any(slot.status == "filled" for slot in aspect))
if filled_aspects >= 3: return 0.0
return clip(PEAK * (3 - filled_aspects) / 3.0, 0.0, 1.0)
```

Fires when planned form ∈ `HIGH_RES` AND `filled_aspects < 3`;
linear ramp from `0.95` (no aspect filled) to `0` (3 aspects filled).

### amnesia

Group: dead-end. Surfaces F-10 (open slots must be revisited before
they go stale) and F-23 (convergence requires the ontology to
finish). Inputs: `slots_touched` from agent turns; per-slot
`turn_first`, `turn_last`, `status` from `ontology.yaml`.

```
recent3 = last 3 agent turns up to and including N (or fewer if N<3)
worst   = 0.0
for slot in ontology where slot.status == "open":
    span = slot.turn_last - slot.turn_first
    if span < 5: continue
    if any(slot.name in t.slots_touched for t in recent3): continue
    worst = max(worst, min(1.0, (span - 4) / 6.0))
return worst
```

Fires when at least one `open` slot has `turn_last - turn_first >=
5` AND was absent from `slots_touched` in each of the last three
agent turns; ramps `0.167` at `span=5` → `1.0` at `span >= 11`.

### dimension_repetition

Group: dead-end. Surfaces F-09 ("do not repeat the same ambiguity
dimension three turns in a row" anti-pattern). The signal makes the
anti-pattern observable as a metric; F-09 itself is enforced by the
agent's turn-time check. Inputs: `dimension` from every agent turn.

```
agent_turns = [t for t in turns_1_to_N if t.agent_or_user == "agent"]
consec = max trailing run of agent_turns where dimension is non-null
         AND identical to agent_turns[-1].dimension
if consec < 3: return 0.0
return 1.0
```

Fires at `consec >= 3`; binary `0` or `1`. One or two same-dimension
turns is intentional mid-drill.

### frame_collapse

Group: dead-end. Surfaces F-08 (two consecutive `(d) none of these`
selections signal the question frame is wrong). The schema has no
`escape_hatch_used` field, so the recorder infers a `(d)` pick: a
user turn with empty `slots_touched` immediately after an agent
multi-choice turn (planned form ∈ `HIGH_RES`). Inputs:
`slots_touched`, `agent_or_user`, `question_form` over the last four
turns.

```
HIGH_RES = {"decision-matrix", "forced-choice"}
d_picks  = []
for i, t in enumerate(turns_1_to_N):
    if t.agent_or_user != "user" or t.slots_touched != []: continue
    prev = turns_1_to_N[i-1] if i > 0 else None
    if prev and prev.agent_or_user == "agent" \
       and prev.question_form in HIGH_RES:
        d_picks.append(t.turn_id)
consec_d = max run of d_picks whose preceding agent multi-choice
           turns are themselves back-to-back multi-choice rounds
if consec_d < 2: return 0.0
return 1.0
```

Fires at `consec_d >= 2`; binary. One `(d)` is a normal escape.

### checklist_regression

Group: dead-end. Surfaces F-23, F-24 (the convergence checklist must
improve monotonically; regression is a smell). Inputs:
`checklist_state` from turns `N-2`, `N-1`, and `N` (planned for N).

```
REGRESSION_CAP = 8
ORDER = {"❌": 0, "⚠️": 1, "✅": 2}   # higher = better
count = 0
for (a_id, b_id) in [(N-2, N-1), (N-1, N)]:
    a = checklist_state_of(a_id)
    b = checklist_state_of(b_id)
    for row in ["C-01","C-02","C-03","C-04","C-05","C-06","C-07"]:
        if ORDER[b[row]] < ORDER[a[row]]: count += 1
return clip(count / REGRESSION_CAP, 0.0, 1.0)
```

Fires at `count >= 1`. The cap of `8` keeps the signal in `[0, 1]`
even when many rows regress in one transition (the clip catches the
rare overshoot).

## Composites

The two composites are weighted sums, explicitly clipped to `[0, 1]`:

```
composite_premature = clip(w1*slot_focus_imbalance
                         + w2*e_probe_over_use
                         + w3*question_form_jump, 0.0, 1.0)

composite_dead_end  = clip(u1*amnesia + u2*dimension_repetition
                         + u3*frame_collapse + u4*checklist_regression,
                         0.0, 1.0)
```

Clipping rule `min(1.0, max(0.0, raw_sum))` is mandatory; emitting
outside `[0, 1]` violates the schema contract in
`intermediate-result-schema.md` (both composites typed
`float in [0, 1]`).

## Defaults

```yaml
defaults:
  premature:
    threshold: 0.6
    weights:
      slot_focus_imbalance: 0.34
      e_probe_over_use: 0.33
      question_form_jump: 0.33
  dead_end:
    threshold: 0.6
    weights:
      amnesia: 0.25
      dimension_repetition: 0.25
      frame_collapse: 0.25
      checklist_regression: 0.25
```

**Invariant — per-composite weights sum to 1.0** (within `±0.01`
integer-rounding tolerance): premature `0.34+0.33+0.33 = 1.00`,
dead-end `0.25*4 = 1.00`. A scorer whose effective weights sum
outside `[0.99, 1.01]` MUST fail loudly per AGENTS.md "no silent
failures".

## Tuning hook

Per-session overrides live at `.local/pensees/.config.yaml`. The
file mirrors the `defaults` block under a top-level
`mid_result_analysis:` key (e.g.
`mid_result_analysis.premature.threshold`,
`mid_result_analysis.dead_end.weights.amnesia`):

```yaml
mid_result_analysis:
  premature:
    threshold: 0.55                  # any subset of keys is OK
    weights: {slot_focus_imbalance: 0.40, e_probe_over_use: 0.30,
              question_form_jump: 0.30}
  dead_end:
    threshold: 0.65                  # weights omitted -> defaults
```

Semantics:

- **Read once per session**, at session start (turn 1); mid-session
  edits are ignored so scoring stays deterministic for replay.
- **Partial overrides allowed.** Missing keys fall back to `defaults`.
- **Out-of-range values fail loudly.** The recorder MUST refuse to
  start a session if any of: `threshold` outside `[0.0, 1.0]`;
  post-merge per-composite weights summing outside `[0.99, 1.01]`;
  any negative weight; any unknown signal key under `weights:` (typo
  guard). Failure surfaces as a startup error log plus non-zero
  exit; per AGENTS.md §"No Silent Failures" the recorder MUST NOT
  silently fall back to defaults on a malformed override.

## Worked example

Replay of the schema-doc example record (`turn_id=5`, see
`intermediate-result-schema.md` §"Worked example"). Trajectory (all
three agent turns share `dimension="intent"`):

| Turn | Side | Key fields |
|---:|---|---|
| 1 | agent | `forced-choice` on `max-delay-seconds`; `slots_touched=["max-delay-seconds"]`; checklist `C-01=✅`, `C-05=✅`, rest `❌` |
| 2 | user | picks `(e) max-delay-seconds`; `slots_touched=["max-delay-seconds"]` |
| 3 | agent | F-31 detail probe + re-emit on `max-delay-seconds`; `e_probe_target="max-delay-seconds"`, checklist unchanged |
| 4 | user | picks `(e) max-delay-seconds` again |
| 5 | agent (planned) | F-31 detail probe bridging to `per-day-cap`; `e_probe_target="max-delay-seconds"`, planned `question_form="forced-choice"`, `slots_touched=["max-delay-seconds","per-day-cap"]`; planned checklist regresses `C-01: ✅→⚠️`, `C-05: ✅→⚠️` |

Ontology: 5 `open` slots across 5 aspects, 0 `filled` aspects.
Computed signals (planned-action view, pre-guardrail):

| Signal | Value | Derivation |
|---|---:|---|
| `slot_focus_imbalance` | `1.00` | `focal=max-delay-seconds`, `focal_count=3` of `agent_turns=3`; `other_open=4 ≥ 3`; `min(1, 3/3)=1.00` |
| `e_probe_over_use` | `0.50` | `consec=2` (turns 3 and 5 both target `max-delay-seconds`, still `open`); `min(1, (2-1)/2)=0.50` |
| `question_form_jump` | `0.95` | planned `forced-choice` ∈ `HIGH_RES`; `filled_aspects=0`; `0.95 * (3-0)/3 = 0.95` |
| `amnesia` | `0.00` | session is 5 turns old; no `open` slot has `span ≥ 5` |
| `dimension_repetition` | `1.00` | turns 1, 3, 5 all `dimension="intent"`; `consec=3 ≥ 3` |
| `frame_collapse` | `0.00` | user turns picked `(e)`, so `slots_touched` non-empty; `consec_d=0` |
| `checklist_regression` | `0.25` | `0` regressions turn 3→4, `2` turn 4→5 (`C-01`, `C-05` both `✅→⚠️`); `clip(2/8, 0, 1)=0.25` |

Apply default weights (clipped to `[0, 1]`, both within range):

```
composite_premature = 0.34*1.00 + 0.33*0.50 + 0.33*0.95
                    = 0.3400 + 0.1650 + 0.3135 = 0.8185  -> emit 0.82
composite_dead_end  = 0.25*0.00 + 0.25*1.00 + 0.25*0.00 + 0.25*0.25
                    = 0.0000 + 0.2500 + 0.0000 + 0.0625 = 0.3125  -> emit 0.31
```

Both rounded values match the schema-doc record's
`composite_premature: 0.82` and `composite_dead_end: 0.31`. Recorders
SHOULD round to two decimals; raw `[0, 1]` values also OK. Because
`0.82 >= T1` AND `0.31 < T2`, the guardrail picks the soft-nudge only
(had both crossed, dead-end hard-pause would win — see priority rule).

## Threshold semantics

The two thresholds (`T1 = T2 = 0.6` by default) drive the in-skill
guardrail added by F-33..F-36 (separate wave — not yet in
`skill/SKILL.md`). This file specifies the *mapping*; the
*implementation* lives in SKILL.md once that wave lands.

- **Crossing T1 (premature)** — `composite_premature >= T1` →
  **soft-nudge**. The agent's next planned multi-choice question
  gains a `(z) 退一步, 这个问题是不是问错了` (`(z) step back — is
  this question even right?`) option appended after the existing
  `(d)` / `(e)` lines. No turn is shelved; F-31 `(e)` and F-08 `(d)`
  remain present. `(z)` is the only injected element. Mechanism:
  F-33..F-34.
- **Crossing T2 (dead-end)** — `composite_dead_end >= T2` →
  **hard-pause**. The agent's next turn is replaced by a single
  meta-question with at most two options plus the `(d)` escape; the
  planned domain question is shelved one agent turn and re-attempted
  at turn `N+2`. Mechanism: F-35..F-36.
- **Priority cap — at most one guardrail-injected element per turn.**
  When both composites cross simultaneously, dead-end hard-pause wins
  (full turn replacement is the heavier intervention); the premature
  soft-nudge is suppressed for that turn and re-evaluated at `N+2`.

## Cross-references

- Per-turn record fields: `intermediate-result-schema.md` (this file's
  data input).
- Open / filled slot status, `turn_first` / `turn_last`:
  `ontology-schema.md`.
- `checklist_state` row identifiers `C-01` .. `C-07`:
  `checklist-rubric.md`.
- `dimension` enum values: `ambiguity-taxonomy.md` (also surfaced in
  F-09 of `../SKILL.md`).
- F-rules referenced: F-08, F-09, F-10, F-17, F-23, F-24, F-31 — all
  in `../SKILL.md`. F-33..F-36 are reserved for the guardrail wave
  (referenced in "Threshold semantics" but not yet in SKILL.md).

## Anti-patterns

- Do **not** silently fall back to defaults when
  `.local/pensees/.config.yaml` fails to parse. A malformed override
  is a hard error, not graceful degradation.
- Do **not** rename a signal without bumping `schema_version` in
  `intermediate-result-schema.md`; renaming is a breaking change to
  the data contract.
- Do **not** let `composite_premature` or `composite_dead_end` exceed
  `1.0` by skipping the explicit `clip(...)` step. Both are typed
  `float in [0, 1]`; an unclipped emit silently corrupts every
  threshold comparison downstream.
- Do **not** invent new signals here. The Lite scorer is fixed at
  these seven; additions must ride a v0.3.3+ design pass plus a
  `schema_version` bump (Standard variant).
- Do **not** retroactively rewrite a past turn's composite when the
  ontology updates. Each `turns.jsonl` line is a snapshot at emission
  time; replay-only consumers MUST recompute fresh, never edit the
  on-disk record.
