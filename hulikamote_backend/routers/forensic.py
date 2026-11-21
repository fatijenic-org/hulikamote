from pydantic import BaseModel
import asyncio
import uuid
import cv2
import json
from store import add_violation, get_user_by_plate, _levenshtein, delete_violations
import asyncio
import functools
import logging
import queue
import threading
from datetime import datetime, timezone
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, BackgroundTasks
from fastapi.responses import JSONResponse, Response
import shutil
from engine.segment_writer import SegmentedVideoWriter
from engine.ticket_photos import photo_names
from engine.video_window import frame_window, number_or_none
from routers.trimmer import local_only
from engine.pipeline import DecoupledPipeline
from yolo_inference import get_inference

router = APIRouter(prefix="/api/forensic", tags=["Forensic"])
log = logging.getLogger("root.forensic")

# In-memory store for forensic tasks status
forensic_tasks = {}

_LINK_TOLERANCE_S = 1.0


def _reid_label(task_id: str, ticket: dict) -> str:
    return f"{task_id[:8]}_{ticket.get('ticket_uid', 'x')}"


def _record_reid(kind: str, task_id: str, groups: dict) -> None:
    """Send an operator decision to the ReID training dataset (best effort)."""
    from engine.pipeline import EVIDENCE_DIR
    from engine.reid_dataset import record
    record(kind, task_id, groups, EVIDENCE_DIR)


def _link_crops_to_frames(ticket: dict) -> None:
    """Tie each evidence frame to the plate crop taken closest in time (within tolerance).
    Writes `crop` (image file) and `plate` (that crop's own OCR read) into evidence_meta."""
    timed = [c for c in ticket.get("crop_results", []) if c.get("t") is not None]
    for m in ticket.get("evidence_meta", []):
        m["crop"], m["plate"] = None, None
        if m.get("t") is None or not timed:
            continue
        best = min(timed, key=lambda c: abs(c["t"] - m["t"]))
        if abs(best["t"] - m["t"]) <= _LINK_TOLERANCE_S:
            m["crop"] = best["image_raw"]
            m["plate"] = best.get("cleaned")


async def _skip_db(**_kwargs):
    """Benchmark runs (config "benchmark": true) only score the tickets: nothing goes to the Inbox database."""
    return None


class _ForensicCancelled(Exception):
    """The operator pressed Cancel: the run is thrown away."""


def _stop_mode(task_id: str) -> str | None:
    """What the operator asked for while the run goes: 'finish' (stop here, keep what was found),
    'cancel' (throw the run away) or None."""
    return forensic_tasks.get(task_id, {}).get("stop")


def _say(task_id: str, text: str) -> None:
    """Short status line for the dashboard ("Reading plates: 12 of 340"). Never hides a pending stop request."""
    task = forensic_tasks.get(task_id)
    if task is not None and not task.get("stop"):
        task["message"] = text


def _discard_run(pipeline, written: list, task_dir: Path, released: list | None = None) -> None:
    """Cancel: delete what the run produced, i.e. the evidence photos of the cars it saw (also of the tickets already
    released: `released` are the ledger's tickets handed to the releaser), the plate pictures it saved so far,
    and the whole task folder (the uploaded copy, the partial videos, the settings)."""
    def unlink(path) -> None:
        try:
            Path(path).unlink(missing_ok=True)
        except OSError as e:
            log.warning(f"[Forensic] Could not remove {path}: {e}")

    holders = []
    if pipeline is not None:
        manager = pipeline.ledger_manager
        holders = [(l.evidence_paths, l.evidence_meta) for l in manager.ledgers.values()]
        holders += [(t.get("evidence_paths", []), t.get("evidence_meta", [])) for t in manager.pending_tickets]
    holders += [(t.get("evidence_paths", []), t.get("evidence_meta", [])) for t in (released or [])]
    for paths, metas in holders:
        for path, meta in zip(paths, metas):
            unlink(path)
            for key in ("car_crop", "clean"):     # the vehicle crop and the clean harvest crop sit next to the photo
                if meta.get(key):
                    unlink(Path(path).parent / meta[key])
            for detail in meta.get("details") or []:     # the close-ups kept as extra evidence
                unlink(Path(path).parent / detail["file"])
    if pipeline is not None:                              # close-ups of cars still on screen, not tied to a photo yet
        for ledger in pipeline.ledger_manager.ledgers.values():
            for detail in getattr(ledger, "detail_crops", []):
                unlink(detail["path"])
    for path in written:
        unlink(path)
    if task_dir.parent.name == "forensic":            # only ever remove a run folder
        shutil.rmtree(task_dir, ignore_errors=True)


# ─── tickets are released while the video is still being read ────────────────────────────────────────────────
# A vehicle that left the scene is judged at once. A background worker reads its plate and adds the ticket to the report
# and the Inbox database, so the operator can open it while the analysis goes on. Merging a ticket into an earlier one of
# the same car (same plate) still happens, as long as nobody has decided that earlier ticket yet.

RELEASE_EVERY = 5               # frames between looks for vehicles that left the scene
_UNREAD = ("unidentified", "no_plate_found", "")
_main_loop = None               # the app's event loop (the upload endpoint sets it)
_report_lock = asyncio.Lock()   # a report.json is edited by the analysis AND by the operator: one at a time


def _load_tickets(path: Path, strict: bool = False) -> list:
    """The tickets of a report.json ([] when there is none). BLOCKING - a live report is several MB: call it with asyncio.to_thread, so the
    event loop (which also carries the live feed) never waits for it. A report that cannot be read is [] (strict: the error is raised)."""
    try:
        return json.loads(path.read_text()) if path.exists() else []
    except ValueError:
        if strict:
            raise
        return []


def _write_report(path: Path, tickets: list) -> None:
    """Write a report.json in one piece: the dashboard downloads it while tickets are added, so it must never be half written.
    BLOCKING: call it with asyncio.to_thread."""
    import os
    import time

    text = json.dumps(tickets, indent=2)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    for attempt in range(6):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:                  # Windows: a reader has the file open right now
            time.sleep(0.05 * (attempt + 1))
    path.write_text(text)
    tmp.unlink(missing_ok=True)


def _serialized(fn):
    """Endpoint decorator: report edits run one at a time (a running analysis may add tickets to the same report)."""
    @functools.wraps(fn)
    async def wrapper(*args, **kwargs):
        async with _report_lock:
            return await fn(*args, **kwargs)
    return wrapper


def _run_async(coro):
    """Run a coroutine from the analysis thread: on the app's event loop when there is one (database and report work then
    never overlaps an operator's edit), otherwise in a loop of its own (tests, scripts)."""
    loop = _main_loop
    if loop is not None and loop.is_running():
        return asyncio.run_coroutine_threadsafe(coro, loop).result()
    return asyncio.run(coro)


def _plate_stop(task_id: str) -> str | None:
    """What the plate reading must obey: 'cancel' at any time; 'finish' only once the video part is over (the first
    Stop here ends the video and the plates are still read, pressing it again then skips the plates not read yet)."""
    mode = _stop_mode(task_id)
    if mode == "finish" and not forensic_tasks.get(task_id, {}).get("video_done"):
        return None
    return mode


def _ticket_from_ledger(lt: dict, config: dict) -> dict:
    """The report's ticket for one vehicle the ledger finished."""
    from engine.video_clock import hours_matter, ticket_time
    metas = list(lt.get("evidence_meta", []))
    first = min((m["t"] for m in metas if m.get("t") is not None), default=None)
    when = ticket_time(config.get("video_clock"), first, hours_matter(config, lt["violations"]))
    ticket = {
        "track_id": lt["track_id"],
        "violations": lt["violations"],
        "privacy_blurred": bool(config.get("blur_privacy", True)),   # False: the photos show faces and other plates, never sent
        "plate_text": lt["plate_text"],
        "plate_crops": lt.get("plate_crops", []),
        "evidence_paths": [Path(p).name for p in lt.get("evidence_paths", [])],
        "evidence_meta": list(lt.get("evidence_meta", [])),
        "metadata": {
            "primary_model": config.get("primary_model"),
            "use_sahi": config.get("use_sahi"),
            "plate_model": config.get("plate_model"),
            "plate_method": config.get("plate_method"),
            "plate_format": config.get("plate_format"),
            "ocr_engine": config.get("ocr_engine"),
            "enhancement": config.get("enhancement"),
            "tracker": config.get("tracker"),
            "violation_settings": {v: config.get("per_violation_configs", {}).get(v) for v in lt["violations"]},
        },
    }
    if when:        # when it happened, and where that time came from (or: the hour matters and it is not known)
        ticket["time"] = when
    return ticket


def _read_ticket_plate(task_id: str, t: dict, config: dict, written: list, on_crop=None) -> None:
    """Deep OCR of one ticket (Pass 2): every plate crop is read twice, as seen and enhanced (the GAN), and the reads vote for
    the best plate (engine/plate_vote.py). The video pass keeps plate crops only while the no_plate violation is on; without crops
    the plate is looked for, and read, in the evidence photos of the ticket. `on_crop()` is called before each crop is read.
    Raises _ForensicCancelled when the operator cancels."""
    from engine import plate_vote
    from engine.pipeline import EVIDENCE_DIR, _extract_plate_reads
    from engine.ticket_merge import revote
    from yolo_inference import YoloInference

    plate_format = config.get("plate_format", "ph_standard")
    crops = t.pop("plate_crops", [])
    t["plate_crop_paths"] = []
    if _plate_stop(task_id) == "finish":
        return          # Stop here: this ticket's plates are not read, the plate stays as the video pass left it
    if not crops:
        _read_from_photos(t, config, plate_format, written)
        return

    crop_results = []
    for item in crops:
        mode = _plate_stop(task_id)
        if mode == "cancel":
            raise _ForensicCancelled()
        if mode == "finish":
            break         # Stop here: keep the plates read so far
        if on_crop is not None:
            on_crop()
        crop_t = None
        if isinstance(item, tuple) and len(item) >= 2:
            crop, context_crop = item[0], item[1]
            crop_t = item[2] if len(item) >= 3 else None
        else:
            crop, context_crop = item, None

        crop_filename = None
        try:
            crop_path = YoloInference.save_snapshot(crop, EVIDENCE_DIR)
            crop_filename = Path(crop_path).name
            written.append(EVIDENCE_DIR / crop_filename)
            t["plate_crop_paths"].append(crop_filename)
        except Exception:
            pass

        context_filename = None
        if context_crop is not None:
            try:
                c_path = YoloInference.save_snapshot(context_crop, EVIDENCE_DIR)
                context_filename = Path(c_path).name
                written.append(EVIDENCE_DIR / context_filename)
            except Exception:
                pass

        got = _extract_plate_reads(crop, plate_format, config.get("ocr_engine", "easyocr"), config.get("enhancement", "lanczos"))
        top = plate_vote.best_read(got["reads"], plate_format)

        sr_filename = None
        try:
            sr_path = YoloInference.save_snapshot(got["enhanced_crop"], EVIDENCE_DIR)
            sr_filename = Path(sr_path).name
            written.append(EVIDENCE_DIR / sr_filename)
        except Exception:
            pass

        if crop_filename:
            crop_results.append({
                "image_raw": crop_filename,
                "image_sr": sr_filename,
                "image_context": context_filename,
                "t": crop_t,
                "raw": top["raw"],
                "cleaned": top["cleaned"],
                "confidence": top["confidence"],
                "reads": got["reads"],
            })

    t["crop_results"] = crop_results
    _link_crops_to_frames(t)
    revote(t, plate_format)            # plate_text, vote_tally, plate_candidates, winning crop (winner first), length warning
    if t.get("plate_text", "unidentified") in _UNREAD:
        # no text: the status from the plate looks stays (no_plate / not_read / unclear / not_checked)
        t.setdefault("plate_status", "not_read" if crop_results else "not_checked")
    else:
        t["plate_status"] = "read"


def _read_from_photos(t: dict, config: dict, plate_format: str, written: list) -> None:
    """No plate crops came from the video: find the plate in the clean vehicle picture of every evidence photo of the ticket and
    read it (as seen and enhanced). The ticket is changed in place."""
    if not any(m.get("clean") or m.get("car_crop") for m in t.get("evidence_meta", [])):
        return                  # no clean vehicle picture to look in
    try:
        new, _summary = _reread_with_models(t, [], config, plate_format, written)
    except ValueError:
        return
    t.clear()
    t.update(new)
    if t.get("plate_text", "unidentified") in _UNREAD:
        t.setdefault("plate_status", "not_read" if t.get("crop_results") else "not_checked")
    else:
        t["plate_status"] = "read"


