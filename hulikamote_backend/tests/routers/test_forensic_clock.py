"""
The time of a video in the Forensic Analyzer: rules with ban hours (truck ban) judge each frame by the time found in the video,
every ticket says when it happened and where that time came from, and a ticket that depends on the hour but has no known time
is flagged for a human check. Same tiny generated clip and fake pipeline as the stop tests; no OCR model is loaded.
"""
import json
from datetime import datetime

import pytest
from httpx import ASGITransport, AsyncClient

from engine import video_clock
from tests.routers.test_forensic_stop import FakePipeline, TASK, _report, env  # noqa: F401  (env is a fixture)
from tests.routers.test_forensic_trim import clip  # noqa: F401  (a generated clip, and the evidence folder)
from tests.routers.test_forensic import WIZARD, live  # noqa: F401  (a temp camera config and a client)

HOURS = [["06:00", "09:00"], ["16:00", "19:00"]]


@pytest.fixture
def no_clock_in_the_video(monkeypatch):
    """The generated clip has no clock in its picture, no creation tag and no name with a time (and no OCR model is loaded)."""
    monkeypatch.setattr(video_clock, "start_from_screen", lambda path, reader=None, today=None: None)
    monkeypatch.setattr(video_clock, "start_from_metadata", lambda path: None)


def truck_ticket(first_t=2.5, track_id=1):
    return {"track_id": track_id, "violations": ["truck_ban"], "plate_text": "unidentified", "plate_crops": [],
            "evidence_paths": [], "evidence_meta": [{"file": f"t{track_id}.jpg", "bbox": [0, 0, 10, 10], "t": first_t}]}


def truck_config(**extra):
    return {"active_violations": ["truck_ban"], "per_violation_configs": {"truck_ban": {"rois": [], "ban_windows": HOURS}}, **extra}


# ─── an analysis ─────────────────────────────────────────────────────────────────────────────────────────

def test_a_typed_start_time_is_on_the_run_and_every_ticket(env, no_clock_in_the_video):  # noqa: F811
    FakePipeline.tickets = [truck_ticket(first_t=2.5)]
    task = env.go(**truck_config(video_start="2026-11-05 07:30"))
    assert task["status"] == "completed"
    assert task["clock"]["source"] == "operator" and task["clock"]["confirmed"] and task["clock"]["start"] == "2026-11-05T07:30:00"
    ticket = _report(env)[0]
    assert ticket["time"]["at"] == "2026-11-05T07:30:02"                           # the start plus the first photo's second
    assert ticket["time"]["source"] == "operator" and ticket["time"]["confirmed"] is True
    assert "needs_check" not in ticket["time"]
    assert not any(f["type"] == "time_unconfirmed" for f in ticket["flags"])


def test_the_trimmed_start_is_added_so_the_time_is_that_of_the_first_analysed_frame(env, no_clock_in_the_video):  # noqa: F811
    FakePipeline.tickets = [truck_ticket(first_t=1.0)]
    task = env.go(**truck_config(video_start="2026-11-05 07:30", trim_start=1.0))
    assert task["clock"]["start"] == "2026-11-05T07:30:01"                         # the video's start + the 1 s that was skipped
    assert _report(env)[0]["time"]["at"] == "2026-11-05T07:30:02"


def test_the_pipeline_gets_the_clock_the_rules_read(env, no_clock_in_the_video, monkeypatch):  # noqa: F811
    seen = []

    class Watching(FakePipeline):
        def process_frame(self, frame, idx, timestamp=None):
            if not seen:
                seen.append(self.clock.at(timestamp))
            return frame, []

    monkeypatch.setattr(env.forensic, "DecoupledPipeline", Watching)
    env.go(**truck_config(video_start="2026-11-05 07:30"))
    assert seen == [datetime(2026, 11, 5, 7, 30, 0, 100000)]


def test_when_no_time_is_found_a_ticket_of_an_hour_rule_asks_for_a_human_check(env, no_clock_in_the_video):  # noqa: F811
    FakePipeline.tickets = [truck_ticket()]
    task = env.go(**truck_config())
    assert task["clock"]["start"] is None and not task["clock"]["confirmed"] and task["clock"]["source"] in ("estimate", "none")
    ticket = _report(env)[0]
    assert ticket["time"]["at"] is None and ticket["time"]["needs_check"] is True and ticket["time"]["confirmed"] is False
    flag = next(f for f in ticket["flags"] if f["type"] == "time_unconfirmed")
    assert "No time was found" in flag["detail"] and "check the time" in flag["detail"]


