"""
demo_replay.py - a recorded run, played back in the Live Monitor as a DEMO.

How a demo is made (all in the open, nothing is hidden):
  1. Run the Live Monitor once with "Save this run" on: every picture and its boxes go to a folder (engine/live_run.py).
  2. Review and fix the live tickets by hand (plates, merge, split ...): the usual review screen.
  3. "Make demo from the last saved run" (POST /settings/demo/create): the pictures, the boxes and the tickets (with their photos) are copied
     to demos/<id>/, with the name of the video file they belong to.

How it is used: the Demo switch is on, the operator picks the video and sets up the violations as usual, presses Start, and when the video
file has a demo, the Live Monitor plays the recorded run (pictures, boxes, timeline, tickets released at the moment they happened) instead of
running the models. The screen shows a "DEMO REPLAY" badge all the time.

demos/<id>/: demo.json, index.jsonl, frames/, tickets.json, config.json, photos/.
"""
import base64
import bisect
import json
import re
import shutil
from datetime import datetime
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
DEMO_ROOT = BACKEND_DIR / "demos"
FLAG_PATH = BACKEND_DIR / "demo_mode.json"
TICKET_DELAY_S = 0.5                    # a ticket shows this long after the last photo of its vehicle
PROC_AHEAD_S = 6.0                      # the timeline shows the "backend" this far ahead of the screen (never beyond the end)


def is_on() -> bool:
    try:
        return bool(json.loads(FLAG_PATH.read_text(encoding="utf-8")).get("on"))
    except (OSError, ValueError):
        return False


def set_on(on: bool) -> bool:
    FLAG_PATH.write_text(json.dumps({"on": bool(on)}), encoding="utf-8")
    return is_on()


def _key(video) -> str:
    return Path(str(video)).name.strip().lower()