def _first_track_id(t: dict) -> int:
    ids = t.get("merged_track_ids") or [t.get("track_id")]
    return next((i for i in ids if isinstance(i, int)), -1)


def _owner_id(plate_text: str, owner) -> str:
    if plate_text == "unidentified":
        return "no_plate_found"
    return owner["id"] if owner else "unregistered"


async def _save_rows(task_id: str, t: dict, classes: list, user_id: str, plate_text: str, save_violation,
                     track_id: int | None = None, source: str = "forensic") -> list:
    """One 'pending' Inbox row per violation class of the ticket (pending triggers the Pop Quiz Inbox).
    `track_id`: the tracker number the rows carry (default: the ticket's own)."""
    ids = []
    for v in classes:
        # The first plate crop is the Inbox picture, else the first evidence photo
        img_path = ""
        if t.get("plate_crop_paths"):
            img_path = f"snapshots/evidence/{t['plate_crop_paths'][0]}"
        elif t.get("evidence_paths"):
            img_path = f"snapshots/evidence/{Path(t['evidence_paths'][0]).name}"
        v_res = await save_violation(
            cls=v, confidence=1.0, user_id=user_id, image_path=img_path, notify=False, status="pending",
            evidence_paths=photo_names(t), track_id=_first_track_id(t) if track_id is None else track_id,
            source=source,
            session_id=task_id, plate_text=plate_text, dedupe=False,
        )
        if v_res and "id" in v_res:
            ids.append(v_res["id"])
    return ids


async def _nobody_decided(ticket: dict) -> bool:
    """True while every Inbox row of the ticket still waits for the operator (no rows = nothing to protect)."""
    from store import get_violation

    for rid in ticket.get("db_ids", []):
        row = await get_violation(rid)
        if row and row.get("status") != "pending":
            return False
    return True


async def _publish_ticket(task_id: str, t: dict, config: dict, output_dir: Path, save_violation, ids_sink: list,
                          source: str = "forensic", unread_user: str = "no_plate_found") -> None:
    """Add one finished ticket to the report and the Inbox database. When an earlier ticket has the same plate (one letter
    of OCR jitter allowed) and nobody has decided it yet, the two are the same car and are merged instead."""
    from engine.ticket_flags import annotate_tickets
    from engine.ticket_merge import merge_tickets
    from store import get_violation, merge_violation_rows

    plate_text = t.get("plate_text", "unidentified")
    owner = await get_user_by_plate(plate_text) if plate_text != "unidentified" else None
    user_id = _owner_id(plate_text, owner) if plate_text not in _UNREAD else unread_user

    async with _report_lock:
        report_path = output_dir / "report.json"
        tickets = await asyncio.to_thread(_load_tickets, report_path, True)

        twin = None
        if plate_text not in _UNREAD:
            twin = next((x for x in tickets if x.get("plate_text", "unidentified") not in _UNREAD
                         and _levenshtein(plate_text.upper(), x["plate_text"].upper()) <= 1), None)
        if twin is not None and await _nobody_decided(twin):
            merged = merge_tickets(twin, t)
            have = set()
            for rid in twin.get("db_ids", []):
                row = await get_violation(rid)
                if row:
                    have.add(row["cls"])
            new_ids = await _save_rows(task_id, merged, [v for v in t["violations"] if v not in have],
                                       user_id, merged.get("plate_text", plate_text), save_violation, source=source)
            ids_sink.extend(new_ids)
            merged["db_ids"] = list(twin.get("db_ids", [])) + new_ids
            if merged["db_ids"]:
                merged["db_ids"] = await merge_violation_rows(
                    merged["db_ids"], [], photo_names(merged), merged.get("plate_text", "unidentified"),
                    _first_track_id(merged))
            tickets[tickets.index(twin)] = merged
        else:
            t["db_ids"] = await _save_rows(task_id, t, t.get("violations", []), user_id, plate_text, save_violation, source=source)
            ids_sink.extend(t["db_ids"])
            tickets.append(t)

        await asyncio.to_thread(annotate_tickets, tickets, _levenshtein, config.get("flag_sensitivity", 4))
        await asyncio.to_thread(_write_report, report_path, tickets)
        task = forensic_tasks.get(task_id)
        if task is not None:
            task["tickets"] = tickets
            task["ticket_count"] = len(tickets)


# ─── The live feed's tickets ───────────────────────────────────────────────────────────────────────────────────
# A vehicle that the Live Monitor finished becomes a ticket of one standing run, "live" (report.json and forensic_config.json in
# snapshots/evidence/forensic/live/output, Inbox rows with source "live"). So the review of the forensic analyzer works on it as it is:
# choose photos, set them aside, merge with another ticket, read the plate again, type or pick another plate. The live pipeline reads
# NO plate: it is read from the evidence photos when the reviewer asks (or the no_plate violation decides, when that one is on).

LIVE_TASK = "live"
LIVE_PENDING_USER = "plate_pending"        # the Inbox row's owner while nobody has read the plate yet


def live_output_dir() -> Path:
    from engine.pipeline import EVIDENCE_DIR
    return EVIDENCE_DIR / "forensic" / LIVE_TASK / "output"


def _live_run_config(config: dict) -> dict:
    """What the plate tools of the live review read from forensic_config.json: the plate settings of the live setup."""
    keys = ("plate_format", "ocr_engine", "enhancement", "plate_model", "plate_method", "primary_model", "tracker", "use_sahi",
            "flag_sensitivity", "per_violation_configs", "blur_privacy")
    cfg = {k: config[k] for k in keys if k in config}
    cfg.setdefault("plate_format", "ph_standard")
    cfg.setdefault("ocr_engine", "easyocr")
    # the GAN (Real-ESRGAN) when its model is installed, else a plain upscale: the plate is read as seen AND enhanced
    models = Path(__file__).resolve().parent.parent / "models"
    cfg.setdefault("enhancement", "realesrgan" if next(models.rglob("realesrgan.onnx"), None) else "lanczos")
    return cfg


async def publish_live_ticket(lt: dict, config: dict, save_violation) -> list:
    """A vehicle the live feed finished (a ledger ticket) becomes a ticket of the "live" run, plate not read yet. `config` = the live
    pipeline's settings. Returns the ids of the Inbox rows made."""
    out = live_output_dir()
    out.mkdir(parents=True, exist_ok=True)
    cfg = _live_run_config(config)
    cfg_path = out / "forensic_config.json"
    text = json.dumps(cfg, indent=2, default=str)
    if not cfg_path.exists() or cfg_path.read_text() != text:
        cfg_path.write_text(text)
    ticket = _ticket_from_ledger({**lt, "plate_crops": [], "plate_text": "unidentified"}, cfg)
    ticket["plate_status"] = lt.get("plate_status") if "no_plate" in ticket["violations"] and lt.get("plate_status") else "pending"
    ticket["source"] = "live"
    ids: list = []
    await _publish_ticket(LIVE_TASK, ticket, cfg, out, save_violation, ids, source="live", unread_user=LIVE_PENDING_USER)
    from engine.plate_service import SERVICE
    SERVICE.warm()                              # once: the plate process loads its models now, so the first click on a ticket is fast
    ensure_live_plate_worker()                  # the plate is read in the background, one ticket at a time
    return ids


# ─── The live plate queue ──────────────────────────────────────────────────────────────────────────────────────
# A live ticket is saved at once (nothing is lost) with plate_status "pending" and listed at once, in the order it came. By default the plate
# is read ONLY when the reviewer opens (clicks) the ticket: POST /live-tickets/read-plate. With HK_LIVE_PLATE_AUTO=1 ONE background worker
# reads the plates of the pending tickets one by one instead (the same read as "Read the plate": the plate is found in the evidence photos, read as seen and enhanced,
# and voted). When a ticket is done its status becomes read / not_read / not_found, and only then does the Live Monitor's side list show
# it. The worker never blocks the live feed (the read runs in a thread) and never overwrites what the reviewer did meanwhile.

LIVE_MAX_ATTEMPTS = 3
_live_worker: "asyncio.Task | None" = None
_live_wake: "asyncio.Event | None" = None
_live_current: str | None = None                 # the ticket being read now
_live_attempts: dict[str, int] = {}


def _auto_read() -> bool:
    import os
    return os.environ.get("HK_LIVE_PLATE_AUTO", "0").strip() == "1"


def ensure_live_plate_worker() -> None:
    """Start the worker if it is not running (also after a restart: tickets that were still pending are then picked up), or wake it.
    Only when HK_LIVE_PLATE_AUTO=1: otherwise the plate is read when the reviewer opens the ticket."""
    global _live_worker, _live_wake
    if not _auto_read():
        return
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        return                                   # no event loop (a script): nothing to start
    if _live_wake is None:
        _live_wake = asyncio.Event()
    if _live_worker is None or _live_worker.done():
        _live_worker = loop.create_task(_live_plate_loop())
    _live_wake.set()


def _pending_live(tickets: list) -> list[dict]:
    return [t for t in tickets if t.get("plate_status") == "pending" and t.get("ticket_uid")]


_live_state_cache: tuple | None = None           # ((mtime_ns, size) of report.json, tickets waiting): the dashboard asks every few seconds
_live_down_s = 0.0                               # wait when the plate process cannot start; it grows, so a broken start is not tried in a tight loop


async def _live_queue_state() -> dict:
    """{"waiting": n, "reading": uid or None}: the tickets whose plate is still to be read (the one being read counts).
    The report (several MB) is parsed only when the file has changed, and never on the event loop that carries the live feed."""
    global _live_state_cache
    report_path = live_output_dir() / "report.json"
    try:
        stat = report_path.stat()
    except OSError:
        return {"waiting": 0, "reading": _live_current}
    key = (stat.st_mtime_ns, stat.st_size)
    if _live_state_cache is None or _live_state_cache[0] != key:
        async with _report_lock:
            tickets = await asyncio.to_thread(_load_tickets, report_path)
        _live_state_cache = (key, len(_pending_live(tickets)))
    return {"waiting": _live_state_cache[1], "reading": _live_current}


async def _save_live_tickets(out_dir: Path, report_path: Path, tickets: list, reflag: bool) -> None:
    """_save_edited for the live queue, off the event loop. The duplicate flags are worked out again only when a plate changed: they depend
    on the plates and on the boxes and times of the photos, and a read that finds no plate changes none of those."""
    from engine.ticket_flags import annotate_tickets

    def work() -> None:
        if reflag:
            annotate_tickets(tickets, _levenshtein, _run_config(out_dir).get("flag_sensitivity", 4))
        _write_report(report_path, tickets)

    await asyncio.to_thread(work)
    if LIVE_TASK in forensic_tasks:
        forensic_tasks[LIVE_TASK]["tickets"] = tickets


async def _live_plate_loop() -> None:
    global _live_current
    while True:
        try:
            _live_wake.clear()                   # cleared BEFORE looking, so a ticket that arrives meanwhile still wakes the next wait
            async with _report_lock:
                pending = _pending_live(await asyncio.to_thread(_load_tickets, live_output_dir() / "report.json"))
            if not pending:
                try:
                    await asyncio.wait_for(_live_wake.wait(), timeout=15)
                except asyncio.TimeoutError:
                    pass
                continue
            _live_current = pending[0]["ticket_uid"]
            await _read_live_ticket(pending[0])
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("The live plate queue hit an error")
            await asyncio.sleep(2)
        finally:
            _live_current = None


_live_reading: set = set()                       # live tickets being read right now (a second click, or the queue, leaves them alone)


