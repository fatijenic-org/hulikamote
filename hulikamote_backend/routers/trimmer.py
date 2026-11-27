import asyncio
import sys
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

import clip_cutter

LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost"}
FILMSTRIP_DIR = Path(tempfile.gettempdir()) / "hulikamote_filmstrips"
PREVIEW_DIR = Path(tempfile.gettempdir()) / "hulikamote_previews"


def local_only(request: Request) -> None:
    """These tools read and write files by path, so only the laptop itself may use them (the phone can reach the
    backend over Wi-Fi, but never this)."""
    host = request.client.host if request.client else ""
    if host not in LOCAL_HOSTS:
        raise HTTPException(status_code=403, detail="The video tools only work from this laptop.")


router = APIRouter(prefix="/api/trimmer", tags=["trimmer"], dependencies=[Depends(local_only)])

_manager: clip_cutter.JobManager | None = None


def manager() -> clip_cutter.JobManager:
    global _manager
    if _manager is None:
        _manager = clip_cutter.JobManager()
    return _manager


class Clip(BaseModel):
    start: float
    end: float
    label: str = ""


class JobsRequest(BaseModel):
    file_path: str
    clips: list[Clip]
    exact: bool = False             # re-encode for an exact cut; otherwise copy (instant, cut snaps to a keyframe)
    output_dir: str = ""            # empty = next to the video


def _video(path: str) -> Path:
    source = Path(path)
    if not source.is_file():
        raise HTTPException(status_code=404, detail="That video was not found")
    if source.suffix.lower() not in clip_cutter.VIDEO_EXTENSIONS:
        raise HTTPException(status_code=400, detail="That does not look like a video file")
    return source


@router.get("/probe")
async def probe_video(file_path: str):
    source = _video(file_path)
    try:
        return await asyncio.to_thread(clip_cutter.probe, source)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


_previews = clip_cutter.PreviewManager(PREVIEW_DIR)


@router.get("/setups")
async def saved_setups():
    """The saved setups (zones, signs and settings drawn for a camera view) the benchmark labeller can score clips with."""
    from engine.setup_presets import SetupPresets
    return {"setups": [{"id": p["id"], "name": p["name"], "violations": p["violations"], "updated": p["updated"]} for p in SetupPresets().list()]}


@router.get("/preview")
async def video_preview(file_path: str):
    """The file the trimmer should PLAY: the video itself when it is light, else a small copy made once in the background
    (poll until state is "ready"). The cuts always come from the original."""
    source = _video(file_path)
    try:
        info = await asyncio.to_thread(clip_cutter.probe, source)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return await asyncio.to_thread(_previews.status, source, info)


@router.get("/filmstrip")
async def video_filmstrip(file_path: str, count: int = 24):
    """The picture strip behind the timeline."""
    source = _video(file_path)
    try:
        picture = await asyncio.to_thread(clip_cutter.filmstrip, source, max(2, min(count, 60)), FILMSTRIP_DIR)
    except (ValueError, OSError) as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return FileResponse(picture, media_type="image/jpeg")


@router.post("/jobs", status_code=202)
async def start_jobs(req: JobsRequest):
    """Queue one cut per clip and return at once; poll GET /jobs for progress."""
    source = _video(req.file_path)
    if not 1 <= len(req.clips) <= clip_cutter.MAX_CLIPS_PER_REQUEST:
        raise HTTPException(status_code=400, detail=f"Send between 1 and {clip_cutter.MAX_CLIPS_PER_REQUEST} clips")
    try:
        info = await asyncio.to_thread(clip_cutter.probe, source)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    for number, clip in enumerate(req.clips, 1):
        if clip.start < 0 or clip.end - clip.start < clip_cutter.MIN_CLIP_SECONDS:
            raise HTTPException(status_code=400, detail=f"Clip {number} must start at 0 or later and be at least {clip_cutter.MIN_CLIP_SECONDS} s long")
        if clip.end > info["duration"] + 0.5:
            raise HTTPException(status_code=400, detail=f"Clip {number} ends after the video does ({info['duration']:.1f} s)")
    out_dir = None
    if req.output_dir.strip():
        out_dir = Path(req.output_dir.strip())
        try:
            out_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise HTTPException(status_code=400, detail=f"Cannot use that folder ({exc})")
    jobs = manager().submit(source, [c.model_dump() for c in req.clips], req.exact, out_dir)
    return {"jobs": [manager().get(j.id) for j in jobs]}


class BenchSlice(BaseModel):
    start: float
    end: float
    labels: list[str] = []          # violation keys, or "clean" for a stretch with nothing illegal
    export: bool = True             # false: cut before; only counted as an event inside neighbouring clips
    pad: float | None = None        # this slice's own extra seconds before and after (else the request's pad)
    count: int = 1                  # how many vehicles break the rule in this slice (each one is an event)
    plate: str | None = None        # the true plate of the vehicle (for the plate scores); empty = not readable
    clean_for: list[str] = []       # a clean slice: the violations it is clean for (empty = the common ones)


class BenchRequest(BaseModel):
    file_path: str
    slices: list[BenchSlice]
    pad: float = 3.0                # seconds of normal traffic kept around each event
    output_dir: str = ""            # empty = A:/huli-kamote/benchmark-videos
    reverse_counterflow: bool = False   # simulated wrong-way traffic: flip the legal direction of the counterflow rule
    setup_id: str | None = None     # a saved setup (zones, signs, settings of this camera view) to score the clips with
    incoming_two_wheelers: bool = False       # demo: judge motorcycles and tricycles that come toward the camera too
    overloading_max_riders: int | None = None  # demo: the most riders a motorcycle may carry (default 2)


