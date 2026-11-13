"""
routers/forensic.py - "Stop here" and "Cancel" for a running analysis (POST /api/forensic/stop/{task_id}).
The video is a tiny generated clip, the pipeline and the plate reader are fakes, ffmpeg is a file copy,
and the run folder and the evidence folder are temp dirs: nothing real is touched.
"""
import asyncio
import json
import shutil
import subprocess
import time
from types import SimpleNamespace

import cv2
import numpy as np
import pytest

TASK = "11111111-1111-1111-1111-111111111111"
FRAMES = 30
FPS = 10.0


class FakeLedgerManager:
    def __init__(self, tickets, ledgers):
        self.pending_tickets = tickets
        self.ledgers = ledgers

    def finalize_all(self):
        pass

    def drain_tickets(self):
        tickets, self.pending_tickets = self.pending_tickets, []
        return tickets


class FakePipeline:
    """Stands in for DecoupledPipeline: lets a test press a dashboard button at a chosen frame."""
    on_frame = None      # callable(frame_idx)
    tickets: list = []
    ledgers: dict = {}

    def __init__(self, config_path):
        self.flow_mode = "zones"
        self.learns_flow = False
        self.ledger_manager = FakeLedgerManager(list(type(self).tickets), dict(type(self).ledgers))

    def process_frame(self, frame, idx, timestamp=None):
        if type(self).on_frame:
            type(self).on_frame(idx)
        return frame, []

    def annotate_frame_fast(self, frame, detections, boxes=True):
        return frame

    def box_specs(self, detections):
        return []


def _fake_ffmpeg(cmd, **_kwargs):
    shutil.copy(cmd[cmd.index("-i") + 1], cmd[-1])
    return subprocess.CompletedProcess(cmd, 0, "", "")


def _ticket(track_id, crops=3):
    crop = np.zeros((10, 30, 3), np.uint8)
    return {"track_id": track_id, "violations": ["counterflow"], "plate_text": "unidentified",
            "plate_crops": [(crop, None, float(i)) for i in range(crops)],
            "evidence_paths": [], "evidence_meta": []}


@pytest.fixture
def env(tmp_path, monkeypatch):
    import engine.pipeline as pipeline_module
    from routers import forensic

    monkeypatch.setattr(pipeline_module, "EVIDENCE_DIR", tmp_path)
    monkeypatch.setattr(forensic, "get_inference", lambda *a, **k: None)
    monkeypatch.setattr(forensic, "DecoupledPipeline", FakePipeline)

    async def no_owner(plate):
        return None

    monkeypatch.setattr(forensic, "get_user_by_plate", no_owner)
    monkeypatch.setattr(subprocess, "run", _fake_ffmpeg)

    reads = []        # one entry per plate the fake reader was asked to read
    hook = {"on_read": None, "same_plate": False}

    def fake_read(crop, plate_format, engine, enhancement):
        reads.append(1)
        if hook["on_read"]:
            hook["on_read"](len(reads))
        img = np.zeros((8, 20, 3), np.uint8)
        # three crops per ticket: the first ticket reads ABC1234, the second one XYZ9876 (unless a test wants the same car twice)
        plate = "ABC1234" if hook["same_plate"] or (len(reads) - 1) // 3 == 0 else "XYZ9876"
        return "RAW", plate, img, img, 0.9

    monkeypatch.setattr(pipeline_module, "_extract_plate_text", fake_read)

    FakePipeline.on_frame = None
    FakePipeline.tickets = []
    FakePipeline.ledgers = {}

    run_dir = tmp_path / "forensic" / TASK
    (run_dir / "output").mkdir(parents=True)
    video = run_dir / "input_video.mp4"
    writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*"mp4v"), FPS, (64, 48))
    assert writer.isOpened()
    for i in range(FRAMES):
        writer.write(np.full((48, 64, 3), i * 5, np.uint8))
    writer.release()

    forensic.forensic_tasks[TASK] = {"status": "processing", "progress": 0.0, "result_video": None, "tickets": []}

    def press(mode):
        forensic.forensic_tasks[TASK]["stop"] = mode

    def go_with(**overrides):
        config = {"active_violations": [], "benchmark": True, "tracker": "deepsort",
                  "plate_format": "ph_standard", "per_violation_configs": {}, **overrides}
        forensic.forensic_processing_task(TASK, video, run_dir / "output", config)
        return forensic.forensic_tasks[TASK]

    yield SimpleNamespace(go=go_with, go_with=go_with, press=press, reads=reads, hook=hook, run_dir=run_dir,
                          root=tmp_path, forensic=forensic)
    forensic.forensic_tasks.pop(TASK, None)


def _report(env):
    return json.loads((env.run_dir / "output" / "report.json").read_text())


def _wait_for(condition, seconds=10.0):
    """The release worker runs beside the video loop: wait (briefly) for what a test expects it to have done."""
    deadline = time.time() + seconds
    while not condition() and time.time() < deadline:
        time.sleep(0.01)
    return condition()