async def _read_live_ticket(snapshot: dict, background: bool = True) -> None:
    """Read the plate of one pending live ticket (`snapshot`: the ticket as it was found) from its evidence photos and save the result (see
    the section text above). `background` = the queue's read (tried a few times, then given up); False = the reviewer opened the ticket: it is
    tried once and a failure is raised to the caller. The report is read and written in threads: it is several MB, and the event loop also
    carries the live feed."""
    global _live_down_s
    from store import update_violation_plate

    uid = snapshot["ticket_uid"]
    if uid in _live_reading:
        return
    _live_reading.add(uid)
    try:
        out = live_output_dir()
        report_path = out / "report.json"
        gave_up = False
        if background:
            _live_attempts[uid] = _live_attempts.get(uid, 0) + 1
            gave_up = _live_attempts[uid] > LIVE_MAX_ATTEMPTS
        before = photo_names(snapshot)
        config = _run_config(out)
        plate_format = config.get("plate_format") or "ph_standard"
        new, summary = None, None
        if not gave_up:
            from engine.plate_service import SERVICE, PlateServiceDown
            try:
                if background:
                    # a background job of the plate process: the reviewer's own reads go before it
                    new, summary = await asyncio.to_thread(SERVICE.run_in_background, _reread_with_models, snapshot, [], config, plate_format)
                else:
                    # opened by the reviewer: fast. At most 8 photos, spread over the whole ticket (all of them when there are fewer)
                    names = [m["file"] for m in snapshot.get("evidence_meta", []) if m.get("file")]
                    pick = [names[round(i * (len(names) - 1) / 7)] for i in range(8)] if len(names) > 8 else []
                    new, summary = await asyncio.to_thread(_reread_with_models, snapshot, pick, config, plate_format)
                _live_down_s = 0.0
            except ValueError:
                new = None                                            # nothing to read in these photos
                _live_down_s = 0.0
            except PlateServiceDown:
                if not background:
                    raise
                _live_attempts[uid] -= 1                              # the process could not start: not this ticket's fault
                _live_down_s = min(120.0, max(10.0, _live_down_s * 2))
                log.exception("The plate process could not start (next try in %.0f s)", _live_down_s)
                await asyncio.sleep(_live_down_s)
                return
            except Exception:
                if not background:
                    raise
                log.exception("Reading the plate of live ticket %s failed", uid)
                return                                                # tried again next round, up to LIVE_MAX_ATTEMPTS
        async with _report_lock:
            tickets = await asyncio.to_thread(_load_tickets, report_path)
            idx = next((i for i, t in enumerate(tickets) if t.get("ticket_uid") == uid), None)
            if idx is None:
                return                                                # merged away or removed meanwhile
            current = tickets[idx]
            if current.get("plate_status") != "pending" or photo_names(current) != before:
                return                                                # the reviewer changed it: their work wins
            done = new if new is not None else dict(current)
            if done.get("plate_text", "unidentified") not in _UNREAD:
                done["plate_status"] = "read"
            elif summary is not None and summary.get("found"):
                done["plate_status"] = "not_read"                     # a plate was seen, no text could be read
            else:
                done["plate_status"] = "not_found"                    # no plate could be found in the photos
            if done["plate_status"] != "read":
                await update_violation_plate(done.get("db_ids", []), "unidentified", "no_plate_found")
            else:
                await _sync_plate(current, done)                      # the Inbox rows follow the plate (and its owner)
            tickets[idx] = done
            await _save_live_tickets(out, report_path, tickets, reflag=done.get("plate_text") != current.get("plate_text"))
        _live_attempts.pop(uid, None)
    finally:
        _live_reading.discard(uid)


def _live_photo_files(tickets: list) -> set:
    """Every picture file the live tickets own: the evidence photos, the vehicle and clean crops, the close-ups, the plate crops. They all sit
    in the evidence folder (by name, or by a path under it); a file under another run's folder is never touched."""
    from engine.pipeline import EVIDENCE_DIR

    root = EVIDENCE_DIR.resolve()
    forensic_dir = (EVIDENCE_DIR / "forensic").resolve()
    found: set = set()

    def walk(value) -> None:
        if isinstance(value, dict):
            for item in value.values():
                walk(item)
        elif isinstance(value, (list, tuple)):
            for item in value:
                walk(item)
        elif isinstance(value, str) and value.lower().endswith((".jpg", ".jpeg", ".png")):
            try:
                path = (EVIDENCE_DIR / Path(value).name if Path(value).is_absolute() else EVIDENCE_DIR / value).resolve()
            except OSError:
                return
            if root in path.parents and forensic_dir not in path.parents:
                found.add(path)

    walk(tickets)
    return found


async def clear_live_tickets() -> dict:
    """Start the Live Monitor's tickets from nothing: every ticket the live feed made before (the standing "live" run: its report, its
    Inbox rows, its evidence photos) is deleted. Tickets of forensic analyses are never touched. {"tickets", "rows", "files"}."""
    from store import delete_violations_by_source

    out = live_output_dir()
    async with _report_lock:
        report_path = out / "report.json"
        try:
            tickets = json.loads(report_path.read_text()) if report_path.exists() else []
        except ValueError:
            tickets = []
        def remove_files(paths) -> int:
            removed = 0
            for path in paths:
                try:
                    path.unlink(missing_ok=True)
                    removed += 1
                except OSError as exc:
                    log.warning("Could not remove %s: %s", path, exc)
            return removed

        # thousands of pictures: removed in a thread, so the backend (and the live feed's messages) are not frozen meanwhile
        files = await asyncio.to_thread(remove_files, _live_photo_files(tickets))
        rows = await delete_violations_by_source("live")
        shutil.rmtree(out, ignore_errors=True)               # report.json and forensic_config.json (written again with the next ticket)
        forensic_tasks.pop(LIVE_TASK, None)
        _live_attempts.clear()
    return {"tickets": len(tickets), "rows": rows, "files": files}


@router.delete("/live-tickets")
async def delete_live_tickets():
    """Clear every ticket of the Live Monitor (not the forensic analyses)."""
    return await clear_live_tickets()


@router.get("/live-queue")
async def live_plate_queue():
    """The Live Monitor's side list: how many live tickets wait for their plate, and which one is being read now."""
    from engine.plate_service import SERVICE

    ensure_live_plate_worker()                                    # after a restart this picks the waiting tickets up again
    return {**await _live_queue_state(), "plate_process": SERVICE.status()}


class LiveReadRequest(BaseModel):
    ticket_uid: str


@router.post("/live-tickets/release-focus")
async def release_live_focus():
    """The reviewer left the live review: the live monitor goes on at once (it pauses while a plate is read). A read in progress goes on."""
    from engine.plate_service import SERVICE

    SERVICE.focus_release()
    return {"ok": True}


@router.post("/live-tickets/read-plate")
async def read_live_ticket_plate(req: LiveReadRequest):
    """The reviewer opened a live ticket: read its plate now when it has not been read yet (the plates are read on demand, one ticket at a
    time, in the plate process). Returns the live tickets. A failure of the plate process comes back as an error the review shows."""
    from engine.plate_service import PlateServiceError

    report_path = live_output_dir() / "report.json"
    async with _report_lock:
        tickets = await asyncio.to_thread(_load_tickets, report_path)
    snapshot = next((x for x in tickets if x.get("ticket_uid") == req.ticket_uid), None)
    if snapshot is None:
        return JSONResponse(status_code=404, content={"error": "Ticket not found"})
    if snapshot.get("plate_status") == "pending":
        try:
            await _read_live_ticket(snapshot, background=False)
        except PlateServiceError as exc:
            return JSONResponse(status_code=503, content={"error": str(exc)})
        except Exception as exc:
            log.exception("Reading the plate of live ticket %s failed", req.ticket_uid)
            return JSONResponse(status_code=500, content={"error": f"{type(exc).__name__}: {exc}"})
        async with _report_lock:
            tickets = await asyncio.to_thread(_load_tickets, report_path)
    return {"tickets": tickets}


async def _close_report(task_id: str, output_dir: Path, config: dict, save_violation) -> list:
    """The run is over: make sure a report exists (an empty run says so in the Inbox) and return its tickets."""
    from engine.ticket_flags import annotate_tickets

    async with _report_lock:
        report_path = output_dir / "report.json"
        tickets = json.loads(report_path.read_text()) if report_path.exists() else []
        if not tickets:
            await save_violation(
                cls="no_violations_detected", confidence=1.0, user_id="empty_session", image_path="", notify=False,
                status="pending", evidence_paths=[], track_id=-1, source="forensic", session_id=task_id,
                plate_text="unidentified",
            )
        annotate_tickets(tickets, _levenshtein, config.get("flag_sensitivity", 4))
        report_path.write_text(json.dumps(tickets, indent=2))
        task = forensic_tasks.get(task_id)
        if task is not None:
            task["tickets"] = tickets
            task["ticket_count"] = len(tickets)
        return tickets


class _TicketReleaser:
    """Worker thread of one analysis. The video loop hands it the vehicles that left the scene; it reads their plates and
    publishes the tickets one by one, while the loop keeps reading the video."""

    def __init__(self, task_id: str, config: dict, output_dir: Path, written: list, save_violation):
        self.task_id, self.config, self.output_dir = task_id, config, output_dir
        self.written, self.save_violation = written, save_violation
        self.submitted: list = []      # the ledger's tickets handed in (the Cancel clean-up needs their photos)
        self.db_ids: list = []         # Inbox rows made so far (a Cancel removes them again)
        self.crops_total = 0
        self.crops_done = 0
        self.cancelled = False
        self.error: Exception | None = None
        self._queue: queue.Queue = queue.Queue()
        self._thread = threading.Thread(target=self._work, name=f"release-{task_id[:8]}", daemon=True)
        self._thread.start()

    def submit(self, ledger_tickets: list) -> None:
        for lt in ledger_tickets:
            self.submitted.append(lt)
            self.crops_total += len(lt.get("plate_crops") or [])
            self._queue.put(lt)

    def _on_crop(self) -> None:
        self.crops_done += 1

    def _work(self) -> None:
        while True:
            lt = self._queue.get()
            if lt is None:
                return
            if self.cancelled or self.error is not None:
                continue
            try:
                t = _ticket_from_ledger(lt, self.config)
                _read_ticket_plate(self.task_id, t, self.config, self.written, self._on_crop)
                _run_async(_publish_ticket(self.task_id, t, self.config, self.output_dir, self.save_violation, self.db_ids))
            except _ForensicCancelled:
                self.cancelled = True
            except Exception as e:      # reported by finish()
                log.error(f"[Forensic] Could not release a ticket of task {self.task_id}: {e}", exc_info=True)
                self.error = e

    def finish(self) -> None:
        """Wait for the last tickets; shows how far the plate reading is. Raises _ForensicCancelled / the worker's error."""
        self._queue.put(None)
        while self._thread.is_alive():
            self._thread.join(timeout=0.5)
            _say(self.task_id, f"Reading plates: {self.crops_done} of {self.crops_total}")
            forensic_tasks[self.task_id]["progress"] = round(92.0 + 7.0 * self.crops_done / max(1, self.crops_total), 1)
        if self.error is not None:
            raise self.error
        if self.cancelled or _stop_mode(self.task_id) == "cancel":
            raise _ForensicCancelled()

    def abort(self) -> None:
        """Cancel or a failure: stop the worker and wait for it, so nothing is written after the clean-up."""
        self.cancelled = True
        self._queue.put(None)
        self._thread.join()


def prepare_pipeline_config(config: dict) -> dict:
    """
    The dashboard wizard's settings -> the pipeline's camera config (changes `config` in place and returns it).
    Flutter's per_violation_configs become the pipeline's regions_of_interest: each violation module maps its own
    wizard settings (engine/violations/*.py: from_wizard / settings_from_wizard).
    """
    from engine.violations import ALL as ALL_VIOLATIONS, LEGACY_KEYS, ZONE_VIOLATIONS, current_keys
    # rules merged into one: an old saved setup still loads under the new key
    config["active_violations"] = current_keys(config.get("active_violations"))
    per_v = {}
    for key, settings in (config.get("per_violation_configs") or {}).items():
        per_v.setdefault(LEGACY_KEYS.get(key, key), {}).update(settings or {})
    config["per_violation_configs"] = per_v
    rois = {v.zone_key: v.from_wizard(per_v[v.key]) for v in ZONE_VIOLATIONS if v.key in per_v}
    for violation in ALL_VIOLATIONS:
        if violation.key in per_v:
            config.update(violation.settings_from_wizard(per_v[violation.key]))

    config["regions_of_interest"] = rois

    # Hardcoded 1920x1080 because Flutter frontend currently scales the 640x360 canvas by 3.0
    config["video_native_width"] = 1920
    config["video_native_height"] = 1080
    return config


