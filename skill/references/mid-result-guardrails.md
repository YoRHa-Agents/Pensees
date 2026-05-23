# Reference — Mid-Result Guardrails (F-32..F-37, v0.3.2 Lite)

> Load this file when authoring or reviewing the in-skill guardrail layer
> that wires the Lite scorer (see `composite-signals.md`) to the per-turn
> on-disk recorder (see `intermediate-result-schema.md`). This file owns
> HOW the six guardrail F-rules behave at agent-turn time; the data
> contract owns WHAT lands in `turns.jsonl`, and the signals doc owns HOW
> the two composite scores are computed. Lite-only — Standard / Heavy
> variants will arrive behind a bumped `schema_version` and are out of
> scope here.

## When to Load

Read this reference whenever any of the following holds:

- You are implementing or reviewing the per-turn append hook that writes
  one JSONL record to `<session_dir>/turns.jsonl` (F-32).
- You are wiring the two threshold-cross actions onto the planned next
  agent turn — soft-nudge (`(z)` option append, F-33..F-34) or hard-pause
  (full-turn replacement, F-35..F-36).
- You need to reason about which guardrail wins when both composites
  cross simultaneously, or about what the cap "one guardrail-injected
  element per turn" means in practice (F-37).
- You are auditing a recorded session and want to recover the exact
  boundary rules that should have applied at a given turn.

The default thresholds (`T1 = T2 = 0.6`) and per-session override file
(`.local/pensees/.config.yaml` under `mid_result_analysis:`) live in
`composite-signals.md` §"Defaults" and §"Tuning hook"; this file refers
to them but does not redefine them.

## F-32 — Per-turn recorder

After every agent turn, append exactly one JSONL line to
`<session_dir>/turns.jsonl` matching the schema documented in
`intermediate-result-schema.md`. The append MUST include all 13 Required
Lite fields plus the 3 Reserved forward-compat fields at their Lite
defaults (`llm_judge: null`, `classifier_label: null`,
`external_evidence: []`).

