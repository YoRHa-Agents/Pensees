# Reference — Experience Ontology Schema

> Load this file when initializing or updating `ontology.yaml` for the
> active session. Source: OntoAgent, arXiv:2605.05828 (`+33% IRE`).

## Three levels

- **aspect** — the top-level category of the user's thought
  (e.g. `audience`, `format`, `success-criterion`, `risk`).
- **dimension** — a sub-axis of an aspect that can be ambiguous
  (e.g. for `audience` → `expertise-level`, `motivation`, `device`).
- **slot** — the minimal askable unit; one slot = one question's worth
  of resolution.

## File format

`.local/pensees/{date}-{slug}/ontology.yaml`, ≤ 50 lines total:

```yaml
aspects:
  - name: <aspect>
    dimensions:
      - name: <dimension>
        slots:
          - name: <slot>
            status: open | filled
            definition: <≥ 5 char definition of the term once filled>
            value: <user-confirmed value or null>
            turn_first: <N>          # turn slot was first surfaced
            turn_last: <N>            # turn slot was last touched
            term_aliases: [<x>, <y>]  # other words the user used for same concept
```

## Update rules

- After user turn 2, write the initial ontology. Never start the file
  before turn 2 (premature schema = overfit to the first sentence).
- Every new slot must be linked to a transcript turn via `turn_first`.
- When F-13 fuzzy-term sharpening lands, append the canonical term as
  `definition` and the rejected aliases to `term_aliases`.
- A slot can only flip `open → filled` after the user explicitly confirms
  the value (binary `yes` / picked option / accepted forced-choice).
- Drive next question from `status: open` slots. Do not free-form a
  question that does not correspond to any slot.

## Worked example 1 — software session

User opening: "I want a notification system that's fast but not annoying."

```yaml
aspects:
  - name: notification-trigger
    dimensions:
      - name: latency-budget
        slots:
          - name: max-delay-seconds
            status: open
            term_aliases: ["fast"]
            turn_first: 1
  - name: user-experience
    dimensions:
      - name: frequency-cap
        slots:
          - name: per-day-cap
            status: open
            term_aliases: ["not annoying"]
            turn_first: 1
      - name: channel
        slots:
          - name: push-vs-email-vs-inapp
            status: open
            turn_first: 1
```

## Worked example 2 — non-software session

User opening: "I want my first podcast episode to land hard with the
right people."

```yaml
aspects:
  - name: audience
    dimensions:
      - name: expertise-level
        slots:
          - name: novice-vs-insider
            status: open
            turn_first: 1
            term_aliases: ["right people"]
      - name: emotional-state
        slots:
          - name: curious-vs-skeptical
            status: open
            turn_first: 1
  - name: format
    dimensions:
      - name: solo-vs-interview
        slots:
          - name: host-mode
            status: open
            turn_first: 1
  - name: success-criterion
    dimensions:
      - name: signal-of-landing
        slots:
          - name: what-listener-does-next
            status: open
            turn_first: 1
            term_aliases: ["land hard"]
```

Note how `right people` and `land hard` are caught as ambiguous terms and
moved into `term_aliases` for later F-13 sharpening — both are linguistic
ambiguities that would otherwise drift through the session.

## Anti-patterns

- Pre-loading a generic 20-slot ontology before turn 2 — defeats the
  point.
- Updating `value:` from agent inference without explicit user confirm.
- Letting > 8 slots stay `open` simultaneously — focus is lost.
