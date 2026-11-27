"""
labeler.py - Turns the slices a person marks on a long video (each with violation labels) into benchmark clips.

  plan(...)      slices -> clips to cut: each event gets `pad` seconds of normal traffic before and after; slices that are close
                 are cut as ONE clip; every other slice that falls inside a clip's time is added to it as an event, so a ticket
                 for it is not wrongly counted as a false alarm. A slice labelled "clean" becomes a clip with nothing illegal in it.
  register(...)  after a clip is cut: write its settings file and add it to benchmarks/registry.yaml (events in the clip's own seconds).

Plain functions, folders passed in, so tests can use temporary folders. The HTTP side is routers/trimmer.py (POST /benchmark).
"""
from __future__ import annotations

import hashlib
import json
import re
import threading
from pathlib import Path

from . import registry, service
from .violations import KEYS, NEEDS

CLEAN = "clean"
DEFAULT_OUT = Path("A:/huli-kamote/benchmark-videos")
FOLDERS = [*KEYS, CLEAN]     # the export makes one folder for each
DEFAULT_PAD = 3.0            # seconds of normal traffic kept before and after an event
MIN_CLIP = 1.0
TWO_WHEELER_RULES = {"no_helmet", "overloading", "missing_side_mirror", "tricycle_on_highway"}   # the rules a motorcycle or tricycle can break
_LOCK = threading.Lock()     # the registry is one file: clips that finish together take turns writing it


class PlanError(ValueError):
    pass


def _stem(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "-", Path(name).stem).strip("-")[:28] or "video"


def _stamp(seconds: float) -> str:
    whole = int(seconds)
    return f"{whole // 60:02d}m{whole % 60:02d}s"


def plan(source_name: str, duration: float, slices: list[dict], pad: float = DEFAULT_PAD) -> dict:
    """slices: [{start, end, labels: [violation keys or "clean"], export?, pad?}] in seconds of the long video. `pad` = that slice's own
    extra seconds (else the `pad` argument). A slice with export false
    was cut before: it is not cut again, but it still counts as an event inside the clips that overlap it.
    Returns {"clips": [{name, start, end, clean, events: [{violation, start, end}], labels}], "skipped": [text]}."""
    pad = max(0.0, float(pad))
    skipped: list[str] = []
    events: list[tuple[float, float, str, str]] = [] # (start, end, violation, true plate or "") in the long video: ALL labelled slices
    cut: list[tuple[float, float, float, str]] = []  # (start, end, pad, violation) of the event slices cut now (the others were exported before)
    cleans: list[tuple[float, float, tuple[str, ...]]] = []   # (start, end, the violations it is clean for; empty = the common ones)
    for n, s in enumerate(slices, 1):
        a, b = float(s["start"]), float(s["end"])
        a, b = max(0.0, min(a, b)), min(duration, max(a, b))
        labels = [str(x) for x in (s.get("labels") or [])]
        bad = [x for x in labels if x != CLEAN and x not in KEYS]
        if bad:
            raise PlanError(f"Slice {n} has an unknown label: {', '.join(bad)}")
        if not labels:
            skipped.append(f"Slice {n} ({_stamp(a)}) has no label, so it was left out.")
            continue
        if b - a < 0.1:
            skipped.append(f"Slice {n} ({_stamp(a)}) is too short.")
            continue
        clean_for = tuple(sorted({str(x) for x in (s.get("clean_for") or []) if str(x) in KEYS}))
        for x in labels:
            if x == CLEAN:
                if s.get("export", True):
                    cleans.append((a, b, clean_for))
            else:
                n = max(1, min(50, int(s.get("count") or 1)))       # "N vehicles in this slice": N events, so N tickets can each catch one
                for _ in range(n):
                    events.append((a, b, x, str(s.get("plate") or "").strip() if n == 1 else ""))
                if s.get("export", True):
                    cut.append((a, b, max(0.0, float(s["pad"])) if s.get("pad") is not None else pad, x))

    # ONE violation per clip: the windows around the events are made and merged for each violation on its own, so a clip never holds
    # two violations (two slices of different violations over the same seconds are cut as two clips)
    windows: list[tuple[str, float, float]] = []
    for violation in sorted({v for *_, v in cut}):
        merged: list[list[float]] = []
        for a, b, p, _ in sorted(c for c in set(cut) if c[3] == violation):
            w = [max(0.0, a - p), min(duration, b + p)]
            if merged and w[0] <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], w[1])
            else:
                merged.append(w)
        windows.extend((violation, ws, we) for ws, we in merged)

    clips = []
    for violation, ws, we in windows:
        if we - ws < MIN_CLIP:
            we = min(duration, ws + MIN_CLIP)
            ws = max(0.0, we - MIN_CLIP)
        inside = [(max(a, ws) - ws, min(b, we) - ws, v, pl) for a, b, v, pl in events if v == violation and a < we and b > ws]
        clips.append({"start": ws, "end": we, "clean": False, "labels": [violation],
                      "events": [{"violation": v, "start": round(a, 2), "end": round(b, 2), **({"plate": pl} if pl else {})}
                                 for a, b, v, pl in sorted(inside)]})

    for a, b, clean_for in cleans:
        # a clean slice only clashes with a violation window it is clean for (no list = any violation)
        if any(a < we and b > ws and (not clean_for or v in clean_for) for v, ws, we in windows):
            skipped.append(f"A clean slice at {_stamp(a)} overlaps a violation, so it was left out.")
            continue
        if b - a < MIN_CLIP:
            skipped.append(f"A clean slice at {_stamp(a)} is shorter than {MIN_CLIP:.0f} s, so it was left out.")
            continue
        clips.append({"start": a, "end": b, "clean": True, "labels": [CLEAN], "events": [], "clean_for": list(clean_for)})

    stem = _stem(source_name)
    for c in clips:
        # one folder per violation: the clip goes where its violation is (a clip with no violation: "clean")
        c["folder"] = CLEAN if c["clean"] else c["labels"][0]
    for c in sorted(clips, key=lambda c: c["start"]):
        tag = "-".join(v.replace("_", "") for v in (c.get("clean_for") or c["labels"])[:2])
        tag = f"clean-{tag}" if c["clean"] and tag else (tag or CLEAN)
        c["name"] = f"{stem}_{_stamp(c['start'])}_{tag}"[:60]
    return {"clips": sorted(clips, key=lambda c: c["start"]), "skipped": skipped}


