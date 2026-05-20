# Pensees — User Guide

A deeper walkthrough than the [QUICK_GUIDE](QUICK_GUIDE.md): every install
knob, every dialogue rule, every host quirk, with explicit pointers back
to the behavior contract in [skill/SKILL.md](../skill/SKILL.md). The
contract is the single source of truth; this guide explains it.

Sections:

1. [Overview](#1-overview)
2. [Install in detail](#2-install-in-detail)
3. [Opening turn behavior](#3-opening-turn-behavior)
4. [Core dialogue rules](#4-core-dialogue-rules)
5. [Presets and switch phrases](#5-presets-and-switch-phrases)
6. [HTML demos](#6-html-demos)
7. [Local preview server](#7-local-preview-server)
8. [Convergence and delivery](#8-convergence-and-delivery)
9. [Per-host quirks, troubleshooting, emergency stop](#9-per-host-quirks-troubleshooting-emergency-stop)
10. [Read next](#10-read-next)

## 1. Overview

Pensees is a **skill package**, not an inference service. The host agent
(Cursor / Claude Code / Codex CLI) does all reasoning; Pensees holds the
behavior contract (`skill/SKILL.md`), a small reference bundle
(`skill/references/`), 4 demo templates (`skill/templates/demo-*.html`),
and 2 deliverable templates (`requirements.template.md`,
`acceptance-criteria.template.md`). There are no API keys, no telemetry,
no outbound calls. This posture is called BYOCC: bring-your-own-
cognition-and-context.

Pensees is **manually invoked**. The host agent autoloads the skill only
when the user message contains one of the trigger phrases declared in
`skill/SKILL.md`'s YAML frontmatter. The current trigger set is:

| Language | Phrases |
|---|---|
| literal | `pensees` |
| Chinese | `模糊的想法`, `帮我想清楚`, `理一下需求`, `做需求澄清` |
| English | `fuzzy thought`, `help me think through`, `clarify requirements`, `elicit` |

If none of those appear, Pensees stays asleep. It will not load on
generic "help me plan" / "what should I do" / "brainstorm with me" —
this is the AR-06 anti-greedy posture. Likewise it will not advertise
itself in response to "what can you do" (AR-06).

Pensees is **domain-neutral**. The examples in this guide lean software,
but the skill is designed for research, business decisions, life
choices, and any task that starts fuzzy and needs to land at a
third-party-verifiable spec (`requirements.md` +
`acceptance-criteria.md`). One worked non-software example ships at
`skill/examples/example-non-software-session.md`.

## 2. Install in detail

### 2.1 The curl one-liner (recommended)

```bash
curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

This downloads `get.sh` from the project's GitHub Pages site, pipes it
to `sh`, and the bootstrap script:

1. Detects your OS (`Darwin` / `Linux` / `FreeBSD` accepted; native
   Windows is rejected with a pointer to WSL).
2. Resolves the install root (`PENSEES_HOME`, default
   `$HOME/.local/share/pensees`).
3. Resolves the version (`PENSEES_VERSION`, default `latest` — looks up
   the latest release tag via the GitHub releases API).
4. Downloads the tarball, verifies size ≥ 1024 bytes, extracts into a
   staging dir, then atomically swaps `PENSEES_HOME/current` to point at
   the new release (any prior install is backed up under
   `PENSEES_HOME/.bak.<unix-ts>/`).
5. `cd`s into `PENSEES_HOME/current` and runs `./install.sh "$@"`,
   forwarding any extra args you passed through.
6. Prints a success summary and exits 0.

Re-running with the same `PENSEES_VERSION` is a no-op (idempotent):
`get.sh` detects the existing install and prints `[skip] already at
<TAG>`. Re-running with a different version performs an upgrade and
leaves exactly one backup directory behind.

### 2.2 `get.sh` environment variables

| Variable | Default | What it does | For users? |
|---|---|---|---|
| `PENSEES_HOME` | `$HOME/.local/share/pensees` | Install root for the source tree | yes |
| `PENSEES_VERSION` | `latest` | Release tag, or `latest`, or `main` for tip-of-tree | yes |
| `PENSEES_VERBOSE` | `0` | If `1`, runs `set -x` for debugging | yes |
| `PENSEES_REPO` | `YoRHa-Agents/Pensees` | Override the GitHub `org/repo` | testing only |
| `PENSEES_DOWNLOAD_URL_BASE` | (unset) | Override the tarball host + path prefix | testing only |
| `PENSEES_API_URL_BASE` | (GitHub releases API host) | Override the latest-release API host | testing only |
| `PENSEES_NO_INSTALL` | `0` | If `1`, extract only — skip the call to `install.sh` | testing only |

The most useful one in normal operation is `PENSEES_VERSION`. Pin it for
reproducible installs:

```bash
PENSEES_VERSION=v0.3.0 curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

Or follow tip-of-tree on `main`:

```bash
PENSEES_VERSION=main curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

### 2.3 `get.sh` exit codes

| Code | Meaning |
|---|---|
| 0 | success (or idempotent skip) |
| 1 | uncaught / generic (should be unreachable) |
| 2 | unrecognized argument |
| 3 | unsupported platform (e.g. native Windows — use WSL) |
| 4 | a required tool is missing on PATH (`curl` / `tar` / `mkdir` / `mv` / `rm` / `uname`) |
| 5 | the latest-release API lookup failed (retry, or pin `PENSEES_VERSION`) |
| 6 | tarball download failed or empty |
| 7 | tarball extract failed (corrupted / unexpected layout) |
| 9 | backup of the previous install failed (check write perms on `PENSEES_HOME`) |
| 10+ | `install.sh`'s own exit code, forwarded verbatim |

No code is silently swallowed; every failure prints an explicit error
line to stderr naming what failed (AGENTS.md §2 "No silent failures").

### 2.4 `install.sh` flags (used by both the curl path and `git clone`)

The bootstrap calls `install.sh` with whatever arguments you forwarded
via `sh -s --`. The same flags work if you run `./install.sh` directly
after `git clone`:

```bash
./install.sh                       # symlink ./skill into all 3 default targets
./install.sh --target=cursor       # one target only (cursor|claude|codex)
./install.sh --target cursor       # space-separated form, equivalent
./install.sh --workspace PATH      # symlink under PATH instead of $HOME
./install.sh --copy                # copy instead of symlink (sandbox-friendly)
./install.sh --uninstall           # remove (refuses to delete unrelated paths)
./install.sh --dry-run             # print the plan, do nothing
./install.sh --help                # print this header
```

The three default symlink destinations are:

- Cursor — `$HOME/.cursor/skills-cursor/pensees`
- Claude Code — `$HOME/.claude/skills/pensees`
- Codex CLI — `$HOME/.codex/skills/pensees`

`install.sh --uninstall` only removes paths it can verify are Pensees
installs (matching symlink target, or a directory whose `SKILL.md` has
`name: pensees`). It refuses to touch unrelated paths, even if you
named them. This is intentional — there is no silent destruction.

### 2.5 Manual symlink fallback

If neither the curl path nor `install.sh` fits your sandbox, link the
skill directory yourself:

```bash
ln -s "$PWD/skill" ~/.claude/skills/pensees
ln -s "$PWD/skill" ~/.cursor/skills-cursor/pensees
ln -s "$PWD/skill" ~/.codex/skills/pensees
```

Some Cursor setups expect the path `~/.cursor/skills/pensees` (no
`-cursor` suffix). If autoload fails after install, add that link too.

## 3. Opening turn behavior

The first agent turn after Pensees loads MUST contain three elements
(F-02 contracting move):

1. **Preset declaration**: `I'm running in **Exploratory** mode by default.`
2. **Switch hints**: mention both `**Challenge**` and `**Convergence**`
   by name once each, with at least one switch phrase listed (see §5).
3. **One question**: ends with exactly one `?`, targeted at a specific
   ambiguity in the user's message — never a generic "what would you
   like to do?".

A canonical opening turn:

> I'm running in **Exploratory** mode by default. Switch with
> `挑战这个` (Challenge — tightens the critique) or
> `让我们收敛` / `let's converge` (Convergence — locks choices in).
> Say `慢一点, 重述` anytime to slow down.
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

The `<!-- ambiguity-tag: ... -->` comment is part of F-09 (see §4); it
is reviewer-only and does not render in chat.

## 4. Core dialogue rules

### 4.1 F-07 — one question at a time

Every agent turn ends with at most one `?`. Multiple-choice options
`(a)/(b)/(c)/(d)/(e)` count as one structured question, not five. Pensees
never batch-dumps several open questions in a single turn (AR-09). If
the agent feels pressure to ask several things, it should pick the one
with the highest information value and ask only that one.

### 4.2 F-08 — escape hatch

Every multiple-choice question must include
`(d) 都不是, 让我描述` (or the English equivalent
`(d) none of these, let me describe`). Two consecutive `(d)` selections
trigger an automatic preset check — the agent will ask whether to switch
out of Exploratory into Challenge or Convergence, because two
"none-of-these" usually signals the option space itself is wrong.

### 4.3 F-31 — option detail probe

Every multi-choice question also carries
`(e) 我想先详细听 (X) 这个选项再决定`. When the user picks `(e) X`, the
agent's next turn must contain four bold subsections in this exact
order:

- **后果** — what happens if you pick X
- **对比** — how X differs from the other options
- **场景** — when X wins vs. when it loses
- **未知** — what we still don't know about X

The detail turn caps at ~350 chars total. After it, the agent re-emits
the original question with `(f) 已了解 (X), 再问 (Y)` appended so the
question tree continues from where it paused. The reference is
`skill/references/question-forms.md`.

### 4.4 F-09 — ambiguity tags

When the agent identifies an ambiguity in the user's turn, it appends an
HTML comment at the end of its own turn:

```
<!-- ambiguity-tag: linguistic|intent|contextual|epistemic|interactional -->
```

The tag is reviewer-only (invisible in rendered chat) and required, not
optional. The 5 dimensions are documented in
`skill/references/ambiguity-taxonomy.md`. The same dimension may not
appear ≥ 3 turns in a row; if it does, the agent switches dimension or
calls F-13 (fuzzy-term sharpening).

### 4.5 F-10 — experience ontology

After turn 2 the agent writes a lightweight
`.local/pensees/{date}-{slug}/ontology.yaml` mapping
`aspect → dimension → slot`. The file caps at ~50 lines. Subsequent
questions are driven by the empty / fuzziest slots in the ontology, not
free-form. The schema lives in `skill/references/ontology-schema.md`.

### 4.6 F-13 — fuzzy-term sharpening

When the user uses the same word ≥ 2 times in different senses, the
agent pauses and proposes a canonical definition:

> I notice you've said "X" in different senses. Propose to define it as
> Y (because ...). Does that match, or do you want to sharpen it?

This is how Pensees prevents a word like "cache", "user", or "MVP" from
silently drifting between turns.

### 4.7 F-11 — under-clarification counter

The default is "ask one more round". If the agent wants to stop asking
and propose convergence early, the stopping turn must cite ≥ 2 concrete
evidence items (e.g. "ontology has 8 slots, 7 filled"; "user expressed
satisfaction 3 turns in a row"). No vibes-based "I think we're done".

## 5. Presets and switch phrases

| Preset | When it wins | Switch phrases (ZH) | Switch phrases (EN) |
|---|---|---|---|
| **Exploratory** (default) | User said "I'm not sure yet" or used ≥ 2 fuzzy words | `让我们探索` / `我还没想清楚` | `let's explore` / `i'm not sure yet` |
| **Challenge** | A near-final proposal exists; user wants stress-test | `挑战这个` / `戳一下漏洞` / `pre-mortem` | `push back` / `challenge this` / `pre-mortem` |
| **Convergence** | 5–6 of 7 checklist rows already ✅ | `让我们收敛` / `锁一下` / `把它写下来` | `let's converge` / `lock this` / `write this down` |
| universal sub-primitive | Any preset, any turn | `慢一点, 重述` | `slow down, restate` |

When a switch phrase appears in the user's last message, the agent
opens the next turn with the word `switch` (or `切换`) and the target
preset's name, then adjusts question form and fatigue level per
`skill/references/styles.md`. The universal `慢一点, 重述` does not
change the preset — it just triggers one Reflective turn that restates
the user's last substantive message in the agent's own words and asks
a confirmation question.

## 6. HTML demos

### 6.1 When the agent emits a demo (F-18)

A demo is **a form of question**, not decoration. The agent emits when
at least one of these four conditions holds:

1. The user used a fuzzy word and ≥ 2 rounds of text clarification have
   already failed.
2. A conflict requires a trade-off.
3. The user explicitly asked for a sketch / mockup.
4. One ontology slot maps to ≥ 2 plausible interpretations.

### 6.2 4 candidate forms (F-17)

The agent picks one (or mixes two) of these four forms per emit. Each
template is at `skill/templates/demo-*.html`.

| Form | When it wins |
|---|---|
| `decision-matrix` | Trade-offs across ≥ 2 options on ≥ 2 axes |
| `mockup` | Visual layout / placement decision |
| `explorable` | Behaviour depends on parameters the user can tweak |
| `forced-choice` | A vs. B, decide which side wins on the named axis |

Selection logic lives in `skill/references/demo-decision-tree.md`. Each
file's `<head>` must include `<meta name="pensees-candidate"
content="<form>">`.

### 6.3 2–3 variants per emit (F-16)

Always produce 2 or 3 variant files, never just 1. A single demo is a
rabbit-hole risk. The variant difference axis (density / aesthetic /
decision-structure / emphasis) must be named in the agent turn that
ships the demo.

### 6.4 F-15 — single-file HTML, offline-double-clickable

Every variant is a single `.html` file with inline `<style>` and inline
`<script>`. No `http://` / `https://` external resources, no CDN fonts,
no `fetch()`, no `<iframe src="https:...">`. A demo file must open
correctly when double-clicked from the file manager with no network.
This is enforced by `tests/lint-templates.sh` and
`tests/lint-references.sh`.

### 6.5 F-19 — visibly-rough aesthetic

Demos use a cursive / handwriting font family (Caveat → Comic Neue →
cursive fallback), 1.5–2 px dashed border, a top banner
`DRAFT — please critique`, and at least one `<!-- TODO -->` comment.
No rounded corners ≥ 8 px, no shadow blur ≥ 8 px, no full-page
gradient. The aesthetic intentionally signals "this is not finished" so
the user is invited to push back. Full spec lives in
`skill/references/demo-decision-tree.md` §visibly-rough.

### 6.6 F-20 / F-21 / F-22 — anchor, question, path

- **F-20 anchor**: first line of each demo file is a comment
  `<!-- pensees-anchor: session={slug}; turn={N}; user_quote="{≤80 chars}" -->`.
- **F-21 demo as question**: the agent turn that ships a demo must
  contain a comparative question with one `?` and an explicit escape
  hatch.
- **F-22 path**: files land at
  `.local/pensees/{YYYY-MM-DD}-{slug}/demos/NN-{topic}-A.html` (and
  `-B.html`, optionally `-C.html`).

For a live render of a real demo session, see the embedded iframe on
<https://yorha-agents.github.io/Pensees/demo.html>.

## 7. Local preview server

After any demo emit, the agent asks:

> Run a local HTTP port to view this? (y = yes · **N default** =
> file:// only · s = LAN-share · p = custom port)

The protocol (F-30):

- **`y`** — Probe ports 8765..8775 on `127.0.0.1`, take the first free
  one, run `python3 -m http.server <port> --bind 127.0.0.1 --directory
  <session>/demos/`. The PID is written to `<session>/.server.pid`.
- **`N` (default)** — Do nothing; `file://` open the demo HTML directly.
- **`s` (LAN-share)** — Same as `y` but binds `0.0.0.0`. Pensees first
  shows an explicit warning and requires a second `y` confirmation
  before binding to anything other than loopback.
- **`p` (custom port)** — Asks for a port in `1024..65535`.

If `python3` is not on PATH, Pensees **fails loudly** with the exact
message `no python3 available; please use file:// path instead`. It
does NOT silently fall back to `node`, `netcat`, or anything else
(AGENTS.md §2 — no silent failures).

Stop conditions (any one ends the server):

- User says `stop server` / `停掉端口`.
- The session ends (normal close).
- Emergency stop fires (see §9.5).

On stop: `kill $(cat .server.pid) && rm .server.pid`.

## 8. Convergence and delivery

### 8.1 The 7-row checklist (C-01..C-07)

After each turn the agent updates
`.local/pensees/{date}-{slug}/checklist-status.md`, marking each row
`✅` / `⚠️` / `❌` with a one-sentence evidence pointer. The 7 rows are:

| # | Row | Pass criterion (one-line) |
|---|---|---|
| C-01 | Key terms defined | every recognized ontology slot has a non-empty `definition:` ≥ 5 chars |
| C-02 | Scope boundary explicit | running draft of `requirements.md` §5 has ≥ 5 anti-requirement rows |
| C-03 | Acceptance criteria are independently verifiable | draft `acceptance-criteria.md` has zero subjective words (`should be good` / `更好` / `nice to have` / ...) |
| C-04 | ≥ 2–3 alternatives considered with explicit trade-offs | at least one demo emit group (≥ 2 variants) exists AND user stated a preference |
| C-05 | Who / how / not-for explicit | `requirements.md` §1 has ≥ 1 sentence each for target user, typical use, and out-of-scope audience |
| C-06 | ≥ 1 demo seen by user with specific feedback | transcript shows the user comparing variants on a named axis, not "looks good" |
| C-07 | Risks / assumptions listed | `requirements.md` has a section with the keywords `risk` / `assumption` / `dependency` (or `风险` / `假设` / `依赖`) with ≥ 2 items |

The full rubric is in `skill/references/checklist-rubric.md`.

### 8.2 HARD-GATE (F-14)

The agent will not create any file under
`.local/pensees/{date}-{slug}/outputs/` until BOTH:

1. All 7 checklist rows are `✅`.
2. After the agent proposes convergence, the user replies with an
   explicit approval token: `可以` / `go` / `yes` / `ok`.

If the user vetoes (`还没准备好` / `not yet` / `再想想 X`), the agent
stays silent on convergence for at least 3 agent turns before proposing
again (F-25 — no nagging).

On approval, the agent generates:

- `.local/pensees/{date}-{slug}/outputs/requirements.md`
- `.local/pensees/{date}-{slug}/outputs/acceptance-criteria.md`

…from `skill/templates/requirements.template.md` and
`skill/templates/acceptance-criteria.template.md`. A one-line entry is
appended to `.local/pensees/INDEX.md`:

```
| {YYYY-MM-DD} | {slug} | {title ≤ 30 chars} | completed |
```

### 8.3 Handoff (AR-04)

Each deliverable ends with a short "downstream suggestion" paragraph
(≤ 100 chars). Examples:

> 若用 OpenSpec: `openspec import outputs/requirements.md`.

Pensees **never** automatically transitions to another skill
(writing-plans, openspec, spec-kit). The user decides the next step.
This is non-negotiable (AR-04).

## 9. Per-host quirks, troubleshooting, emergency stop

### 9.1 Cursor

- Default install path: `~/.cursor/skills-cursor/pensees`.
- Some Cursor builds expect `~/.cursor/skills/pensees` (no `-cursor`
  suffix). If autoload fails, add the second link manually.
- Cursor autoloads when the trigger phrase appears in the user message;
  the assistant should declare the Exploratory preset and ask one
  question in its first turn (§3).
- Cursor's "skills" panel UI may not list the skill until you reopen the
  chat tab after install.

### 9.2 Claude Code

- Default install path: `~/.claude/skills/pensees`.
- Claude Code reads the YAML frontmatter from `SKILL.md`; if you edit
  the trigger phrase list locally, restart Claude Code so the new
  frontmatter is picked up.
- The `description:` field is capped at 1024 characters by the host;
  the shipped value is well under that limit.

### 9.3 Codex CLI

- Default install path: `~/.codex/skills/pensees`.
- Codex CLI behaves similarly to Claude Code with respect to YAML
  frontmatter. A skill that does not parse will be silently skipped on
  load — see `tests/lint-frontmatter.sh` for the precondition checks.

### 9.4 Troubleshooting (deep)

| Symptom | Likely cause | Fix |
|---|---|---|
| Curl install fails with exit 4 | A required tool (`curl` / `tar` / `mkdir` / `mv` / `rm` / `uname`) is missing on PATH | Install the named tool; on minimal containers, `apk add tar` / `apt-get install tar` |
| Curl install fails with exit 5 | The latest-release API lookup failed (rate-limited or transient) | Retry, or pin `PENSEES_VERSION=v0.3.0` to skip the API call |
| Curl install fails with exit 6 | Tarball returned 404 or 0 bytes | Verify the tag exists in the GitHub releases list; double-check `PENSEES_VERSION` for typos |
| `install.sh` errors with exit 3 | A target path exists but is not a Pensees symlink | Either run with `--copy` to overwrite, or `rm` the conflicting path first |
| Host agent does not pick up the skill | Trigger phrase missing from the message, or autoload requires a reopened tab | Send a message with one of the trigger phrases in §1; reopen the chat tab |
| `python3` missing for local preview | F-30 requires `python3` on PATH | Install `python3`, or stay on `N`-default and open the demo via `file://` |
| Pensees writes outside `.local/pensees/` | This should never happen | Run `tests/lint-skill.sh` and `tests/lint-frontmatter.sh`; file an issue with the transcript |

### 9.5 Emergency stop (F-29)

If the user message contains any of `销毁本会话` / `forget this` /
`wipe session` (case-insensitive), then within 2 seconds the agent:

1. Halts all in-flight tool calls.
2. `rm -rf .local/pensees/{date}-{slug}/`.
3. Removes the session's row from `.local/pensees/INDEX.md` if present.
4. Appends to `.local/pensees/.audit/destruction.log`:
   `[YYYY-MM-DD HH:MM:SS] session {date}-{slug} DESTROYED by phrase "{X}" — content not retained`.
5. Replies:
   `Session destroyed; audit recorded in .audit/destruction.log (fact only, no content).`

The audit log records the destruction fact only — never any session
content. There is no "undo" once emergency stop has fired.

## 10. Read next

- The 5-minute version of this guide:
  [QUICK_GUIDE.md](QUICK_GUIDE.md).
- 中文版本（同一份用户指南的中文表达）:
  [USER_GUIDE.zh.md](USER_GUIDE.zh.md).
- The behavior contract (single source of truth, F-numbers and rules
  verbatim): [skill/SKILL.md](../skill/SKILL.md).
- Live demo, day/night toggle, ZH/EN toggle on the project site:
  <https://yorha-agents.github.io/Pensees/>.
- Back to the project [README.md](../README.md).
