"""
"Detect road" in the live monitor: a frozen frame, the last stretch of footage, every step of the finder handed back as a picture,
then Apply or Discard. Synthetic frames and a stand-in for the finder (no video, no model, no ffmpeg).
"""
import json
import threading

import numpy as np

from engine import live_calibrator as lc
from engine.road_lines import WALKTHROUGH
from tests.engine.test_live_calibrator import H, SOLID, STOP, W, calibrator, canned, feed_seconds, view


def walking_stub(result=None, release=None):
    """A stand-in for the finder that reports every step of the walkthrough the way the real one does."""
    def analyse(clip, trace=None):
        if release is not None:
            release.wait(5)
        for step, _title, _about in WALKTHROUGH:
            if step == "marks":
                continue                                                           # the calibrator draws this one itself
            if trace:
                trace(step, "start", None, {})
                picture = None
                if step != "steady":
                    picture = np.zeros((clip["colour_size"][1], clip["colour_size"][0], 4), np.uint8)
                    picture[10:20, 10:20] = (255, 255, 0, 255)
                trace(step, "done", picture, {})
        out = result() if callable(result) else (result if result is not None else canned())
        return out, view()
    return analyse


def detecting(tmp_path, **kw):
    kw.setdefault("analyse", walking_stub())
    cal = calibrator(tmp_path, **kw)
    cal.attach("cam")
    return cal


def test_detect_needs_a_picture_first(tmp_path):
    cal = detecting(tmp_path)
    assert cal.begin_detect() == {"ok": False, "reason": "There is no picture from the camera yet."}
    assert cal.detect_status() == {"state": "none"}


def test_detect_freezes_the_frame_waits_for_footage_then_walks_through_every_step(tmp_path):
    cal = detecting(tmp_path)
    t = feed_seconds(cal, 0.5)
    started = cal.begin_detect()
    assert started["ok"] and started["detect"]["state"] == "collecting"
    assert [s["state"] for s in started["detect"]["steps"]] == ["waiting"] * len(WALKTHROUGH)
    frozen = cal.detect_frame()
    assert frozen[:2] == b"\xff\xd8"                                               # a JPEG of the moment the button was pressed

    feed_seconds(cal, 0.5, picture=view(flip=True), start=t)                       # still collecting: the frozen picture does not change
    assert cal.detect_status()["state"] == "collecting" and cal.detect_frame() == frozen
    feed_seconds(cal, 3.0, start=t + 0.5)
    status = cal.detect_status()
    assert status["state"] == "done" and status["rules"] == ["pedestrian_lane"] and status["found"]["crosswalks"] == 1
    assert [s["id"] for s in status["steps"]] == [sid for sid, _t, _a in WALKTHROUGH]
    assert all(s["state"] == "done" for s in status["steps"])
    assert not status["steps"][0]["has_overlay"] and all(s["has_overlay"] for s in status["steps"][1:])    # "steady" has no picture
    assert cal.detect_overlay("marks")[:4] == b"\x89PNG" and cal.detect_overlay("steady") is None


def test_detect_cannot_be_started_twice_and_a_discarded_one_is_forgotten(tmp_path):
    release = threading.Event()
    cal = detecting(tmp_path, analyse=walking_stub(release=release), background=True)
    feed_seconds(cal, 3.0)
    assert cal.begin_detect()["ok"]
    feed_seconds(cal, 1.0, start=3.0)
    assert cal.detect_status()["state"] == "analysing"
    assert cal.begin_detect() == {"ok": False, "reason": "The road is already being read."}
    assert cal.discard_detect() is True and cal.detect_status() == {"state": "none"}
    release.set()
    for thread in threading.enumerate():
        if thread.name == "road-detect":
            thread.join(5)
    assert cal.detect_status() == {"state": "none"}                                # the late reading did not come back to life
    assert cal.apply_detect()["ok"] is False