def test_a_run_nobody_stops_reads_every_plate_and_is_not_marked_early(env):
    FakePipeline.tickets = [_ticket(1), _ticket(2)]
    task = env.go()
    assert task["status"] == "completed" and task["progress"] == 100.0
    assert len(env.reads) == 6
    assert [t["plate_text"] for t in _report(env)] == ["ABC1234", "XYZ9876"]
    assert not (env.run_dir / "output" / "stopped_early.json").exists()
    assert "stopped_early" not in task


def test_stop_here_during_the_video_keeps_what_was_found_and_still_reads_the_plates(env):
    FakePipeline.tickets = [_ticket(1), _ticket(2)]
    FakePipeline.on_frame = lambda idx: env.press("finish") if idx == 10 else None
    task = env.go()
    assert task["status"] == "completed"
    assert task["stopped_early"]["frames"] == 10                 # frame 10 was finished, 11 never started
    assert task["stopped_early"]["at_seconds"] == 1.0
    assert json.loads((env.run_dir / "output" / "stopped_early.json").read_text())["frames"] == 10
    assert (env.run_dir / "output" / "evidence_replay.mp4").exists()
    assert (env.run_dir / "output" / "report.json").exists()
    assert len(env.reads) == 6                                    # the flag was cleared: plates are still read
    assert not task.get("stop")


def test_stop_here_during_the_plate_reading_skips_the_plates_not_read_yet(env):
    FakePipeline.tickets = [_ticket(1), _ticket(2)]

    def second_press(n):
        if n == 2:        # the video part must be over: a first Stop here only ends the video, a second one skips plates
            assert _wait_for(lambda: env.forensic.forensic_tasks[TASK].get("video_done"))
            env.press("finish")

    env.hook["on_read"] = second_press
    task = env.go()
    assert task["status"] == "completed"
    assert len(env.reads) == 2                                    # the 3rd crop and the whole 2nd ticket were skipped
    assert task["stopped_early"]["plates_read"] == 2 and task["stopped_early"]["of_plates"] == 6
    tickets = _report(env)
    assert len(tickets) == 2
    assert tickets[0]["plate_text"] == "ABC1234"                  # what was read is kept
    assert tickets[1]["plate_text"] == "unidentified"             # the rest is left unread
    assert (env.run_dir / "output" / "stopped_early.json").exists()


def test_a_first_stop_here_while_plates_are_being_read_only_ends_the_video(env):
    """The plates are read while the video runs now, so one Stop here must not skip them."""
    FakePipeline.tickets = [_ticket(1), _ticket(2)]
    FakePipeline.on_frame = lambda idx: time.sleep(0.01)          # the video outlasts the first plate read
    env.hook["on_read"] = lambda n: env.press("finish") if n == 1 else None
    task = env.go()
    assert task["status"] == "completed"
    assert len(env.reads) == 6                                    # every plate was still read
    assert "plates_read" not in task.get("stopped_early", {})


def test_tickets_can_be_opened_while_the_video_is_still_running(env):
    FakePipeline.tickets = [_ticket(1), _ticket(2)]
    seen = {}

    def look(idx):
        if idx == FRAMES:         # the last frame: the earlier frames let the worker release both tickets
            seen["released"] = _wait_for(lambda: env.forensic.forensic_tasks[TASK].get("ticket_count") == 2)
            seen["status"] = env.forensic.forensic_tasks[TASK]["status"]
            seen["video_done"] = env.forensic.forensic_tasks[TASK]["video_done"]
            seen["report"] = _report(env)

    FakePipeline.on_frame = look
    env.go()
    assert seen["released"] and seen["status"] == "processing" and seen["video_done"] is False
    assert [t["plate_text"] for t in seen["report"]] == ["ABC1234", "XYZ9876"]   # complete tickets, plates included
    assert all(t.get("ticket_uid") and t.get("plate_crop_paths") for t in seen["report"])


def test_the_status_leaves_the_ticket_list_out_while_running_unless_asked(env):
    forensic = env.forensic
    forensic.forensic_tasks[TASK]["tickets"] = [{"ticket_uid": "u1"}]
    forensic.forensic_tasks[TASK]["ticket_count"] = 1
    light = asyncio.run(forensic.get_forensic_status(TASK))
    assert "tickets" not in light and light["ticket_count"] == 1 and light["status"] == "processing"
    full = asyncio.run(forensic.get_forensic_status(TASK, include="tickets"))
    assert full["tickets"] == [{"ticket_uid": "u1"}]
    forensic.forensic_tasks[TASK]["status"] = "completed"
    assert asyncio.run(forensic.get_forensic_status(TASK))["tickets"] == [{"ticket_uid": "u1"}]


def test_two_tickets_of_one_plate_become_one_when_nobody_decided_the_first(env):
    FakePipeline.tickets = [_ticket(1), _ticket(2)]
    env.hook["same_plate"] = True
    task = env.go()
    assert task["status"] == "completed"
    tickets = _report(env)
    assert len(tickets) == 1 and tickets[0]["track_id"] == "1 & 2" and tickets[0]["plate_text"] == "ABC1234"


