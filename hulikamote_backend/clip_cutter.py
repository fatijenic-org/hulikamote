"""
clip_cutter.py - cut clips out of a video with ffmpeg, as background jobs.

Every clip is its own job. Jobs wait in a small queue, two run at the same time, and the dashboard checks their
progress, so a person can keep editing (or open another video) while earlier clips are still being cut.

Two ways to cut:
  fast   copies the video as it is: no quality loss and almost instant, but the cut snaps to the nearest keyframe
         before the start time (usually within a second or two).
  exact  re-encodes just the clip so it starts and ends where asked. Slower.
"""
import hashlib
import json
import re
import subprocess
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass, field
from pathlib import Path

VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".m4v", ".webm", ".ts", ".mpg", ".mpeg", ".wmv", ".flv"}
MIN_CLIP_SECONDS = 0.1
MAX_CLIPS_PER_REQUEST = 50
WORKERS = 2


# ─── names and commands ──────────────────────────────────────────────────────

def clean_label(label: str) -> str:
    """Letters, digits, spaces, dashes and underscores only (it becomes part of a file name)."""
    kept = re.sub(r"[^A-Za-z0-9 _-]", "", label or "").strip()
    return re.sub(r"\s+", "-", kept)[:40]


def stamp(seconds: float) -> str:
    """65.5 -> '01m05s', 3725 -> '1h02m05s' (for file names)."""
    whole = int(seconds)
    hours, rest = divmod(whole, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}h{minutes:02d}m{secs:02d}s" if hours else f"{minutes:02d}m{secs:02d}s"


def output_path(source: Path, out_dir: Path | None, label: str, start: float, end: float, taken=lambda p: p.exists()) -> Path:
    """`<video>_<label>_<start>-<end>.<ext>` next to the video (or in out_dir). Never an existing file: -2, -3 ... is added."""
    parts = [source.stem, clean_label(label), f"{stamp(start)}-{stamp(end)}"]
    base = "_".join(p for p in parts if p)
    folder = out_dir or source.parent
    candidate, n = folder / f"{base}{source.suffix}", 2
    while taken(candidate):
        candidate = folder / f"{base}-{n}{source.suffix}"
        n += 1
    return candidate


def build_command(source: Path, output: Path, start: float, end: float, exact: bool, ffmpeg: str = "ffmpeg") -> list[str]:
    duration = end - start
    head = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1",
            "-ss", f"{start:.3f}", "-i", str(source), "-t", f"{duration:.3f}", "-map", "0:v:0", "-map", "0:a?"]
    if exact:
        return head + ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-c:a", "aac", "-b:a", "160k", str(output)]
    return head + ["-c", "copy", "-avoid_negative_ts", "make_zero", str(output)]


def progress_from_line(line: str, duration: float) -> float | None:
    """ffmpeg -progress prints out_time_us=<microseconds>. Returns 0..1, or None for any other line."""
    key, _, value = line.strip().partition("=")
    if key not in ("out_time_us", "out_time_ms") or not value.lstrip("-").isdigit():
        return None
    return max(0.0, min(1.0, int(value) / 1_000_000 / duration)) if duration > 0 else None


# ─── probing and the timeline picture ────────────────────────────────────────

def probe(path: Path, run=subprocess.run) -> dict:
    """{duration, fps, width, height} of a video, or raises ValueError if ffprobe cannot read it."""
    cmd = ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
           "stream=width,height,r_frame_rate,duration:format=duration", "-of", "json", str(path)]
    try:
        out = run(cmd, capture_output=True, text=True, timeout=30)
        data = json.loads(out.stdout or "{}")
        stream = (data.get("streams") or [{}])[0]
        duration = float(stream.get("duration") or data.get("format", {}).get("duration") or 0)
        num, _, den = str(stream.get("r_frame_rate", "0/1")).partition("/")
        fps = float(num) / float(den or 1) if float(den or 1) else 0.0
        if duration <= 0 or not stream.get("width"):
            raise ValueError("no video found")
        return {"duration": duration, "fps": round(fps, 3), "width": int(stream["width"]), "height": int(stream["height"])}
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, ZeroDivisionError) as exc:
        raise ValueError(f"ffmpeg cannot read this file ({exc})") from exc