def test_a_failed_reading_shows_the_reason_and_skips_the_steps_it_never_reached(tmp_path):
    def stops_early(clip, trace=None):
        trace("steady", "start", None, {})
        trace("steady", "done", None, {})
        trace("empty", "start", None, {})
        return canned(ok=False), view()
    cal = detecting(tmp_path, analyse=stops_early)
    feed_seconds(cal, 0.5)
    cal.begin_detect()
    feed_seconds(cal, 3.0, start=0.5)
    status = cal.detect_status()
    assert status["state"] == "failed" and "traffic" in status["reason"]
    states = {s["id"]: s["state"] for s in status["steps"]}
    assert states["steady"] == "done" and states["empty"] == "skipped" and states["marks"] == "skipped"


def test_a_crash_while_detecting_is_reported_not_raised(tmp_path):
    def boom(clip, trace=None):
        raise RuntimeError("the finder fell over")
    cal = detecting(tmp_path, analyse=boom)
    feed_seconds(cal, 0.5)
    cal.begin_detect()
    feed_seconds(cal, 3.0, start=0.5)
    assert cal.detect_status()["state"] == "failed" and "fell over" in cal.detect_status()["reason"]


def test_apply_makes_the_detected_road_the_cameras_road_and_saves_it(tmp_path):
    cal = detecting(tmp_path)
    feed_seconds(cal, 0.5)
    cal.begin_detect()
    feed_seconds(cal, 3.0, start=0.5)
    cal.state, before = "refused", cal.version                                     # e.g. the automatic reading had given up
    done = cal.apply_detect()
    assert done == {"ok": True, "zones": ["pedestrian_lane"]}
    assert cal.status()["state"] == "ready" and "Road applied" in cal.status()["message"] and cal.version > before
    assert list(cal.active_zones()) == ["pedestrian_lane"] and cal.detect_status()["applied"] is True
    saved = json.loads((tmp_path / "camera_config.json").read_text())["learned_road"]["cam"]
    assert list(saved["zones"]) == ["pedestrian_lane"] and saved["view_hash"]


def test_apply_with_nothing_clear_does_nothing(tmp_path):
    cal = detecting(tmp_path, analyse=walking_stub(result=lambda: canned(stripes=3, score=0.7)))
    feed_seconds(cal, 0.5)
    cal.begin_detect()
    feed_seconds(cal, 3.0, start=0.5)
    assert cal.detect_status()["state"] == "done" and cal.detect_status()["rules"] == []
    assert cal.apply_detect()["ok"] is False and cal.active_zones() == {}


def test_the_marks_picture_says_why_a_mark_was_ignored():
    narrow = canned(stripes=6, score=0.9)
    narrow["crosswalks"][0]["top"] = {"u0": 50.0, "u1": 150.0, "v0": 100.0, "v1": 160.0}
    narrow["crosswalks"][0]["polygon"] = [[50, 100], [150, 100], [150, 160], [50, 160]]
    picture, marks = lc.marks_overlay(narrow, (1280, 720), False)
    assert picture.shape == (720, 1280, 4) and picture[..., 3].any()
    assert marks == [{"kind": "crosswalk", "status": "ignored", "why": "too narrow to span the road", "stripes": 6}]

    good = canned(stripes=6, score=0.9, stops=[STOP], lanes=[SOLID])
    good["crosswalks"][0]["polygon"] = [[50, 100], [350, 100], [350, 160], [50, 160]]
    _picture, marks = lc.marks_overlay(good, (1280, 720), False)
    assert [(m["kind"], m["status"]) for m in marks] == [("crosswalk", "rule"), ("stop_line", "hint"), ("solid_line", "hint")]
    assert [m["status"] for m in lc.marks_overlay(good, (1280, 720), True)[1]][1:] == ["rule", "rule"]


def test_the_rolling_buffer_keeps_only_the_last_stretch_and_a_new_camera_starts_clean(tmp_path):
    cal = detecting(tmp_path)
    feed_seconds(cal, 6.0)
    assert 0 < cal._ring_span() <= 2.2 and len(cal._ring_g) <= 18                   # learn_seconds is 2 in these tests
    clip = cal._ring_clip()
    assert clip["video"] == (W, H) and len(clip["greys"]) == len(cal._ring_g) and len(clip["colours"]) == len(clip["colour_at"])
    cal.attach("another cam")
    assert len(cal._ring_g) == 0 and cal._last_frame is None and cal.detect_status() == {"state": "none"}
