# Reference — Per-Turn Record Schema (v0.3.2 Lite)

> Load this file when authoring or reviewing the per-turn recorder that
> appends to `<session_dir>/turns.jsonl`, or when building tooling that
> consumes those records (e.g. the offline reviewer CLI). This file is a
> data contract only — it does not specify how the recorder or scorer
> is implemented.

## When to Load

Read this reference whenever you need to write, read, validate, or
extend a single record in `turns.jsonl`. One record is appended after
every agent turn; the append hook itself is defined elsewhere (F-32 in
`../SKILL.md` will land in a follow-up wave) and is not specified here.
Tooling that consumes `turns.jsonl` (the offline reviewer CLI, future
dashboards, replay utilities) MUST treat every "Required Lite field"
below as required and every "Reserved forward-compat field" below as
present-with-default.

## Required Lite fields

Every Lite-emitted record MUST include all of the following keys in a
single flat JSON object (with one nested object, `checklist_state`).
Unknown extra keys are tolerated by readers but discouraged in writers.

| Field | Type | Meaning |
|---|---|---|
| `schema_version` | string | FIXED value `"0.3.2-lite"` for this version. Future Standard / Heavy variants will bump it. |
| `turn_id` | int | Monotonic per session, starting at `1` and incremented by `1` on every turn (agent or user). |
| `timestamp` | string | ISO-8601 in UTC, e.g. `"2026-05-23T03:42:11Z"`. |
| `agent_or_user` | string | Enum: `"agent"` or `"user"` — which side authored the turn. |
| `dimension` | string or null | Enum (matches F-09 in `../SKILL.md`): `"linguistic"` / `"intent"` / `"contextual"` / `"epistemic"` / `"interactional"`. `null` when no ambiguity was tagged this turn. |
| `preset` | string or null | Enum: `"Exploratory"` / `"Challenge"` / `"Convergence"`. `null` if the session has not yet declared a preset. |
| `slots_touched` | list of string | Slot names referenced this turn. Names MUST match entries in the session's `ontology.yaml` (see `ontology-schema.md`). Empty list `[]` is allowed. |
| `e_probe_target` | string or null | Slot name that was the target of an F-31 `(e)` detail probe this turn; `null` otherwise. |
| `question_form` | string or null | Enum: `"decision-matrix"` / `"mockup"` / `"explorable"` / `"forced-choice"` / `"open"` / `"meta-pause"`. `null` for non-question turns (user turns, detail-probe answers, etc.). |
| `ambiguity_tag` | string or null | Verbatim copy of the value inside the `<!-- ambiguity-tag: ... -->` HTML comment if present in the turn; else `null`. Intentionally redundant with `dimension` so the on-disk record preserves source-text fidelity even if the enum vocabulary later widens. |
| `checklist_state` | object | Snapshot of all 7 convergence rows (see `checklist-rubric.md`). Keys are `C-01` through `C-07`; each value is one of `✅`, `⚠️`, `❌`. All 7 keys required. |
| `composite_premature` | float in `[0, 1]` | Composite premature-detail score for THIS turn. Higher = stronger signal that the agent is jumping into solution detail before the ontology is filled. |
| `composite_dead_end` | float in `[0, 1]` | Composite dead-end score for THIS turn. Higher = stronger signal that the dialogue is looping or has lost forward motion. |

Both composite scores are produced by the Lite scorer; their formulas
live in `composite-signals.md` (forthcoming companion reference). At
the schema level, treat them as opaque numbers in the closed interval
`[0, 1]`.

## Reserved forward-compat fields

Every Lite-emitted record MUST also include the three keys below, set
to the listed default. Standard / Heavy variants will populate them
with structured data; Lite never does, but consumers can rely on the
keys always existing.

| Field | Type | Lite default | Purpose |
|---|---|---|---|
| `llm_judge` | object or null | `null` | Standard variant — structured output from an LLM-as-judge pass over the turn. |
| `classifier_label` | string or null | `null` | Heavy variant — label emitted by a fine-tuned classifier. |
| `external_evidence` | list | `[]` | Misc Standard / Heavy attestations (citations, tool-call traces, scorer feedback). |