def filmstrip(path: Path, count: int, cache_dir: Path, run=subprocess.run) -> Path:
    """One wide picture of `count` frames side by side, for behind the timeline. Cached. Only keyframes are decoded,
    so even a long recording takes seconds."""
    info = probe(path, run)
    stat = path.stat()
    key = hashlib.sha1(f"{path.resolve()}|{stat.st_mtime_ns}|{stat.st_size}|{count}".encode()).hexdigest()[:16]
    target = cache_dir / f"{key}.jpg"
    if target.exists():
        return target
    cache_dir.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-skip_frame", "nokey", "-i", str(path),
           "-vf", f"fps={count}/{info['duration']:.3f},scale=-2:72,tile={count}x1", "-frames:v", "1", "-q:v", "6", str(target)]
    done = run(cmd, capture_output=True, text=True, timeout=180)
    if done.returncode != 0 or not target.exists():
        raise ValueError(f"could not make the picture ({(done.stderr or '').strip()[-200:]})")
    return target


# ─── jobs ────────────────────────────────────────────────────────────────────

@dataclass
class Job:
    id: str
    source: str
    output: str
    start: float
    end: float
    label: str
    exact: bool
    status: str = "queued"            # queued | running | done | failed | cancelled
    progress: float = 0.0
    error: str = ""
    created_at: float = field(default_factory=time.time)
    finished_at: float = 0.0


class JobManager:
    def __init__(self, workers: int = WORKERS, popen=subprocess.Popen, ffmpeg: str = "ffmpeg"):
        self._popen, self._ffmpeg = popen, ffmpeg
        self._pool = ThreadPoolExecutor(max_workers=workers, thread_name_prefix="trim")
        self._lock = threading.Lock()
        self._jobs: dict[str, Job] = {}
        self._procs: dict[str, object] = {}

    def submit(self, source: Path, clips: list[dict], exact: bool, out_dir: Path | None) -> list[Job]:
        """One job per clip ({start, end, label}). Returns them at once; they run in the background."""
        made: list[Job] = []
        reserved: set[Path] = set()
        for clip in clips:
            out = output_path(source, out_dir, clip.get("label", ""), clip["start"], clip["end"], taken=lambda p: p.exists() or p in reserved)
            reserved.add(out)
            job = Job(id=uuid.uuid4().hex[:10], source=str(source), output=str(out), start=clip["start"], end=clip["end"],
                      label=clip.get("label", ""), exact=exact)
            with self._lock:
                self._jobs[job.id] = job
            made.append(job)
            self._pool.submit(self._run, job)
        return made

    def jobs(self) -> list[dict]:
        """Newest first."""
        with self._lock:
            return [asdict(j) for j in sorted(self._jobs.values(), key=lambda j: j.created_at, reverse=True)]

    def get(self, job_id: str) -> dict | None:
        with self._lock:
            job = self._jobs.get(job_id)
            return asdict(job) if job else None

    def cancel(self, job_id: str) -> bool:
        """Stops a waiting or running job. False if it is unknown or already finished."""
        with self._lock:
            job = self._jobs.get(job_id)
            if not job or job.status not in ("queued", "running"):
                return False
            job.status = "cancelled"
            job.finished_at = time.time()
            proc = self._procs.get(job_id)
        if proc is not None:
            proc.terminate()
        return True

    def clear_finished(self) -> int:
        with self._lock:
            gone = [i for i, j in self._jobs.items() if j.status in ("done", "failed", "cancelled")]
            for i in gone:
                del self._jobs[i]
            return len(gone)

    def _set(self, job: Job, **changes) -> None:
        with self._lock:
            for key, value in changes.items():
                setattr(job, key, value)

    def _run(self, job: Job) -> None:
        with self._lock:
            if job.status == "cancelled":
                return
            job.status = "running"
        out = Path(job.output)
        try:
            out.parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            self._finish(job, "failed", f"Cannot use the output folder: {exc}")
            return
        cmd = build_command(Path(job.source), out, job.start, job.end, job.exact, self._ffmpeg)
        try:
            proc = self._popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            with self._lock:
                self._procs[job.id] = proc
            for line in proc.stdout:
                fraction = progress_from_line(line, job.end - job.start)
                if fraction is not None and job.status == "running":
                    self._set(job, progress=fraction)
            error = (proc.stderr.read() or "").strip()
            code = proc.wait()
        except OSError as exc:
            self._finish(job, "failed", f"Could not start ffmpeg: {exc}")
            return
        finally:
            with self._lock:
                self._procs.pop(job.id, None)
        if job.status == "cancelled":
            out.unlink(missing_ok=True)
        elif code != 0 or not out.exists():
            out.unlink(missing_ok=True)
            self._finish(job, "failed", error[-400:] or f"ffmpeg stopped with code {code}")
        else:
            self._finish(job, "done", "", progress=1.0)

    def _finish(self, job: Job, status: str, error: str, progress: float | None = None) -> None:
        changes = {"status": status, "error": error, "finished_at": time.time()}
        if progress is not None:
            changes["progress"] = progress
        self._set(job, **changes)