def forensic_processing_task(task_id: str, video_path: Path, output_dir: Path, config: dict):
    pipeline = None          # known to the Cancel clean-up
    releaser = None          # turns the vehicles that left the scene into tickets while the video is still being read
    written: list = []       # plate pictures saved so far (also for the Cancel clean-up)
    early: dict = {}         # filled when the operator pressed "Stop here"
    try:
        log.info(f"[Forensic] Starting task {task_id}")
        forensic_tasks[task_id].setdefault("ticket_count", 0)
        forensic_tasks[task_id]["video_done"] = False
        save_violation = _skip_db if config.get("benchmark") else add_violation

        # Road and traffic overlays placed in the wizard: paint them, read the markings back, give them to the rules
        if config.get("scene_overlays"):
            from engine import scene_overlays
            forensic_tasks[task_id]["message"] = "Reading the road markings..."
            forensic_tasks[task_id]["message"] = scene_overlays.apply(config, video_path) or ""

        # "Crossing a solid line" with no drawn line: find the painted solid lines of the video first (engine/auto_lines.py)
        if "crossing_solid_line" in (config.get("active_violations") or []):
            from engine.auto_lines import fill_solid_lines
            forensic_tasks[task_id]["message"] = "Finding the painted solid lines..."
            forensic_tasks[task_id]["message"] = fill_solid_lines(config, video_path) or ""

        prepare_pipeline_config(config)

        # Write the transformed config to a temporary file for the pipeline to read
        temp_config_path = output_dir / "forensic_config.json"
        with open(temp_config_path, "w") as f:
            json.dump(config, f)

        # Extract model selection from the payload
        # Empty = use the active vehicle detector (set in the Models tab); a file name = use that one
        primary_model = config.get("primary_model")
        if primary_model:
            from yolo_inference import set_model_path
            if not primary_model.endswith(".onnx"):
                primary_model += ".onnx"
            try:
                set_model_path(primary_model)
            except Exception as e:
                log.error(f"Failed to load selected model {primary_model}, falling back to default: {e}")

        yolo = get_inference(force_reload=True, tracker_type=config.get("tracker", "bytetrack"))
        if yolo is not None:                                # the wizard's tile switch: also look for small people in tiles
            yolo.small_people = bool(config.get("use_sahi"))
        pipeline = DecoupledPipeline(str(temp_config_path))

        # The part of the video to analyze (the dashboard's trim step): seconds from the start of the file, or None
        trim_start = number_or_none(config.get("trim_start")) or 0.0
        trim_end = number_or_none(config.get("trim_end"))

        # Rules that only hold at certain hours (truck ban hours), or a start time typed by the operator: find the time of the
        # video (typed > clock in the picture > the file's own information > file name; engine/video_clock.py)
        from engine.video_clock import clock_wanted, resolve_clock
        if clock_wanted(config):
            forensic_tasks[task_id]["message"] = "Finding the time of the video..."
            clock = resolve_clock(video_path, start_text=config.get("video_start"), name=config.get("video_name"),
                                  trim_start=trim_start)
            pipeline.clock = clock                       # the rules read it frame by frame
            config["video_clock"] = clock.to_dict()      # the tickets read it
            forensic_tasks[task_id]["clock"] = clock.to_dict()
            log.info(f"[Forensic] Time of the video: {clock.to_dict()}")
            forensic_tasks[task_id]["message"] = ""

        # A rule that needs the traffic flow (counterflow, parking, loading) is on with nothing drawn, or flow_mode is "auto":
        # learn which way traffic goes from the first seconds of the clip (no zones or arrows needed)
        if pipeline.learns_flow and float(config.get("flow_prescan_seconds", 60)) > 0:
            from engine.flow_prescan import prescan_flow
            forensic_tasks[task_id]["message"] = "Learning the traffic flow..."
            prescan_seconds = float(config.get("flow_prescan_seconds", 60))
            if trim_end is not None and trim_end > trim_start:
                prescan_seconds = min(prescan_seconds, trim_end - trim_start)
            flow_summary = prescan_flow(pipeline, video_path, prescan_seconds, start_seconds=trim_start)
            log.info(f"[Forensic] Flow learned: {flow_summary}")
            forensic_tasks[task_id]["message"] = ""

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            raise Exception("Failed to open uploaded video file.")

        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps <= 0: fps = 30.0
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        video_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        first_frame, window = frame_window(fps, video_frames, trim_start, trim_end)      # analyze only the chosen part
        total_frames = window if window else max(video_frames - first_frame, 0)
        if total_frames <= 0: total_frames = 1000 # fallback
        if first_frame:
            cap.set(cv2.CAP_PROP_POS_FRAMES, first_frame)
            log.info(f"[Forensic] Task {task_id}: analyzing from frame {first_frame}" + (f" for {window} frames" if window else " to the end"))
        out_video_path = output_dir / "evidence_replay.mp4"

        frame_boxes: list = []        # per video frame: the boxes to draw over the replay

        def _save_boxes_part(part: int, first: int, last: int) -> None:
            # Every closed video piece also saves its boxes, so a crash does not lose the boxes of the finished pieces.
            try:
                (output_dir / f"boxes_part{part:04d}.json").write_text(
                    json.dumps(frame_boxes[first - 1:last], separators=(",", ":")), encoding="utf-8")
            except Exception:
                log.exception("[Forensic] boxes of video piece %s not saved", part)

        # The raw video is written in short pieces (see engine/segment_writer.py): a crash loses at most the open piece.
        out = SegmentedVideoWriter(output_dir, fps, (width, height), on_part_closed=_save_boxes_part)

        releaser = _TicketReleaser(task_id, config, output_dir, written, save_violation)
        frame_idx = 0
        stop_asked = None
        while cap.isOpened():
            stop_asked = _stop_mode(task_id)      # Stop here / Cancel from the dashboard
            if stop_asked:
                break
            if window is not None and frame_idx >= window:
                break                                   # the end of the chosen part
            ret, frame = cap.read()
            if not ret:
                break

            frame_idx += 1

            # 3. Process frame (no skipping! Rigorous forensic analysis)
            current_timestamp = frame_idx / fps if fps > 0 else frame_idx / 30.0
            _, detections = pipeline.process_frame(frame, frame_idx, timestamp=current_timestamp)

            # 4. Burn the zones into the frame. The boxes go to boxes.json instead: the dashboard draws them over the video,
            # so their lines stay thin when the video is zoomed.
            annotated_frame = pipeline.annotate_frame_fast(frame.copy(), detections, boxes=False)
            try:
                frame_boxes.append(pipeline.box_specs(detections))
            except Exception:
                log.exception("[Forensic] Boxes of frame %s not saved", frame_idx)
                frame_boxes.append([])

            # 5. Write to raw video file
            out.write(annotated_frame)

            # Vehicles that left the scene are judged: hand them on, the operator can open their tickets at once
            if frame_idx % RELEASE_EVERY == 0:
                releaser.submit(pipeline.ledger_manager.drain_tickets())

            # Update progress (scale to 90% to leave room for FFmpeg compression)
            if frame_idx % 15 == 0:
                progress = round((frame_idx / total_frames) * 90, 1)
                forensic_tasks[task_id]["progress"] = min(90.0, progress)

        cap.release()
        out.release()
        try:
            (output_dir / "boxes.json").write_text(
                json.dumps({"w": width, "h": height, "fps": fps, "frames": frame_boxes}, separators=(",", ":")), encoding="utf-8")
        except Exception:
            log.exception("[Forensic] boxes.json not written: the replay shows no boxes")
        if stop_asked == "finish" and frame_idx == 0:
            stop_asked = "cancel"      # nothing was analyzed yet: there is nothing to keep
        if stop_asked == "cancel":
            raise _ForensicCancelled()
        if stop_asked == "finish":
            # Keep everything found up to here. The flag is cleared so a second "Stop here" can still cut the plate reading short.
            early.update(at_seconds=round(frame_idx / fps, 1), frames=frame_idx, of_frames=total_frames)
            forensic_tasks[task_id]["stop"] = None
            log.info(f"[Forensic] Task {task_id} stopped early at {early['at_seconds']} s")
        forensic_tasks[task_id]["video_done"] = True

        # Cars still on screen when the video ended get the same end-of-track decisions as cars that left (e.g. no_plate).
        # Their plates are read while the evidence video is being compressed.
        pipeline.ledger_manager.finalize_all()
        releaser.submit(pipeline.ledger_manager.drain_tickets())

        # 6. Compress and convert to web-safe H.264 using FFmpeg
        import subprocess
        _say(task_id, "Preparing the evidence video...")
        log.info(f"[Forensic] Converting {len(out.parts)} raw video pieces to H.264...")
        raw_input = out.ffmpeg_input()
        # NVENC might fail if NVIDIA drivers are older than v610 (FFmpeg 9.0+ requirement).
        # We try hardware acceleration first, and gracefully fallback to libx264 CPU encoding if it fails.
        nvenc_cmd = [
            "ffmpeg", "-y", *raw_input,
            "-c:v", "h264_nvenc", "-preset", "p6", "-b:v", "5M",
            "-movflags", "+faststart", str(out_video_path)
        ]
        cpu_cmd = [
            "ffmpeg", "-y", *raw_input,
            "-c:v", "libx264", "-preset", "fast", "-crf", "23",
            "-movflags", "+faststart", str(out_video_path)
        ]
        try:
            subprocess.run(nvenc_cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e_nv:
            short_err = str(e_nv.stderr).strip().split('\n')[-1] if e_nv.stderr else "Unknown fallback reason"
            log.warning(f"[Forensic] NVENC skipped (Driver < v610). Falling back to CPU libx264... ({short_err})")
            try:
                subprocess.run(cpu_cmd, check=True, capture_output=True, text=True)
            except subprocess.CalledProcessError as e_cpu:
                log.error(f"[Forensic] FATAL: CPU FFmpeg also failed! Error: {e_cpu.stderr}")
                raise RuntimeError(f"FFmpeg failed completely. CPU Error: {e_cpu.stderr}") from None

        # Clean up the massive raw pieces (and the per-piece box files: boxes.json holds them all)
        out.remove_parts()
        for part_file in output_dir.glob("boxes_part*.json"):
            part_file.unlink(missing_ok=True)
        if _stop_mode(task_id) == "cancel":
            raise _ForensicCancelled()
        forensic_tasks[task_id]["progress"] = 92.0
        _say(task_id, "Reading plates...")

        # Wait for the plates of the last tickets (the earlier ones were released while the video ran)
        releaser.finish()
        _run_async(_close_report(task_id, output_dir, config, save_violation))
        if releaser.crops_done < releaser.crops_total:
            early.update(plates_read=releaser.crops_done, of_plates=releaser.crops_total)

        if early:    # "Stop here" was used: say so in the run folder (the Library reads it) and in the status
            with open(output_dir / "stopped_early.json", "w") as f:
                json.dump(early, f)
            forensic_tasks[task_id]["stopped_early"] = early
        forensic_tasks[task_id]["stop"] = None
        forensic_tasks[task_id]["message"] = ""
        forensic_tasks[task_id]["status"] = "completed"
        forensic_tasks[task_id]["progress"] = 100.0
        forensic_tasks[task_id]["result_video"] = f"/snapshots/evidence/forensic/{task_id}/output/evidence_replay.mp4"

        log.info(f"[Forensic] Task {task_id} completed successfully!")

        # The uploaded video is only needed during analysis (the replay video is what gets watched).
        # Delete it to save disk space unless the operator asked to keep it (e.g. for Send to Live Monitor).
        if not config.get("keep_input_video", False):
            try:
                video_path.unlink(missing_ok=True)
                log.info(f"[Forensic] Removed uploaded video for task {task_id}")
            except Exception as e_del:
                log.warning(f"[Forensic] Could not remove uploaded video: {e_del}")

    except _ForensicCancelled:
        log.info(f"[Forensic] Task {task_id} cancelled by the operator")
        released = []
        if releaser is not None:
            releaser.abort()
            released = releaser.submitted
            rows = set(releaser.db_ids)
            try:        # tickets the operator made meanwhile (a new ticket from Holding) are in the report too
                rows.update(i for t in json.loads((output_dir / "report.json").read_text()) for i in t.get("db_ids", []))
            except (OSError, ValueError):
                pass
            if rows:         # tickets already released are thrown away with the rest
                try:
                    _run_async(delete_violations(sorted(rows)))
                except Exception as e_db:
                    log.warning(f"[Forensic] Could not remove the released tickets of {task_id} from the Inbox: {e_db}")
        _discard_run(pipeline, written, output_dir.parent, released)
        forensic_tasks[task_id]["tickets"] = []
        forensic_tasks[task_id]["ticket_count"] = 0
        forensic_tasks[task_id]["message"] = "Cancelled."
        forensic_tasks[task_id]["status"] = "cancelled"
    except Exception as e:
        if releaser is not None:
            releaser.abort()
        log.error(f"[Forensic] Task {task_id} failed: {e}", exc_info=True)
        forensic_tasks[task_id]["status"] = "failed"
        forensic_tasks[task_id]["error"] = str(e)


@router.post("/upload")
async def upload_forensic_video(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    config_json: str = Form(...)
):
    try:
        config = json.loads(config_json)
    except Exception as e:
        return JSONResponse(status_code=400, content={"error": "Invalid JSON config"})

    task_id = str(uuid.uuid4())
    
    from engine.pipeline import EVIDENCE_DIR
    task_dir = EVIDENCE_DIR / "forensic" / task_id
    task_dir.mkdir(parents=True, exist_ok=True)
    
    video_path = task_dir / "input_video.mp4"
    output_dir = task_dir / "output"
    output_dir.mkdir(exist_ok=True)
    
    with open(video_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    forensic_tasks[task_id] = {
        "status": "processing",
        "progress": 0.0,
        "result_video": None,
        "tickets": [],
        "ticket_count": 0,        # tickets released so far (the operator can open them while the video is read)
        "video_done": False,
    }

    global _main_loop
    _main_loop = asyncio.get_running_loop()      # the analysis thread posts its report / database work here

    background_tasks.add_task(
        forensic_processing_task,
        task_id,
        video_path,
        output_dir,
        config
    )
    
    return {"task_id": task_id, "message": "Forensic analysis started in the background."}

@router.get("/status/{task_id}")
async def get_forensic_status(task_id: str, include: str = ""):
    """Progress of an analysis. While it runs the (growing) ticket list is only sent when asked for with
    `?include=tickets`: the dashboard polls every second and most polls only need the progress."""
    task = forensic_tasks.get(task_id)
    if task is None:
        return JSONResponse(status_code=404, content={"error": "Task not found"})
    if task.get("status") == "processing" and include != "tickets":
        return {k: v for k, v in task.items() if k != "tickets"}
    return task


@router.post("/stop/{task_id}")
async def stop_forensic(task_id: str, mode: str = "finish"):
    """Operator: end a running analysis.
    mode=finish ("Stop here") keeps everything found so far; asked again during the plate reading it also skips the
    plates not read yet. mode=cancel throws the whole run away (no tickets, no files). The run notices within a frame or a plate."""
    if mode not in ("finish", "cancel"):
        return JSONResponse(status_code=400, content={"error": "mode must be 'finish' or 'cancel'"})
    task = forensic_tasks.get(task_id)
    if task is None:
        return JSONResponse(status_code=404, content={"error": "Task not found"})
    if task.get("status") != "processing":
        return JSONResponse(status_code=409, content={"error": "This analysis is not running."})
    if task.get("stop") != "cancel":                  # a Cancel already asked for cannot be softened
        task["stop"] = mode
        task["message"] = "Cancelling..." if mode == "cancel" else "Stopping, keeping what was found..."
    return {"task_id": task_id, "stop": task["stop"]}


@router.post("/send-to-live/{task_id}")
async def send_to_live(task_id: str):
    """Use a finished forensic run's video + rules as the live monitor source (demo helper)."""
    from engine.pipeline import EVIDENCE_DIR
    from routers import stream

    try:
        uuid.UUID(task_id)
    except ValueError:
        return JSONResponse(status_code=400, content={"error": "Invalid task id"})

    task_dir = EVIDENCE_DIR / "forensic" / task_id
    video_path = task_dir / "input_video.mp4"
    config_path = task_dir / "output" / "forensic_config.json"
    if not config_path.exists():
        return JSONResponse(status_code=404, content={"error": "Forensic run or its config not found"})
    if not video_path.exists():
        return JSONResponse(status_code=410, content={
            "error": "The uploaded video of this run was deleted to save space. "
                     "Turn on 'Keep uploaded video' in the analysis settings to use Send to Live Monitor."})

    with open(config_path, "r") as f:
        config = json.load(f)
    config.setdefault("camera_id", f"forensic_{task_id[:8]}")
    config["source_url"] = str(video_path)
    config["source_type"] = "video_file"
    try:                                                       # keep the saved camera addresses
        existing = json.loads(stream.CONFIG_PATH.read_text(encoding="utf-8")) if stream.CONFIG_PATH.exists() else {}
    except ValueError:
        existing = {}
    if "camera_profiles" in existing:
        config["camera_profiles"] = existing["camera_profiles"]
    with open(stream.CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)

    # Match the tracker used in the forensic run (the inference singleton is global)
    get_inference(force_reload=True, tracker_type=config.get("tracker", "bytetrack"))

    from routers.settings import _apply_video_source, _remember_source
    _remember_source(str(video_path))
    _apply_video_source(str(video_path))
    return {"message": "Live monitor now uses this forensic run's video and rules", "video": str(video_path)}


@router.post("/live-config")
async def use_wizard_for_live(config: dict):
    """
    The wizard's zones and settings (the same payload as /upload) become the Live Monitor's rules, so every one of the
    violations the wizard offers works live without an analysis run. The camera itself is not touched: pick it in
    Camera input. The saved camera addresses and the chosen camera are kept.
    """
    from engine.start_log import START
    from routers import stream

    START.begin("apply")                                       # (the timeline of this start: GET /settings/live/perf -> "startup")
    config = prepare_pipeline_config(dict(config))
    selected = config.get("active_violations", [])
    if not selected:
        return JSONResponse(status_code=400, content={"error": "Switch at least one violation on first."})
    try:
        existing = json.loads(stream.CONFIG_PATH.read_text(encoding="utf-8")) if stream.CONFIG_PATH.exists() else {}
    except ValueError:
        existing = {}
    # the camera choice, what the camera learned about its road and the operator's setting for it are not the wizard's to overwrite
    for key in ("camera_profiles", "active_source", "learned_road", "learned_lines_as_rules"):
        if key in existing:
            config[key] = existing[key]
    config.setdefault("camera_id", existing.get("camera_id", "live"))
    if str(config.get("video_start") or "").strip():          # "pretend it is 7:30": rules with hours use it live
        config["clock_start"] = config["video_start"]
    with open(stream.CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
    START.mark("rules saved")

    def build() -> None:
        # Loading models takes seconds. It runs in a thread, so the backend keeps answering (the dashboard's other requests are served,
        # its "Processing" view stays alive). What was loaded before (detector, ReID networks, the models of the rules that did not change)
        # is used again, not loaded a second time: see get_inference / ModelRegistry.
        try:
            get_inference(force_reload=True, tracker_type=config.get("tracker", "bytetrack"))
            START.mark("detector ready")
            stream.reset_rules()                               # a new setup: every rule of it is on
            stream.reload_pipeline()
            START.mark("pipeline built")
            stream.warm_up_pipeline()                          # the first run of each model, now and not on the first live picture
            START.mark("models warm")
        finally:
            stream.end_rebuild()                               # the feed that waits for the new rules may start (also when the build failed)

    # A running live view stops NOW (it closes its connection and the dashboard reconnects): its last pictures must not be judged on the
    # fresh trackers that the build below puts in place, and the feed that connects meanwhile must wait for the NEW pipeline, not take the old.
    stream.begin_rebuild()
    stream._stream_generation += 1
    await asyncio.to_thread(build)
    return {"message": "The Live Monitor now uses these zones and settings", "violations": selected}


@router.get('/history')
async def get_forensic_history():
    from engine.pipeline import EVIDENCE_DIR
    import os
    
    forensic_dir = EVIDENCE_DIR / 'forensic'
    if not forensic_dir.exists():
        return []
        
    history = []
    for task_dir in forensic_dir.iterdir():
        if not task_dir.is_dir(): continue
        
        task_id = task_dir.name
        report_path = task_dir / 'output' / 'report.json'
        video_path = task_dir / 'output' / 'evidence_replay.mp4'
        
        if report_path.exists():
            with open(report_path, 'r') as f:
                try:
                    tickets = json.load(f)
                except:
                    tickets = []
                    
            history.append({
                'task_id': task_id,
                'created_at': os.path.getctime(report_path),
                'ticket_count': len(tickets),
                'stopped_early': (task_dir / 'output' / 'stopped_early.json').exists(),
                'running': forensic_tasks.get(task_id, {}).get('status') == 'processing',
                'video_url': f'/snapshots/evidence/forensic/{task_id}/output/evidence_replay.mp4' if video_path.exists() else None,
                'report_url': f'/snapshots/evidence/forensic/{task_id}/output/report.json'
            })
            
    # Sort newest first
    history.sort(key=lambda x: x['created_at'], reverse=True)
    return history


@router.get('/road-markings', dependencies=[Depends(local_only)])
async def road_markings(file_path: str):
    """Find the painted stop line, crosswalk and solid lane lines of a video on this laptop (engine/road_lines.py, no model)
    and suggest zones for the rules that need them, in the wizard's own zone shape. Suggestions only: the operator checks them.
    It needs a fixed camera with some traffic passing; when it cannot read the road, "message" says why in plain words."""
    from clip_cutter import VIDEO_EXTENSIONS
    from engine.road_lines import analyse_video, reference_zones

    source = Path(file_path)
    if not source.is_file():
        raise HTTPException(status_code=404, detail="That video was not found")
    if source.suffix.lower() not in VIDEO_EXTENSIONS:
        raise HTTPException(status_code=400, detail="That does not look like a video file")
    try:
        found, _background = await asyncio.to_thread(analyse_video, source)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    solid = [ln for ln in found["lane_lines"] if ln["style"] == "solid"]
    return {
        "zones": reference_zones(found),
        "message": None if found["ok"] else found["reason"],
        "found": {"stop_lines": len(found["stop_lines"]), "crosswalks": len(found["crosswalks"]),
                  "solid_lines": len(solid), "dashed_lines": len(found["lane_lines"]) - len(solid)},
    }


@router.get('/overlay-object', dependencies=[Depends(local_only)])
def overlay_object(kind: str = "sign", scale: float = 1.0, angle: float = 0.0, tilt: float = 0.0, stand: str = "",
                   realistic: bool = True, frame_width: int = 1920):
    """An overlay object (hydrant, sign on a pole ...) as a PNG with see-through parts, for the wizard to draw on the first frame. The
    headers X-Offset-X / X-Offset-Y say where its top-left pixel sits relative to the spot it stands on, in pixels of a picture
    `frame_width` wide. Same drawing as the photos (engine/overlay_objects.py)."""
    from engine import overlay_objects
    png, ox, oy = overlay_objects.preview(kind, scale, angle, tilt, stand or None, realistic, min(max(frame_width, 320), 4096))
    return Response(content=png, media_type="image/png", headers={
        "X-Offset-X": str(ox), "X-Offset-Y": str(oy), "Access-Control-Expose-Headers": "X-Offset-X, X-Offset-Y", "Cache-Control": "max-age=3600"})


class OverlayLineRequest(BaseModel):
    points: list[list[float]]
    look: dict = {}
    realistic: bool = True


@router.post('/overlay-line', dependencies=[Depends(local_only)])
def overlay_line(request: OverlayLineRequest):
    """Road paint along a line (points in the 1920x1080 reference space) as a PNG with see-through parts, for the wizard to draw on the first
    frame. The headers X-Offset-X / X-Offset-Y say where its top-left pixel sits on the picture. Same drawing as the photos (engine/line_paint.py)."""
    from engine import line_paint
    png, ox, oy = line_paint.preview(request.points, request.look, request.realistic)
    if not png:
        raise HTTPException(status_code=422, detail="A line needs two or more points")
    return Response(content=png, media_type="image/png", headers={
        "X-Offset-X": str(ox), "X-Offset-Y": str(oy), "Access-Control-Expose-Headers": "X-Offset-X, X-Offset-Y"})


@router.get('/video-clock', dependencies=[Depends(local_only)])
async def video_clock(file_path: str, video_start: str = "", trim_start: float = 0.0):
    """What time of day is this video (a file on this laptop, found by its path)? The same search the analysis does, so the
    operator sees the answer - and where it came from - before starting, and can type the right time if it is wrong or missing.
    {start, source, label, confirmed, note, daylight}; `start` is null when no real time was found."""
    from clip_cutter import VIDEO_EXTENSIONS
    from engine.video_clock import resolve_clock

    source = Path(file_path)
    if not source.is_file():
        raise HTTPException(status_code=404, detail="That video was not found")
    if source.suffix.lower() not in VIDEO_EXTENSIONS:
        raise HTTPException(status_code=400, detail="That does not look like a video file")
    clock = await asyncio.to_thread(resolve_clock, source, start_text=video_start, trim_start=max(trim_start, 0.0))
    return clock.to_dict()


@router.post('/scene-preview', dependencies=[Depends(local_only)])
async def scene_preview(body: dict):
    """One frame of a video on this laptop with the wizard's road and traffic overlays painted on it, and what the road
    finder reads from that picture outlined. Body: {"file_path", "seconds", "overlays": [...]} (engine/scene_overlays.py).
    Returns {"image": base64 JPEG, "found": counts, "width", "height"}."""
    import base64

    from engine import scene_overlays

    source = Path(str(body.get("file_path") or ""))
    if not source.is_file():
        raise HTTPException(status_code=404, detail="That video was not found")
    picture, found = await asyncio.to_thread(scene_overlays.preview, source, float(body.get("seconds") or 0.0), body.get("overlays"))
    if picture is None:
        raise HTTPException(status_code=400, detail="That frame could not be read")
    ok, jpeg = cv2.imencode(".jpg", picture, [cv2.IMWRITE_JPEG_QUALITY, 88])
    return {"image": base64.b64encode(jpeg.tobytes()).decode("ascii"), "found": found,
            "width": int(picture.shape[1]), "height": int(picture.shape[0])}


@router.get('/video-frame', dependencies=[Depends(local_only)])
async def video_frame(file_path: str, seconds: float = 0.0):
    """One frame of a video on this laptop, found by its path (nothing is uploaded), with the video's speed and length.
    The trim step uses it for the picture that zones are drawn on."""
    from clip_cutter import VIDEO_EXTENSIONS
    from engine.pipeline import EVIDENCE_DIR

    source = Path(file_path)
    if not source.is_file():
        raise HTTPException(status_code=404, detail="That video was not found")
    if source.suffix.lower() not in VIDEO_EXTENSIONS:
        raise HTTPException(status_code=400, detail="That does not look like a video file")

    from engine.video_clock import look_ahead
    look_ahead(source)       # a video was just picked: start reading its time now, in the background (nothing waits for it)

    def read() -> dict | None:
        cap = cv2.VideoCapture(str(source))
        try:
            fps = cap.get(cv2.CAP_PROP_FPS)
            fps = fps if fps and fps > 0 else 30.0
            count = max(int(cap.get(cv2.CAP_PROP_FRAME_COUNT)), 0)
            if seconds > 0 and count > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, min(round(seconds * fps), count - 1))
            ok, frame = cap.read()
            if not ok and seconds > 0:                  # a seek that landed past the readable end: use the first frame
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ok, frame = cap.read()
            if not ok:
                return None
            temp_dir = EVIDENCE_DIR / 'forensic' / 'temp'
            temp_dir.mkdir(parents=True, exist_ok=True)
            name = f'{uuid.uuid4()}.jpg'
            cv2.imwrite(str(temp_dir / name), frame)
            return {'frame_url': f'/snapshots/evidence/forensic/temp/{name}', 'fps': fps, 'frame_count': count,
                    'duration': count / fps if count else 0.0}
        finally:
            cap.release()

    found = await asyncio.to_thread(read)
    if found is None:
        raise HTTPException(status_code=400, detail="Failed to read that video file")
    return found


@router.post('/extract-frame')
async def extract_first_frame(file: UploadFile = File(...)):
    from engine.pipeline import EVIDENCE_DIR
    import os
    
    task_id = str(uuid.uuid4())
    temp_dir = EVIDENCE_DIR / 'forensic' / 'temp'
    temp_dir.mkdir(parents=True, exist_ok=True)
    
    video_path = temp_dir / f'{task_id}.mp4'
    frame_path = temp_dir / f'{task_id}.jpg'
    
    with open(video_path, 'wb') as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    cap = cv2.VideoCapture(str(video_path))
    ret, frame = cap.read()
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()

    video_path.unlink(missing_ok=True)

    if not ret:
        return JSONResponse(status_code=400, content={'error': 'Failed to read video file'})

    cv2.imwrite(str(frame_path), frame)

    return {
        'frame_url': f'/snapshots/evidence/forensic/temp/{task_id}.jpg',
        'fps': fps if fps and fps > 0 else 30.0,
        'frame_count': max(frame_count, 0),
    }



class ConvertRequest(BaseModel):
    file_path: str

@router.post("/convert")
async def convert_video(req: ConvertRequest):
    input_path = Path(req.file_path)
    if not input_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
        
    output_path = input_path.with_name(f"{input_path.stem}_h264{input_path.suffix}")
    
    nvenc_cmd = [
        "ffmpeg", "-y", "-hwaccel", "cuda", 
        "-i", str(input_path), 
        "-c:v", "h264_nvenc", "-preset", "p6", "-b:v", "10M", 
        "-c:a", "copy", 
        str(output_path)
    ]
    cpu_cmd = [
        "ffmpeg", "-y", 
        "-i", str(input_path), 
        "-c:v", "libx264", "-preset", "fast", "-crf", "23", 
        "-c:a", "copy", 
        str(output_path)
    ]
    
    import subprocess
    try:
        def run_nvenc():
            return subprocess.run(nvenc_cmd, capture_output=True, text=True)
            
        def run_cpu():
            return subprocess.run(cpu_cmd, capture_output=True, text=True)
            
        process = await asyncio.to_thread(run_nvenc)
        
        # If NVENC fails due to driver age, gracefully fallback to CPU
        if process.returncode != 0:
            err_str = process.stderr.strip().split('\n')[-1] if process.stderr else "Unknown error"
            log.warning(f"NVENC skipped, falling back to CPU: {err_str}")
            process = await asyncio.to_thread(run_cpu)
            
            if process.returncode != 0:
                raise HTTPException(status_code=500, detail=f"FFmpeg CPU fallback error: {process.stderr}")
                
        return {"status": "success", "output_path": str(output_path)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class TrimRequest(BaseModel):
    file_path: str
    start_time: str
    end_time: str

@router.post("/trim")
async def trim_video(req: TrimRequest):
    from fastapi import HTTPException
    input_path = Path(req.file_path)
    if not input_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
        
    output_path = input_path.with_name(f"{input_path.stem}_trimmed{input_path.suffix}")
    
    cmd = [
        "ffmpeg", "-y", 
        "-ss", req.start_time,
        "-to", req.end_time,
        "-i", str(input_path), 
        "-c", "copy",
        str(output_path)
    ]
    
    import subprocess
    try:
        def run_trim():
            return subprocess.run(cmd, capture_output=True, text=True)
            
        process = await asyncio.to_thread(run_trim)
        
        if process.returncode != 0:
            raise HTTPException(status_code=500, detail=f"FFmpeg trim error: {process.stderr}")
                
        return {"status": "success", "output_path": str(output_path)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class TicketMergeRequest(BaseModel):
    task_id: str
    keep_uid: str
    merge_uid: str


@router.post("/tickets/merge")
@_serialized
async def merge_forensic_tickets(req: TicketMergeRequest):
    """Operator 'Same car': fold ticket `merge_uid` into `keep_uid`, in report.json and the DB."""
    from engine.pipeline import EVIDENCE_DIR
    from engine.ticket_merge import merge_tickets
    from engine.ticket_flags import annotate_tickets
    from store import merge_violation_rows

    if req.keep_uid == req.merge_uid:
        return JSONResponse(status_code=400, content={"error": "Cannot merge a ticket with itself"})

    out_dir = EVIDENCE_DIR / "forensic" / req.task_id / "output"
    report_path = out_dir / "report.json"
    if not report_path.exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})

    tickets = json.loads(report_path.read_text())
    by_uid = {t.get("ticket_uid"): t for t in tickets}
    keep, drop = by_uid.get(req.keep_uid), by_uid.get(req.merge_uid)
    if keep is None or drop is None:
        return JSONResponse(status_code=404, content={"error": "Ticket not found"})

    merged = merge_tickets(keep, drop)
    _record_reid("merge", req.task_id,
                 {_reid_label(req.task_id, keep): keep.get("evidence_meta", []) + drop.get("evidence_meta", [])})

    try:
        first_id = next(i for i in merged["merged_track_ids"] if isinstance(i, int))
    except StopIteration:
        first_id = -1
    merged["db_ids"] = await merge_violation_rows(
        keep.get("db_ids", []), drop.get("db_ids", []),
        photo_names(merged), merged.get("plate_text", "unidentified"), first_id)

    tickets = [merged if t is keep else t for t in tickets if t is not drop]

    sensitivity = 4
    try:
        sensitivity = json.loads((out_dir / "forensic_config.json").read_text()).get("flag_sensitivity", 4)
    except Exception:
        pass
    annotate_tickets(tickets, _levenshtein, sensitivity)

    report_path.write_text(json.dumps(tickets, indent=2))
    if req.task_id in forensic_tasks:
        forensic_tasks[req.task_id]["tickets"] = tickets
    return {"tickets": tickets}


class TicketMoveFramesRequest(BaseModel):
    task_id: str
    keep_uid: str
    from_uid: str
    frames: list[str]   # evidence file names of `from_uid` that are the same car as `keep_uid`


@router.post("/tickets/move-frames")
@_serialized
async def move_frames_into_ticket(req: TicketMoveFramesRequest):
    """Operator 'Merge selected frames': only the chosen frames of `from_uid` join `keep_uid`.
    When every frame is chosen this is a plain merge and the other ticket disappears."""
    from engine.pipeline import EVIDENCE_DIR
    from engine.ticket_merge import merge_tickets, split_ticket
    from engine.ticket_flags import annotate_tickets
    from store import merge_violation_rows, split_violation_rows

    if req.keep_uid == req.from_uid:
        return JSONResponse(status_code=400, content={"error": "Cannot merge a ticket with itself"})

    out_dir = EVIDENCE_DIR / "forensic" / req.task_id / "output"
    report_path = out_dir / "report.json"
    if not report_path.exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})

    tickets = json.loads(report_path.read_text())
    by_uid = {t.get("ticket_uid"): t for t in tickets}
    keep, src = by_uid.get(req.keep_uid), by_uid.get(req.from_uid)
    if keep is None or src is None:
        return JSONResponse(status_code=404, content={"error": "Ticket not found"})

    all_frames = set(src.get("evidence_paths", [])) | {m["file"] for m in src.get("evidence_meta", [])}
    chosen = set(req.frames)
    if not chosen or not chosen <= all_frames:
        return JSONResponse(status_code=400, content={"error": "Pick at least one frame of the other ticket"})

    if chosen >= all_frames:
        remaining, moved = None, src          # whole ticket moves = plain merge
    else:
        remaining, moved = split_ticket(src, req.frames)
        moved["db_ids"] = await split_violation_rows(
            remaining.get("db_ids", []), photo_names(remaining), photo_names(moved), req.task_id)
        moved["track_id"] = src.get("track_id")       # it is still the other car's track, not a new one
        moved["ticket_uid"] = req.from_uid

    merged = merge_tickets(keep, moved)
    _record_reid("merge", req.task_id,
                 {_reid_label(req.task_id, keep): keep.get("evidence_meta", []) + moved.get("evidence_meta", [])})
    try:
        first_id = next(i for i in merged["merged_track_ids"] if isinstance(i, int))
    except StopIteration:
        first_id = -1
    merged["db_ids"] = await merge_violation_rows(
        keep.get("db_ids", []), moved.get("db_ids", []),
        photo_names(merged), merged.get("plate_text", "unidentified"), first_id)

    out = []
    for t in tickets:
        if t is keep:
            out.append(merged)
        elif t is src:
            if remaining is not None:
                out.append(remaining)
        else:
            out.append(t)
    tickets = out

    sensitivity = 4
    try:
        sensitivity = json.loads((out_dir / "forensic_config.json").read_text()).get("flag_sensitivity", 4)
    except Exception:
        pass
    annotate_tickets(tickets, _levenshtein, sensitivity)

    report_path.write_text(json.dumps(tickets, indent=2))
    if req.task_id in forensic_tasks:
        forensic_tasks[req.task_id]["tickets"] = tickets
    return {"tickets": tickets}