def find(video) -> Path | None:
    """The demo folder that belongs to this video file (by file name), or None."""
    key = _key(video)
    for meta in sorted(DEMO_ROOT.glob("*/demo.json")):
        try:
            data = json.loads(meta.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if key in [str(v).strip().lower() for v in data.get("videos", [])]:
            return meta.parent
    return None


def list_demos() -> list[dict]:
    out = []
    for meta in sorted(DEMO_ROOT.glob("*/demo.json")):
        try:
            data = json.loads(meta.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        out.append({"id": meta.parent.name, **data})
    return out


def delete_demo(demo_id: str) -> bool:
    folder = DEMO_ROOT / Path(demo_id).name
    if folder.is_dir() and (folder / "demo.json").exists():
        shutil.rmtree(folder, ignore_errors=True)
        return True
    return False


def last_saved_run(root: Path) -> Path | None:
    """The newest saved live run (a live_run_<stamp> folder with index.jsonl) under `root`."""
    runs = [p for p in root.glob("live_run_*") if (p / "index.jsonl").exists()] if root.is_dir() else []
    return max(runs, key=lambda p: p.stat().st_mtime, default=None)


def _read_index(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue                          # a half-written last line
    return rows


def create(run_dir: Path, videos: list[str], title: str, tickets: list, config: dict, photo_files) -> dict:
    """Copy a saved run and the live tickets into a new demo. `photo_files(ticket)` -> the picture files (Paths) a ticket owns.
    BLOCKING (copies the pictures): call it in a thread. Raises ValueError when the run has no pictures."""
    rows = _read_index(run_dir / "index.jsonl")
    rows = [r for r in rows if (run_dir / "frames" / str(r.get("file"))).exists()]
    if not rows:
        raise ValueError("That run has no pictures.")
    slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_") or "demo"
    folder = DEMO_ROOT / f"{slug}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    (folder / "photos").mkdir(parents=True)
    shutil.copytree(run_dir / "frames", folder / "frames")
    (folder / "index.jsonl").write_text("\n".join(json.dumps(r, default=str) for r in rows) + "\n", encoding="utf-8")
    t0 = float(rows[0]["t"])
    duration = float(rows[-1]["t"]) - t0
    items = []
    for ticket in tickets:
        metas = [m.get("t") for m in ticket.get("evidence_meta", []) if isinstance(m.get("t"), (int, float))]
        at = (max(metas) - t0 + TICKET_DELAY_S) if metas else 0.0
        clean = {k: v for k, v in ticket.items() if k not in ("db_ids", "ticket_uid")}
        for src in photo_files(ticket):
            try:
                shutil.copy2(src, folder / "photos" / Path(src).name)
            except OSError:
                continue                          # a photo that is gone: the ticket shows without it
        items.append({"at": round(max(0.0, min(at, duration)), 2), "ticket": clean})
    items.sort(key=lambda i: i["at"])
    (folder / "tickets.json").write_text(json.dumps(items, indent=2, default=str), encoding="utf-8")
    (folder / "config.json").write_text(json.dumps(config, indent=2, default=str), encoding="utf-8")
    meta = {"title": title, "videos": [Path(v).name for v in videos], "created": datetime.now().isoformat(timespec="seconds"),
            "pictures": len(rows), "tickets": len(items), "duration_s": round(duration, 1), "source_run": str(run_dir)}
    (folder / "demo.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return {"id": folder.name, **meta}


# ── The demo editor: correct what a vehicle is called, its plate and its violation, in every picture and ticket of the demo ──────────

VIOLATION_COLORS = {"no_helmet": (255, 165, 0), "no_seatbelt": (255, 255, 0), "red_light": (255, 0, 0), "wrong_lane": (255, 0, 255)}   # RGB, as the box file keeps them
VEHICLE_KINDS = ("car", "motorcycle", "bus", "jeepney", "truck", "tricycle", "pickup")


def violation_keys() -> list[str]:
    try:
        from engine.violations import REGISTRY
        return sorted(REGISTRY)
    except Exception:
        return []


def _vehicle_spec(specs, bbox):
    """The box of the vehicle itself in a picture's box file (it has a "plate" entry; timers and marks with the same box do not)."""
    if not isinstance(specs, list):
        return None
    return next((s for s in specs if isinstance(s, dict) and "plate" in s and list(s.get("box") or []) == list(bbox)), None)


def _parse_label(line: str | None) -> tuple[str | None, str]:
    """"PLATE - KIND" or "KIND" -> (plate or None, KIND)."""
    if not line:
        return None, "VEHICLE"
    if " - " in line:
        plate, kind = line.rsplit(" - ", 1)
        return (plate.strip() or None), kind.strip().upper() or "VEHICLE"
    return None, line.strip().upper() or "VEHICLE"


def _inside(box, outer, slack: int = 3) -> bool:
    try:
        x, y, w, h = [float(v) for v in box]
        ox, oy, ow, oh = [float(v) for v in outer]
    except (TypeError, ValueError):
        return False
    return x >= ox - slack and y >= oy - slack and x + w <= ox + ow + slack and y + h <= oy + oh + slack


def _point_inside(at, outer, slack: int = 3) -> bool:
    try:
        x, y = float(at[0]), float(at[1])
        ox, oy, ow, oh = [float(v) for v in outer]
    except (TypeError, ValueError, IndexError):
        return False
    return ox - slack <= x <= ox + ow + slack and oy - slack <= y <= oy + oh + slack


def tracks(folder: Path) -> list[dict]:
    """The vehicles of a demo (one entry per tracker number): what they are called now, their plate, their violation, how long they are seen."""
    rows = _read_index(Path(folder) / "index.jsonl")
    if not rows:
        return []
    t0 = float(rows[0]["t"])
    found: dict = {}
    for n, row in enumerate(rows):
        for d in row.get("detections") or []:
            tid = d.get("track_id")
            if not isinstance(tid, int) or tid < 0:
                continue
            spec = _vehicle_spec(row.get("boxes"), d.get("bbox") or [])
            violator = bool(d.get("is_violator"))
            if spec is None and (violator is False and d.get("class") not in VEHICLE_KINDS):
                continue                                              # a person or another thing, not a vehicle
            plate, kind = _parse_label(spec["lines"][-1] if spec and spec.get("lines") else None)
            if spec is None:
                kind = str(d.get("class") or "vehicle").upper() if not violator else "VEHICLE"
                plate = d.get("user_name") or None
            item = found.setdefault(tid, {"track_id": tid, "frames": 0, "first_s": round(float(row["t"]) - t0, 1), "best": n,
                                          "best_area": 0})
            item["frames"] += 1
            item["last_s"] = round(float(row["t"]) - t0, 1)
            item["kind"], item["plate"] = kind.lower(), plate
            item["violation"] = str(d.get("class") or "") if violator else ""
            bb = d.get("bbox") or [0, 0, 0, 0]
            area = (bb[2] * bb[3]) if len(bb) == 4 else 0
            if area > item["best_area"]:
                item["best_area"], item["best"] = area, n
    try:
        tickets = json.loads((Path(folder) / "tickets.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        tickets = []
    out = []
    for item in sorted(found.values(), key=lambda i: i["first_s"]):
        item["tickets"] = sum(1 for e in tickets if item["track_id"] in _ticket_tracks(e["ticket"]))
        item.pop("best_area", None)
        out.append(item)
    return out


def _ticket_tracks(ticket: dict) -> list:
    return [i for i in (ticket.get("merged_track_ids") or [ticket.get("track_id")]) if isinstance(i, int)]


def _edit_row(row: dict, track_id: int, kind, plate, violation, delete: bool) -> bool:
    dets = row.get("detections") or []
    specs = row.get("boxes")
    hit = False
    for d in list(dets):
        if d.get("track_id") != track_id:
            continue
        hit = True
        bbox = list(d.get("bbox") or [0, 0, 0, 0])
        spec = _vehicle_spec(specs, bbox)
        if delete:
            dets.remove(d)
            if isinstance(specs, list):
                specs[:] = [s for s in specs if not (isinstance(s, dict) and (_inside(s.get("box"), bbox) or _point_inside(s.get("at"), bbox)))]
            continue
        old_plate, old_kind = _parse_label(spec["lines"][-1] if spec and spec.get("lines") else None)
        if spec is None:
            old_kind, old_plate = "VEHICLE", d.get("user_name") or None
        new_kind = str(kind).strip().upper() if kind else old_kind
        new_plate = old_plate if plate is None else (str(plate).strip().upper() or None)
        who = f"{new_plate} - {new_kind}" if new_plate else new_kind
        was = str(d.get("class") or "") if d.get("is_violator") else ""
        now = was if violation is None else str(violation).strip()
        d["user_name"] = new_plate
        if now:
            d["is_violator"], d["class"] = True, now
        else:
            d["is_violator"] = False
            d["class"] = new_kind.lower() if new_kind != "VEHICLE" else (d.get("class") if d.get("class") in VEHICLE_KINDS else "car")
            d["marks"] = []
        if spec is not None:
            if now:
                spec["color"] = list(VIOLATION_COLORS.get(now.split("+")[0], (255, 0, 0)))
                spec["lines"] = now.replace("_", " ").upper().split("+") + [who]
            else:
                spec["color"] = [0, 255, 0]
                spec["lines"] = [who]
                specs[:] = [s for s in specs if s is spec or not (isinstance(s, dict) and (_inside(s.get("box"), bbox) or _point_inside(s.get("at"), bbox)))]
    return hit


def edit_track(folder: Path, track_id: int, kind: str | None = None, plate: str | None = None, violation: str | None = None,
               delete: bool = False) -> dict:
    """Correct one vehicle in every picture and ticket of the demo. `kind` (car, motorcycle ...) and `plate` change its label; `violation`
    sets its violation ("" = none: the box turns green and its ticket goes); `delete` removes the vehicle and its tickets. None = unchanged.
    BLOCKING (rewrites the files). Returns {"pictures", "tickets"} = how many were changed."""
    from engine.ticket_merge import apply_plate_edit

    folder = Path(folder)
    if kind is not None and str(kind).strip().lower() not in VEHICLE_KINDS and str(kind).strip():
        raise ValueError(f"Unknown vehicle: {kind}")
    if violation and not re.fullmatch(r"[a-z_+]+", violation.strip()):
        raise ValueError(f"Unknown violation: {violation}")
    rows = _read_index(folder / "index.jsonl")
    changed = sum(1 for row in rows if _edit_row(row, track_id, kind or None, plate, violation, delete))
    tmp = folder / "index.jsonl.tmp"
    tmp.write_text("\n".join(json.dumps(r, default=str) for r in rows) + "\n", encoding="utf-8")
    tmp.replace(folder / "index.jsonl")

    try:
        items = json.loads((folder / "tickets.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        items = []
    kept, touched = [], 0
    for entry in items:
        ticket = entry["ticket"]
        if track_id not in _ticket_tracks(ticket):
            kept.append(entry)
            continue
        touched += 1
        if delete or (violation is not None and not violation.strip()):
            continue                                                  # its vehicle has no violation (any more): no ticket
        if plate is not None:
            fmt = (ticket.get("metadata") or {}).get("plate_format", "ph_standard")
            ticket = apply_plate_edit(ticket, str(plate), plate_format=fmt)
        if violation:
            ticket["violations"] = [v for v in violation.strip().split("+") if v]
        entry["ticket"] = ticket
        kept.append(entry)
    tmp = folder / "tickets.json.tmp"
    tmp.write_text(json.dumps(kept, indent=2, default=str), encoding="utf-8")
    tmp.replace(folder / "tickets.json")
    try:
        meta = json.loads((folder / "demo.json").read_text(encoding="utf-8"))
        meta["tickets"] = len(kept)
        (folder / "demo.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    except (OSError, ValueError):
        pass
    return {"pictures": changed, "tickets": touched}


def track_crop_jpeg(folder: Path, track_id: int) -> bytes | None:
    """A picture of one vehicle (its biggest box in the demo), cut out with some room around it, as JPEG. None when it is not found."""
    import cv2
    import numpy as np

    folder = Path(folder)
    best, best_area = None, 0
    for row in _read_index(folder / "index.jsonl"):
        for d in row.get("detections") or []:
            bb = d.get("bbox") or []
            if d.get("track_id") == track_id and len(bb) == 4 and bb[2] * bb[3] > best_area:
                best, best_area = (row, bb), bb[2] * bb[3]
    if best is None:
        return None
    row, (x, y, w, h) = best
    img = cv2.imdecode(np.frombuffer((folder / "frames" / str(row["file"])).read_bytes(), np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        return None
    sx = img.shape[1] / float(row.get("w") or img.shape[1])
    sy = img.shape[0] / float(row.get("h") or img.shape[0])
    pad = 0.15
    x0, y0 = max(0, int((x - w * pad) * sx)), max(0, int((y - h * pad) * sy))
    x1, y1 = min(img.shape[1], int((x + w * (1 + pad)) * sx)), min(img.shape[0], int((y + h * (1 + pad)) * sy))
    crop = img[y0:y1, x0:x1]
    if crop.size == 0:
        return None
    ok, buf = cv2.imencode(".jpg", crop, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return buf.tobytes() if ok else None


class Demo:
    """A demo, loaded to be played: the pictures' times (from 0), the tickets and where to find the files."""

    def __init__(self, folder: Path):
        self.folder = Path(folder)
        self.meta = json.loads((self.folder / "demo.json").read_text(encoding="utf-8"))
        rows = _read_index(self.folder / "index.jsonl")
        self.t0 = float(rows[0]["t"])
        self.rows = rows
        self.times = [float(r["t"]) - self.t0 for r in rows]
        self.duration = self.times[-1]
        try:
            self.tickets = json.loads((self.folder / "tickets.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            self.tickets = []
        try:
            self.config = json.loads((self.folder / "config.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            self.config = {}
        self.fps = (len(rows) - 1) / self.duration if self.duration > 0 else 10.0

    def index_at(self, pos: float) -> int:
        """The picture that is on the screen at `pos` seconds."""
        return max(0, min(len(self.rows) - 1, bisect.bisect_right(self.times, pos) - 1))

    def picture_b64(self, i: int) -> str | None:
        try:
            return base64.b64encode((self.folder / "frames" / str(self.rows[i]["file"])).read_bytes()).decode("ascii")
        except OSError:
            return None

    def restore_photos(self, ticket: dict, evidence_dir: Path) -> None:
        """Put the photos of a ticket back into the evidence folder (the live tickets are cleared when the Live Monitor opens)."""
        evidence_dir.mkdir(parents=True, exist_ok=True)
        names: set = set()

        def walk(value) -> None:
            if isinstance(value, dict):
                for item in value.values():
                    walk(item)
            elif isinstance(value, (list, tuple)):
                for item in value:
                    walk(item)
            elif isinstance(value, str) and value.lower().endswith((".jpg", ".jpeg", ".png")):
                names.add(Path(value).name)

        walk(ticket)
        for name in names:
            src = self.folder / "photos" / Path(name).name
            dst = evidence_dir / Path(name).name
            if src.exists() and not dst.exists():
                try:
                    shutil.copy2(src, dst)
                except OSError:
                    pass
