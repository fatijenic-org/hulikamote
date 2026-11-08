"""
service.py - What the command line and the dashboard's Benchmark tab both do with the registry and with past forensic runs:
copy a run into the benchmark, suggest events from what it flagged, edit a clip's events, count coverage, list reports.
Plain functions with the folders passed in (the API fills in the real ones), so tests can use temporary folders.
"""
from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

from . import registry
from .violations import KEYS

BENCH = registry.BENCH
FORENSIC_DIR = registry.ROOT / "hulikamote_backend" / "snapshots" / "evidence" / "forensic"
EVIDENCE_DIR = FORENSIC_DIR.parent

_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*")


class ServiceError(ValueError):
    """A mistake the user can fix; the message is written to be shown. `status` is the HTTP code the API answers with."""

    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


def safe_name(value, what: str, limit: int = 64) -> str:
    """Clip names, run ids and report names become file names, so only letters, digits, - and _ are allowed."""
    if not isinstance(value, str) or len(value) > limit or not _NAME.fullmatch(value):
        raise ServiceError(f"{what} may only have letters, digits, - and _ (up to {limit} characters).")
    return value


# --------------------------------------------------------------------------- past forensic runs

def run_dir(task_id: str, forensic_dir: Path) -> Path:
    task = Path(forensic_dir) / safe_name(task_id, "The run id")
    if not (task / "output" / "forensic_config.json").exists():
        raise ServiceError(f"No forensic run {task_id} (looked in {task}).", 404)
    return task


def suggestions(task_id: str, forensic_dir: Path) -> dict:
    """What a run switched on, whether it kept its video, and what it flagged (to confirm by watching the clip)."""
    task = run_dir(task_id, forensic_dir)
    cfg = json.loads((task / "output" / "forensic_config.json").read_text(encoding="utf-8"))
    found = []
    report_file = task / "output" / "report.json"
    if report_file.exists():
        for t in json.loads(report_file.read_text(encoding="utf-8")):
            times = [m["t"] for m in t.get("evidence_meta", []) if m.get("t") is not None]
            plate = t.get("plate_text")
            for v in t.get("violations", []):
                found.append({"violation": v, "track": t.get("track_id"),
                              "start": round(max(0.0, min(times) - 1), 1) if times else None,
                              "end": round(max(times) + 1, 1) if times else None,
                              "plate": plate if plate and plate != "unidentified" else None})
    return {"enabled": list(cfg.get("active_violations", [])), "video_kept": (task / "input_video.mp4").exists(),
            "suggestions": found}


def copy_run(task_id: str, clip_id: str, forensic_dir: Path, bench: Path, video: Path | None = None) -> None:
    """Copy a run's settings (and its video, or the original clip you name) into benchmarks/ under the clip's name."""
    task = run_dir(task_id, forensic_dir)
    clip_id = safe_name(clip_id, "The clip name")
    source = Path(video) if video else task / "input_video.mp4"
    if not source.exists():
        if video:
            raise ServiceError(f"Clip not found: {video}")
        raise ServiceError("That run did not keep its copy of the video. Choose the original clip (command line: "
                           "--video \"C:/path/to/clip.mp4\"), or turn on 'Keep the uploaded video' in the wizard's "
                           "Settings step and run it again.")
    (bench / "clips").mkdir(parents=True, exist_ok=True)
    (bench / "settings").mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, bench / "clips" / f"{clip_id}.mp4")
    shutil.copy2(task / "output" / "forensic_config.json", bench / "settings" / f"{clip_id}.json")


# --------------------------------------------------------------------------- editing the registry

def clean_events(raw_events) -> list[dict]:
    """Check what the user typed and turn it into registry entries (times in seconds)."""
    out = []
    for e in raw_events or []:
        key = e.get("violation")
        if key not in KEYS:
            raise ServiceError(f"Unknown violation {key!r}.")
        try:
            start = registry.parse_time(e.get("start", 0))
            end_raw = e.get("end")
            end = start if end_raw in (None, "") else registry.parse_time(end_raw)
        except registry.RegistryError as err:
            raise ServiceError(f"{key}: {err}") from None
        if end < start:
            raise ServiceError(f"{key}: the event ends ({end:g} s) before it starts ({start:g} s).")
        item = {"violation": key, "start": round(start, 2), "end": round(end, 2)}
        if (e.get("plate") or "").strip():
            item["plate"] = e["plate"].strip()
        if (e.get("note") or "").strip():
            item["note"] = e["note"].strip()
        out.append(item)
    return out