## Worked example

Mid-session, turn 5, an agent turn whose `meta-pause` question form was
raised because the Lite guardrail fired on a high `composite_premature`
score. Pretty-printed for human review:

```json
{
  "schema_version": "0.3.2-lite",
  "turn_id": 5,
  "timestamp": "2026-05-23T03:42:11Z",
  "agent_or_user": "agent",
  "dimension": "intent",
  "preset": "Exploratory",
  "slots_touched": ["max-delay-seconds", "per-day-cap"],
  "e_probe_target": null,
  "question_form": "meta-pause",
  "ambiguity_tag": "intent",
  "checklist_state": {
    "C-01": "⚠️",
    "C-02": "❌",
    "C-03": "❌",
    "C-04": "❌",
    "C-05": "⚠️",
    "C-06": "❌",
    "C-07": "❌"
  },
  "composite_premature": 0.82,
  "composite_dead_end": 0.31,
  "llm_judge": null,
  "classifier_label": null,
  "external_evidence": []
}
```

On disk this is exactly one line in `turns.jsonl`. Newlines and
indentation above are for human reading only. The actual wire form
(LF-terminated, no trailing comma, no internal whitespace) is:

```
{"schema_version":"0.3.2-lite","turn_id":5,"timestamp":"2026-05-23T03:42:11Z","agent_or_user":"agent","dimension":"intent","preset":"Exploratory","slots_touched":["max-delay-seconds","per-day-cap"],"e_probe_target":null,"question_form":"meta-pause","ambiguity_tag":"intent","checklist_state":{"C-01":"⚠️","C-02":"❌","C-03":"❌","C-04":"❌","C-05":"⚠️","C-06":"❌","C-07":"❌"},"composite_premature":0.82,"composite_dead_end":0.31,"llm_judge":null,"classifier_label":null,"external_evidence":[]}
```

Recorders MUST emit the wire form (single line + `\n`); reviewers MAY
re-pretty-print for display.

## Cross-references

- Slot names appearing in `slots_touched` reference the per-session
  `ontology.yaml` schema documented in `ontology-schema.md`.
- The 7 keys inside `checklist_state` mirror the rubric rows defined in
  `checklist-rubric.md`. Use the same `C-01` .. `C-07` identifiers; do
  not invent new ones at the schema layer.
- The `dimension` enum tracks the ClarifyMT 5-dim taxonomy referenced
  by F-09 in `../SKILL.md` (and detailed in `ambiguity-taxonomy.md`).
- The `question_form` enum extends the four canonical forms named by
  F-17 in `../SKILL.md` (`decision-matrix` / `mockup` / `explorable` /
  `forced-choice`); `"open"` covers any non-multi-choice question, and
  `"meta-pause"` is reserved for guardrail hard-pause turns that F-35
  .. F-36 (added in a separate wave — not yet in `../SKILL.md`) will
  emit.
- Composite-score derivation, weights, and trigger thresholds live in
  `composite-signals.md` (forthcoming companion reference); this
  schema intentionally does not reproduce them.

## Anti-patterns

- Do **not** bump `schema_version` until the Standard variant lands.
  A Lite recorder that writes any other value silently breaks every
  downstream consumer.
- Do **not** write `composite_premature` or `composite_dead_end` if
  the Lite scorer's signals reference (`composite-signals.md`) is
  missing from the repo at write time. The recorder MUST refuse to
  emit this turn's record and log loudly, not fabricate `0.0`.
- Do **not** omit `dimension` when an `<!-- ambiguity-tag: ... -->`
  HTML comment is present in the agent turn. `dimension` and
  `ambiguity_tag` MUST hold the same value in that case; mismatch is a
  hard schema error.
- Do **not** populate `llm_judge`, `classifier_label`, or
  `external_evidence` from a Lite recorder. Those keys exist so the
  wire shape stays stable across variants; filling them in Lite would
  lie about which variant produced the record.
- Do **not** rewrite history. `turn_id` is append-only — if a recorder
  detects a duplicate or out-of-order turn it MUST fail loudly, never
  overwrite an existing line in `turns.jsonl`.
