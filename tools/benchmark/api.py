"""
api.py - The dashboard's Benchmark tab talks to this. hulikamote_backend/main.py mounts `router` at /api/benchmark.

    GET    /overview            coverage per violation, the clips with their events, problems, saved reports, a run in progress
    GET    /suggestions/{run}   what a past forensic run switched on and flagged (to turn into events after watching the clip)
    PUT    /clips/{id}          add a clip from a forensic run, or change a clip's events / note / clean flag
    DELETE /clips/{id}          remove a clip and the copies this tool made
    POST   /run                 score the clips (slow, in the background: about 10x the footage length)
    GET    /run/{id}            progress of that run;   POST /run/{id}/cancel   stop after the clip being analysed
    GET    /reports/{name}      one saved report

The scoring runs through this same backend over HTTP (like the command line), with "benchmark": true so nothing is
written to the Inbox. Folders come from service.BENCH / service.FORENSIC_DIR so tests can point them elsewhere.
"""
from __future__ import annotations

import threading
import time
import uuid
from pathlib import Path
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from . import registry, report, runner, scoring, service

router = APIRouter(prefix="/api/benchmark", tags=["benchmark"])

_RUNS: dict[str, dict] = {}
_LOCK = threading.Lock()


class EventIn(BaseModel):
    violation: str
    start: Any = 0
    end: Any = None
    plate: Optional[str] = None
    note: str = ""


class ClipIn(BaseModel):
    task_id: Optional[str] = None       # the forensic run this clip comes from (needed for a new clip)
    video_path: Optional[str] = None    # the original clip, when that run did not keep its own copy
    note: str = ""
    clean: bool = False
    events: list[EventIn] = []


class RunIn(BaseModel):
    label: str = "baseline"
    clips: Optional[list[str]] = None
    overrides: dict = {}


def _dump(model: BaseModel) -> dict:
    return model.model_dump() if hasattr(model, "model_dump") else model.dict()


def _fail(e: Exception):
    status = getattr(e, "status", 400)
    raise HTTPException(status_code=status, detail=str(e))


def _registry() -> registry.Registry:
    f = service.BENCH / "registry.yaml"
    try:
        return registry.load(f) if f.exists() else registry.Registry(dict(registry.DEFAULTS), [])
    except Exception as e:                                             # a hand-edit slip (bad YAML, unknown violation...)
        raise HTTPException(status_code=400, detail=f"benchmarks/registry.yaml cannot be read: {e}")


def _public(run: dict | None) -> dict | None:
    if run is None:
        return None
    return {k: v for k, v in run.items() if k not in ("cancel",)}


def _active() -> dict | None:
    return next((r for r in _RUNS.values() if r["status"] == "running"), None)


@router.get("/overview")
def overview():
    reg = _registry()
    clips = []
    for c in reg.clips:
        seconds = runner.probe(c.file)["seconds"] if c.file.exists() else None
        clips.append(service.clip_json(c, seconds))
    last = max(_RUNS.values(), key=lambda r: r["started"], default=None)
    return {"defaults": {"tolerance_s": reg.defaults["tolerance_s"], "min_events": reg.defaults["min_events"],
                         "pass": reg.defaults["pass"]},
            "violations": service.coverage(reg), "clips": clips, "problems": registry.problems(reg),
            "reports": service.list_reports(service.BENCH / "reports"), "run": _public(_active() or last)}


@router.get("/suggestions/{task_id}")
def suggestions(task_id: str):
    try:
        return service.suggestions(task_id, service.FORENSIC_DIR)
    except service.ServiceError as e:
        _fail(e)


@router.put("/clips/{clip_id}")
def save_clip(clip_id: str, body: ClipIn):
    f = service.BENCH / "registry.yaml"
    try:
        clip_id = service.safe_name(clip_id, "The clip name")
        raw = registry.load_raw(f)
        known = any(str(c.get("id")) == clip_id for c in raw.get("clips") or [])
        if body.task_id:
            service.copy_run(body.task_id, clip_id, service.FORENSIC_DIR, service.BENCH,
                             Path(body.video_path) if body.video_path else None)
        elif not known:
            raise service.ServiceError("A new clip needs the forensic run it comes from: the run carries the wizard's settings.")
        service.upsert_clip(raw, clip_id, body.note, body.clean, [_dump(e) for e in body.events])
        registry.save_raw(raw, f)
    except service.ServiceError as e:
        _fail(e)
    reg = _registry()
    clip = next(c for c in reg.clips if c.id == clip_id)
    return {"clip": service.clip_json(clip), "problems": [p for p in registry.problems(reg) if p.startswith(clip_id + ":")]}


