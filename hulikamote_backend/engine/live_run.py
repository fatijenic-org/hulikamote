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
CURRENT: dict = {"run": None}          # the run being written now (the "Save and pause" endpoint finds it here)
CONTINUE: dict = {"folder": None}      # a saved monitoring to go on with: the next run is written into this folder, after what is there
SAVED_REPLAY_S = 600.0                 # a saved run: how far back the live timeline can go (everything stays on disk, and is replayable in full later)


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
    def __init__(self, folder: Path, keep_all: bool, resume: bool = False):
        self.folder = Path(folder)
        self.keep_all = keep_all
        self.resumed = bool(resume)
        self.frames = self.folder / "frames"
        self.frames.mkdir(parents=True, exist_ok=True)
        self.started = datetime.now().isoformat(timespec="seconds")
        self._n = 0
        self._count = 0
        self._t_last = None                  # a run that goes on: the time of its last picture (the new pictures continue after it)
        self._t_first = None                 # the time of the first picture of the run (the replay counts from it)
        self._t_written = None               # the time of the newest picture written
        self._t_shift = None
        self._meta: dict = {}
        if resume:
            self._n = max((int(p.stem) for p in self.frames.glob("*.jpg") if p.stem.isdigit()), default=0)
            self._count = self._n
            self._t_last = self._tail_time()
            self._t_written = self._t_last
            self._t_first = self._head_time()
            try:
                self._meta = json.loads((self.folder / "run.json").read_text(encoding="utf-8"))
                self.started = self._meta.get("started") or self.started
            except (OSError, ValueError):
                pass
        self._lock = threading.Lock()
        self._index = open(self.folder / "index.jsonl", "a", encoding="utf-8") if keep_all else None
        self._index_lock = threading.Lock()
        self.set_meta()

    def _head_time(self):
        """The time of the first picture in index.jsonl (None when there is none)."""
        try:
            with open(self.folder / "index.jsonl", "rb") as fh:
                for line in fh:
                    try:
                        return float(json.loads(line)["t"])
                    except (ValueError, KeyError):
                        continue
        except OSError:
            pass
        return None

    def _tail_time(self):
        """The time of the last picture in index.jsonl (None when there is none)."""
        try:
            with open(self.folder / "index.jsonl", "rb") as fh:
                fh.seek(0, 2)
                fh.seek(max(0, fh.tell() - 65536))
                lines = fh.read().splitlines()
            for line in reversed(lines):
                try:
                    return float(json.loads(line)["t"])
                except (ValueError, KeyError):
                    continue
        except OSError:
            pass
        return None

    def set_meta(self, **extra) -> None:
        """run.json: what this run is. Written at the start and every few hundred pictures (a run that is cut off, e.g. by a restart, still says what it is)."""
        if not self.keep_all:
            return
        self._meta.update(extra)
        info = {**self._meta, "started": self.started, "ended": None, "pictures": self._count}
        try:
            (self.folder / "run.json").write_text(json.dumps(info, indent=2, default=str), encoding="utf-8")
        except OSError:
            pass

    def save_session(self, data: dict) -> None:
        """session.json: everything needed to go on with this monitoring later (setup, source, where the video was)."""
        marks: list = []                     # every place where this monitoring was saved and paused, on the replay's timeline (seconds from its start)
        try:
            marks = list(json.loads((self.folder / "session.json").read_text(encoding="utf-8")).get("pauses") or [])
        except (OSError, ValueError):
            pass
        if self._t_first is not None and self._t_written is not None:
            marks.append({"t": round(self._t_written - self._t_first, 3), "saved_at": data.get("saved_at"), "pos_s": data.get("pos_s")})
        data = {**data, "pauses": marks}
        tmp = self.folder / "session.json.tmp"
        tmp.write_text(json.dumps(data, indent=2, default=str), encoding="utf-8")
        tmp.replace(self.folder / "session.json")
        if self._index is not None:
            with self._index_lock:
                self._index.flush()
        self.set_meta()

    def reserve(self) -> str:
        """The name of the next picture file (made now, written by write() a moment later, in a worker)."""
        with self._lock:
            self._n += 1
            return f"{self._n:07d}.jpg"

    def write(self, name: str, picture_b64: str) -> str:
        (self.frames / name).write_bytes(base64.b64decode(picture_b64))
        self._count += 1
        return name

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
        if self._t_shift is None:
            self._t_shift = (self._t_last + 1.0 / 30.0 - float(t)) if self._t_last is not None else 0.0     # (a run that goes on keeps counting up)
        t = float(t) + self._t_shift
        if self._t_first is None:
            self._t_first = t
        self._t_written = t
        line = json.dumps({"file": name, "t": round(float(t), 3), "wall": round(time.time(), 3), "w": w, "h": h, "detections": detections, "boxes": boxes}, default=str)
        with self._index_lock:
            self._index.write(line + "\n")
            if self._count % 5 == 0:
                self._index.flush()
        if self._count % 300 == 0:
            self.set_meta()

    def close(self, meta: dict | None = None) -> None:
        try:
            if self._index is not None:
                with self._index_lock:
                    self._index.flush()
                    self._index.close()
            if self.keep_all:
                info = {**self._meta, "started": self.started, "ended": datetime.now().isoformat(timespec="seconds"), "pictures": self._count, **(meta or {})}
                (self.folder / "run.json").write_text(json.dumps(info, indent=2, default=str), encoding="utf-8")
        except OSError:
            pass
        if CURRENT.get("run") is self:
            CURRENT["run"] = None


def will_save() -> bool:
    """True when the next run is saved (the operator's switch, or a saved monitoring that goes on)."""
    settings = read_settings()
    return bool(CONTINUE.get("folder")) or bool(settings["save"] and settings["dir"])


def start() -> LiveRun | None:
    """A new run: in the folder the operator chose (saved), or in a temporary one (older temporary runs are removed first). None when the
    disk cannot be written: the pictures then stay in memory, as before."""
    try:
        settings = read_settings()
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        cont = CONTINUE.get("folder")
        CONTINUE["folder"] = None
        if cont and Path(cont).is_dir():                               # a saved monitoring goes on in its own folder
            run = LiveRun(Path(cont), keep_all=True, resume=True)
        elif settings["save"] and settings["dir"]:
            run = LiveRun(Path(settings["dir"]) / f"live_run_{stamp}", keep_all=True)
        else:
            shutil.rmtree(TEMP_ROOT, ignore_errors=True)
            run = LiveRun(TEMP_ROOT / stamp, keep_all=False)
        CURRENT["run"] = run
        return run
    except Exception as exc:
        log.warning("The live run folder could not be made (%s): pictures stay in memory", exc)
        return None
