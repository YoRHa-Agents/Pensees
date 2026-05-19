# Pensees

Pensees is a domain-neutral skill package that helps a host agent (Cursor /
Claude Code / Codex CLI) walk a user from "a fuzzy idea" to "a
third-party-verifiable spec" through one-question-at-a-time dialogue plus
on-demand 2–3 variant single-file HTML demos. Pensees holds no inference API
keys; the host agent does the thinking, Pensees holds the contract and the
templates.

The skill is invoked manually — say "pensees", "帮我想清楚", "clarify
requirements", or one of the trigger phrases listed in `skill/SKILL.md`. It
does not autoload for routine planning.

## Behavior preview

| # | Status-quo chat | Pensees |
|---|---|---|
| V-01 | "Design X for me" → immediate plan dump | Detects fuzzy words → asks one structured question first |
| V-02 | Bundles 3–5 questions per turn | Strict one-question-at-a-time |
| V-03 | After ~5 turns, summarizes and ships | Stays in dialogue until 7-row checklist is green AND user explicitly approves |

## Quick start

```bash
git clone <this-repo> pensees
cd pensees
./install.sh                  # symlinks ./skill into all 3 default target dirs
```

After install, open Cursor / Claude Code / Codex CLI and send a message
containing one of the trigger phrases (`pensees`, `帮我想清楚`, ...).

### Other install modes

```bash
./install.sh --dry-run                       # show the plan, do nothing
./install.sh --target=claude                 # single-target only
./install.sh --workspace ~/my-side-project   # install to a non-$HOME root
./install.sh --copy                          # copy instead of symlink
./install.sh --uninstall                     # remove (refuses unrelated paths)
```

### Manual fallback (if `install.sh` does not fit your setup)

```bash
ln -s "$PWD/skill" ~/.claude/skills/pensees
ln -s "$PWD/skill" ~/.cursor/skills-cursor/pensees
ln -s "$PWD/skill" ~/.codex/skills/pensees
```

### Troubleshooting

- **Cursor does not autoload after install.** Some Cursor setups expect
  the path `~/.cursor/skills/pensees` (no `-cursor` suffix). If autoload
  fails, also create that link:
  `ln -s "$PWD/skill" ~/.cursor/skills/pensees`.
- **No agent picks it up at all.** Confirm the trigger phrase made it
  into the message — Pensees is intentionally non-greedy and will not
  load for generic "plan / brainstorm / help" without the trigger word.
- **Local preview server fails.** Pensees needs `python3` on PATH for the
  optional `8765`-port preview (F-30). If `python3` is missing, the
  skill explicitly refuses to silently fall back; open the HTML file via
  `file://` instead.

## What ships in `skill/`

```
skill/
├── SKILL.md                  # 246-line behavior contract (the entrypoint)
├── references/               # lazy-loaded — agent reads only what it needs
│   ├── styles.md
│   ├── ambiguity-taxonomy.md
│   ├── question-forms.md
│   ├── demo-decision-tree.md
│   ├── checklist-rubric.md
│   ├── methods.csv
│   └── ontology-schema.md
├── templates/
│   ├── demo-decision-matrix.html
│   ├── demo-mockup.html
│   ├── demo-explorable.html
│   ├── demo-forced-choice.html
│   ├── requirements.template.md
│   └── acceptance-criteria.template.md
└── examples/
    └── example-non-software-session.md
```

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
