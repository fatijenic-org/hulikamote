import asyncio
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

import clip_cutter

LOCAL_HOSTS = {"127.0.0.1", "::1", "localhost"}
FILMSTRIP_DIR = Path(tempfile.gettempdir()) / "hulikamote_filmstrips"


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