Violation classes that MUST trigger a loud failure (per AGENTS.md "no
silent failures"):

- `composite_premature` or `composite_dead_end` outside the closed
  interval `[0, 1]` (an unclipped scorer output is a schema bug, not a
  rounding tolerance to swallow).
- Any Required Lite field absent from the planned record.
- `timestamp` not parseable as ISO-8601 in UTC.
- `dimension` not equal to `ambiguity_tag` when the agent turn carries
  an `<!-- ambiguity-tag: ... -->` HTML comment (F-09 / schema
  cross-check).

On any of the above, the recorder MUST emit a stderr log line naming
the violated invariant AND MUST NOT write a partial record to
`turns.jsonl`. A partial record silently corrupts every downstream
consumer (offline reviewer, replay utilities, future dashboards); a
missing record is recoverable from the agent's transcript.

Pseudocode shape (normative for the violation handling, illustrative
for the rest):

```
record = build_required_and_reserved_fields(turn)
violations = validate(record)
if violations:
    log_stderr("F-32 schema violation: " + join(violations))
    return  # do NOT append
append_jsonl_line(session_dir + "/turns.jsonl", record)
```

The recorder MUST emit the wire form (single line + `\n`, no internal
whitespace). Pretty-printed JSON is for human review only and never
lands in `turns.jsonl`.

## F-33 — Premature-detail soft-nudge trigger

When the Lite scorer computes `composite_premature >= T1` for the
planned NEXT agent turn (default `T1 = 0.6`, override-able via
`mid_result_analysis.premature.threshold` in
`.local/pensees/.config.yaml` per `composite-signals.md` §"Tuning
hook"), the agent's planned multi-choice question gains exactly one
extra option appended AFTER the existing F-08 `(d) ...` escape and the
F-31 `(e) ...` detail-probe lines:

- Chinese form: `(z) 退一步, 这个问题是不是问错了`
- English form: `(z) step back — is this question even right?`

Both forms are acceptable; match the language of the prevailing
dialogue. The agent does not invent a third localization.

Ordering on the resulting turn:

```
... (existing question body) ...
(a) option-a
(b) option-b
(c) option-c
(d) 都不是, 让我描述
(e) 我想先详细听 (X) 这个选项再决定
(z) 退一步, 这个问题是不是问错了
```

The injection happens only on multi-choice questions; for an `open`
question form there is nothing to append `(z)` to, so a soft-nudge in
that turn collapses to a no-op for the option list and the
`composite_premature` value is still recorded per F-32.

## F-34 — Soft-nudge boundary rules

The F-33 `(z)` injection has four strict boundary rules. Each rule is
load-bearing for downstream behavior and MUST hold simultaneously:

- **(a) No semantic change.** Appending `(z)` does NOT alter the
  existing question semantics. Options `(a)`..`(c)`, the F-08 `(d)`
  escape, and the F-31 `(e)` detail-probe wording are byte-identical
  to the planned pre-guardrail turn.
- **(b) Not an F-08 escape.** A user picking `(z)` does NOT count
  toward the F-08 two-consecutive-`(d)` escape-hatch trigger.
  `(z)` is a meta-frame question, not a frame-rejection, and conflating
  the two breaks the F-08 preset-check semantics.
- **(c) Not an F-31 probe.** A user picking `(z)` does NOT count as an
  F-31 `(e)` detail probe. The agent's next turn after a `(z)` pick
  does NOT need to emit the four-section (后果 / 对比 / 场景 / 未知)
  detail expansion.
- **(d) Sole injection.** `(z)` is the ONLY guardrail-injected element
  this turn. No `[guardrail]` prefix on `(d)` or `(e)`, no extra
  explanatory paragraph above or below the question, no extra
  `<!-- ambiguity-tag: ... -->` HTML comment beyond what the
  underlying question already carries.

The agent records the firing `composite_premature` value and the chosen
`question_form` (unchanged from the planned form) in the turn's
`turns.jsonl` record per F-32. The recorded `question_form` MUST be the
underlying form (`decision-matrix` / `forced-choice` / etc.) — not
`meta-pause`, which is reserved for F-35 hard-pause turns.

## F-35 — Dead-end hard-pause trigger

When the Lite scorer computes `composite_dead_end >= T2` for the
planned NEXT agent turn (default `T2 = 0.6`, override-able via
`mid_result_analysis.dead_end.threshold` in
`.local/pensees/.config.yaml` per `composite-signals.md` §"Tuning
hook"), the agent's next turn is REPLACED by a single meta-question
— NOT the planned domain question.

The replacement meta-question has a fixed shape:

- `question_form` set to `"meta-pause"` (the enum value reserved for
  this branch in `intermediate-result-schema.md`).
- At most 2 substantive options.
- Plus the standard `(d) 都不是, 让我描述` escape (F-08 still applies).
- No `(e)` detail probe (F-31 does not fire on a hard-pause turn).
- Exactly one `<!-- ambiguity-tag: ... -->` HTML comment, carrying
  the most-recently-tagged dimension value (see F-36 below).

Suggested template (Chinese):

```
我们可能在 X 上原地打转, 要不要
(a) 暂停回到上一个 open slot Y,
(b) 整体重述目标?
(d) 都不是, 让我描述
<!-- ambiguity-tag: intent -->
```

Suggested template (English), with the same structural slots:

```
We might be going in circles on X — would you rather
(a) pause and return to the previous open slot Y,
(b) restate the overall goal?
(d) none of these, let me describe
<!-- ambiguity-tag: intent -->
```

`X` is the loop topic the scorer detected (typically the focal slot
that drove `slot_focus_imbalance` or the dimension repeated by
`dimension_repetition`); `Y` is the most-recently-touched still-`open`
slot from `ontology.yaml`. The agent fills both before emitting.

## F-36 — Hard-pause boundary rules

The shelved domain question is re-attempted at agent turn `N+2`,
skipping one turn for the user's response to the meta-pause. The
hard-pause turn itself is recorded per F-32 with three constraints:

- `question_form: "meta-pause"` (NOT the shelved planned form).
- `e_probe_target: null` (no F-31 probe fires on a hard-pause turn).
- `dimension` and `ambiguity_tag` set to the same value as the
  most-recently-tagged dimension on a prior agent turn, preserving the
  F-09 dimension trail. If no prior agent turn carried a dimension tag,
  the recorder MUST refuse to emit (the scorer should not have fired
  `composite_dead_end` in that case; investigate).

Re-entry semantics at turn `N+2`:

- If the user's `(a)` reply at `N+1` selected the pause-and-return
  option, the agent at `N+2` re-emits the shelved domain question
  against the chosen `open` slot `Y`. The re-emit may incorporate the
  user's clarification verbatim; it MUST NOT silently drop the
  original ambiguity dimension.
- If the user's `(b)` reply at `N+1` selected goal restatement, the
  agent at `N+2` opens a top-level restatement question and the
  shelved domain question is closed (not re-emitted at `N+2`).
- If the user's `(d)` reply at `N+1` rejected both meta-options, the
  agent at `N+2` follows the user's free-text frame.

Escalation rule (loud failure surface):

If `composite_dead_end` is STILL `>= T2` at turn `N+2` after the
meta-pause user response, the agent MUST NOT fire another hard-pause
back-to-back. Instead, per AGENTS.md "no silent failures", the agent
emits a single-paragraph operator-visible warning:

```
Lite guardrail unable to break loop after one hard-pause;
consider manual reset.
```

The warning is part of the agent turn text (not a stderr log) so the
operator can see it in the live transcript. The agent still appends a
`turns.jsonl` record per F-32 for that turn.

## F-37 — Priority cap and pointers

**Priority cap.** At most ONE guardrail-injected element per agent
turn. When both composites cross simultaneously
(`composite_premature >= T1` AND `composite_dead_end >= T2` for the
same planned turn), the dead-end hard-pause (F-35) wins because
full-turn replacement is the heavier intervention; the premature-detail
soft-nudge (F-33) is suppressed for that turn and re-evaluated at turn
`N+2` from the fresh composite values.

The cap is also a tie-break rule when an agent is tempted to layer
additional surface decorations onto a guardrail turn (e.g. add a
`[guardrail]` prefix AND a `(z)` option AND an extra ambiguity tag).
The cap says: pick the single injection mandated by F-33 or F-35 — no
others.

**Pointers.**

- Schema for `turns.jsonl` records: `intermediate-result-schema.md`.
- Signal definitions, default thresholds (`T1 = T2 = 0.6`), and the
  per-session tuning hook: `composite-signals.md`.
- Tuning override file: `.local/pensees/.config.yaml`, under the
  top-level `mid_result_analysis:` key. Schema mirrors the `defaults:`
  block in `composite-signals.md` §"Defaults".

## Cross-references

- Per-turn record fields (`turn_id`, `dimension`, `question_form`,
  `composite_premature`, `composite_dead_end`, etc.):
  `intermediate-result-schema.md`.
- Signal definitions (`slot_focus_imbalance`, `e_probe_over_use`,
  `question_form_jump`, `amnesia`, `dimension_repetition`,
  `frame_collapse`, `checklist_regression`) and composites:
  `composite-signals.md`.
- F-08 escape hatch and the `(d) 都不是, 让我描述` form: `../SKILL.md`
  §2 plus `question-forms.md`.
- F-09 ambiguity tags and the 5-dimension enum:
  `ambiguity-taxonomy.md`.
- F-10 ontology slots and `open` / `filled` status:
  `ontology-schema.md`.
- F-31 `(e)` detail probe (the four bold sections 后果 / 对比 / 场景 /
  未知): `../SKILL.md` §2 plus `question-forms.md`.
- The `meta-pause` `question_form` enum value:
  `intermediate-result-schema.md` §"Required Lite fields".

## Anti-patterns

- Do **not** stack a soft-nudge `(z)` AND a hard-pause replacement
  in the same agent turn. The F-37 priority cap is explicit — pick
  one. Stacking violates "at most one guardrail-injected element per
  turn" and breaks downstream replay analysis.
- Do **not** treat the soft-nudge `(z)` as an F-08 escape pick or an
  F-31 detail probe. F-34 is explicit on both points; conflating them
  corrupts the preset-check trigger and the four-section detail rule.
- Do **not** rewrite the planned `question_form` to `meta-pause` on a
  soft-nudge turn. `meta-pause` is reserved for F-35 hard-pause
  replacements; mis-recording the form on a soft-nudge turn breaks the
  offline reviewer's "Top contributing signals" table for that turn.
- Do **not** fire a second hard-pause at turn `N+2` if the first one
  did not unstick the loop. F-36's escalation rule mandates an
  operator-visible warning instead — silent re-fire is a guardrail
  loop, not a loop break.
- Do **not** silently fall back to default thresholds if
  `.local/pensees/.config.yaml` exists but fails to parse or carries
  out-of-range values. A malformed override is a hard error per
  AGENTS.md "no silent failures"; the recorder must refuse to start
  the session, not pretend the override was absent.
