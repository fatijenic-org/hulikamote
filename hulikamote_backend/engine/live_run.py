"""
live_run.py - the pictures of one live run, kept on disk.

The playback buffer (engine/playout.py) holds only the times and the boxes of a finished picture in memory; the picture itself (a JPEG) is
written here the moment it is finished and read back when it is shown. So the screen can be far behind the backend (the enforcer paused, or
is looking at a ticket) and can go back and forth over what is done, without the memory growing with it.

By default a run is temporary: pictures that are far behind the playhead are deleted, and the next run clears the old folder. When the
operator chose "Save this run" (live_record.json: {"save": true, "dir": "..."}), the run goes to that folder and every picture stays, with
`index.jsonl` (one line per picture: time, size, boxes) and `run.json`, so it can be replayed later like a forensic run.
"""
import base64
import json
import logging
import shutil
import threading
import time
from datetime import datetime
from pathlib import Path

log = logging.getLogger(__name__)

BACKEND_DIR = Path(__file__).resolve().parent.parent
TEMP_ROOT = BACKEND_DIR / "snapshots" / "live_run"
SETTINGS_PATH = BACKEND_DIR / "live_record.json"


def read_settings() -> dict:
    """{"save": bool, "dir": str}: what the operator chose in the live setup (not saving, and the default folder, when nothing was chosen)."""
    try:
        data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    return {"save": bool(data.get("save")), "dir": str(data.get("dir") or "")}


def write_settings(save: bool, folder: str) -> dict:
    """Keep the choice. A folder that cannot be made is an error (ValueError) and nothing is changed."""
    folder = (folder or "").strip()
    if save:
        if not folder:
            raise ValueError("Choose the folder to save the run in.")
        try:
            Path(folder).mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise ValueError(f"The folder cannot be used: {exc}") from exc
    SETTINGS_PATH.write_text(json.dumps({"save": bool(save), "dir": folder}, indent=2), encoding="utf-8")
    return read_settings()


class LiveRun:
    def __init__(self, folder: Path, keep_all: bool):
        self.folder = Path(folder)
        self.keep_all = keep_all
        self.frames = self.folder / "frames"
        self.frames.mkdir(parents=True, exist_ok=True)
        self.started = datetime.now().isoformat(timespec="seconds")
        self._n = 0
        self._count = 0
        self._lock = threading.Lock()
        self._index = open(self.folder / "index.jsonl", "a", encoding="utf-8") if keep_all else None
        self._index_lock = threading.Lock()

    def store(self, picture_b64: str) -> str:
        """Write one finished picture (base64 JPEG) and return its file name."""
        with self._lock:
            self._n += 1
            name = f"{self._n:07d}.jpg"
        (self.frames / name).write_bytes(base64.b64decode(picture_b64))
        self._count += 1
        return name

    def load_b64(self, name: str) -> str | None:
        try:
            return base64.b64encode((self.frames / name).read_bytes()).decode("ascii")
        except OSError:
            return None

    def drop(self, name: str | None) -> None:
        """A picture that nobody will show again (not when the run is saved)."""
        if self.keep_all or not name:
            return
        try:
            (self.frames / name).unlink(missing_ok=True)
        except OSError:
            pass

    def note(self, name: str | None, t: float, w: int, h: int, detections, boxes) -> None:
        """Saved runs only: one line per picture with its time and boxes (the same boxes the live screen and the forensic replay draw)."""
        if self._index is None or not name:
            return
        line = json.dumps({"file": name, "t": round(float(t), 3), "w": w, "h": h, "detections": detections, "boxes": boxes}, default=str)
        with self._index_lock:
            self._index.write(line + "\n")
            if self._count % 30 == 0:
                self._index.flush()

    def close(self, meta: dict | None = None) -> None:
        try:
            if self._index is not None:
                with self._index_lock:
                    self._index.flush()
                    self._index.close()
            if self.keep_all:
                info = {"started": self.started, "ended": datetime.now().isoformat(timespec="seconds"), "pictures": self._count, **(meta or {})}
                (self.folder / "run.json").write_text(json.dumps(info, indent=2, default=str), encoding="utf-8")
        except OSError:
            pass


def start() -> LiveRun | None:
    """A new run: in the folder the operator chose (saved), or in a temporary one (older temporary runs are removed first). None when the
    disk cannot be written: the pictures then stay in memory, as before."""
    try:
        settings = read_settings()
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        if settings["save"] and settings["dir"]:
            return LiveRun(Path(settings["dir"]) / f"live_run_{stamp}", keep_all=True)
        shutil.rmtree(TEMP_ROOT, ignore_errors=True)
        return LiveRun(TEMP_ROOT / stamp, keep_all=False)
    except Exception as exc:
        log.warning("The live run folder could not be made (%s): pictures stay in memory", exc)
        return None