class TicketNotDuplicateRequest(BaseModel):
    task_id: str
    uid_a: str
    uid_b: str


@router.post("/tickets/not-duplicate")
@_serialized
async def mark_not_duplicate(req: TicketNotDuplicateRequest):
    """Operator 'Different car': remember the pair so it is not flagged as a duplicate again."""
    from engine.pipeline import EVIDENCE_DIR
    from engine.ticket_flags import annotate_tickets

    out_dir = EVIDENCE_DIR / "forensic" / req.task_id / "output"
    report_path = out_dir / "report.json"
    if not report_path.exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})

    tickets = json.loads(report_path.read_text())
    by_uid = {t.get("ticket_uid"): t for t in tickets}
    a, b = by_uid.get(req.uid_a), by_uid.get(req.uid_b)
    if a is None or b is None:
        return JSONResponse(status_code=404, content={"error": "Ticket not found"})

    _record_reid("not_same", req.task_id, {
        _reid_label(req.task_id, a): a.get("evidence_meta", []),
        _reid_label(req.task_id, b): b.get("evidence_meta", []),
    })
    a.setdefault("not_same_as", []).append(req.uid_b)
    b.setdefault("not_same_as", []).append(req.uid_a)

    sensitivity = 4
    try:
        sensitivity = json.loads((out_dir / "forensic_config.json").read_text()).get("flag_sensitivity", 4)
    except Exception:
        pass
    annotate_tickets(tickets, _levenshtein, sensitivity)

    report_path.write_text(json.dumps(tickets, indent=2))
    if req.task_id in forensic_tasks:
        forensic_tasks[req.task_id]["tickets"] = tickets
    return {"tickets": tickets}


