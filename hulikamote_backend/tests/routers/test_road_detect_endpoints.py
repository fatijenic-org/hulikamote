"""routers/settings.py - the Live Monitor's "Detect road": start, poll, fetch the frozen frame and each step's picture, apply or discard."""
import json

import pytest
from fastapi.testclient import TestClient

from engine.live_calibrator import LiveCalibrator
from main import app
from routers import settings as settings_router
from routers import stream
from tests.engine.test_live_calibrator import feed_seconds
from tests.engine.test_live_detect import walking_stub

client = TestClient(app)


@pytest.fixture
def road(tmp_path, monkeypatch):
    """A road learner that reads in the caller's thread, a temp config, and a pipeline reload that is only counted."""
    cal = LiveCalibrator(config_path=tmp_path / "camera_config.json", learn_seconds=2.0, min_pictures=8,
                         analyse=walking_stub(), background=False)
    cal.attach("cam")
    monkeypatch.setattr(stream, "road", cal)
    monkeypatch.setattr(settings_router, "CONFIG_PATH", tmp_path / "camera_config.json")
    reloads = []
    monkeypatch.setattr(stream, "reload_pipeline", lambda: reloads.append(1))
    return cal, reloads, tmp_path / "camera_config.json"


def test_detect_without_a_picture_says_so(road):
    assert client.post("/settings/video/road/detect").json() == {"ok": False, "reason": "There is no picture from the camera yet."}
    assert client.get("/settings/video/road/detect").json() == {"state": "none"}
    assert client.get("/settings/video/road/detect/frame").status_code == 404


def test_the_whole_walkthrough_over_http(road):
    cal, reloads, config = road
    t = feed_seconds(cal, 0.5)
    started = client.post("/settings/video/road/detect").json()
    assert started["ok"] and started["detect"]["state"] == "collecting"

    frame = client.get("/settings/video/road/detect/frame")
    assert frame.status_code == 200 and frame.headers["content-type"] == "image/jpeg" and frame.content[:2] == b"\xff\xd8"
    assert client.get("/settings/video/road/detect/step/marks").status_code == 404            # nothing has finished yet

    feed_seconds(cal, 3.0, start=t)
    status = client.get("/settings/video/road/detect").json()
    assert status["state"] == "done" and status["rules"] == ["pedestrian_lane"]
    assert [s["state"] for s in status["steps"]] == ["done"] * len(status["steps"])
    empty = client.get("/settings/video/road/detect/step/empty")
    assert empty.status_code == 200 and empty.headers["content-type"] == "image/png" and empty.content[:4] == b"\x89PNG"
    assert client.get("/settings/video/road/detect/step/steady").status_code == 404           # that step has no picture
    assert client.get("/settings/video/road/detect/step/nonsense").status_code == 404

    generation = stream._stream_generation
    applied = client.post("/settings/video/road/detect/apply").json()
    assert applied["ok"] and applied["zones"] == ["pedestrian_lane"] and applied["switched_on"] == ["pedestrian_lane"]
    assert json.loads(config.read_text())["active_violations"] == ["pedestrian_lane"]
    assert reloads == [1] and stream._stream_generation == generation + 1                      # the live view restarts once, with the rule on
    assert applied["road"]["state"] == "ready" and "applied" in applied["road"]["message"]


def test_apply_keeps_the_violations_already_on_and_does_not_restart_the_view_when_nothing_is_added(road):
    cal, reloads, config = road
    config.write_text(json.dumps({"active_violations": ["pedestrian_lane", "no_helmet"], "camera_id": "barangay_1"}))
    feed_seconds(cal, 0.5)
    cal.begin_detect()
    feed_seconds(cal, 3.0, start=0.5)
    generation = stream._stream_generation
    applied = client.post("/settings/video/road/detect/apply").json()
    assert applied["ok"] and applied["switched_on"] == []
    assert reloads == [] and stream._stream_generation == generation
    saved = json.loads(config.read_text())
    assert saved["active_violations"] == ["pedestrian_lane", "no_helmet"] and saved["camera_id"] == "barangay_1"


def test_apply_without_a_finished_detection_and_discard(road):
    cal, reloads, config = road
    assert client.post("/settings/video/road/detect/apply").json()["ok"] is False and reloads == []
    feed_seconds(cal, 0.5)
    cal.begin_detect()
    assert client.post("/settings/video/road/detect/discard").json() == {"ok": True}
    assert client.get("/settings/video/road/detect").json() == {"state": "none"}
    assert client.post("/settings/video/road/detect/discard").json() == {"ok": False}
