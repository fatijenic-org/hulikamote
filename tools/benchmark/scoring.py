"""
scoring.py - Compare the tickets a run produced with the events that really happen in the clip.

Words used in the report:  Caught = true positive, False alarm = false positive, Missed = false negative.
A ticket Caught an event when it is the same violation and its evidence time is within the tolerance of the
event's [start, end]. One ticket catches at most one event and the other way round (best time match first).
Logging accuracy (the thesis' second metric) judges each CAUGHT event: was the plate text, the evidence picture
and the vehicle recorded correctly? Pure functions: no files, no network, easy to test.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from .registry import Clip, Event

UNKNOWN_PLATES = {"", "UNIDENTIFIED", "NOPLATEFOUND", "NOPLATE"}


def edit_distance(a: str, b: str) -> int:
    """Levenshtein distance (characters to change to turn a into b)."""
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def norm_plate(text) -> str:
    """'abc 123-4' -> 'ABC1234'; 'unidentified' and friends -> ''."""
    t = re.sub(r"[^A-Z0-9]", "", str(text or "").upper())
    return "" if t in UNKNOWN_PLATES else t


@dataclass
class Prediction:
    violation: str
    start: float | None            # None = the ticket carries no time
    end: float | None
    plate: str
    track: object
    files: list[str] = field(default_factory=list)
    boxes: list[tuple[float, list]] = field(default_factory=list)      # (time, [x, y, w, h] in pixels)


def predictions(tickets: list[dict], enabled: set[str] | None = None) -> list[Prediction]:
    """One prediction per (ticket, violation). Only violations switched on for the clip count."""
    out = []
    for t in tickets:
        meta = t.get("evidence_meta") or []
        times = [m["t"] for m in meta if m.get("t") is not None]
        boxes = [(m["t"], m["bbox"]) for m in meta if m.get("t") is not None and m.get("bbox")]
        files = [m.get("file") for m in meta if m.get("file")] or list(t.get("evidence_paths") or [])
        for v in t.get("violations", []):
            if enabled and v not in enabled:
                continue
            out.append(Prediction(v, min(times) if times else None, max(times) if times else None,
                                  norm_plate(t.get("plate_text")), t.get("track_id"), files, boxes))
    return out


def gap(e: Event, p: Prediction) -> float | None:
    """Seconds between the event window and the prediction window (0 = they overlap); None = prediction has no time."""
    if p.start is None:
        return None
    return max(0.0, max(e.start, p.start) - min(e.end, p.end))


def match(events: list[Event], preds: list[Prediction], tol: float):
    """-> (pairs [(event idx, prediction idx)], unmatched event idxs, unmatched prediction idxs)."""
    cands = []
    for i, e in enumerate(events):
        t = e.tol if e.tol is not None else tol
        for j, p in enumerate(preds):
            if p.violation != e.violation:
                continue
            g = gap(e, p)
            if g is None:
                g = t                          # no time on the ticket: allowed, but only when nothing fits better
            if g <= t:
                cands.append((g, e.start, i, j))
    cands.sort()
    used_e, used_p, pairs = set(), set(), []
    for _, _, i, j in cands:
        if i not in used_e and j not in used_p:
            used_e.add(i)
            used_p.add(j)
            pairs.append((i, j))
    return (sorted(pairs), [i for i in range(len(events)) if i not in used_e],
            [j for j in range(len(preds)) if j not in used_p])


def _iou(a: list[float], b: list[float]) -> float:
    iw, ih = min(a[2], b[2]) - max(a[0], b[0]), min(a[3], b[3]) - max(a[1], b[1])
    if iw <= 0 or ih <= 0:
        return 0.0
    inter = iw * ih
    return inter / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter)


def logging_check(e: Event, p: Prediction, frame: tuple[int, int] | None = None,
                  evidence_dir: Path | None = None) -> dict:
    """True / False for what was checked, None for what could not be (no expected plate, no frame size...)."""
    plate, dist = None, None
    if e.plate:
        dist = edit_distance(norm_plate(e.plate), p.plate)
        plate = dist == 0
    if not p.files:
        evidence = False
    elif evidence_dir is not None and evidence_dir.exists():
        evidence = any((evidence_dir / f).exists() for f in p.files)
    else:
        evidence = True
    vehicle = None
    if e.box and p.boxes and frame:
        mid = (e.start + e.end) / 2
        t, (x, y, w, h) = min(p.boxes, key=lambda b: abs(b[0] - mid))
        vehicle = _iou([x / frame[0], y / frame[1], (x + w) / frame[0], (y + h) / frame[1]], e.box) >= 0.3
    done = [v for v in (plate, evidence, vehicle) if v is not None]
    # LOAR (the thesis' strict record check): violation type (matched already) + vehicle + plate string all right.
    # Only events that carry the true plate can be checked this way.
    loar = None if plate is None else (plate and vehicle is not False)
    return {"plate": plate, "plate_dist": dist, "plate_len": len(norm_plate(e.plate)) if e.plate else None,
            "evidence": evidence, "vehicle": vehicle, "loar": loar, "ok": all(done)}


@dataclass
class ClipResult:
    clip_id: str
    seconds: float | None
    enabled: set[str]
    caught: list[dict] = field(default_factory=list)       # {violation, start, end, ticket track, checks, ...}
    false_alarms: list[dict] = field(default_factory=list)
    missed: list[dict] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)       # events on violations that were not switched on


def score_clip(clip: Clip, tickets: list[dict], tol: float, seconds: float | None = None,
               frame: tuple[int, int] | None = None, evidence_dir: Path | None = None) -> ClipResult:
    enabled = clip.enabled
    res = ClipResult(clip.id, seconds, enabled)
    events = [e for e in clip.events if not enabled or e.violation in enabled]
    res.skipped = sorted({e.violation for e in clip.events} - {e.violation for e in events})
    preds = predictions(tickets, enabled or None)
    pairs, miss_idx, extra_idx = match(events, preds, tol)
    for i, j in pairs:
        e, p = events[i], preds[j]
        res.caught.append({"violation": e.violation, "start": e.start, "end": e.end, "track": p.track,
                           "ticket_start": p.start, "ticket_end": p.end, "plate": p.plate, "note": e.note,
                           "checks": logging_check(e, p, frame, evidence_dir)})
    for i in miss_idx:
        e = events[i]
        res.missed.append({"violation": e.violation, "start": e.start, "end": e.end, "note": e.note})
    for j in extra_idx:
        p = preds[j]
        res.false_alarms.append({"violation": p.violation, "track": p.track, "ticket_start": p.start,
                                 "ticket_end": p.end, "plate": p.plate})
    return res


def _ratio(a: int, b: int) -> float | None:
    return a / b if b else None


def plate_stats(checks: list[dict]) -> dict:
    """LOAR, plate CER and WER over the caught events that carry the true plate (thesis definitions). Raw sums are kept so
    several violations can be added up."""
    withp = [c for c in checks if c["plate"] is not None]
    loar = [c for c in withp if c["loar"] is not None]
    s = {"checked": len(withp), "loar_n": len(loar), "loar_correct": sum(1 for c in loar if c["loar"]),
         "dist_sum": sum(c["plate_dist"] for c in withp), "len_sum": sum(c["plate_len"] for c in withp),
         "wrong": sum(1 for c in withp if c["plate_dist"] > 0)}
    s.update(loar=_ratio(s["loar_correct"], s["loar_n"]), cer=_ratio(s["dist_sum"], s["len_sum"]), wer=_ratio(s["wrong"], s["checked"]))
    return s


def summarize(results: list[ClipResult], defaults: dict) -> dict:
    """Per violation: Caught / False alarms / Missed, precision, recall, F1, false alarms per minute, logging, status."""
    keys = sorted({k for r in results for k in r.enabled}
                  | {x["violation"] for r in results for lst in (r.caught, r.missed, r.false_alarms) for x in lst})
    target = defaults["pass"]
    out = {}
    for k in keys:
        clips = [r for r in results if k in r.enabled or any(x["violation"] == k for x in r.caught + r.missed)]
        tp = sum(1 for r in clips for x in r.caught if x["violation"] == k)
        fn = sum(1 for r in clips for x in r.missed if x["violation"] == k)
        fp = sum(1 for r in clips for x in r.false_alarms if x["violation"] == k)
        minutes = sum((r.seconds or 0) for r in clips) / 60
        checked = [x["checks"] for r in clips for x in r.caught if x["violation"] == k]
        precision, recall = _ratio(tp, tp + fp), _ratio(tp, tp + fn)
        f1 = (2 * precision * recall / (precision + recall)) if precision and recall else (0.0 if tp + fp + fn else None)
        events = tp + fn
        if events == 0:
            status = "no real events in any clip" if not fp else "false alarms, but no real events to catch"
        elif events < defaults["min_events"]:
            status = f"too few events ({events} of {defaults['min_events']})"
        else:
            status = "PASS" if (precision or 0) >= target["precision"] and (recall or 0) >= target["recall"] else "FAIL"
        out[k] = {"clips": len(clips), "events": events, "caught": tp, "false_alarms": fp, "missed": fn,
                  "precision": precision, "recall": recall, "f1": f1,
                  "false_alarms_per_min": (fp / minutes) if minutes else None,
                  "plates": plate_stats(checked),
                  "logging": {"checked": len(checked), "all_correct": sum(1 for c in checked if c["ok"]),
                              "rate": _ratio(sum(1 for c in checked if c["ok"]), len(checked)),
                              "plate_wrong": sum(1 for c in checked if c["plate"] is False),
                              "no_evidence": sum(1 for c in checked if c["evidence"] is False),
                              "wrong_vehicle": sum(1 for c in checked if c["vehicle"] is False)},
                  "status": status}
    return out


def overall(summary: dict) -> dict:
    tp = sum(v["caught"] for v in summary.values())
    fp = sum(v["false_alarms"] for v in summary.values())
    fn = sum(v["missed"] for v in summary.values())
    ok = sum(v["logging"]["all_correct"] for v in summary.values())
    n = sum(v["logging"]["checked"] for v in summary.values())
    pl = {k: sum(v["plates"][k] for v in summary.values()) for k in ("checked", "loar_n", "loar_correct", "dist_sum", "len_sum", "wrong")}
    return {"caught": tp, "false_alarms": fp, "missed": fn, "precision": _ratio(tp, tp + fp), "recall": _ratio(tp, tp + fn),
            "false_alarm_share": _ratio(fp, tp + fp), "miss_rate": _ratio(fn, tp + fn), "logging_rate": _ratio(ok, n),
            "plates_checked": pl["checked"], "loar": _ratio(pl["loar_correct"], pl["loar_n"]),
            "cer": _ratio(pl["dist_sum"], pl["len_sum"]), "wer": _ratio(pl["wrong"], pl["checked"])}
