"""
replay_run.py - a saved live run, replayed in the Live Monitor (no models, no backend work) and kept up to date in its own folder.

A saved run is ONE folder (made by engine/live_run.py when "Save this run" is on, normally under A:\\huli-kamote\\videos):
    frames/NNNNNNN.jpg     the clean pictures
    index.jsonl            one line per picture: time, size, boxes (and "wall": the clock the tickets use)
    run.json               what it was
    tickets/report.json    the tickets of the run (the same report.json the review works on)
    tickets/forensic_config.json, tickets/photos/...   the plate settings and every evidence photo of those tickets
    tickets/state.json     the decisions made on the tickets (the Inbox status of each row), by ticket

While a run is SAVED live, and while it is REPLAYED, a Syncer copies the live tickets into that folder whenever they change (a plate typed or
read, photos set aside, a ticket merged, a decision made), so the enforcer can come back to the run later and find everything as it was left.
"""
import asyncio
import bisect
import json
import logging
import os
import shutil
import time
from datetime import datetime
from pathlib import Path

log = logging.getLogger(__name__)

DEFAULT_ROOT = Path(os.environ.get("HK_REPLAY_ROOT", r"A:\huli-kamote\videos"))
ACTIVE: dict = {"folder": None}          # the run the Live Monitor replays now (None: the normal live source)
TICKET_LEAD_S = 0.5                      # a ticket shows this long after the last photo of its vehicle


def roots() -> list[Path]:
    """The folders that hold saved runs: the one chosen in the live setup ("Save this run"), and the default one."""
    from engine import live_run
    found: list[Path] = []
    chosen = live_run.read_settings().get("dir") or ""
    for item in (chosen, str(DEFAULT_ROOT)):
        if item and Path(item) not in found:
            found.append(Path(item))
    return found


def is_run(folder: Path) -> bool:
    return (folder / "index.jsonl").is_file() and (folder / "frames").is_dir()


def list_runs() -> list[dict]:
    out = []
    for root in roots():
        try:
            folders = sorted((p for p in root.iterdir() if p.is_dir() and is_run(p)), key=lambda p: p.name, reverse=True)
        except OSError:
            continue
        for folder in folders:
            meta = {}
            try:
                meta = json.loads((folder / "run.json").read_text(encoding="utf-8"))
            except (OSError, ValueError):
                pass
            tickets = None
            try:
                tickets = len(json.loads((folder / "tickets" / "report.json").read_text(encoding="utf-8")))
            except (OSError, ValueError):
                pass
            session = None
            try:
                s = json.loads((folder / "session.json").read_text(encoding="utf-8"))
                session = {"pos_s": s.get("pos_s"), "saved_at": s.get("saved_at"), "source_name": s.get("source_name")}
            except (OSError, ValueError):
                pass
            out.append({"id": folder.name, "path": str(folder), "started": meta.get("started") or _stamp_text(folder.name),
                        "ended": meta.get("ended"), "pictures": meta.get("pictures"), "source": meta.get("source"), "tickets": tickets,
                        "session": session})
    return out


def find(run_id: str) -> Path | None:
    name = Path(run_id).name
    for root in roots():
        folder = root / name
        if is_run(folder):
            return folder
    return None


def activate(folder: Path) -> None:
    ACTIVE["folder"] = Path(folder)


def deactivate() -> None:
    ACTIVE["folder"] = None


def active() -> Path | None:
    return ACTIVE["folder"]


def quick_duration(folder: Path) -> float:
    """The length of a saved run in seconds, from the first and the last line of its index (no need to read it all)."""
    index = Path(folder) / "index.jsonl"
    first = last = None
    try:
        with open(index, "rb") as fh:
            for line in fh:
                try:
                    first = float(json.loads(line)["t"])
                    break
                except (ValueError, KeyError):
                    continue
            fh.seek(0, 2)
            fh.seek(max(0, fh.tell() - 65536))
            for line in reversed(fh.read().splitlines()):
                try:
                    last = float(json.loads(line)["t"])
                    break
                except (ValueError, KeyError):
                    continue
    except OSError:
        return 0.0
    return max(0.0, (last - first)) if first is not None and last is not None else 0.0


