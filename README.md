# Pensees

A skill that walks one fuzzy idea into one verifiable spec, one question at a time.

Pensees 是一个领域中性的"想法澄清"技能包。中文用户请看 [docs/QUICK_GUIDE.zh.md](docs/QUICK_GUIDE.zh.md)。

Pensees is a domain-neutral skill package that helps a host agent (Cursor /
Claude Code / Codex CLI) walk a user from "a fuzzy idea" to "a
third-party-verifiable spec" through one-question-at-a-time dialogue plus
on-demand 2–3 variant single-file HTML demos. Pensees holds no inference API
keys; the host agent does the thinking, Pensees holds the contract and the
templates.

## Install

```bash
curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

After install, open Cursor / Claude Code / Codex CLI and send a message
containing one of the trigger phrases (`pensees`, `帮我想清楚`, ...). The
skill is invoked manually — it does not autoload for routine planning.

Verify:

```bash
ls "$HOME/.cursor/skills-cursor/pensees"
```

<details>
<summary>Install via <code>git clone</code> (existing path, fully supported)</summary>

```bash
git clone https://github.com/YoRHa-Agents/Pensees pensees
cd pensees
./install.sh                  # symlinks ./skill into all 3 default target dirs
```

Other install modes:

```bash
./install.sh --dry-run                       # show the plan, do nothing
./install.sh --target=claude                 # single-target only (cursor|claude|codex)
./install.sh --workspace ~/my-side-project   # install under a non-$HOME root
./install.sh --copy                          # copy instead of symlink
./install.sh --uninstall                     # remove (refuses unrelated paths)
```

</details>

<details>
<summary>Manual symlink fallback (if <code>install.sh</code> does not fit your setup)</summary>

```bash
ln -s "$PWD/skill" ~/.claude/skills/pensees
ln -s "$PWD/skill" ~/.cursor/skills-cursor/pensees
ln -s "$PWD/skill" ~/.codex/skills/pensees
```

Some Cursor setups expect the path `~/.cursor/skills/pensees` (no `-cursor`
suffix). If autoload fails, also create that link:
`ln -s "$PWD/skill" ~/.cursor/skills/pensees`.

</details>

## What is Pensees

The skill is invoked manually — say `pensees`, `帮我想清楚`,
`clarify requirements`, `做需求澄清`, `理一下需求`, or one of the trigger
phrases listed in `skill/SKILL.md`. Pensees is intentionally non-greedy:
without one of those phrases it stays asleep. It runs one-question-at-a-time
multi-turn dialogue plus on-demand 2–3 variant single-file HTML demos, and
produces exactly two deliverables per session (`requirements.md` and
`acceptance-criteria.md`) only after the user explicitly approves
convergence.

| # | Status-quo chat | Pensees |
|---|---|---|
| V-01 | "Design X for me" → immediate plan dump | Detects fuzzy words → asks one structured question first |
| V-02 | Bundles 3–5 questions per turn | Strict one-question-at-a-time |
| V-03 | After ~5 turns, summarizes and ships | Stays in dialogue until 7-row checklist is green AND user explicitly approves |

## See it in action

- Public site (NieR-themed; day/night and ZH/EN toggles persist per visitor):
  <https://yorha-agents.github.io/Pensees/>
- 5-minute orientation: [docs/QUICK_GUIDE.md](docs/QUICK_GUIDE.md)
  (中文: [docs/QUICK_GUIDE.zh.md](docs/QUICK_GUIDE.zh.md))
- Deeper walkthrough: [docs/USER_GUIDE.md](docs/USER_GUIDE.md)
  (中文: [docs/USER_GUIDE.zh.md](docs/USER_GUIDE.zh.md))

## Where session output lands

Inside the user's repo (or wherever the host agent is rooted):

```
.local/pensees/{YYYY-MM-DD}-{slug}/
├── transcript.md
├── ontology.yaml
├── checklist-status.md
├── demos/        # 2–3 variant HTML files per emit
└── outputs/      # generated only after the user approves convergence
    ├── requirements.md
    └── acceptance-criteria.md