def settings_for(violations: list[str], template: dict | None = None) -> dict:
    """The wizard settings a clip is scored with: only its own violations on. Zone rules get no drawn zone (see needs_zone)."""
    base = dict(template or {})
    base.update({"active_violations": sorted(violations), "flow_mode": "auto", "regions_of_interest": {}})
    base.setdefault("tracker", "deepsort")
    base.setdefault("plate_method", "smart")
    base.setdefault("plate_format", "ph_standard")
    base.setdefault("ocr_engine", "easyocr")
    base.setdefault("enhancement", "lanczos")
    base.setdefault("use_sahi", False)
    base.setdefault("flag_sensitivity", 5)
    base.setdefault("evidence_gap", 5)
    base.setdefault("keep_input_video", False)
    base.setdefault("blur_privacy", True)
    base.setdefault("primary_model", "")
    cfg = dict(base.get("per_violation_configs") or {})
    if "overloading" in violations:
        cfg.setdefault("overloading", {"max_riders": 2})
    base["per_violation_configs"] = cfg
    return base


def needs_zone(violations) -> list[str]:
    """Violations of a clip that are zone rules: they judge a drawn zone, so open the clip in the Forensic Analyzer and adopt it."""
    zone = {n.key for n in NEEDS if n.kind == "zone rule"}
    try:                                   # a rule that works on the whole picture (truck ban, tricycle ban ...) needs no drawn zone
        from engine.violations import REGISTRY
        whole = {k for k, c in REGISTRY.items() if getattr(c, "whole_frame", False)}
    except Exception:
        whole = set()
    return sorted(v for v in violations if v in zone and v not in whole)


def register(clip: dict, video: Path, bench: Path, note: str = "", setup: dict | None = None, reverse_counterflow: bool = False,
             incoming_two_wheelers: bool = False, overloading_max_riders: int | None = None) -> str:
    """Write the clip's settings and add it to the registry. Returns the clip's id. Safe to call from several threads.
    [setup] = a saved setup's config (zones, signs and settings drawn for this camera view): the clip is then scored inside those zones.
    [incoming_two_wheelers] = demo: judge motorcycles and tricycles that come toward the camera too (a front view shows no plate).
    [overloading_max_riders] = demo: the most riders a motorcycle may carry (default 2; 1 = every two-up motorcycle counts)."""
    cid = service.safe_name(clip["name"], "The clip name")
    violations = sorted({e["violation"] for e in clip["events"]}) or []
    template_file = Path(bench) / "settings" / "public_helmet.json"
    template = json.loads(template_file.read_text(encoding="utf-8")) if template_file.exists() else {}
    if setup:
        template = json.loads(json.dumps(setup))           # the saved setup replaces the plain template: its zones and overlays count
    template.pop("active_violations", None)
    # a clean clip is judged only for the violations it is clean for (none chosen: the common ones), so false alarms on it show
    judged = violations or [v for v in (clip.get("clean_for") or []) if v in KEYS] or ["no_helmet", "overloading"]
    cfg = settings_for(judged, template)
    if incoming_two_wheelers and TWO_WHEELER_RULES & set(judged):
        cfg["judge_incoming_two_wheelers"] = True
        note = (note or "Labelled in the dashboard's video labeller.") + " DEMO: incoming motorcycles and tricycles are judged too."
    if overloading_max_riders is not None and "overloading" in judged:
        limit = max(1, min(9, int(overloading_max_riders)))
        cfg["per_violation_configs"] = {**cfg["per_violation_configs"], "overloading": {**(cfg["per_violation_configs"].get("overloading") or {}), "max_riders": limit}}
        if limit != 2:
            note = (note or "Labelled in the dashboard's video labeller.") + f" DEMO: overloading limit set to {limit} rider(s)."
    if reverse_counterflow and "counterflow" in judged:
        # simulated wrong-way traffic: the legal direction is flipped, so ordinary traffic counts as counterflow
        cfg["per_violation_configs"] = {**cfg["per_violation_configs"], "counterflow": {**(cfg["per_violation_configs"].get("counterflow") or {}), "invert_flow": True}}
        note = (note or "Labelled in the dashboard's video labeller.") + " Counterflow is SIMULATED: the legal direction was reversed."
    key = hashlib.sha1(json.dumps(cfg, sort_keys=True).encode()).hexdigest()[:8]
    settings_rel = f"settings/labeled_{key}.json"
    settings_path = Path(bench) / settings_rel
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    if not settings_path.exists():
        settings_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    with _LOCK:
        f = Path(bench) / "registry.yaml"
        raw = registry.load_raw(f)
        entry = service.upsert_clip(raw, cid, note or "Labelled in the dashboard's video labeller.", clip["clean"], clip["events"])
        entry["file"] = str(video).replace("\\", "/")
        entry["settings"] = settings_rel
        registry.save_raw(raw, f)
    return cid
