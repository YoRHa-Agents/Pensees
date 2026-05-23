#!/usr/bin/env python3
# No network egress: pure-stdlib + pyyaml; offline-only.
"""Offline reviewer CLI for Pensees v0.3.2 Lite (S02-W01-T02).

Renders ``<session_dir>/review.md`` from ``<session_dir>/turns.jsonl`` plus
the optional siblings ``ontology.yaml``, ``checklist-status.md``, and
per-session tuning override ``.config.yaml``.

See:
  * ``skill/references/intermediate-result-schema.md`` — per-turn record shape.
  * ``skill/references/composite-signals.md`` — the 7 base signals + the 2
    composites + threshold/weight defaults + the tuning hook.
  * ``skill/templates/review-report.template.md`` — the 19 placeholders this
    CLI fills (plain ``str.replace`` substitution, no Jinja).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import textwrap
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Optional, Sequence

import yaml

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCHEMA_VERSION = "0.3.2-lite"
REVIEWER_VERSION = f"pensees-review v{SCHEMA_VERSION}"

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATE_PATH = REPO_ROOT / "skill" / "templates" / "review-report.template.md"

PREMATURE_SIGNALS: tuple[str, ...] = (
    "slot_focus_imbalance",
    "e_probe_over_use",
    "question_form_jump",
)
DEAD_END_SIGNALS: tuple[str, ...] = (
    "amnesia",
    "dimension_repetition",
    "frame_collapse",
    "checklist_regression",
)
ALL_SIGNALS: tuple[str, ...] = PREMATURE_SIGNALS + DEAD_END_SIGNALS
SIGNAL_GROUP: Mapping[str, str] = {
    **{s: "premature" for s in PREMATURE_SIGNALS},
    **{s: "dead-end" for s in DEAD_END_SIGNALS},
}

HIGH_RES_FORMS: frozenset[str] = frozenset({"decision-matrix", "forced-choice"})
CHECKLIST_ROWS: tuple[str, ...] = ("C-01", "C-02", "C-03", "C-04", "C-05", "C-06", "C-07")
CHECKLIST_ORDER: Mapping[str, int] = {"❌": 0, "⚠️": 1, "✅": 2}
REGRESSION_CAP = 8.0
QUESTION_FORM_JUMP_PEAK = 0.95

WEIGHT_SUM_LO = 0.99
WEIGHT_SUM_HI = 1.01

EXIT_OK = 0
EXIT_GENERIC = 1
EXIT_MISSING_TURNS = 2
EXIT_EMPTY_TURNS = 3
EXIT_MALFORMED_TURNS = 4
EXIT_BAD_CONFIG = 5

PLACEHOLDER_NAMES: tuple[str, ...] = (
    "SESSION_SLUG",
    "SESSION_DATE",
    "REVIEWER_VERSION",
    "TURN_COUNT",
    "GENERATED_AT_ISO",
    "PREMATURE_MAX",
    "PREMATURE_MEAN",
    "PREMATURE_THRESHOLD",
    "DEAD_END_MAX",
    "DEAD_END_MEAN",
    "DEAD_END_THRESHOLD",
    "TURN_SCORE_CHART",
    "FLAGGED_TURNS_LIST",
    "TOP_SIGNALS_TABLE",
    "VERDICT",
    "VERDICT_RATIONALE",
    "RECOMMENDATIONS_LIST",
    "TURNS_JSONL_PATH",
    "SCHEMA_VERSION",
)

SESSION_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})(?:-(.+))?$")


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Turn:
    """A single record from ``turns.jsonl`` (Lite shape)."""

    turn_id: int
    schema_version: str
    timestamp: Optional[str]
    agent_or_user: str
    dimension: Optional[str]
    preset: Optional[str]
    slots_touched: tuple[str, ...]
    e_probe_target: Optional[str]
    question_form: Optional[str]
    ambiguity_tag: Optional[str]
    checklist_state: Mapping[str, str]
    composite_premature: Optional[float]
    composite_dead_end: Optional[float]


@dataclass(frozen=True)
class OntologySlot:
    name: str
    status: str
    turn_first: Optional[int]
    turn_last: Optional[int]
    aspect: str


@dataclass(frozen=True)
class OntologySnapshot:
    """Flattened view of ``ontology.yaml`` for scorer consumption."""

    slots: tuple[OntologySlot, ...]

    def open_slots_excluding(self, focal: str) -> int:
        return sum(1 for s in self.slots if s.status == "open" and s.name != focal)

    def filled_aspects(self) -> int:
        by_aspect: dict[str, list[OntologySlot]] = {}
        for s in self.slots:
            by_aspect.setdefault(s.aspect, []).append(s)
        return sum(
            1
            for slots in by_aspect.values()
            if any(s.status == "filled" for s in slots)
        )

    def slot_status(self, name: str) -> Optional[str]:
        for s in self.slots:
            if s.name == name:
                return s.status
        return None

    def slot(self, name: str) -> Optional[OntologySlot]:
        for s in self.slots:
            if s.name == name:
                return s
        return None


@dataclass(frozen=True)
class ScoringConfig:
    """Thresholds + weights for both composites (defaults from
    ``composite-signals.md`` §Defaults; per-session override merged from
    ``<session_dir>/.config.yaml``)."""

    premature_threshold: float
    premature_weights: Mapping[str, float]
    dead_end_threshold: float
    dead_end_weights: Mapping[str, float]


# ---------------------------------------------------------------------------
# Logging helpers (stderr; per AGENTS.md §"No Silent Failures")
# ---------------------------------------------------------------------------


class MalformedJsonl(Exception):
    def __init__(self, line_no: int, message: str) -> None:
        super().__init__(message)
        self.line_no = line_no
        self.message = message


class ConfigError(Exception):
    """Raised when ``.config.yaml`` overrides violate the documented invariants."""


def warn(message: str) -> None:
    print(f"warning: {message}", file=sys.stderr)


def error(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------


def load_template() -> str:
    return TEMPLATE_PATH.read_text(encoding="utf-8")


def load_turns(path: Path) -> list[Turn]:
    turns: list[Turn] = []
    with path.open("r", encoding="utf-8") as fh:
        for idx, raw in enumerate(fh, start=1):
            line = raw.strip()
            if not line:
                # Tolerate blank lines (trailing newline at EOF is common).
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise MalformedJsonl(idx, f"JSON parse error: {exc.msg}") from None
            if not isinstance(record, dict):
                raise MalformedJsonl(idx, "record is not a JSON object")
            turns.append(_parse_turn(record, idx))
    return turns


def _parse_turn(record: Mapping[str, Any], line_no: int) -> Turn:
    if "turn_id" not in record:
        raise MalformedJsonl(line_no, "missing required field 'turn_id'")
    try:
        turn_id = int(record["turn_id"])
    except (TypeError, ValueError):
        raise MalformedJsonl(
            line_no, f"turn_id must be int-like, got {record['turn_id']!r}"
        ) from None

    schema_version = str(record.get("schema_version") or "")
    agent_or_user = str(record.get("agent_or_user") or "")

    slots_raw = record.get("slots_touched") or []
    if not isinstance(slots_raw, list):
        raise MalformedJsonl(line_no, "slots_touched must be a list")
    slots_touched = tuple(str(s) for s in slots_raw)

    checklist_raw = record.get("checklist_state") or {}
    if not isinstance(checklist_raw, dict):
        raise MalformedJsonl(line_no, "checklist_state must be an object")
    checklist_state: dict[str, str] = {str(k): str(v) for k, v in checklist_raw.items()}

    def _opt_float(key: str) -> Optional[float]:
        v = record.get(key)
        if v is None:
            return None
        try:
            return float(v)
        except (TypeError, ValueError):
            raise MalformedJsonl(
                line_no, f"{key} must be a number, got {v!r}"
            ) from None

    def _opt_str(key: str) -> Optional[str]:
        v = record.get(key)
        return None if v is None else str(v)

    return Turn(
        turn_id=turn_id,
        schema_version=schema_version,
        timestamp=_opt_str("timestamp"),
        agent_or_user=agent_or_user,
        dimension=_opt_str("dimension"),
        preset=_opt_str("preset"),
        slots_touched=slots_touched,
        e_probe_target=_opt_str("e_probe_target"),
        question_form=_opt_str("question_form"),
        ambiguity_tag=_opt_str("ambiguity_tag"),
        checklist_state=checklist_state,
        composite_premature=_opt_float("composite_premature"),
        composite_dead_end=_opt_float("composite_dead_end"),
    )


def load_ontology(path: Path) -> Optional[OntologySnapshot]:
    # Loud-not-silent: a malformed ontology becomes "ontology absent" with a
    # stderr WARN and a report-side annotation, never silently scored as if
    # everything were fine.
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        warn(f"ontology.yaml parse failed ({exc}); treating as absent")
        return None
    if not isinstance(data, dict):
        warn("ontology.yaml root is not a mapping; treating as absent")
        return None
    aspects = data.get("aspects") or []
    if not isinstance(aspects, list):
        warn("ontology.yaml 'aspects' is not a list; treating as absent")
        return None

    slots: list[OntologySlot] = []
    for aspect in aspects:
        if not isinstance(aspect, dict):
            continue
        aspect_name = str(aspect.get("name") or "")
        for dim in aspect.get("dimensions") or []:
            if not isinstance(dim, dict):
                continue
            for slot in dim.get("slots") or []:
                if not isinstance(slot, dict):
                    continue
                slots.append(
                    OntologySlot(
                        name=str(slot.get("name") or ""),
                        status=str(slot.get("status") or "open"),
                        turn_first=_safe_int(slot.get("turn_first")),
                        turn_last=_safe_int(slot.get("turn_last")),
                        aspect=aspect_name,
                    )
                )
    return OntologySnapshot(slots=tuple(slots))


def _safe_int(v: Any) -> Optional[int]:
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def default_config() -> ScoringConfig:
    return ScoringConfig(
        premature_threshold=0.6,
        premature_weights={
            "slot_focus_imbalance": 0.34,
            "e_probe_over_use": 0.33,
            "question_form_jump": 0.33,
        },
        dead_end_threshold=0.6,
        dead_end_weights={
            "amnesia": 0.25,
            "dimension_repetition": 0.25,
            "frame_collapse": 0.25,
            "checklist_regression": 0.25,
        },
    )


def load_config(path: Path) -> ScoringConfig:
    defaults = default_config()
    if not path.is_file():
        return defaults
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise ConfigError(f"YAML parse failed: {exc}") from None
    if data is None:
        return defaults
    if not isinstance(data, dict):
        raise ConfigError(
            f"config root must be a mapping, got {type(data).__name__}"
        )
    root = data.get("mid_result_analysis")
    if root is None:
        return defaults
    if not isinstance(root, dict):
        raise ConfigError("'mid_result_analysis' must be a mapping")

    p_thresh, p_weights = _merge_branch(
        root,
        "premature",
        PREMATURE_SIGNALS,
        defaults.premature_threshold,
        defaults.premature_weights,
    )
    d_thresh, d_weights = _merge_branch(
        root,
        "dead_end",
        DEAD_END_SIGNALS,
        defaults.dead_end_threshold,
        defaults.dead_end_weights,
    )
    return ScoringConfig(
        premature_threshold=p_thresh,
        premature_weights=p_weights,
        dead_end_threshold=d_thresh,
        dead_end_weights=d_weights,
    )


def _merge_branch(
    root: Mapping[str, Any],
    branch_name: str,
    allowed_signals: tuple[str, ...],
    default_threshold: float,
    default_weights: Mapping[str, float],
) -> tuple[float, dict[str, float]]:
    branch = root.get(branch_name)
    if branch is None:
        return default_threshold, dict(default_weights)
    if not isinstance(branch, dict):
        raise ConfigError(f"mid_result_analysis.{branch_name} must be a mapping")

    threshold = branch.get("threshold", default_threshold)
    try:
        threshold = float(threshold)
    except (TypeError, ValueError):
        raise ConfigError(
            f"mid_result_analysis.{branch_name}.threshold must be a number, "
            f"got {threshold!r}"
        ) from None
    if not 0.0 <= threshold <= 1.0:
        raise ConfigError(
            f"mid_result_analysis.{branch_name}.threshold must be in [0.0, 1.0], "
            f"got {threshold}"
        )

    weights_in = branch.get("weights")
    if weights_in is None:
        return threshold, dict(default_weights)
    if not isinstance(weights_in, dict):
        raise ConfigError(
            f"mid_result_analysis.{branch_name}.weights must be a mapping"
        )
    unknown = set(weights_in.keys()) - set(allowed_signals)
    if unknown:
        raise ConfigError(
            f"mid_result_analysis.{branch_name}.weights has unknown keys: "
            f"{sorted(unknown)}"
        )
    weights: dict[str, float] = dict(default_weights)
    for k, v in weights_in.items():
        try:
            weights[k] = float(v)
        except (TypeError, ValueError):
            raise ConfigError(
                f"mid_result_analysis.{branch_name}.weights.{k} must be a number, "
                f"got {v!r}"
            ) from None
    for k, v in weights.items():
        if v < 0:
            raise ConfigError(
                f"mid_result_analysis.{branch_name}.weights.{k} must be >= 0, "
                f"got {v}"
            )
    total = sum(weights.values())
    if not WEIGHT_SUM_LO <= total <= WEIGHT_SUM_HI:
        raise ConfigError(
            f"mid_result_analysis.{branch_name}.weights must sum to ~1.0 "
            f"(tolerance ±0.01), got {total:.4f}"
        )
    return threshold, weights


# ---------------------------------------------------------------------------
# Signal computations
# ---------------------------------------------------------------------------


def _agent_turns(turns_so_far: Sequence[Turn]) -> list[Turn]:
    return [t for t in turns_so_far if t.agent_or_user == "agent"]


def compute_slot_focus_imbalance(
    turns_so_far: Sequence[Turn], ontology: Optional[OntologySnapshot]
) -> float:
    if ontology is None:
        return 0.0
    agents = _agent_turns(turns_so_far)
    if len(agents) < 3:
        return 0.0
    counts: dict[str, int] = {}
    for t in agents:
        for s in t.slots_touched:
            counts[s] = counts.get(s, 0) + 1
    if not counts:
        return 0.0
    focal, focal_count = max(counts.items(), key=lambda kv: (kv[1], kv[0]))
    other_open = ontology.open_slots_excluding(focal)
    if focal_count < 3 or other_open < 3:
        return 0.0
    return min(1.0, focal_count / len(agents))


def compute_e_probe_over_use(
    turns_so_far: Sequence[Turn], ontology: Optional[OntologySnapshot]
) -> float:
    agents = _agent_turns(turns_so_far)
    if not agents:
        return 0.0
    target = agents[-1].e_probe_target
    if target is None:
        return 0.0
    # Without ontology we cannot verify status; treat as still-open (worst
    # case for the signal) so we don't silently mask the anti-pattern.
    if ontology is not None:
        status = ontology.slot_status(target)
        if status is not None and status != "open":
            return 0.0
    consec = 0
    for t in reversed(agents):
        if t.e_probe_target == target:
            consec += 1
        else:
            break
    if consec < 2:
        return 0.0
    return min(1.0, (consec - 1) / 2.0)


def compute_question_form_jump(
    turn_n: Turn, ontology: Optional[OntologySnapshot]
) -> float:
    if turn_n.question_form not in HIGH_RES_FORMS:
        return 0.0
    if ontology is None:
        # No ontology means we can't count filled aspects; assume zero filled
        # (worst case) so a HIGH_RES form still surfaces as a strong signal.
        return QUESTION_FORM_JUMP_PEAK
    filled = ontology.filled_aspects()
    if filled >= 3:
        return 0.0
    raw = QUESTION_FORM_JUMP_PEAK * (3 - filled) / 3.0
    return max(0.0, min(1.0, raw))


def compute_amnesia(
    turns_so_far: Sequence[Turn], ontology: Optional[OntologySnapshot]
) -> float:
    if ontology is None:
        return 0.0
    agents = _agent_turns(turns_so_far)
    if not agents:
        return 0.0
    recent3 = agents[-3:]
    touched_recent: set[str] = set()
    for t in recent3:
        touched_recent.update(t.slots_touched)
    worst = 0.0
    for slot in ontology.slots:
        if slot.status != "open":
            continue
        if slot.turn_first is None or slot.turn_last is None:
            continue
        span = slot.turn_last - slot.turn_first
        if span < 5:
            continue
        if slot.name in touched_recent:
            continue
        worst = max(worst, min(1.0, (span - 4) / 6.0))
    return worst


def compute_dimension_repetition(turns_so_far: Sequence[Turn]) -> float:
    agents = _agent_turns(turns_so_far)
    if not agents:
        return 0.0
    last_dim = agents[-1].dimension
    if last_dim is None:
        return 0.0
    consec = 0
    for t in reversed(agents):
        if t.dimension == last_dim:
            consec += 1
        else:
            break
    return 1.0 if consec >= 3 else 0.0


def compute_frame_collapse(turns_so_far: Sequence[Turn]) -> float:
    # A "(d) none of these" pick is inferred as: a user turn with empty
    # slots_touched immediately following an agent HIGH_RES turn. We then
    # require ≥2 such picks where the agent rounds are back-to-back, i.e.
    # the second agent multi-choice turn lands one slot after the first
    # user d-pick.
    pairs: list[tuple[int, int]] = []
    for i in range(1, len(turns_so_far)):
        prev = turns_so_far[i - 1]
        cur = turns_so_far[i]
        if cur.agent_or_user != "user" or list(cur.slots_touched):
            continue
        if prev.agent_or_user == "agent" and prev.question_form in HIGH_RES_FORMS:
            pairs.append((i - 1, i))
    if len(pairs) < 2:
        return 0.0
    longest = 1
    current = 1
    for k in range(1, len(pairs)):
        if pairs[k][0] == pairs[k - 1][1] + 1:
            current += 1
            longest = max(longest, current)
        else:
            current = 1
    return 1.0 if longest >= 2 else 0.0


def compute_checklist_regression(turns_so_far: Sequence[Turn]) -> float:
    if len(turns_so_far) < 2:
        return 0.0
    n = len(turns_so_far)
    window = turns_so_far[max(0, n - 3) : n]
    count = 0
    for i in range(1, len(window)):
        a = window[i - 1].checklist_state
        b = window[i].checklist_state
        for row in CHECKLIST_ROWS:
            sa = CHECKLIST_ORDER.get(a.get(row, ""))
            sb = CHECKLIST_ORDER.get(b.get(row, ""))
            if sa is None or sb is None:
                continue
            if sb < sa:
                count += 1
    return max(0.0, min(1.0, count / REGRESSION_CAP))


def signals_for_turn(
    turns_so_far: Sequence[Turn], ontology: Optional[OntologySnapshot]
) -> dict[str, float]:
    if not turns_so_far:
        return {s: 0.0 for s in ALL_SIGNALS}
    turn_n = turns_so_far[-1]
    return {
        "slot_focus_imbalance": compute_slot_focus_imbalance(turns_so_far, ontology),
        "e_probe_over_use": compute_e_probe_over_use(turns_so_far, ontology),
        "question_form_jump": compute_question_form_jump(turn_n, ontology),
        "amnesia": compute_amnesia(turns_so_far, ontology),
        "dimension_repetition": compute_dimension_repetition(turns_so_far),
        "frame_collapse": compute_frame_collapse(turns_so_far),
        "checklist_regression": compute_checklist_regression(turns_so_far),
    }


def session_totals(
    turns: Sequence[Turn], ontology: Optional[OntologySnapshot]
) -> dict[str, float]:
    totals: dict[str, float] = {s: 0.0 for s in ALL_SIGNALS}
    for n in range(1, len(turns) + 1):
        sigs = signals_for_turn(turns[:n], ontology)
        for k, v in sigs.items():
            totals[k] += v
    return totals


# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------


def truncate_quote(text: Optional[str], max_len: int = 80) -> str:
    if text is None:
        return "<no quote>"
    text = str(text).strip()
    if not text:
        return "<no quote>"
    if len(text) <= max_len:
        return text
    return text[:max_len] + "..."


def derive_verdict(flagged_count: int) -> str:
    if flagged_count == 0:
        return "clean"
    if flagged_count <= 3:
        return "flagged"
    return "high-friction"


def derive_session_slug(dir_name: str) -> str:
    m = SESSION_DATE_RE.match(dir_name)
    if m and m.group(2):
        return m.group(2)
    return dir_name or "session"


def derive_session_date(dir_name: str, first_turn: Turn) -> str:
    m = SESSION_DATE_RE.match(dir_name)
    if m:
        return m.group(1)
    if first_turn.timestamp:
        try:
            dt = datetime.fromisoformat(first_turn.timestamp.replace("Z", "+00:00"))
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            pass
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%d")


def render_turn_chart(
    turns: Sequence[Turn],
    composites: Sequence[tuple[float, float]],
    p_thresh: float,
    d_thresh: float,
) -> str:
    lines = [
        "| turn_id | premature | dead_end | flagged? |",
        "|---:|---:|---:|:-:|",
    ]
    for t, (p, d) in zip(turns, composites):
        flags: list[str] = []
        if p >= p_thresh:
            flags.append("P")
        if d >= d_thresh:
            flags.append("D")
        flag_str = f"({','.join(flags)})" if flags else ""
        lines.append(f"| {t.turn_id} | {p:.2f} | {d:.2f} | {flag_str} |")
    return "\n".join(lines)


def render_flagged_turns(
    turns: Sequence[Turn],
    composites: Sequence[tuple[float, float]],
    p_thresh: float,
    d_thresh: float,
) -> str:
    bullets: list[str] = []
    for t, (p, d) in zip(turns, composites):
        dead_end_crossed = d >= d_thresh
        premature_crossed = p >= p_thresh
        # Order matters when both fire on a single turn: dead-end first
        # (heavier intervention), then premature-detail.
        if dead_end_crossed:
            quote = truncate_quote(t.ambiguity_tag)
            bullets.append(
                f'- Turn {t.turn_id} | dead-end | composite={d:.2f} | '
                f'quote: "{quote}"'
            )
        if premature_crossed:
            quote = truncate_quote(t.ambiguity_tag)
            bullets.append(
                f'- Turn {t.turn_id} | premature-detail | composite={p:.2f} | '
                f'quote: "{quote}"'
            )
    if not bullets:
        return "- (no flagged turns)"
    return "\n".join(bullets)


def render_top_signals_table(
    totals: Mapping[str, float], ontology_present: bool
) -> str:
    rows = sorted(totals.items(), key=lambda kv: (-kv[1], kv[0]))
    lines = [
        "| Signal | Group | Total Contribution |",
        "|---|---|---:|",
    ]
    for name, val in rows:
        lines.append(f"| {name} | {SIGNAL_GROUP[name]} | {val:.2f} |")
    if not ontology_present:
        lines.append("")
        lines.append(
            "_Note: `ontology.yaml` was absent; "
            "`slot_focus_imbalance` and `amnesia` are forced to 0._"
        )
    return "\n".join(lines)


def render_verdict_rationale(
    composites: Sequence[tuple[float, float]],
    turns: Sequence[Turn],
    p_thresh: float,
    d_thresh: float,
    schema_mismatch: bool,
    schema_version_seen: str,
) -> str:
    premature_crossed = [
        (t.turn_id, p) for t, (p, _) in zip(turns, composites) if p >= p_thresh
    ]
    dead_end_crossed = [
        (t.turn_id, d) for t, (_, d) in zip(turns, composites) if d >= d_thresh
    ]

    if not premature_crossed and not dead_end_crossed:
        sentence = (
            f"No turn crossed premature-detail (T1={p_thresh:.2f}) or "
            f"dead-end (T2={d_thresh:.2f}) thresholds."
        )
    else:
        parts: list[str] = []
        if premature_crossed:
            p_max_id, p_max_v = max(premature_crossed, key=lambda kv: kv[1])
            parts.append(
                f"{len(premature_crossed)} "
                f"turn{'s' if len(premature_crossed) != 1 else ''} crossed "
                f"premature-detail (max={p_max_v:.2f} at turn {p_max_id})"
            )
        else:
            parts.append("premature-detail stayed clean")
        if dead_end_crossed:
            d_max_id, d_max_v = max(dead_end_crossed, key=lambda kv: kv[1])
            parts.append(
                f"{len(dead_end_crossed)} "
                f"turn{'s' if len(dead_end_crossed) != 1 else ''} crossed "
                f"dead-end (max={d_max_v:.2f} at turn {d_max_id})"
            )
        else:
            parts.append("dead-end stayed clean")
        sentence = "; ".join(parts) + "."

    if schema_mismatch:
        sentence += (
            f" (NOTE: schema_version mismatch — file claims "
            f"{schema_version_seen!r}, this CLI is {SCHEMA_VERSION!r}; "
            f"rendering best-effort.)"
        )
    return sentence


def render_recommendations(
    verdict: str,
    totals: Mapping[str, float],
    composites: Sequence[tuple[float, float]],
    p_thresh: float,
    d_thresh: float,
) -> str:
    if verdict == "clean":
        return "- (no recommendations)"

    p_fired = any(p >= p_thresh for p, _ in composites)
    d_fired = any(d >= d_thresh for _, d in composites)
    p_totals = {k: totals.get(k, 0.0) for k in PREMATURE_SIGNALS}
    d_totals = {k: totals.get(k, 0.0) for k in DEAD_END_SIGNALS}

    bullets: list[str] = []
    if d_fired:
        top_d = sorted(d_totals.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        bullets.append(
            f"- dead-end dominated by '{top_d}' — "
            f"consider a hard-pause meta-question or session reset "
            f"before drilling further."
        )
    if p_fired:
        top_p = sorted(p_totals.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        bullets.append(
            f"- premature-detail dominated by '{top_p}' — "
            f"consider widening the ontology before drilling further."
        )

    if verdict == "high-friction":
        bullets.append(
            "- consider manual reset / re-run with stricter thresholds "
            "in `.config.yaml`."
        )
        top2_names = {n for n, _ in sorted(totals.items(), key=lambda kv: (-kv[1], kv[0]))[:2]}
        if "dimension_repetition" in top2_names:
            bullets.append(
                "- review session for F-09 dimension-repetition pattern "
                "(3+ consecutive same-dimension agent turns)."
            )

    return "\n".join(bullets) if bullets else "- (no recommendations)"


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def parse_args(argv: list[str]) -> argparse.Namespace:
    epilog = textwrap.dedent(
        """\
        Inputs read from <session_dir>:
          turns.jsonl          REQUIRED - one record per line per
                               skill/references/intermediate-result-schema.md
          ontology.yaml        OPTIONAL - aspect/dimension/slot schema. If
                               absent, 'slot_focus_imbalance' and 'amnesia'
                               are forced to 0; the report notes the omission.
          checklist-status.md  OPTIONAL - human-facing convergence snapshot.
                               When absent, the per-turn 'checklist_state'
                               objects in turns.jsonl are the source of truth
                               and 'checklist_regression' derives from those.
          .config.yaml         OPTIONAL - per-session tuning override under
                               mid_result_analysis.{premature,dead_end}.
                               {threshold,weights}. Partial overrides allowed;
                               out-of-range values fail loudly.

        Output:
          <session_dir>/review.md  rendered from
              skill/templates/review-report.template.md
          stdout (on success):
              wrote <session_dir>/review.md (verdict=<v>, turns=<N>)

        Exit codes:
          0  success
          1  generic error (template unreadable, OS error)
          2  missing turns.jsonl
          3  empty turns.jsonl (zero records)
          4  malformed JSONL (parse error or required field missing/invalid)
          5  invalid .config.yaml override

        Semantic references:
          skill/references/composite-signals.md
          skill/references/intermediate-result-schema.md
        """
    )
    parser = argparse.ArgumentParser(
        prog="pensees_review",
        description=(
            "Offline reviewer for a Pensees session: derives composite "
            "premature-detail and dead-end scores from "
            "<session_dir>/turns.jsonl and renders <session_dir>/review.md."
        ),
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "session_dir",
        help=(
            "session directory containing turns.jsonl (and optional "
            "ontology.yaml, checklist-status.md, .config.yaml)"
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    session_dir = Path(args.session_dir).expanduser()

    try:
        template = load_template()
    except OSError as exc:
        error(f"cannot read template at {TEMPLATE_PATH}: {exc}")
        return EXIT_GENERIC

    turns_path = session_dir / "turns.jsonl"
    if not turns_path.is_file():
        error(f"turns.jsonl missing at {turns_path}")
        return EXIT_MISSING_TURNS

    try:
        turns = load_turns(turns_path)
    except MalformedJsonl as exc:
        error(f"malformed JSONL at {turns_path}:{exc.line_no}: {exc.message}")
        return EXIT_MALFORMED_TURNS
    except OSError as exc:
        error(f"cannot read {turns_path}: {exc}")
        return EXIT_GENERIC

    if not turns:
        error(f"turns.jsonl is empty (zero records) at {turns_path}")
        return EXIT_EMPTY_TURNS

    ontology_path = session_dir / "ontology.yaml"
    ontology = load_ontology(ontology_path) if ontology_path.is_file() else None
    ontology_present = ontology is not None

    config_path = session_dir / ".config.yaml"
    try:
        config = load_config(config_path)
    except ConfigError as exc:
        error(f"invalid config at {config_path}: {exc}")
        return EXIT_BAD_CONFIG

    first = turns[0]
    schema_mismatch = first.schema_version != SCHEMA_VERSION
    if schema_mismatch:
        warn(
            f"schema_version mismatch: file claims {first.schema_version!r}, "
            f"this CLI is {SCHEMA_VERSION!r}"
        )

    composites: list[tuple[float, float]] = []
    for t in turns:
        prem = t.composite_premature
        if prem is None:
            warn(
                f"turn {t.turn_id} missing composite_premature; "
                f"treating as 0.0 for chart/verdict"
            )
            prem = 0.0
        dead = t.composite_dead_end
        if dead is None:
            warn(
                f"turn {t.turn_id} missing composite_dead_end; "
                f"treating as 0.0 for chart/verdict"
            )
            dead = 0.0
        composites.append((prem, dead))

    totals = session_totals(turns, ontology)

    flagged_count = sum(
        1
        for p, d in composites
        if p >= config.premature_threshold or d >= config.dead_end_threshold
    )
    verdict = derive_verdict(flagged_count)
    rationale = render_verdict_rationale(
        composites,
        turns,
        config.premature_threshold,
        config.dead_end_threshold,
        schema_mismatch,
        first.schema_version,
    )

    generated_at = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    premature_max = max(p for p, _ in composites)
    premature_mean = sum(p for p, _ in composites) / len(composites)
    dead_end_max = max(d for _, d in composites)
    dead_end_mean = sum(d for _, d in composites) / len(composites)

    placeholders: dict[str, str] = {
        "SESSION_SLUG": derive_session_slug(session_dir.name),
        "SESSION_DATE": derive_session_date(session_dir.name, first),
        "REVIEWER_VERSION": REVIEWER_VERSION,
        "TURN_COUNT": str(len(turns)),
        "GENERATED_AT_ISO": generated_at,
        "PREMATURE_MAX": f"{premature_max:.2f}",
        "PREMATURE_MEAN": f"{premature_mean:.2f}",
        "PREMATURE_THRESHOLD": f"{config.premature_threshold:.2f}",
        "DEAD_END_MAX": f"{dead_end_max:.2f}",
        "DEAD_END_MEAN": f"{dead_end_mean:.2f}",
        "DEAD_END_THRESHOLD": f"{config.dead_end_threshold:.2f}",
        "TURN_SCORE_CHART": render_turn_chart(
            turns, composites, config.premature_threshold, config.dead_end_threshold
        ),
        "FLAGGED_TURNS_LIST": render_flagged_turns(
            turns, composites, config.premature_threshold, config.dead_end_threshold
        ),
        "TOP_SIGNALS_TABLE": render_top_signals_table(totals, ontology_present),
        "VERDICT": verdict,
        "VERDICT_RATIONALE": rationale,
        "RECOMMENDATIONS_LIST": render_recommendations(
            verdict,
            totals,
            composites,
            config.premature_threshold,
            config.dead_end_threshold,
        ),
        "TURNS_JSONL_PATH": str(turns_path),
        "SCHEMA_VERSION": first.schema_version or "<missing>",
    }

    rendered = template
    for name in PLACEHOLDER_NAMES:
        rendered = rendered.replace("{{" + name + "}}", placeholders[name])

    review_path = session_dir / "review.md"
    try:
        review_path.write_text(rendered, encoding="utf-8")
    except OSError as exc:
        error(f"cannot write {review_path}: {exc}")
        return EXIT_GENERIC

    print(f"wrote {review_path} (verdict={verdict}, turns={len(turns)})")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