@router.post("/benchmark", status_code=202)
async def start_benchmark_cuts(req: BenchRequest):
    """The benchmark labeller: cut every labelled slice into its own exact clip (several videos can be queued at once, they
    are cut in the background) and add each finished clip to benchmarks/registry.yaml with its events and settings."""
    source = _video(req.file_path)
    try:
        sys.path.append(str(Path(__file__).resolve().parents[2]))
        from tools.benchmark import labeler, registry as bench_registry
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"The benchmark tool could not be loaded ({exc})")
    try:
        info = await asyncio.to_thread(clip_cutter.probe, source)
        plan = labeler.plan(source.name, info["duration"], [s.model_dump() for s in req.slices], req.pad)
    except (ValueError, labeler.PlanError) as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if not plan["clips"]:
        raise HTTPException(status_code=400, detail="Nothing to cut: label at least one slice. " + " ".join(plan["skipped"]))
    if len(plan["clips"]) > clip_cutter.MAX_CLIPS_PER_REQUEST:
        raise HTTPException(status_code=400, detail=f"Too many clips at once (most {clip_cutter.MAX_CLIPS_PER_REQUEST}): export part of the video first.")
    out_dir = Path(req.output_dir.strip()) if req.output_dir.strip() else labeler.DEFAULT_OUT
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise HTTPException(status_code=400, detail=f"Cannot use that folder ({exc})")

    setup = None
    if req.setup_id:
        from engine.setup_presets import SetupPresets
        found = SetupPresets().get(req.setup_id)
        if found is None:
            raise HTTPException(status_code=404, detail="That saved setup was not found.")
        setup = found.get("config")

    def after_for(clip: dict):
        def after(job: dict) -> None:
            labeler.register(clip, Path(job["output"]), bench_registry.BENCH, setup=setup, reverse_counterflow=req.reverse_counterflow,
                             incoming_two_wheelers=req.incoming_two_wheelers, overloading_max_riders=req.overloading_max_riders)
        return after

    try:
        for key in labeler.FOLDERS:                                    # one folder for every violation (and "clean"), made once
            (out_dir / key).mkdir(exist_ok=True)
    except OSError as exc:
        raise HTTPException(status_code=400, detail=f"Cannot make the violation folders ({exc})")
    cuts = [{"start": c["start"], "end": c["end"], "name": c["name"], "label": "|".join(c["labels"]),
             "folder": str(out_dir / c["folder"]), "after": after_for(c)} for c in plan["clips"]]
    jobs = manager().submit(source, cuts, True, out_dir)          # exact: the events' seconds must match the clip
    return {"jobs": [manager().get(j.id) for j in jobs], "skipped": plan["skipped"], "folder": str(out_dir),
            "clip_ids": [c["name"] for c in plan["clips"]],
            "needs_zone": labeler.needs_zone({e["violation"] for c in plan["clips"] for e in c["events"]})}


@router.get("/benchmark/stats")
async def benchmark_stats():
    """What the benchmark folder holds, per violation: clips, events, seconds, events with a typed plate, and how far it is from the
    minimum number of events a verdict needs. Clean clips are counted by the violation they are judged for."""
    try:
        sys.path.append(str(Path(__file__).resolve().parents[2]))
        from tools.benchmark import labeler, registry as bench_registry
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"The benchmark tool could not be loaded ({exc})")

    def collect():
        reg = bench_registry.load(only_folder=bench_registry.CLIP_FOLDER)
        need = int(reg.defaults.get("min_events", 10))
        rows = {k: {"violation": k, "clips": 0, "events": 0, "seconds": 0.0, "plates": 0, "clean_clips": 0, "need": need} for k in labeler.FOLDERS}
        total = {"clips": 0, "seconds": 0.0, "missing": 0}
        for clip in reg.clips:
            seconds = 0.0
            if not clip.file.exists():
                total["missing"] += 1          # in the registry, but the video is gone: not counted (the folder does not hold it)
                continue
            try:
                seconds = float(clip_cutter.probe(clip.file)["duration"])
            except (ValueError, OSError, KeyError):
                seconds = 0.0
            total["clips"] += 1
            total["seconds"] += seconds
            if clip.clean:
                judged = [v for v in sorted(clip.enabled) if v in rows] or [labeler.CLEAN]
                for v in judged:
                    rows[v]["clean_clips"] += 1
                row = rows[labeler.CLEAN]
                row["clips"] += 1
                row["seconds"] += seconds
                continue
            for v in sorted({e.violation for e in clip.events}):
                row = rows.get(v)
                if row is None:
                    continue
                row["clips"] += 1
                row["seconds"] += seconds
                for e in clip.events:
                    if e.violation == v:
                        row["events"] += 1
                        row["plates"] += 1 if e.plate else 0
        out = [{**r, "seconds": round(r["seconds"], 1)} for r in rows.values() if r["clips"] or r["clean_clips"] or r["violation"] != labeler.CLEAN]
        return {"rows": out, "total": {**total, "seconds": round(total["seconds"], 1)}, "need": need}

    return await asyncio.to_thread(collect)


@router.get("/jobs")
async def list_jobs():
    return {"jobs": manager().jobs()}


@router.post("/jobs/clear")
async def clear_jobs():
    """Forget the finished, failed and cancelled jobs (the files stay)."""
    return {"cleared": manager().clear_finished()}


@router.delete("/jobs/{job_id}")
async def cancel_job(job_id: str):
    if not manager().cancel(job_id):
        raise HTTPException(status_code=404, detail="That job is not running or waiting")
    return manager().get(job_id)