```

Pensees writes ONLY to `.local/pensees/**` and never touches the host
repo (`skill/`, `README.md`, etc.). See `skill/SKILL.md` §8 for the full
write-path whitelist.

## Privacy and provenance

- No telemetry. No API calls outbound. No keys.
- Emergency stop: say `销毁本会话` / `forget this` / `wipe session` and
  Pensees deletes the session directory within 2 seconds. An audit line
  recording the destruction fact (no content) lands in
  `.local/pensees/.audit/destruction.log`.

## Running the tests

```bash
./tests/run.sh
```

The static gate now covers **6 hard gates fully + 4 partial = effectively
8 / 13** from `acceptance-criteria.md` (was 7 / 13, then 9 / 13, then 9.5 / 13).
"Effectively 8" is a stricter accounting than "9.5": HG-01, HG-02, HG-03,
and HG-06 each contribute their static preconditions but their full end-to-end
verification still needs a real host-agent session. We score each as 0.5.
`lint-skill` + `lint-templates` + `lint-frontmatter` + `lint-references` +
`smoke-install` cover HG-05, the HG-06 static subset (across templates AND
reference code blocks), the HG-01..HG-03 autoload preconditions, and
HG-08..HG-13. Three fixture-based lints extend the coverage:

- `lint-transcript` parses `skill/examples/example-non-software-session.md`
  and asserts every agent turn has at most one sentence-ending `?` —
  a static proxy for HG-07 (the worked example itself must not contradict
  the rule).
- `lint-deliverable-templates` asserts the two deliverable templates are
  substantive (≥ 60 non-blank lines, ≥ 4 H2 headings) and that
  `acceptance-criteria.template.md` reads standalone (no `见 requirements`
  / `see requirements.md` cross-refs, AP-12) — readiness proxy for HG-04.
- `lint-frontmatter` parses `skill/SKILL.md`'s YAML frontmatter (with
  PyYAML when available, falling back to an awk structural parser — no
  silent fallback) and asserts: name == `pensees`, description present +
  ≤ 1024 chars, ≥ 2 zh + ≥ 2 en trigger phrases present, no autoload-
  inducing phrases. Malformed frontmatter is the most common failure mode
  for HG-01..HG-03 — none of the three host agents will autoload a skill
  whose frontmatter does not parse.

`lint-templates` enumerates every F-15-forbidden network-egress pattern
inside the demo HTML templates (`fetch(`, `XMLHttpRequest`,
`new WebSocket(`, `new EventSource(`, `navigator.sendBeacon`, single-quoted
`src='http`/`href='http`/`@import url('http`, CSS `url(http...)` outside
`@import`, ES module `import ... from 'http`, and external
`<iframe>`/`<embed>`/`<object>`). `lint-references` re-runs the same
patterns inside any `html` / `js` / `javascript` / `ts` / `typescript` /
`css` code blocks found in `skill/references/*.md` and `skill/examples/*.md`,
so a regression that smuggles a forbidden pattern into a teaching example
is caught too. `test-lint-templates` is the meta-test that proves the
`lint-templates` regex is still functional: it injects each forbidden
pattern into a temp copy and asserts the lint exits non-zero with the
right sub-check named in the FAIL line.

The remaining gaps (full end-to-end HG-01..HG-03 host-agent autoload plus
the full runtime no-network smoke for HG-06) still require a real session
in Cursor / Claude Code / Codex CLI and must be smoke-tested manually
after install. CI runs the full `tests/run.sh` gate on every push and PR
to `main` via `.github/workflows/test.yml` (ubuntu-latest, pure-bash, no
language toolchain beyond what the runner ships).

## License

MIT. See [LICENSE](./LICENSE). Portions of `skill/references/methods.csv`
are derived from [BMAD-METHOD](https://github.com/bmadcode/BMAD-METHOD)
(also MIT) and are tagged in the CSV header.