def test_a_cancel_also_takes_back_the_tickets_already_released(env, monkeypatch):
    rows, deleted = [], []

    async def fake_add(**kwargs):
        row = {"id": f"row{len(rows) + 1}", **kwargs}
        rows.append(row)
        return row

    async def fake_delete(ids):
        deleted.extend(ids)
        return len(ids)

    monkeypatch.setattr(env.forensic, "add_violation", fake_add)
    monkeypatch.setattr(env.forensic, "delete_violations", fake_delete)
    FakePipeline.tickets = [_ticket(1), _ticket(2)]

    def cancel_after_first_ticket(n):
        if n == 4:        # the first ticket (3 crops) is published before the 4th crop is read
            env.press("cancel")

    env.hook["on_read"] = cancel_after_first_ticket
    task = env.go_with(benchmark=False)
    assert task["status"] == "cancelled" and not env.run_dir.exists()
    assert len(rows) >= 1 and sorted(deleted) == sorted(r["id"] for r in rows)    # every Inbox row of the run is gone
    assert all(r["dedupe"] is False for r in rows)


def test_a_cancel_also_removes_rows_the_operator_made_meanwhile(env, monkeypatch):
    """A new ticket made from Holding is saved straight into the report: the cancel finds its rows there."""
    rows, deleted = [], []

    async def fake_add(**kwargs):
        row = {"id": f"row{len(rows) + 1}", **kwargs}
        rows.append(row)
        return row

    async def fake_delete(ids):
        deleted.extend(ids)
        return len(ids)

    monkeypatch.setattr(env.forensic, "add_violation", fake_add)
    monkeypatch.setattr(env.forensic, "delete_violations", fake_delete)
    FakePipeline.tickets = [_ticket(1), _ticket(2)]

    def operator_then_cancel(n):
        if n == 4:        # ticket 1 is released; the operator has made a ticket of their own; then Cancel
            report = env.run_dir / "output" / "report.json"
            tickets = json.loads(report.read_text())
            tickets.append({"ticket_uid": "opmade", "track_id": 9, "violations": ["counterflow"], "db_ids": ["by-operator"]})
            report.write_text(json.dumps(tickets))
            env.press("cancel")

    env.hook["on_read"] = operator_then_cancel
    task = env.go_with(benchmark=False)
    assert task["status"] == "cancelled"
    assert "by-operator" in deleted and {r["id"] for r in rows} <= set(deleted)


def test_stop_here_before_a_single_frame_was_read_is_a_cancel(env):
    env.press("finish")                       # pressed while the run was still starting up
    task = env.go()
    assert task["status"] == "cancelled"      # an empty video cannot be encoded, and there is nothing to keep
    assert not env.run_dir.exists()


def test_cancel_during_the_video_throws_everything_away(env):
    photo, car = env.root / "ev1.jpg", env.root / "ev1_car.jpg"
    for f in (photo, car):
        f.write_bytes(b"x")
    ledger = SimpleNamespace(evidence_paths=[str(photo)], evidence_meta=[{"file": "ev1.jpg", "car_crop": "ev1_car.jpg"}])
    FakePipeline.ledgers = {1: ledger}
    FakePipeline.on_frame = lambda idx: env.press("cancel") if idx == 5 else None
    task = env.go()
    assert task["status"] == "cancelled"
    assert not env.run_dir.exists()                               # uploaded copy, partial videos, settings: all gone
    assert not photo.exists() and not car.exists()                # the evidence photos this run took


def test_cancel_during_the_plate_reading_removes_the_pictures_saved_so_far(env):
    FakePipeline.tickets = [_ticket(1), _ticket(2)]
    env.hook["on_read"] = lambda n: env.press("cancel") if n == 3 else None
    task = env.go()
    assert task["status"] == "cancelled"
    assert not env.run_dir.exists()
    assert list(env.root.glob("*.jpg")) == []                     # the plate crops written before the cancel were deleted


def test_a_cancel_cannot_be_softened_by_a_later_stop_here(env):
    env.forensic.forensic_tasks[TASK]["status"] = "processing"
    first = asyncio.run(env.forensic.stop_forensic(TASK, "cancel"))
    second = asyncio.run(env.forensic.stop_forensic(TASK, "finish"))
    assert first["stop"] == "cancel" and second["stop"] == "cancel"


def test_the_stop_endpoint_says_no_to_bad_requests(env):
    stop = lambda task, mode="finish": asyncio.run(env.forensic.stop_forensic(task, mode))
    assert stop("no-such-task").status_code == 404
    assert stop(TASK, "explode").status_code == 400
    env.forensic.forensic_tasks[TASK]["status"] = "completed"
    assert stop(TASK).status_code == 409                          # nothing to stop any more
    env.forensic.forensic_tasks[TASK]["status"] = "processing"
    assert stop(TASK)["stop"] == "finish"
    assert env.forensic.forensic_tasks[TASK]["stop"] == "finish"