def test_a_ticket_of_a_rule_without_hours_is_not_flagged_for_the_time(env, no_clock_in_the_video):  # noqa: F811
    FakePipeline.tickets = [{**truck_ticket(), "violations": ["counterflow"]}]
    env.go(**truck_config(video_start="", per_violation_configs={"truck_ban": {"rois": [], "ban_windows": HOURS}, "counterflow": {"rois": []}}))
    ticket = _report(env)[0]
    assert "time" not in ticket or not ticket["time"].get("needs_check")
    assert not any(f["type"] == "time_unconfirmed" for f in ticket["flags"])


def test_a_run_that_does_not_need_the_time_never_looks_for_it(env, monkeypatch):  # noqa: F811
    def forbidden(*a, **k):
        raise AssertionError("the time of the video must not be searched")

    monkeypatch.setattr(video_clock, "resolve_clock", forbidden)
    FakePipeline.tickets = [{**truck_ticket(), "violations": ["counterflow"]}]
    task = env.go(active_violations=["counterflow"], per_violation_configs={"counterflow": {"rois": []}})
    assert task["status"] == "completed" and "clock" not in task
    assert "time" not in _report(env)[0]


def test_a_typed_time_on_a_run_with_no_hours_still_stamps_the_tickets(env, no_clock_in_the_video):  # noqa: F811
    FakePipeline.tickets = [{**truck_ticket(first_t=4.0), "violations": ["counterflow"]}]
    env.go(active_violations=["counterflow"], per_violation_configs={"counterflow": {"rois": []}}, video_start="2026-11-05 18:00")
    assert _report(env)[0]["time"]["at"] == "2026-11-05T18:00:04"


# ─── the dashboard asks before starting ─────────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_the_time_of_a_video_can_be_asked_before_the_run_and_a_typed_time_wins(ac, clip, no_clock_in_the_video):  # noqa: F811
    path, _ = clip
    found = (await ac.get("/api/forensic/video-clock", params={"file_path": str(path)})).json()
    assert found["start"] is None and found["confirmed"] is False and found["daylight"] in ("day", "twilight", "night")
    typed = (await ac.get("/api/forensic/video-clock", params={"file_path": str(path), "video_start": "2026-11-05 07:40"})).json()
    assert typed["start"] == "2026-11-05T07:40:00" and typed["source"] == "operator" and typed["confirmed"] is True
    shifted = (await ac.get("/api/forensic/video-clock", params={"file_path": str(path), "video_start": "2026-11-05 07:40",
                                                                 "trim_start": 30})).json()
    assert shifted["start"] == "2026-11-05T07:40:30"


@pytest.mark.anyio
async def test_only_existing_video_files_are_asked_about_their_time(ac, clip, tmp_path):  # noqa: F811
    notes = tmp_path / "notes.txt"
    notes.write_text("hi")
    assert (await ac.get("/api/forensic/video-clock", params={"file_path": str(tmp_path / "gone.mp4")})).status_code == 404
    assert (await ac.get("/api/forensic/video-clock", params={"file_path": str(notes)})).status_code == 400


@pytest.mark.anyio
async def test_a_phone_on_the_wifi_cannot_ask_about_files_by_path(clip):  # noqa: F811
    from main import app
    async with AsyncClient(transport=ASGITransport(app=app, client=("192.168.68.50", 5555)), base_url="http://test") as phone:
        response = await phone.get("/api/forensic/video-clock", params={"file_path": str(clip[0])})
    assert response.status_code == 403


# ─── the Live Monitor ───────────────────────────────────────────────────────────────────────────────────

def test_a_typed_start_time_pretends_the_clock_of_the_live_monitor(live):  # noqa: F811
    client, cfg, calls, gen, stream = live
    assert client.post("/api/forensic/live-config", json={**WIZARD, "video_start": "7:30"}).status_code == 200
    assert json.loads(cfg.read_text())["clock_start"] == "7:30"


def test_without_a_typed_time_the_live_monitor_uses_the_real_clock(live):  # noqa: F811
    client, cfg, calls, gen, stream = live
    assert client.post("/api/forensic/live-config", json=WIZARD).status_code == 200
    assert "clock_start" not in json.loads(cfg.read_text())


def test_the_ban_hours_reach_the_live_monitors_config(live):  # noqa: F811
    client, cfg, calls, gen, stream = live
    wizard = {"active_violations": ["truck_ban"], "per_violation_configs": {
        "truck_ban": {"rois": [{"polygon": [[0, 0], [1920, 0], [1920, 1080], [0, 1080]]}], "ban_windows": HOURS}}}
    assert client.post("/api/forensic/live-config", json=wizard).status_code == 200
    saved = json.loads(cfg.read_text())
    assert saved["regions_of_interest"]["truck_ban_zones"][0]["ban_windows"] == HOURS
    assert saved["per_violation_configs"]["truck_ban"]["ban_windows"] == HOURS