class TicketSplitRequest(BaseModel):
    task_id: str
    ticket_uid: str
    frames: list[str]   # evidence file names to move to the new ticket


@router.post("/tickets/split")
@_serialized
async def split_forensic_ticket(req: TicketSplitRequest):
    """Operator 'Split': move the chosen evidence frames of one ticket into a new ticket."""
    from engine.pipeline import EVIDENCE_DIR
    from engine.ticket_merge import split_ticket
    from engine.ticket_flags import annotate_tickets
    from store import split_violation_rows

    out_dir = EVIDENCE_DIR / "forensic" / req.task_id / "output"
    report_path = out_dir / "report.json"
    if not report_path.exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})

    tickets = json.loads(report_path.read_text())
    idx = next((i for i, t in enumerate(tickets) if t.get("ticket_uid") == req.ticket_uid), None)
    if idx is None:
        return JSONResponse(status_code=404, content={"error": "Ticket not found"})

    try:
        remaining, new = split_ticket(tickets[idx], req.frames)
    except ValueError as e:
        return JSONResponse(status_code=400, content={"error": str(e)})

    new["db_ids"] = await split_violation_rows(
        remaining.get("db_ids", []), photo_names(remaining), photo_names(new), req.task_id)
    tickets[idx] = remaining
    tickets.insert(idx + 1, new)

    sensitivity = 4
    try:
        sensitivity = json.loads((out_dir / "forensic_config.json").read_text()).get("flag_sensitivity", 4)
    except Exception:
        pass
    annotate_tickets(tickets, _levenshtein, sensitivity)
    _record_reid("split", req.task_id, {
        _reid_label(req.task_id, remaining): remaining.get("evidence_meta", []),
        _reid_label(req.task_id, new): new.get("evidence_meta", []),
    })

    report_path.write_text(json.dumps(tickets, indent=2))
    if req.task_id in forensic_tasks:
        forensic_tasks[req.task_id]["tickets"] = tickets
    return {"tickets": tickets}


