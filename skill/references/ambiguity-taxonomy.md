# Reference — Ambiguity Taxonomy (ClarifyMT 5-dim)

> Load this file when you detect an ambiguity in the user's last message
> and need to tag it. Source: ClarifyMT-Bench, arXiv:2512.21120v1.

## Rule (F-09)

Every ambiguity you identify in the user's turn must be tagged with an HTML
comment at the **end** of your agent turn:

```html
<!-- ambiguity-tag: linguistic -->
```

Required, not optional. Reviewer-only (invisible to rendered chat). One
session must not hit the same dimension ≥ 3 turns in a row — if it does,
switch question dimension or call F-13 fuzzy-term sharpening.

## The five dimensions

### 1. linguistic
The word itself has more than one dictionary sense or is overloaded by the
user across messages.

- Example trigger: user said "active user" in one turn meaning weekly
  loggers and later meaning anyone who clicked once.
- Question form: definition-prompt. "When you say `active user`, do you
  mean (a) anyone who opened the app this week, (b) someone who completed
  one core action, or (d) let me describe?"

### 2. intent
The user's goal-state is unclear; multiple end-states are compatible with
their words.

- Example trigger: "I want this to be useful" — useful to whom, for what?
- Question form: outcome-anchor. "What would happen on day 30 if it
  succeeded? Tell me what you'd see."

### 3. contextual
The setting / time / place / audience that determines correctness is not
specified.

- Example trigger: "It should be fast" — at p50 in browser, or median
  on mobile 4G, or backend latency?
- Question form: scope-card. "Which context matters most: (a) cold-start,
  (b) repeated use, (c) edge / no-network, (d) none of these?"

### 4. epistemic
The user is uncertain about a fact relevant to their request and may not
know they are uncertain.

- Example trigger: "I think most users already use X" — is this a survey
  result, a hunch, or a deduction?
- Question form: confidence-probe. "How sure are you that X — high / low /
  not yet checked?"

### 5. interactional
The conversation itself is misaligned; the user and you have different
assumptions about the state of the discussion.

- Example trigger: user thanks you for a solution you didn't propose.
- Question form: ground-truth restate. "To make sure we're aligned, the
  options on the table right now are A, B, C — which one did you mean?"

## Quick decision tree

```
ambiguity detected
├── one word, multiple meanings           → linguistic
├── multiple end-states compatible        → intent
├── missing setting / scope / audience    → contextual
├── user states fact without basis        → epistemic
└── user and you on different pages       → interactional
```

## Repeat-suppression rule

If the last 2 turns both fired the same dimension tag, the next turn must
either (a) move to a different dimension, or (b) escalate to a demo emit
(F-18 trigger (a) fired). Do not ask a third linguistic-tagged question
in a row.

## Cross-dimension example (single user turn)

> "I want fast notifications but not annoying"

- `fast` → contextual (latency in which scenario?)
- `notifications` → linguistic (push / email / in-app banner?)
- `not annoying` → intent (annoying defined how — frequency, content,
  timing?)

Pick one and tag it; resolve sequentially over 3 turns rather than
asking three questions at once (F-07 one-question-at-a-time).
