# Reference — Dialogue Styles and Preset Tuning

> Load this file when picking or switching presets, or when you want to
> choose a reasoning sub-primitive inside the current preset.
> Source: `.local/research/2026-dialogue-styles-matrix.md` (13-style survey).

## Three presets at a glance

| Preset | When it wins | Primary primitives | Secondary primitives | Fatigue (1–5) |
|---|---|---|---|---|
| **Exploratory** (default) | User said "I'm not sure yet" or used ≥ 2 fuzzy words | Multiple-Choice Brainstorming (Obra) + Reflective Anchoring | Fuzzy-term sharpening + Scaffolding | 1 |
| **Challenge** | A near-final proposal exists; user wants stress-test | Devil's Advocate + BMAD Reasoning-Method Menu | Grill-style scenario probing | 4 |
| **Convergence** | 5–6 of 7 checklist rows already ✅ | GROW (Goal / Reality / Options / Will) + Spec Kit taxonomy-driven scan | Reflective restatement; HMW for branching | 2 |

Universal sub-primitive (does not change preset): **`慢一点, 重述` / `slow
down, restate`** → one Reflective turn that restates the user's last
substantive message in your own words and asks one confirmation question.

## Switch protocol (F-12)

1. Detect a switch phrase in the user's last message (see SKILL.md §3 table).
2. Next agent turn opens with `Switching to **{Preset}** mode.` (or
   `切换到 {Preset} 模式`).
3. Then ask one question whose form matches the new preset:
   - Exploratory → open-ended on the fuzziest slot.
   - Challenge → pre-mortem framing: "what would kill this in 30 days?"
   - Convergence → forced-choice between top 2 remaining options.

## 13-style fatigue summary

Higher fatigue → use sparingly; lower fatigue → safe default fabric.

| # | Style | Fatigue | HTML-demo fit | Use in preset |
|---|---|:-:|:-:|---|
| 1 | Pure Socratic | 4 | Low | Challenge (rare) |
| 2 | Reflective / Active Listening | 1 | Medium | All — trust floor |
| 3 | Motivational Interviewing (OARS) | 2 | Medium | Convergence (commitment) — never default |
| 4 | Devil's Advocate | 4 | High (counter-demos) | Challenge — primary |
| 5 | DevolaFlow Grill | 3 | High (anchors) | Challenge — secondary |
| 6 | 5 Whys (adapted) | 4 | Low | Exploratory only on root-cause topics |
| 7 | Cognitive Walkthrough | 2 | Very High (step demos) | Exploratory + Convergence |
| 8 | Constructivist Scaffolding | 2 | High (concept demos) | Exploratory long-arc |
| 9 | Design-Sprint "How Might We" | 2 | High (variant demos) | Exploratory branching |
| 10 | GROW Coaching | 2 | Medium | Convergence — primary |
| 11 | Multi-Choice Brainstorming | 1 | Very High (variants = answer) | Exploratory — primary |
| 12 | BMAD Reasoning-Method Menu | 3 | Medium | Challenge — primary (post-draft) |
| 13 | Spec Kit Taxonomy Scan | 2 | Medium | Convergence — primary (near-spec) |

## Fatigue budget per session

Aim for average fatigue ≤ 2.5 across the session. Track in your head:
each Devil's Advocate / 5 Whys turn costs 4; balance with Reflective (1)
and Multi-Choice (1) turns. If two consecutive high-fatigue turns landed,
the next turn should be Reflective or a structured multi-choice — not
another grilling.

## Reasoning-method menu (Challenge preset)

Loaded from `methods.csv`. When user invokes Challenge, offer up to 5
methods by name from the CSV, formatted as a multi-choice question with
escape hatch `(d)` and detail probe `(e)`. Apply the chosen method to the
most recent draft / claim / plan.

## Anti-patterns to avoid

- Defaulting to Motivational Interviewing in Exploratory — perceived as
  manipulative when user has already decided to act (survey §3 pitfall).
- Stacking 3+ Devil's Advocate turns — user disengages (fatigue 4 × 3).
- Using Pure Socratic when the user is not a reasoner-by-trade — frustration.
