# Reference — Question Forms

> Load this file when choosing how to phrase the next question.
> Sources: OntoAgent (arXiv:2605.05828) linguistic regulation;
> SKILL.md §3 / F-07 / F-08 / F-31.

## Four canonical forms (slot-state → form)

| Slot state | Default form | Example |
|---|---|---|
| Slot fully unconstrained | **Binary confirm** | `Do you need a notification preference page at all?` |
| Slot has partial constraint | **Open-ended** | `You said it should be quiet during sleep. What does "sleep" mean here — calendar block, OS state, or something else?` |
| Multiple slots empty | **Multiple choice** | `Which feels more important first: (a) timing, (b) channel, (c) content, (d) 都不是, 让我描述, (e) 我想先详细听 (a) / (b) / (c) 这个选项再决定?` |
| Slot already filled but new conflict | **Forced choice** | `Earlier you said P. Just now you said Q. Which one wins?` |

## Multi-choice question — mandatory anatomy

Every multi-choice question MUST contain, in order:

1. A scenario or one-sentence framing (≤ 80 chars).
2. 2–4 labeled options `(a) ...` / `(b) ...` / `(c) ...`.
3. The escape hatch (F-08, AR-08): `(d) 都不是, 让我描述` or
   `(d) none of these, let me describe`.
4. The option-detail probe (F-31): `(e) 我想先详细听 (X) 这个选项再决定`
   or English equivalent.
5. Exactly one `?` at the end.

If the user picks `(d)` two turns in a row, run a preset-fit check (see
`styles.md`) — the form is too restrictive for their current state.

## Canonical form vs fallback (F-38)

A multi-choice question has two render modes — the canonical and the
fallback. Pick by host capability, not by author preference.

**Canonical (preferred)** — when the host agent exposes a structured-
question tool (e.g. Cursor `AskQuestion`):

- Invoke the tool with one entry in `questions[]`.
- `prompt` = the one-sentence framing (≤ 80 chars).
- `options` = list of `{id, label}` where `id` is the letter
  (`"a"`, `"b"`, `"c"`, `"d"`, `"e"`, `"f"`, `"z"`) and `label` is
  the option text.
- `allow_multiple` = `false`.
- The message body in the same turn carries ONLY the framing prose;
  the option list lives entirely in the tool call.

**Fallback** — when no structured-question tool is exposed by the
host (e.g. Codex CLI without an equivalent):

- Emit the framing sentence and the letter-IDed options inline in
  the message body, exactly as the §"Multi-choice question — mandatory
  anatomy" section above describes.

Never silently drop the multi-choice structure (AGENTS.md §2 "No
silent failures"). The letter IDs are stable across both modes —
the user picks `(a)` / `(b)` / ... the same way either way.

## Option-detail probe (F-31) full protocol

When the user message is `(e) <letter>` or a synonym (`详细 X` / `tell me
more about X` / `深入 X` / `先说说 X`):

1. Output one detail turn, ≤ 350 characters total, with these four bold
   subsections in this order:

   - **后果** (Consequences) — ≤ 80 chars. What concretely happens next
     if the user picks this option.
   - **对比** (Comparison) — ≤ 60 chars. Key differences vs the other
     listed options (pick the 1–2 most informative deltas).
   - **场景** (When wins / loses) — ≤ 100 chars. The scenario where this
     option fits, and the scenario where it fits poorly.
   - **未知** (Unknown) — ≤ 50 chars. The 1–2 things we still cannot
     determine if the user picks this.

2. After the detail turn, **re-emit the original question** with all
   original options preserved, plus append:

   `(f) 已了解 (X), 再问 (Y)` — let the user recursively dive into another
   option, or just pick a, b, c directly.

3. Never auto-detail all options unprompted — that overloads the user.
   Wait for `(e)`.

## Escape-hatch wording variations (acceptable)

zh: `都不是, 让我描述` / `其它` / `让我自己说` / `都不太对, 我说一下`
en: `none of these, let me describe` / `other` / `something else` / `let
me put it in my own words`

Each is acceptable; pick consistent wording within a session.

## What is NOT a question

These do not count as one of "one question per turn":

- A rhetorical question used for emphasis (`Right?`).
- A meta-question inside a `<!-- TODO -->` HTML comment.
- A clarifying sub-clause that contains `?` but ends with `.` overall.

These DO count:

- Any line that ends with `?`.
- A multi-choice block (counts as 1 even if it contains internal `?`).

## Free-text vs structured

| When | Form |
|---|---|
| User typing fluency is high (long thoughtful messages) | Open-ended |
| User typing fluency is low (short messages, many "I don't know") | Multi-choice |
| You are stress-testing (Challenge preset) | Forced choice |
| You are closing (Convergence preset, 6/7 ✅) | Binary confirm on remaining row |

Always default to multi-choice when in doubt — it minimizes user typing
burden and produces clean signal.