class TicketPlateRequest(BaseModel):
    task_id: str
    ticket_uid: str
    plate_text: str = ""     # empty = "no readable plate"
    revert: bool = False     # go back to what the OCR read


class TicketNoPlateRequest(BaseModel):
    task_id: str
    ticket_uid: str
    on: bool = True          # False takes the verdict back


async def _drop_no_plate_verdict(ticket: dict) -> None:
    """The enforcer's "no plate" verdict does not stand once the ticket has a plate number: its violation and Inbox row go.
    The ticket is changed in place."""
    from store import delete_violations, get_violation

    ticket["violations"] = [v for v in ticket.get("violations", []) if v != "no_plate"]
    gone, keep = [], []
    for rid in ticket.get("db_ids", []):
        row = await get_violation(rid)
        (gone if row and row.get("cls") == "no_plate" else keep).append(rid)
    if gone:
        await delete_violations(gone)
    ticket["db_ids"] = keep
    ticket.pop("no_plate_by_verdict", None)


@router.post("/tickets/no-plate")
@_serialized
async def set_ticket_no_plate(req: TicketNoPlateRequest):
    """The enforcer's verdict "the vehicle has no plate number": adds the no_plate violation (and its Inbox row) to a ticket whose plate
    is NOT read. Only a ticket without a plate number can carry it: a plate that was read or typed rules the verdict out. `on` = False
    takes the verdict back (the violation the detector found by itself, when no_plate is switched on, is not touched)."""
    from engine.ticket_flags import annotate_tickets

    opened = _open_report(req.task_id, req.ticket_uid)
    if isinstance(opened, JSONResponse):
        return opened
    out_dir, report_path, tickets, idx = opened
    t = tickets[idx]
    if req.on:
        if t.get("plate_text", "unidentified") not in _UNREAD:
            return JSONResponse(status_code=400, content={"error": "This ticket has a plate number, so it cannot be marked as having none"})
        if "no_plate" not in t.get("violations", []):
            t["violations"] = list(t.get("violations", [])) + ["no_plate"]
            new_ids = await _save_rows(req.task_id, t, ["no_plate"], "no_plate_found", "unidentified", add_violation,
                                       source=t.get("source", "forensic"))
            t["db_ids"] = list(t.get("db_ids", [])) + new_ids
            t["no_plate_by_verdict"] = True
        t["plate_status"] = "no_plate"
    else:
        if not t.get("no_plate_by_verdict"):
            return JSONResponse(status_code=400, content={"error": "The no-plate violation of this ticket was found by the detector, not set by a reviewer"})
        await _drop_no_plate_verdict(t)
        t["plate_status"] = "pending" if t.get("source") == "live" else "not_read"
    annotate_tickets(tickets, _levenshtein, _run_config(out_dir).get("flag_sensitivity", 4))
    _save_edited(req.task_id, out_dir, report_path, tickets)
    return {"tickets": tickets}


@router.post("/tickets/set-plate")
@_serialized
async def set_ticket_plate(req: TicketPlateRequest):
    """Operator plate edit: the ticket (report.json and its violation rows) carries the plate the
    reviewer typed instead of the OCR's read; `revert` restores the OCR's read. The owner id of
    the rows follows the plate the same way it does when an analysis ends."""
    from engine.pipeline import EVIDENCE_DIR
    from engine.ticket_merge import apply_plate_edit, normalize_plate
    from engine.ticket_flags import annotate_tickets
    from store import update_violation_plate

    if len(normalize_plate(req.plate_text)) > 12:
        return JSONResponse(status_code=400, content={"error": "A plate has at most 12 letters and digits"})

    out_dir = EVIDENCE_DIR / "forensic" / req.task_id / "output"
    report_path = out_dir / "report.json"
    if not report_path.exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})

    tickets = json.loads(report_path.read_text())
    idx = next((i for i, t in enumerate(tickets) if t.get("ticket_uid") == req.ticket_uid), None)
    if idx is None:
        return JSONResponse(status_code=404, content={"error": "Ticket not found"})

    plate_format = (tickets[idx].get("metadata") or {}).get("plate_format", "ph_standard")
    edited = apply_plate_edit(tickets[idx], req.plate_text, revert=req.revert, plate_format=plate_format)
    tickets[idx] = edited

    plate = edited.get("plate_text", "unidentified")
    if plate in ("unidentified", "no_plate_found", ""):
        user_id = "no_plate_found"
    else:
        user = await get_user_by_plate(plate)
        user_id = user["id"] if user else "unregistered"
    await update_violation_plate(edited.get("db_ids", []), plate, user_id)
    if plate not in ("unidentified", "no_plate_found", "") and edited.get("no_plate_by_verdict"):
        await _drop_no_plate_verdict(edited)                  # it has a plate number now: the "no plate" verdict is void

    sensitivity = 4
    try:
        sensitivity = json.loads((out_dir / "forensic_config.json").read_text()).get("flag_sensitivity", 4)
    except Exception:
        pass
    annotate_tickets(tickets, _levenshtein, sensitivity)

    report_path.write_text(json.dumps(tickets, indent=2))
    if req.task_id in forensic_tasks:
        forensic_tasks[req.task_id]["tickets"] = tickets
    return {"tickets": tickets}


# ─── review tools: take photos out of a ticket, read its plate again, read a plate drawn by hand ───

class TicketFramesRequest(BaseModel):
    task_id: str
    ticket_uid: str
    frames: list[str] = []     # remove-frames: the photos to take out. reread-plate: the photos to read (empty = all)


class PlateBoxRequest(BaseModel):
    task_id: str = ""          # the analysis, to read the plate with the same OCR settings it used
    image: str                 # file name (under snapshots/evidence) of the picture the box was drawn on
    box: list[float]           # [x0, y0, x1, y1] as fractions (0..1) of that picture


def _open_report(task_id: str, ticket_uid: str):
    """(out_dir, report_path, tickets, index) of one ticket of an analysis, or a JSONResponse error."""
    from engine.pipeline import EVIDENCE_DIR

    out_dir = EVIDENCE_DIR / "forensic" / task_id / "output"
    report_path = out_dir / "report.json"
    if not report_path.exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})
    tickets = json.loads(report_path.read_text())
    idx = next((i for i, t in enumerate(tickets) if t.get("ticket_uid") == ticket_uid), None)
    if idx is None:
        return JSONResponse(status_code=404, content={"error": "Ticket not found"})
    return out_dir, report_path, tickets, idx


def _run_config(out_dir) -> dict:
    try:
        return json.loads((out_dir / "forensic_config.json").read_text())
    except Exception:
        return {}


def _save_edited(task_id: str, out_dir, report_path, tickets: list) -> None:
    """Flag duplicates again, write the report, and refresh the copy the status endpoint serves."""
    from engine.ticket_flags import annotate_tickets

    annotate_tickets(tickets, _levenshtein, _run_config(out_dir).get("flag_sensitivity", 4))
    report_path.write_text(json.dumps(tickets, indent=2))
    if task_id in forensic_tasks:
        forensic_tasks[task_id]["tickets"] = tickets


async def _sync_plate(old: dict, new: dict) -> None:
    """When an edit changed the ticket's plate, every violation row follows it (and the owner that goes with it)."""
    from store import update_violation_plate

    plate = new.get("plate_text", "unidentified")
    if plate == old.get("plate_text", "unidentified"):
        return
    if plate in ("unidentified", "no_plate_found", ""):
        user_id = "no_plate_found"
    else:
        user = await get_user_by_plate(plate)
        user_id = user["id"] if user else "unregistered"
    await update_violation_plate(new.get("db_ids", []), plate, user_id)
    if plate not in ("unidentified", "no_plate_found", "") and new.get("no_plate_by_verdict"):
        await _drop_no_plate_verdict(new)                     # it has a plate number now: the "no plate" verdict is void


def _reread_with_models(ticket: dict, frames: list[str], config: dict, plate_format: str, written: list | None = None):
    """Reads the plate of a ticket from its evidence photos with the real plate model, OCR and GAN (slow: call it in a thread). Every
    crop is read as seen and enhanced. `written` (optional) collects the files made, for a clean-up.
    The work is done by the plate PROCESS (engine/plate_service.py), not by this one: the live feed never shares its interpreter, CPU
    threads or GPU with it. Raises ValueError when there is nothing to read, PlateServiceError when the plate process failed."""
    from engine.plate_service import SERVICE
    return SERVICE.reread(ticket, frames, config, plate_format, written)


