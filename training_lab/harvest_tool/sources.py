"""
sources.py - Read what the backend already saved: forensic reports, evidence photos, ticket statuses.

Everything here is READ-ONLY. The tickets database is opened with mode=ro (and copied to a
temp file if SQLite refuses), so reading never blocks or changes the running backend.
"""
import json
import re
import shutil
import sqlite3
import tempfile
from contextlib import closing
from dataclasses import dataclass, field
from pathlib import Path

from .config import Paths

UNREAD_PLATES = ("unidentified", "no_plate_found", "", None)


@dataclass
class Frame:
    image: Path              # clean picture of the vehicle (no boxes / zones drawn on it)
    t: float | None = None   # seconds into the clip
    vclass: str | None = None
    box: tuple | None = None         # the picture's area in the clip's frame: (x, y, w, h) pixels
    car_crop: Path | None = None     # the tight crop of the vehicle itself (what the car matcher is trained with), when saved
    vbox: tuple | None = None        # where the vehicle itself was in the clip's frame: (x, y, w, h)


@dataclass
class Ticket:
    task_id: str
    uid: str
    track_id: int
    violations: list[str]
    plate_text: str
    plate_found: bool
    db_ids: list[str]
    frames: list[Frame] = field(default_factory=list)
    status_by_violation: dict = field(default_factory=dict)   # violation -> approved | rejected | pending
    crops: list[Frame] = field(default_factory=list)          # every usable picture of this vehicle, not a sample


def _ro_uri(db: Path) -> str:
    return db.resolve().as_uri() + "?mode=ro"


def _query(con: sqlite3.Connection, ids: list[str]) -> dict:
    out = {}
    for i in range(0, len(ids), 400):
        chunk = ids[i:i + 400]
        marks = ",".join("?" for _ in chunk)
        for row in con.execute(f"SELECT id, cls, status FROM violations WHERE id IN ({marks})", chunk):
            out[row[0]] = (row[1], row[2])
    return out


def read_statuses(db: Path, ids: list[str]) -> dict[str, tuple[str, str]]:
    """{violation_id: (violation, status)} for the given ids. Empty if the DB is missing."""
    ids = [i for i in ids if i]
    if not ids or not db.exists():
        return {}
    try:
        with closing(sqlite3.connect(_ro_uri(db), uri=True, timeout=5)) as con:
            return _query(con, ids)
    except sqlite3.Error:
        # Fall back to a private copy (never write next to the live DB).
        tmp = Path(tempfile.mkdtemp(prefix="harvest_db_")) / "copy.db"
        try:
            shutil.copy2(db, tmp)
            with closing(sqlite3.connect(tmp)) as con:
                return _query(con, ids)
        except (sqlite3.Error, OSError):
            return {}
        finally:
            shutil.rmtree(tmp.parent, ignore_errors=True)


def review_counts(db: Path) -> dict[str, dict[str, int]]:
    """{violation: {approved, rejected, pending}} for forensic tickets - how the rules are doing."""
    if not db.exists():
        return {}
    try:
        with closing(sqlite3.connect(_ro_uri(db), uri=True, timeout=5)) as con:
            rows = con.execute("SELECT cls, status, COUNT(*) FROM violations WHERE source='forensic' "
                               "GROUP BY cls, status").fetchall()
    except sqlite3.Error:
        return {}
    out: dict[str, dict[str, int]] = {}
    for cls, status, n in rows:
        out.setdefault(cls, {"approved": 0, "rejected": 0, "pending": 0})[status] = n
    return out


def forensic_task_ids(paths: Paths) -> list[str]:
    if not paths.forensic.exists():
        return []
    return sorted(d.name for d in paths.forensic.iterdir()
                  if d.is_dir() and d.name != "temp" and (d / "output" / "report.json").exists())


def _usable(paths: Paths, meta: list[dict], min_side: int) -> list[Frame]:
    """Every clean, big-enough picture of the vehicle, in time order."""
    usable = []
    for m in meta or []:
        name = m.get("clean") or m.get("car_crop")
        if not name:
            continue
        path = paths.evidence / name
        if not path.exists():
            continue
        box = m.get("clean_box") or m.get("bbox") or [0, 0, 0, 0]
        if min(box[2], box[3]) < min_side:
            continue
        crop = paths.evidence / m["car_crop"] if m.get("car_crop") else None
        vbox = tuple(m["bbox"]) if m.get("bbox") else None
        usable.append(Frame(path, m.get("t"), m.get("vclass"), tuple(box), crop if crop and crop.exists() else None, vbox))
    return usable


def _frames(paths: Paths, meta: list[dict], max_frames: int, min_side: int) -> list[Frame]:
    """Up to max_frames evenly spaced, clean, big-enough pictures of the vehicle."""
    usable = _usable(paths, meta, min_side)
    if len(usable) <= max_frames:
        return usable
    step = (len(usable) - 1) / (max_frames - 1) if max_frames > 1 else 0
    return [usable[round(i * step)] for i in range(max_frames)]


def _track_number(value) -> int:
    """The tracker's number of a ticket. A ticket the Forensic Analyzer merged from two tracks says "412 & 5": the first one."""
    match = re.search(r"-?\d+", str(value))
    return int(match.group()) if match else -1


def tickets(paths: Paths, task_id: str, max_frames: int = 3, min_side: int = 60) -> list[Ticket]:
    report = json.loads((paths.forensic / task_id / "output" / "report.json").read_text(encoding="utf-8"))
    ids = [i for t in report for i in t.get("db_ids", [])]
    statuses = read_statuses(paths.db, ids)
    out = []
    for t in report:
        by_violation = {}
        for db_id in t.get("db_ids", []):
            if db_id in statuses:
                cls, status = statuses[db_id]
                by_violation[cls] = status
        plate_text = str(t.get("plate_text") or "")
        out.append(Ticket(
            task_id=task_id,
            uid=str(t.get("ticket_uid") or f"track{t.get('track_id')}"),
            track_id=_track_number(t.get("track_id")),
            violations=list(t.get("violations", [])),
            plate_text=plate_text,
            plate_found=plate_text not in UNREAD_PLATES and bool(t.get("plate_crop_paths")),
            db_ids=list(t.get("db_ids", [])),
            frames=_frames(paths, t.get("evidence_meta", []), max_frames, min_side),
            crops=_usable(paths, t.get("evidence_meta", []), min_side),
            status_by_violation=by_violation,
        ))
    return out


# ── protected clips (benchmark footage must never be harvested) ──

def protected_path(paths: Paths) -> Path:
    return paths.inbox / "protected.json"


def load_protected(paths: Paths) -> set[str]:
    try:
        return set(json.loads(protected_path(paths).read_text()).get("task_ids", []))
    except Exception:
        return set()


def set_protected(paths: Paths, task_id: str, on: bool = True) -> set[str]:
    current = load_protected(paths)
    current.add(task_id) if on else current.discard(task_id)
    paths.inbox.mkdir(parents=True, exist_ok=True)
    protected_path(paths).write_text(json.dumps({"task_ids": sorted(current)}, indent=2))
    return current
