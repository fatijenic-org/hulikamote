"""
registry.py - The ground-truth registry: which clips exist and which violations really happen in them (and when).

benchmarks/registry.yaml
    defaults:  tolerance_s (how far a ticket's time may be from the real event), pass (per-violation targets), min_events
    clips:     id, file, settings (the wizard's saved config), events [{violation, start, end, plate?, box?, tol?}], clean, note
Times are seconds from the start of the clip, as a number or "m:ss.s". A clip with `clean: true` has NO violations:
every ticket on it is a false alarm. Violations that were not switched on in a clip's settings are not judged on it.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .violations import KEYS

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "benchmarks"
DEFAULTS = {"tolerance_s": 3.0, "min_events": 10, "pass": {"precision": 0.80, "recall": 0.80}}


class RegistryError(ValueError):
    pass


def parse_time(value) -> float:
    """12.5 | "12.5" | "1:05" | "0:01:05.5" -> seconds."""
    if isinstance(value, (int, float)):
        return float(value)
    parts = str(value).strip().split(":")
    if not parts or not all(re.fullmatch(r"\d+(\.\d+)?", p) for p in parts) or len(parts) > 3:
        raise RegistryError(f"cannot read the time {value!r} (use seconds or m:ss)")
    seconds = 0.0
    for p in parts:
        seconds = seconds * 60 + float(p)
    return seconds


@dataclass
class Event:
    violation: str
    start: float
    end: float
    plate: str | None = None           # expected plate text (checked in the logging score)
    box: list[float] | None = None     # expected vehicle box [x1, y1, x2, y2] as fractions of the picture (optional)
    tol: float | None = None           # this event's own time tolerance
    note: str = ""


@dataclass
class Clip:
    id: str
    file: Path
    settings_file: Path | None
    events: list[Event] = field(default_factory=list)
    clean: bool = False
    note: str = ""
    settings: dict = field(default_factory=dict)

    @property
    def enabled(self) -> set[str]:
        """Violations switched on in this clip's settings (only these can be judged)."""
        return set(self.settings.get("active_violations", []))


@dataclass
class Registry:
    defaults: dict
    clips: list[Clip]


def _event(raw: dict, clip_id: str) -> Event:
    key = raw.get("violation")
    if key not in KEYS:
        raise RegistryError(f"clip {clip_id}: unknown violation {key!r} (use one of: {', '.join(KEYS)})")
    start, end = parse_time(raw.get("start", 0)), parse_time(raw.get("end", raw.get("start", 0)))
    if end < start:
        raise RegistryError(f"clip {clip_id}: event {key} ends ({end}) before it starts ({start})")
    box = raw.get("box")
    if box is not None and (len(box) != 4 or not all(0 <= float(v) <= 1 for v in box)):
        raise RegistryError(f"clip {clip_id}: box must be 4 fractions [x1, y1, x2, y2]")
    return Event(key, start, end, raw.get("plate"), [float(v) for v in box] if box else None,
                 float(raw["tol"]) if raw.get("tol") is not None else None, str(raw.get("note", "")))


def load(path: Path | None = None) -> Registry:
    path = path or BENCH / "registry.yaml"
    raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    defaults = {**DEFAULTS, **(raw.get("defaults") or {})}
    defaults["pass"] = {**DEFAULTS["pass"], **(defaults.get("pass") or {})}
    clips, seen = [], set()
    for c in raw.get("clips") or []:
        cid = str(c.get("id", "")).strip()
        if not cid or cid in seen:
            raise RegistryError(f"clip id {cid!r} is missing or used twice")
        seen.add(cid)
        events = [_event(e, cid) for e in c.get("events") or []]
        if c.get("clean") and events:
            raise RegistryError(f"clip {cid}: 'clean: true' cannot have events")
        settings_file = (path.parent / c["settings"]) if c.get("settings") else None
        clip = Clip(cid, path.parent / c["file"], settings_file, events, bool(c.get("clean")), str(c.get("note", "")))
        if settings_file and settings_file.exists():
            clip.settings = json.loads(settings_file.read_text(encoding="utf-8"))
        clips.append(clip)
    return Registry(defaults, clips)


HEADER = """# Ground-truth registry: the clips and what REALLY happens in them. See benchmarks/README.md.
# Check it:  python -m tools.benchmark validate      See coverage:  python -m tools.benchmark status
# Score it:  python -m tools.benchmark run --label baseline
# The dashboard's Benchmark tab edits this file too (saving it from there rewrites everything below this header).
"""


def load_raw(path: Path | None = None) -> dict:
    """The registry file as plain data (for editing). A missing file is an empty registry."""
    path = path or BENCH / "registry.yaml"
    return (yaml.safe_load(path.read_text(encoding="utf-8")) or {}) if path.exists() else {}


def save_raw(raw: dict, path: Path | None = None) -> None:
    path = path or BENCH / "registry.yaml"
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {"defaults": raw.get("defaults") or {"tolerance_s": DEFAULTS["tolerance_s"], "min_events": DEFAULTS["min_events"],
                                                "pass": dict(DEFAULTS["pass"])},
            "clips": raw.get("clips") or []}
    path.write_text(HEADER + "\n" + yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")


def problems(reg: Registry) -> list[str]:
    """Things to fix before a run: missing files, events that cannot be judged."""
    out = []
    for c in reg.clips:
        if not c.file.exists():
            out.append(f"{c.id}: video not found: {c.file}")
        if c.settings_file is None or not c.settings_file.exists():
            out.append(f"{c.id}: settings file not found ({c.settings_file}); save the wizard's forensic_config.json there")
        elif not c.enabled:
            out.append(f"{c.id}: its settings switch no violation on (active_violations is empty)")
        for e in c.events:
            if c.enabled and e.violation not in c.enabled:
                out.append(f"{c.id}: expects {e.violation} but the settings do not switch it on")
        if not c.events and not c.clean:
            out.append(f"{c.id}: no events and not marked clean: add events, or 'clean: true' if nothing happens")
    return out