def video_time(folder: Path, t: float) -> float:
    """Seconds on the VIDEO for a time `t` on the run's timeline. After a Save and pause the monitoring went on from the video position that was
    saved, while the timeline counts on: the video time is that position plus what came after it."""
    try:
        data = json.loads((Path(folder) / "session.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return t
    base_t, base_v = 0.0, 0.0
    for p in sorted((p for p in data.get("pauses") or [] if isinstance(p, dict)), key=lambda p: p.get("t") or 0):
        if isinstance(p.get("t"), (int, float)) and isinstance(p.get("pos_s"), (int, float)) and p["t"] <= t:
            base_t, base_v = float(p["t"]), float(p["pos_s"])
    return base_v + (t - base_t)


def replay_time(folder: Path, v: float) -> float:
    """Seconds on the run's timeline for a time `v` on the VIDEO (the opposite of video_time): after a Save and pause the timeline counts on
    from the place where the monitoring went on."""
    try:
        data = json.loads((Path(folder) / "session.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return v
    base_t, base_v = 0.0, 0.0
    for p in sorted((p for p in data.get("pauses") or [] if isinstance(p, dict)), key=lambda p: p.get("pos_s") or 0):
        if isinstance(p.get("t"), (int, float)) and isinstance(p.get("pos_s"), (int, float)) and p["pos_s"] <= v:
            base_t, base_v = float(p["t"]), float(p["pos_s"])
    return base_t + (v - base_v)


def _stamp_epoch(name: str) -> float | None:
    try:
        return datetime.strptime(name.replace("live_run_", ""), "%Y%m%d_%H%M%S").timestamp()
    except ValueError:
        return None


def _stamp_text(name: str) -> str | None:
    epoch = _stamp_epoch(name)
    return datetime.fromtimestamp(epoch).isoformat(timespec="seconds") if epoch else None


class Run:
    """The index of a saved run, kept light: only the times and where each line is. A line (the boxes) is read when its picture is shown."""

    def __init__(self, folder: Path):
        self.folder = Path(folder)
        self.index_path = self.folder / "index.jsonl"
        self.frames = self.folder / "frames"
        self.tickets_dir = self.folder / "tickets"
        times, walls, offsets, files = [], [], [], []
        self.w, self.h = 1280, 720
        with open(self.index_path, "rb") as fh:
            offset = 0
            for line in fh:
                size = len(line)
                try:
                    row = json.loads(line) if line.strip() else None
                except ValueError:
                    row = None                                      # the last line of a run that was cut short
                if row and row.get("file") and (self.frames / row["file"]).exists():
                    times.append(float(row.get("t") or 0.0))
                    walls.append(row.get("wall"))
                    offsets.append(offset)
                    files.append(row["file"])
                    if len(times) == 1:
                        self.w, self.h = int(row.get("w") or 1280), int(row.get("h") or 720)
                offset += size
        if not times:
            raise ValueError("This run has no pictures.")
        self.t0 = times[0]
        self.times = [t - self.t0 for t in times]
        self.walls = walls
        self.offsets = offsets
        self.files = files
        self.duration = self.times[-1]
        self.fps = (len(times) - 1) / self.duration if self.duration > 0 else 25.0
        try:
            self.meta = json.loads((self.folder / "run.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            self.meta = {}
        self.pauses = self._pauses()
        self.entries = self._ticket_entries()

    def handover_pos(self) -> float | None:
        """Where on the video the real monitoring goes on after this saved run (Save and pause was pressed there); None when it cannot go on
        (no session saved, or its video is not there any more)."""
        try:
            data = json.loads((self.folder / "session.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        source = data.get("source")
        if not source or (not str(source).startswith(("rtsp://", "http://", "https://")) and not str(source).isdigit() and not Path(str(source)).exists()):
            return None
        try:
            return max(0.0, float(data.get("pos_s") or 0.0))
        except (TypeError, ValueError):
            return None

    def _pauses(self) -> list[float]:
        """Where this monitoring was saved and paused (seconds from the start of the run): the replay marks them on its timeline."""
        try:
            data = json.loads((self.folder / "session.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []
        return [min(self.duration, max(0.0, float(p["t"]))) for p in data.get("pauses") or [] if isinstance(p, dict) and isinstance(p.get("t"), (int, float))]

    def index_at(self, pos: float) -> int:
        return max(0, min(len(self.times) - 1, bisect.bisect_right(self.times, pos) - 1))

    def row(self, i: int) -> dict:
        with open(self.index_path, "rb") as fh:
            fh.seek(self.offsets[i])
            return json.loads(fh.readline())

    def picture_b64(self, i: int) -> str:
        import base64
        return base64.b64encode((self.frames / self.files[i]).read_bytes()).decode("ascii")

    # ── the tickets ──
    def saved_tickets(self) -> list:
        try:
            return json.loads((self.tickets_dir / "report.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []

    def states(self) -> dict:
        try:
            return json.loads((self.tickets_dir / "state.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}

    def _ticket_entries(self) -> list[dict]:
        """[{at, ticket}] in the order the tickets happened: `at` = seconds on this run when the vehicle's last photo was taken."""
        tickets = self.saved_tickets()
        last = []
        for t in tickets:
            ts = [m.get("t") for m in t.get("evidence_meta", []) if isinstance(m.get("t"), (int, float))]
            last.append(max(ts) if ts else None)
        walls = [w for w in self.walls if isinstance(w, (int, float))]
        ats: list[float | None] = []
        if last and all(w is None or w < 1e8 for w in last):
            # the tickets carry times ON THE VIDEO (a file judged in video time): turn them into times on the run's timeline
            for w in last:
                ats.append(None if w is None else replay_time(self.folder, w) + TICKET_LEAD_S)
        elif len(walls) == len(self.walls) and walls:
            for w in last:
                if w is None:
                    ats.append(None)
                else:
                    j = min(len(walls) - 1, bisect.bisect_left(walls, w))
                    ats.append(self.times[j] + TICKET_LEAD_S)
        else:
            # an older run without the clock in its index: the run started about when its folder was made
            start = _stamp_epoch(self.folder.name)
            for w in last:
                ats.append(None if w is None or start is None else (w - start))
        known = [a for a in ats if a is not None]
        if not known or min(known) < 0 or max(known) > self.duration + 1:
            # the times do not fit this run: spread the tickets over it, in the order they were made
            order = sorted(range(len(tickets)), key=lambda i: (last[i] is None, last[i] or 0.0))
            n = len(tickets)
            ats = [0.0] * n
            for rank, i in enumerate(order):
                ats[i] = self.duration * (rank + 1) / (n + 1)
        else:
            ats = [min(self.duration, a if a is not None else 0.0) for a in ats]
        return sorted(({"at": a, "ticket": t} for a, t in zip(ats, tickets)), key=lambda e: e["at"])


# ── the photos of the tickets ──
def photo_rels(tickets, evidence_dir: Path) -> set[Path]:
    """Every picture file the tickets own, as a path under the evidence folder (by name, or by the path they carry)."""
    found: set[Path] = set()

    def walk(value) -> None:
        if isinstance(value, dict):
            for item in value.values():
                walk(item)
        elif isinstance(value, (list, tuple)):
            for item in value:
                walk(item)
        elif isinstance(value, str) and value.lower().endswith((".jpg", ".jpeg", ".png")):
            rel = Path(Path(value).name) if Path(value).is_absolute() else Path(value)
            if ".." not in rel.parts and not (rel.parts and rel.parts[0] == "forensic"):
                found.add(rel)

    walk(tickets)
    return found


def restore_photos(folder: Path, ticket: dict, evidence_dir: Path) -> None:
    """Put the photos of one saved ticket back into the evidence folder (where the dashboard and the plate tools read them)."""
    for rel in photo_rels(ticket, evidence_dir):
        src, dst = Path(folder) / "tickets" / "photos" / rel, evidence_dir / rel
        if src.exists() and not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)


def _write_json(path: Path, data) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, default=str), encoding="utf-8")
    os.replace(tmp, path)


def _copy_photos(folder: Path, tickets: list, evidence_dir: Path) -> None:
    target = folder / "tickets" / "photos"
    for rel in photo_rels(tickets, evidence_dir):
        src, dst = evidence_dir / rel, target / rel
        if src.exists() and not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copy2(src, dst)
            except OSError as exc:
                log.warning("A photo could not be saved into the run folder: %s", exc)


class Syncer:
    """Keeps <run folder>/tickets up to date with the live tickets. `keep_saved` (a replay): the tickets of the folder that were not shown yet
    stay as they are, and a ticket that was shown and is gone now (merged into another) goes. Not a replay (a run being saved): the folder
    holds exactly what the live tickets are."""

    def __init__(self, folder: Path, keep_saved: bool = False, saved: list | None = None, released: set | None = None, states: dict | None = None, since: float | None = None):
        self.folder = Path(folder)
        self.keep_saved = keep_saved
        self.saved = saved or []
        self.released = released if released is not None else set()
        self._key = None
        self._states_at = 0.0
        self._states: dict = dict(states or {})
        self.since = since                   # a run being saved: only tickets made after it began (older live tickets are not its own)
        self.busy = False                    # a ticket is being put back: the saving waits
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        self._task = asyncio.get_running_loop().create_task(self._forever())

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            self._task = None
        try:
            await self.once(force=True)
        except Exception:
            log.exception("The tickets of the run could not be saved")

    async def _forever(self) -> None:
        while True:
            try:
                await asyncio.sleep(2.0)
                await self.once()
            except asyncio.CancelledError:
                raise
            except Exception:
                log.exception("The tickets of the run could not be saved")

    async def once(self, force: bool = False) -> None:
        from engine.pipeline import EVIDENCE_DIR
        from routers import forensic

        out = forensic.live_output_dir()
        report_path = out / "report.json"
        try:
            stat = report_path.stat()
            key = (stat.st_mtime_ns, stat.st_size)
        except OSError:
            key = None
        now = time.monotonic()
        states_due = now - self._states_at >= 4.0 or force
        if self.busy and not force:
            return
        if not force and key == self._key and not states_due:
            return
        async with forensic._report_lock:
            working = await asyncio.to_thread(forensic._load_tickets, report_path)
        if states_due:
            self._states_at = now
            self._states = await self._capture_states(working)
        changed = key != self._key or force
        self._key = key
        await asyncio.to_thread(self._write, working, out, EVIDENCE_DIR, changed)

    async def _capture_states(self, working: list) -> dict:
        """The Inbox status of every row of every ticket that was decided (by ticket)."""
        from store import get_violation
        states = dict(self._states) if self.keep_saved else {}
        for t in working:
            uid = t.get("ticket_uid")
            ids = t.get("db_ids") or []
            if not uid or not ids:
                continue
            got = []
            for rid in ids:
                row = await get_violation(rid)
                got.append(row.get("status") if row else "pending")
            if any(s != "pending" for s in got):
                states[uid] = got
            else:
                states.pop(uid, None)
        return states

    def _final(self, working: list) -> list:
        if not self.keep_saved:
            if self.since is None:
                return working
            def made_after(t: dict) -> bool:
                ts = [m.get("t") for m in t.get("evidence_meta", []) if isinstance(m.get("t"), (int, float))]
                if not ts or max(ts) < 1e8:
                    return True                              # a time on the VIDEO (small numbers), not a clock: the live tickets are the run's own
                return max(ts) >= self.since
            return [t for t in working if made_after(t)]
        by_uid = {t.get("ticket_uid"): t for t in working}
        final, seen = [], set()
        for s in self.saved:
            uid = s.get("ticket_uid")
            if uid in by_uid:
                final.append(by_uid[uid])
                seen.add(uid)
            elif uid in self.released:
                continue                                           # it was shown and is gone now: merged into another ticket
            else:
                final.append(s)                                    # not shown yet: as it was saved
        final.extend(t for uid, t in by_uid.items() if uid not in seen)
        return final

    def _write(self, working: list, out: Path, evidence_dir: Path, changed: bool) -> None:
        folder = self.folder / "tickets"
        folder.mkdir(parents=True, exist_ok=True)
        final = self._final(working)
        if changed or not (folder / "report.json").exists():
            _copy_photos(self.folder, final, evidence_dir)
            _write_json(folder / "report.json", final)
            cfg = out / "forensic_config.json"
            if cfg.exists():
                shutil.copyfile(cfg, folder / "forensic_config.json")
            if self.keep_saved:
                self.saved = final
        known = {t.get("ticket_uid") for t in final}
        _write_json(folder / "state.json", {u: s for u, s in self._states.items() if u in known})


async def put_back(folder: Path, ticket: dict, states: dict, out: Path, add_violation) -> None:
    """One saved ticket becomes a live ticket again: its photos, its report entry, its Inbox rows and the decisions made on it."""
    from engine.pipeline import EVIDENCE_DIR
    from routers import forensic
    ticket = json.loads(json.dumps(ticket))
    await asyncio.to_thread(restore_photos, folder, ticket, EVIDENCE_DIR)
    plate = ticket.get("plate_text", "unidentified")
    unread = plate in forensic._UNREAD
    owner = None if unread else await forensic.get_user_by_plate(plate)
    user_id = forensic.LIVE_PENDING_USER if unread else forensic._owner_id(plate, owner)
    async with forensic._report_lock:
        report_path = out / "report.json"
        tickets = await asyncio.to_thread(forensic._load_tickets, report_path)
        if any(x.get("ticket_uid") == ticket.get("ticket_uid") for x in tickets):
            return
        ticket["db_ids"] = await forensic._save_rows(forensic.LIVE_TASK, ticket, ticket.get("violations", []), user_id, plate,
                                                      add_violation, source="live")
        tickets.append(ticket)
        await asyncio.to_thread(forensic._write_report, report_path, tickets)
        task = forensic.forensic_tasks.get(forensic.LIVE_TASK)
        if task is not None:
            task["tickets"] = tickets
    await restore_states(ticket, states)


async def put_back_all(folder: Path) -> int:
    """The tickets of a saved monitoring replace the live tickets (to go on with that monitoring). Returns how many."""
    from routers import forensic
    from store import add_violation
    folder = Path(folder)
    try:
        saved = json.loads((folder / "tickets" / "report.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        saved = []
    try:
        states = json.loads((folder / "tickets" / "state.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        states = {}
    await forensic.clear_live_tickets()
    out = forensic.live_output_dir()
    out.mkdir(parents=True, exist_ok=True)
    cfg = folder / "tickets" / "forensic_config.json"
    if cfg.exists():
        shutil.copyfile(cfg, out / "forensic_config.json")
    for ticket in saved:
        await put_back(folder, ticket, states, out, add_violation)
    return len(saved)


async def restore_states(ticket: dict, states: dict) -> None:
    """The decisions made earlier on this ticket are put back on its new Inbox rows."""
    import database as db                                          # straight into the table: no second notice goes to the owner
    saved = states.get(ticket.get("ticket_uid"))
    if not saved:
        return
    for rid, status in zip(ticket.get("db_ids") or [], saved):
        if status and status != "pending":
            try:
                await db.database.execute(db.violations_table.update().where(db.violations_table.c.id == rid).values(status=status))
            except Exception:
                log.exception("A decision could not be put back")