def upsert_clip(raw: dict, clip_id: str, note: str, clean: bool, events) -> dict:
    """Add the clip to the raw registry, or change its note / clean flag / events. Returns the entry."""
    clip_id = safe_name(clip_id, "The clip name")
    events = clean_events(events)
    if clean and events:
        raise ServiceError("A clip with nothing illegal in it cannot also have events.")
    clips = raw.get("clips") or []
    entry = next((c for c in clips if str(c.get("id")) == clip_id), None)
    if entry is None:
        entry = {"id": clip_id, "file": f"clips/{clip_id}.mp4", "settings": f"settings/{clip_id}.json"}
        clips.append(entry)
    entry.update(clean=bool(clean), note=(note or "").strip(), events=events)
    raw["clips"] = clips
    return entry


def delete_clip(raw: dict, clip_id: str, bench: Path) -> bool:
    """Remove the clip and the copies this tool made. Files outside benchmarks/ are never touched."""
    clips = raw.get("clips") or []
    entry = next((c for c in clips if str(c.get("id")) == clip_id), None)
    if entry is None:
        return False
    raw["clips"] = [c for c in clips if c is not entry]
    root = Path(bench).resolve()
    for key in ("file", "settings"):
        target = (Path(bench) / str(entry.get(key) or "")).resolve()
        if entry.get(key) and target.is_file() and root in target.parents:
            target.unlink()
    return True


# --------------------------------------------------------------------------- what the screens show

def coverage(reg: registry.Registry) -> list[dict]:
    """Per violation: real events and clips so far, and what is still needed."""
    need = reg.defaults["min_events"]
    rows = {k: {"key": k, "events": 0, "clips": 0, "clean_clips": 0, "needed": need} for k in KEYS}
    for c in reg.clips:
        for k in c.enabled:
            if k in rows:
                rows[k]["clips"] += 1
                rows[k]["clean_clips"] += 1 if c.clean else 0
        for e in c.events:
            rows[e.violation]["events"] += 1
    for r in rows.values():
        r["state"] = ("ready" if r["events"] >= need
                      else f"needs {need - r['events']} more events" if r["events"] else "no clips yet")
    return list(rows.values())


def clip_json(clip: registry.Clip, seconds: float | None = None) -> dict:
    return {"id": clip.id, "note": clip.note, "clean": clip.clean, "file_ok": clip.file.exists(),
            "settings_ok": bool(clip.settings), "enabled": sorted(clip.enabled), "seconds": seconds,
            "events": [{"violation": e.violation, "start": e.start, "end": e.end, "plate": e.plate or "", "note": e.note}
                       for e in clip.events]}


def list_reports(folder: Path) -> list[dict]:
    """Saved reports, newest first, with the headline numbers."""
    out = []
    for f in sorted(Path(folder).glob("*.json"), reverse=True) if Path(folder).exists() else []:
        try:
            rep = json.loads(f.read_text(encoding="utf-8"))
            o = rep["overall"]
            out.append({"name": f.stem, "label": rep.get("label", f.stem), "created": rep.get("created", ""),
                        "caught": o["caught"], "false_alarms": o["false_alarms"], "missed": o["missed"],
                        "precision": o["precision"], "recall": o["recall"]})
        except (OSError, ValueError, KeyError):
            continue
    return out


def read_report(folder: Path, name: str) -> dict:
    name = safe_name(name, "The report name", limit=160)
    f = Path(folder) / f"{name}.json"
    if not f.exists():
        raise ServiceError(f"No report called {name}.", 404)
    return json.loads(f.read_text(encoding="utf-8"))
