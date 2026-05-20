# Pensees — Quick Guide (5 minutes)

A 5-minute orientation: what Pensees is, how to install it, what one real
session looks like, and where the output lives. For everything else, see
[USER_GUIDE.md](USER_GUIDE.md).

## What it is

Pensees is a skill package — not an inference service. It rides on top of
your existing agent (Cursor / Claude Code / Codex CLI), holds the
dialogue contract and the HTML demo templates, and steers the host agent
into clarifying-rather-than-jumping behavior. There are no API keys to
manage and nothing to log in to; the host agent does all the thinking
("BYOCC": bring-your-own-cognition-and-context). Pensees only holds the
contract and the reference bundle.

Three things differentiate a Pensees session from a normal agent chat:

- **One question at a time** (F-07). The agent ends every turn with
  exactly one `?`. Multiple-choice options `(a)/(b)/(c)/(d)` count as
  one structured question, never a batch dump.
- **Escape hatches built in** (F-08, F-31). Every multi-choice question
  carries `(d) 都不是, 让我描述` (or English `(d) none of these, let me
  describe`) and `(e) 我想先详细听 (X) 这个选项再决定`. You always have
  a way out and a way to dig deeper without losing your place.
- **A 7-row convergence checklist** (C-01..C-07). The agent does not
  produce `requirements.md` / `acceptance-criteria.md` until all 7 rows
  are ✅ AND you explicitly approve (`可以` / `go` / `yes` / `ok`).
  That gate is HARD (F-14) — no early shipping, no implicit hand-off.

Pensees is intentionally non-greedy (AR-06). Without one of the trigger
phrases in [skill/SKILL.md](../skill/SKILL.md), it stays asleep.

## Install in 30 seconds

```bash
curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

Verify the install landed:

```bash
ls "$HOME/.cursor/skills-cursor/pensees"
```

You should see the contents of the `skill/` directory linked into place.
Equivalent links are also created under `~/.claude/skills/pensees` and
`~/.codex/skills/pensees`. If you prefer `bash` over `sh`:

```bash
curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | bash
```

Pin a specific release (recommended for production setups):

```bash
PENSEES_VERSION=v0.3.0 curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

If you cannot use the curl path (corporate proxy, air-gapped env), see
the `git clone` and manual-symlink alternatives in the
[README](../README.md#install). All install paths are equivalent; pick
the one that fits your sandbox.

## Your first session

Open Cursor / Claude Code / Codex CLI, and send a message containing one
of the trigger phrases. Here is a 3-turn opening with a software example
(Pensees is domain-neutral; the same pattern applies to research,
business decisions, or anything that starts fuzzy):

**Turn 1 — you:**

> pensees, 帮我想清楚要不要给现在的 web app 加缓存

**Turn 2 — Pensees (opening / contracting turn, F-02):**

> I'm running in **Exploratory** mode by default. Switch with
> `挑战这个` (Challenge — tightens the critique) or
> `让我们收敛` / `let's converge` (Convergence — locks choices in)
> whenever you're ready. Say `慢一点, 重述` any time to slow down.
>
> Before "cache" can mean one thing, I need to know which layer you're
> thinking about. Which of these is closest?
>
> (a) Per-request memoization inside one HTTP handler
> (b) A cross-request shared cache (in-process, e.g. LRU)
> (c) An external cache service (Redis / Memcached)
> (d) 都不是, 让我描述 / none of these, let me describe
> (e) 我想先详细听 (b) 这个选项再决定
>
> <!-- ambiguity-tag: linguistic -->

**Turn 3 — you:**

> (e)

Pensees responds with a 4-section breakdown (**后果** / **对比** /
**场景** / **未知**) for option (b), keeps the total under ~350 chars,
then re-emits the original question with `(f) 已了解 (b), 再问 (Y)`
appended. That's F-31 in action: detail on demand without losing your
place in the question tree.

The session continues — one question per turn — until the 7-row
checklist is all `✅` and you say `可以` / `go` / `yes` / `ok`. Only
then does Pensees write `requirements.md` and `acceptance-criteria.md`
under `.local/pensees/{date}-{slug}/outputs/`. If you ever want to bail,
say `销毁本会话` / `forget this` / `wipe session`: the session directory
is removed within 2 seconds and a fact-only audit line is kept under
`.local/pensees/.audit/destruction.log`.

## Where output lands

Pensees writes ONLY under `.local/pensees/` (relative to the working
directory of the host agent). It never modifies `skill/`, the README, or
anything outside that prefix (F-28 / NF-06).

```
.local/pensees/{YYYY-MM-DD}-{slug}/
├── transcript.md             # full dialogue, one turn per block
├── ontology.yaml             # aspect → dimension → slot model (≤ 50 lines)
├── checklist-status.md       # 7 rows, updated each turn (C-01..C-07)
├── demos/                    # 2–3 variant HTML files per emit (F-15)
└── outputs/                  # only after HARD-GATE: checklist ✅ + your `go`
    ├── requirements.md
    └── acceptance-criteria.md
```

A one-line index at `.local/pensees/INDEX.md` records each completed
session. The destruction-fact log lives at
`.local/pensees/.audit/destruction.log` and is the only persisted trace
of a `forget this`-ed session — content is never retained.

## Read next

- Deeper walkthrough — every install flag, every preset, every host
  quirk: [USER_GUIDE.md](USER_GUIDE.md).
- 中文版本（同一份指南的中文表达）: [QUICK_GUIDE.zh.md](QUICK_GUIDE.zh.md).
- The behavior contract itself (single source of truth, F-numbers,
  presets, write-path whitelist): [skill/SKILL.md](../skill/SKILL.md).
- Live demo + day/night + ZH/EN toggles on the project site:
  <https://yorha-agents.github.io/Pensees/>.
- Back to the project [README.md](../README.md).