@router.delete("/clips/{clip_id}")
def delete_clip(clip_id: str):
    f = service.BENCH / "registry.yaml"
    raw = registry.load_raw(f)
    if not service.delete_clip(raw, clip_id, service.BENCH):
        raise HTTPException(status_code=404, detail=f"No clip called {clip_id}.")
    registry.save_raw(raw, f)
    return {"deleted": clip_id}


# --------------------------------------------------------------------------- scoring in the background

def _worker(state: dict, clips: list, defaults: dict, base_url: str, overrides: dict) -> None:
    import requests
    try:
        runner.check_backend(base_url, requests)
        results = []
        for i, c in enumerate(clips):
            if state["cancel"]:
                state["status"] = "cancelled"
                return
            state.update(current=c.id, stage="starting")
            meta = runner.probe(c.file)
            out = runner.run_clip(c, base_url, overrides, log=lambda m: state.update(stage=str(m).strip()))
            frame = (meta["width"], meta["height"]) if meta["width"] and meta["height"] else None
            res = scoring.score_clip(c, out["tickets"], defaults["tolerance_s"], meta["seconds"], frame, service.EVIDENCE_DIR)
            results.append(res)
            state["clips_done"] = i + 1
            state["results"].append({"clip_id": c.id, "caught": len(res.caught), "false_alarms": len(res.false_alarms),
                                     "missed": len(res.missed), "seconds": out["wall_s"]})
        rep = report.build(state["label"], results, defaults, {"overrides": overrides, "backend": base_url, "via": "dashboard"})
        j, _ = report.save(rep, service.BENCH / "reports")
        state.update(status="done", report=j.stem, current=None, stage="")
    except Exception as e:                                             # shown in the tab; the backend keeps running
        state.update(status="failed", error=str(e), current=None)


@router.post("/run", status_code=202)
def start_run(body: RunIn, request: Request):
    reg = _registry()
    clips = [c for c in reg.clips if body.clips is None or c.id in body.clips]
    if not clips:
        raise HTTPException(status_code=400, detail="No clips to score. Add a clip first.")
    blocking = [p for p in registry.problems(reg)
                if "no events and not marked clean" not in p and any(p.startswith(c.id + ":") for c in clips)]
    if blocking:
        raise HTTPException(status_code=400, detail="Fix these first: " + " | ".join(blocking))
    with _LOCK:
        if _active():
            raise HTTPException(status_code=409, detail="A benchmark is already running.")
        state = {"id": uuid.uuid4().hex[:12], "status": "running", "label": body.label.strip() or "baseline",
                 "clips_total": len(clips), "clips_done": 0, "current": None, "stage": "", "error": None,
                 "report": None, "results": [], "started": time.time(), "cancel": False}
        _RUNS[state["id"]] = state
    base_url = str(request.base_url).rstrip("/")
    threading.Thread(target=_worker, args=(state, clips, reg.defaults, base_url, body.overrides), daemon=True).start()
    return {"run_id": state["id"]}


@router.get("/run/{run_id}")
def run_progress(run_id: str):
    state = _RUNS.get(run_id)
    if state is None:
        raise HTTPException(status_code=404, detail="No such run (the backend was restarted?).")
    return _public(state)


@router.post("/run/{run_id}/cancel")
def cancel_run(run_id: str):
    state = _RUNS.get(run_id)
    if state is None:
        raise HTTPException(status_code=404, detail="No such run.")
    state["cancel"] = True
    return {"status": "stopping after the clip being analysed"}


@router.get("/reports/{name}")
def get_report(name: str):
    try:
        return service.read_report(service.BENCH / "reports", name)
    except service.ServiceError as e:
        _fail(e)
