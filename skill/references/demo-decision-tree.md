# Reference — Demo Decision Tree

> Load this file when deciding whether to emit a demo, picking a candidate
> form, or generating the variant axis. Sources: SKILL.md §4 / F-15..F-21 /
> `requirements.md §7`.

## Step 1 — Should I emit?

Evaluate the 4 trigger conditions in order. If any is true → emit. If
none → continue with text dialogue.

- (a) User used a fuzzy word AND ≥ 2 prior turns of text clarification
  did not resolve it.
- (b) Two slots in `ontology.yaml` hold conflicting values; a trade-off
  is needed.
- (c) User explicitly requested a sketch / picture / mockup / "show me".
- (d) One ontology slot maps to ≥ 2 plausible interpretations and you
  cannot pick without seeing the user's preference.

If you emit, you MUST be able to map the emit to one of these four
conditions when later reviewed.

## Step 2 — Which candidate form?

| Candidate | Best when | Required elements | Bad when |
|---|---|---|---|
| **① Decision matrix** | User trading off ≥ 3 dimensions | N×M table; short text or emoji per cell; column-footer button `I lean this column` | User has not yet listed the dimensions |
| **② UI mockup** | User imagines a person using the artifact | Visible boundary; labeled regions; ≥ 1 interactive button (`console.log` on click) | Topic is abstract / not visual |
| **③ Bret-Victor explorable** | 1–2 continuous parameters can be tuned | ≥ 1 `<input type=range>`; live readout div | Decision is discrete |
| **④ Forced-choice scenario card** | Preference needs a concrete scenario to surface | Scenario text ≤ 60 chars; 2–3 mutually-exclusive buttons; click writes localStorage | User can directly state the preference |

Mixing is allowed (e.g. A is matrix, B is forced-choice) within a single
2-variant emit.

## Step 3 — Variant axis (F-16)

Single demo is forbidden (rabbit-hole). Produce 2 or 3 variants. State
the difference axis explicitly in the emit turn — do not let the user
guess. Choose ONE of:

- **density** — A has more info per screen, B has less.
- **aesthetic** — A is style X, B is style Y.
- **decision-structure** — A is single-step, B is staged.
- **emphasis** — A foregrounds inputs, B foregrounds outputs.

Forbidden: two variants whose visual diff < 30% (i.e. both look almost
the same — that's not a real choice).

## Step 4 — Visibly-rough aesthetic (F-19)

Every HTML demo file must include all of:

- **Font family**:
  `font-family: 'Caveat', 'Comic Neue', 'Excalifont', cursive, sans-serif;`
- **Border**: `border: 1.5px dashed #555;` or an inline SVG chalk-stroke
  filter. No solid borders ≥ 2px on main containers.
- **Top banner**: a fixed `<div>` with `background:#000;color:#fff;font-family:monospace;`
  containing the text `DRAFT — please critique`.
- **TODO comment**: at least one `<!-- TODO: ... -->` somewhere in the
  body, naming a concrete unfinished aspect.

Forbidden visual signals (these make demos look "done", which kills the
"please critique" reflex):

- `border-radius` ≥ 8px on main containers.
- `box-shadow` blur ≥ 8px on main containers.
- Full-page gradients.
- Material / Tailwind production-grade alignment grids.

## Step 5 — Anchor to turn (F-20)

The very first line of each file (before `<!DOCTYPE html>` or inside
`<head>` as the first comment) must read:

```html
<!-- pensees-anchor: session=2026-05-18-foo; turn=7; user_quote="I want it to feel quiet but not silent" -->
```

- `session=` matches the slug under `.local/pensees/`.
- `turn=` is the agent turn number that decided to emit.
- `user_quote="..."` is the trigger phrase from the user, ≤ 80 chars.

This anchor is how a reviewer (or future-you) can trace why this demo
exists. `grep "pensees-anchor"` must return 100% match across all demo
files.

## Step 6 — Frame as question (F-21)

The agent turn that ships the demos is itself a question, not decoration.
Acceptable wording:

> Here are two variants. A foregrounds **{axis_value_A}**; B foregrounds
> **{axis_value_B}**. Which feels closer to what you want — or pick (d)
> if neither, (e) if you want a deeper look at one?

Forbidden wording (treats demo as decoration):

- `Take a look at what I made.`
- `What do you think?` (no escape hatch, no axis description)
- `Here is the design.` (no question)

## Step 7 — File path and naming (F-22)

```
.local/pensees/{YYYY-MM-DD}-{slug}/demos/
├── 01-{topic-slug}-A.html
├── 01-{topic-slug}-B.html
└── 01-{topic-slug}-C.html   (optional, only if 3 variants used)
```

- `NN` is the emit-group counter (01, 02, ...) within the session.
- `topic-slug` ≤ 4 words, lowercase, hyphenated.
- `variant-letter` is A / B / C.

## Anti-patterns (mapped to AP-XX in acceptance-criteria.md)

- Single demo → AP-03.
- Polished UI → AP-02.
- Demo as decoration without a comparative question → AP-11.
- Missing variant axis description → drops Demo Effectiveness score (B) by 1.