@router.post("/tickets/remove-frames")
@_serialized
async def remove_ticket_frames(req: TicketFramesRequest):
    """Operator 'Remove photos': the chosen photos leave the ticket (and the notice that is sent for it); the plate
    is voted again from the photos that are left."""
    from engine.ticket_merge import remove_frames
    from store import set_violation_evidence

    opened = _open_report(req.task_id, req.ticket_uid)
    if isinstance(opened, JSONResponse):
        return opened
    out_dir, report_path, tickets, idx = opened
    try:
        new = remove_frames(tickets[idx], req.frames)
    except ValueError as e:
        return JSONResponse(status_code=400, content={"error": str(e)})

    await set_violation_evidence(new.get("db_ids", []), photo_names(new))
    await _sync_plate(tickets[idx], new)
    tickets[idx] = new
    _save_edited(req.task_id, out_dir, report_path, tickets)
    return {"tickets": tickets}


@router.post("/tickets/reread-plate")
@_serialized
async def reread_ticket_plate(req: TicketFramesRequest):
    """Operator 'Read the plate again': look for the plate once more in the chosen photos (all by default) and vote
    again. A plate the reviewer typed is kept; the new read is then only returned as `suggested`."""
    opened = _open_report(req.task_id, req.ticket_uid)
    if isinstance(opened, JSONResponse):
        return opened
    out_dir, report_path, tickets, idx = opened
    old = tickets[idx]
    config = _run_config(out_dir)
    plate_format = config.get("plate_format") or (old.get("metadata") or {}).get("plate_format", "ph_standard")
    try:
        new, summary = await asyncio.to_thread(_reread_with_models, old, req.frames, config, plate_format)
    except ValueError as e:
        return JSONResponse(status_code=400, content={"error": str(e)})

    await _sync_plate(old, new)
    tickets[idx] = new
    _save_edited(req.task_id, out_dir, report_path, tickets)
    return {"tickets": tickets, "reread": summary}


@router.post("/tickets/read-plate-box")
async def read_plate_box(req: PlateBoxRequest):
    """Operator 'Draw the plate': read the text inside a box drawn on a photo. Changes no ticket; the reviewer then
    saves the number (or types another) with the plate edit."""
    from engine.pipeline import EVIDENCE_DIR, _extract_plate_text
    from engine.plate_reread import UNREAD, crop_box
    from yolo_inference import YoloInference

    image = cv2.imread(str(EVIDENCE_DIR / Path(req.image).name))
    if image is None:
        return JSONResponse(status_code=404, content={"error": "That photo is no longer on disk"})
    try:
        crop = crop_box(image, req.box)
    except ValueError as e:
        return JSONResponse(status_code=400, content={"error": str(e)})

    config = _run_config(EVIDENCE_DIR / "forensic" / req.task_id / "output") if req.task_id else {}
    plate_format = config.get("plate_format", "ph_standard")
    raw, cleaned, _, _, confidence = await asyncio.to_thread(
        _extract_plate_text, crop, plate_format, config.get("ocr_engine", "easyocr"), config.get("enhancement", "lanczos"))
    crop_file = Path(YoloInference.save_snapshot(crop, EVIDENCE_DIR)).name
    return {"text": "" if cleaned in UNREAD else cleaned, "raw": raw, "confidence": confidence, "crop": crop_file}


# ─── Holding: photos set aside from a ticket (the tracker followed another car for a while) ────────────────────
# The operator ticks the photos that show a different car and sets them aside. They wait in the run's holding.json
# until the operator decides: make a new ticket of them, add them to another ticket, put them back, or throw them away.

class SetAsideRequest(BaseModel):
    task_id: str
    ticket_uid: str
    frames: list[str]        # evidence file names to take out of the ticket


class HoldingActionRequest(BaseModel):
    task_id: str
    batch_id: str
    keep_uid: str = ""       # add-to-ticket: the ticket that receives the photos


_BATCH_ONLY = ("batch_id", "from_uid", "from_track", "created_at")


def _holding_path(out_dir: Path) -> Path:
    return out_dir / "holding.json"


def _load_holding(out_dir: Path) -> list:
    try:
        return json.loads(_holding_path(out_dir).read_text())
    except (OSError, ValueError):
        return []


def _save_holding(out_dir: Path, batches: list) -> None:
    _holding_path(out_dir).write_text(json.dumps(batches, indent=2))


def _batch_as_ticket(batch: dict) -> dict:
    """A batch is the 'new' half of a split: the same shape as a ticket, without the bookkeeping of a batch."""
    return {k: v for k, v in batch.items() if k not in _BATCH_ONLY}


def _open_holding(task_id: str, batch_id: str):
    """(out_dir, report_path, tickets, batches, batch) or a JSONResponse error."""
    from engine.pipeline import EVIDENCE_DIR

    out_dir = EVIDENCE_DIR / "forensic" / task_id / "output"
    report_path = out_dir / "report.json"
    if not report_path.exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})
    batches = _load_holding(out_dir)
    batch = next((b for b in batches if b.get("batch_id") == batch_id), None)
    if batch is None:
        return JSONResponse(status_code=404, content={"error": "Those photos are no longer in Holding"})
    return out_dir, report_path, json.loads(report_path.read_text()), batches, batch


@router.post("/tickets/set-aside")
@_serialized
async def set_photos_aside(req: SetAsideRequest):
    """Operator 'Set aside': the chosen photos leave the ticket and wait in Holding. The ticket keeps the rest and reads
    its plate again from them; nothing is decided about the photos yet."""
    from engine.ticket_merge import split_ticket
    from store import set_violation_evidence

    opened = _open_report(req.task_id, req.ticket_uid)
    if isinstance(opened, JSONResponse):
        return opened
    out_dir, report_path, tickets, idx = opened
    old = tickets[idx]
    try:
        remaining, aside = split_ticket(old, req.frames)
    except ValueError as e:
        return JSONResponse(status_code=400, content={"error": str(e)})

    await set_violation_evidence(remaining.get("db_ids", []), photo_names(remaining))
    await _sync_plate(old, remaining)
    batch = {
        **_batch_as_ticket(aside),
        "batch_id": uuid.uuid4().hex[:12],
        "from_uid": req.ticket_uid,
        "from_track": old.get("track_id"),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    batch.pop("db_ids", None)
    batch.pop("flags", None)
    tickets[idx] = remaining
    batches = _load_holding(out_dir) + [batch]
    _save_holding(out_dir, batches)
    _save_edited(req.task_id, out_dir, report_path, tickets)
    return {"tickets": tickets, "holding": batches}


@router.get("/holding/{task_id}")
@_serialized
async def get_holding(task_id: str):
    """The photos set aside in one analysis."""
    from engine.pipeline import EVIDENCE_DIR

    out_dir = EVIDENCE_DIR / "forensic" / task_id / "output"
    if not (out_dir / "report.json").exists():
        return JSONResponse(status_code=404, content={"error": "Report not found"})
    return {"holding": _load_holding(out_dir)}


@router.post("/holding/make-ticket")
@_serialized
async def holding_make_ticket(req: HoldingActionRequest):
    """Holding -> a ticket of its own: the photos are another car. Its plate is the one read from its own plate crops."""
    opened = _open_holding(req.task_id, req.batch_id)
    if isinstance(opened, JSONResponse):
        return opened
    out_dir, report_path, tickets, batches, batch = opened

    ticket = _batch_as_ticket(batch)
    ticket["ticket_uid"] = uuid.uuid4().hex[:12]
    plate = ticket.get("plate_text", "unidentified")
    owner = await get_user_by_plate(plate) if plate != "unidentified" else None
    save = _skip_db if _run_config(out_dir).get("benchmark") else add_violation
    source = next((t for t in tickets if t.get("ticket_uid") == batch.get("from_uid")), None)
    ticket["db_ids"] = await _save_rows(req.task_id, ticket, ticket.get("violations", []), _owner_id(plate, owner), plate, save,
                                        track_id=_first_track_id(source) if source is not None else -1)
    at = tickets.index(source) + 1 if source is not None else len(tickets)
    tickets.insert(at, ticket)
    if source is not None:
        _record_reid("split", req.task_id, {
            _reid_label(req.task_id, source): source.get("evidence_meta", []),
            _reid_label(req.task_id, ticket): ticket.get("evidence_meta", []),
        })
    batches = [b for b in batches if b.get("batch_id") != req.batch_id]
    _save_holding(out_dir, batches)
    _save_edited(req.task_id, out_dir, report_path, tickets)
    return {"tickets": tickets, "holding": batches, "ticket_uid": ticket["ticket_uid"]}


async def _fold_batch_into(req: HoldingActionRequest, keep_uid: str, *, learn: bool):
    """Holding -> the photos join ticket `keep_uid`. The ticket keeps its own violations; plate crops come along and the
    plate is voted again."""
    from engine.ticket_merge import merge_tickets
    from store import merge_violation_rows

    opened = _open_holding(req.task_id, req.batch_id)
    if isinstance(opened, JSONResponse):
        return opened
    out_dir, report_path, tickets, batches, batch = opened
    keep = next((t for t in tickets if t.get("ticket_uid") == keep_uid), None)
    if keep is None:
        return JSONResponse(status_code=404, content={"error": "That ticket no longer exists"})

    merged = merge_tickets(keep, _batch_as_ticket(batch))
    merged["violations"] = list(keep.get("violations", []))      # the photos are evidence for THIS ticket's violations
    merged["merged_track_ids"] = list(keep.get("merged_track_ids", [keep.get("track_id")]))
    merged["track_id"] = keep.get("track_id")
    if learn:
        _record_reid("merge", req.task_id,
                     {_reid_label(req.task_id, keep): keep.get("evidence_meta", []) + batch.get("evidence_meta", [])})
    if keep.get("db_ids"):
        merged["db_ids"] = await merge_violation_rows(
            keep["db_ids"], [], photo_names(merged), merged.get("plate_text", "unidentified"), _first_track_id(keep))
    tickets = [merged if t is keep else t for t in tickets]
    batches = [b for b in batches if b.get("batch_id") != req.batch_id]
    _save_holding(out_dir, batches)
    _save_edited(req.task_id, out_dir, report_path, tickets)
    return {"tickets": tickets, "holding": batches, "ticket_uid": keep_uid}


@router.post("/holding/add-to-ticket")
@_serialized
async def holding_add_to_ticket(req: HoldingActionRequest):
    """Holding -> another ticket: the photos show the same car as `keep_uid` (a plate found there names them)."""
    if not req.keep_uid:
        return JSONResponse(status_code=400, content={"error": "Say which ticket the photos join"})
    return await _fold_batch_into(req, req.keep_uid, learn=True)


@router.post("/holding/put-back")
@_serialized
async def holding_put_back(req: HoldingActionRequest):
    """Holding -> back where they came from (the set-aside was a mistake). Says so when that ticket is gone."""
    from engine.pipeline import EVIDENCE_DIR

    out_dir = EVIDENCE_DIR / "forensic" / req.task_id / "output"
    batch = next((b for b in _load_holding(out_dir) if b.get("batch_id") == req.batch_id), None)
    if batch is None:
        return JSONResponse(status_code=404, content={"error": "Those photos are no longer in Holding"})
    result = await _fold_batch_into(req, batch.get("from_uid", ""), learn=False)
    if isinstance(result, JSONResponse) and result.status_code == 404:
        return JSONResponse(status_code=409, content={
            "error": "The ticket these photos came from is gone. Add them to another ticket or make a new one."})
    return result


@router.post("/holding/throw-away")
@_serialized
async def holding_throw_away(req: HoldingActionRequest):
    """Holding -> gone: the photos are not evidence of anything. (The picture files stay on disk until the run is cleaned.)"""
    opened = _open_holding(req.task_id, req.batch_id)
    if isinstance(opened, JSONResponse):
        return opened
    out_dir, report_path, tickets, batches, _ = opened
    batches = [b for b in batches if b.get("batch_id") != req.batch_id]
    _save_holding(out_dir, batches)
    return {"tickets": tickets, "holding": batches}
