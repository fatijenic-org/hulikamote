"""
engine/live_calibrator.py - the Live Monitor learns the road paint of its camera by itself, remembers it per camera and
never guesses. Synthetic clips and a stand-in for road_lines.analyse_clip: no video, no model, no ffmpeg.
"""
import json
import threading
from types import SimpleNamespace

import numpy as np
import pytest

from engine import live_calibrator as lc
from engine.live_calibrator import LiveCalibrator, accept, camera_key, hash_distance, view_hash
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY

W, H = 640, 360
STEP = 0.125


def view(flip=False):
    """A picture with structure (so its fingerprint means something): a gradient with blocks."""
    base = np.tile(np.linspace(0, 255, W, dtype=np.float32), (H, 1))
    base[60:140, 100:260] = 30
    base[200:300, 380:560] = 220
    img = np.dstack([base, base * 0.8, base * 0.6]).astype(np.uint8)
    return img[:, ::-1].copy() if flip else img


def feed_seconds(cal, seconds, picture=None, start=0.0):
    t = start
    for _ in range(int(round(seconds / STEP))):
        cal.feed(view() if picture is None else picture, t)
        t += STEP
    return t


def canned(stripes=6, score=0.9, ok=True, stops=None, lanes=None):
    if not ok:
        return {"ok": False, "reason": "Not enough traffic movement to find the road direction.", "video_size": [W, H],
                "crosswalks": [], "stop_lines": [], "lane_lines": []}
    return {"ok": True, "reason": None, "video_size": [W, H],
            "rectifier": {"top_to_video": np.eye(3).tolist(), "top_size": [400, 600]},
            "crosswalks": [{"polygon": [[50, 100], [350, 100], [350, 160], [50, 160]], "stripes": stripes, "score": score,
                            "top": {"u0": 50.0, "u1": 350.0, "v0": 100.0, "v1": 160.0}}],
            "stop_lines": stops or [], "lane_lines": lanes or []}


STOP = {"p0": [50, 300], "p1": [350, 300], "top": {"u0": 50.0, "v0": 300.0, "u1": 350.0, "v1": 300.0}, "length": 300.0}
SOLID = {"p0": [200, 50], "p1": [200, 450], "top": {"u0": 200.0, "v0": 50.0, "u1": 200.0, "v1": 450.0},
         "style": "solid", "colour": "white", "coverage": 0.95}


def calibrator(tmp_path, result=None, **kw):
    """Learns after 2 s of footage and reads the road in the caller's thread (so a test can look at the outcome at once)."""
    seen = {"clips": []}

    def analyse(clip):
        seen["clips"].append(clip)
        out = result() if callable(result) else (result if result is not None else canned())
        return out, view()
    kw.setdefault("min_pictures", 8)
    cal = LiveCalibrator(config_path=tmp_path / "camera_config.json", learn_seconds=2.0,
                         analyse=kw.pop("analyse", analyse), background=kw.pop("background", False), **kw)
    cal.seen = seen
    return cal


# ─── learning ────────────────────────────────────────────────────────────────

def test_it_starts_learning_when_a_camera_with_nothing_saved_connects(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("rtsp://cam/1")
    assert cal.status()["state"] == "learning" and cal.active_zones() == {}
    feed_seconds(cal, 1.0)
    status = cal.status()
    assert status["state"] == "learning" and status["message"] == "Learning the road 0/2 s" or "1/2 s" in status["message"]
    assert 0.5 <= status["progress_s"] <= 1.0


def test_the_clip_it_hands_to_the_road_reader_has_the_shape_the_reader_expects(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam")
    feed_seconds(cal, 2.5)
    clip, = cal.seen["clips"]
    assert clip["video"] == (W, H) and len(clip["greys"]) >= 8 and clip["colours"] and len(clip["colours"]) == len(clip["colour_at"])
    assert clip["grey_size"] == (480, 270) and clip["colour_size"][0] == 1280
    assert all(0 <= i < len(clip["greys"]) for i in clip["colour_at"])           # a colour picture says which grey one it matches


def test_a_clear_crosswalk_becomes_a_pedestrian_lane_zone_and_is_remembered(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam")
    before = cal.version
    feed_seconds(cal, 2.5)
    status = cal.status()
    assert status["state"] == "ready" and status["found"]["crosswalks"] == 1 and "1 crosswalk" in status["message"]
    zones = cal.active_zones()
    assert list(zones) == ["pedestrian_lane"] and cal.version > before
    xs = [p[0] for p in zones["pedestrian_lane"][0]["polygon"]]
    assert max(xs) > 640                                                         # in the wizard's 1920x1080 reference space
    saved = json.loads((tmp_path / "camera_config.json").read_text())["learned_road"]["cam"]
    assert saved["zones"] == zones and saved["view_hash"] and saved["found"]["crosswalks"] == 1


@pytest.mark.parametrize("stripes,score,kept", [(5, 0.65, 1), (6, 0.9, 1), (4, 0.9, 1), (4, 0.7, 0)])
def test_only_clear_crosswalks_are_believed(stripes, score, kept):
    zones, found = accept(canned(stripes=stripes, score=score))
    assert found["crosswalks"] == kept and bool(zones.get("pedestrian_lane")) == bool(kept)


def test_stop_and_solid_lines_need_to_be_long_and_well_painted():
    short_stop = {**STOP, "length": 60.0}
    faint_solid = {**SOLID, "coverage": 0.8}
    short_solid = {**SOLID, "top": {"u0": 200.0, "v0": 100.0, "u1": 200.0, "v1": 160.0}}
    zones, found = accept(canned(stops=[short_stop], lanes=[faint_solid, short_solid]))
    assert found["stop_lines"] == 0 and found["solid_lines"] == 0 and set(zones) == {"pedestrian_lane"}
    zones, found = accept(canned(stops=[STOP], lanes=[SOLID]))
    assert found["stop_lines"] == 1 and found["solid_lines"] == 1 and {"red_light", "crossing_solid_line"} <= set(zones)


def test_a_narrow_crosswalk_is_not_believed_even_with_many_stripes():
    """On a real clip a tiled pavement strip read as a 6-stripe crosswalk; it was narrow, real crosswalks span the road."""
    narrow = canned(stripes=6, score=0.9)
    narrow["crosswalks"][0]["top"] = {"u0": 50.0, "u1": 170.0, "v0": 100.0, "v1": 160.0}      # 30% of the 400 px top view
    zones, found = accept(narrow)
    assert found["crosswalks"] == 0 and zones == {}
    wide = canned(stripes=6, score=0.9)
    wide["crosswalks"][0]["top"] = {"u0": 50.0, "u1": 230.0, "v0": 100.0, "v1": 160.0}        # 45%
    assert accept(wide)[1]["crosswalks"] == 1


def test_a_dashed_line_is_never_a_solid_line_zone():
    zones, found = accept(canned(lanes=[{**SOLID, "style": "dashed"}]))
    assert found["solid_lines"] == 0 and "crossing_solid_line" not in zones


def test_a_road_with_nothing_clear_installs_nothing_but_is_not_an_error(tmp_path):
    cal = calibrator(tmp_path, result=lambda: canned(stripes=3, score=0.7))
    cal.attach("cam")
    feed_seconds(cal, 2.5)
    assert cal.status()["state"] == "empty" and cal.active_zones() == {}
    assert "no zones are used" in cal.status()["message"]


def test_stop_and_solid_lines_are_only_hints_by_default(tmp_path):
    cal = calibrator(tmp_path, result=lambda: canned(stops=[STOP], lanes=[SOLID]))
    cal.attach("cam")
    feed_seconds(cal, 2.5)
    status = cal.status()
    assert list(cal.active_zones()) == ["pedestrian_lane"]                       # only the crosswalk is a rule
    assert status["hints"] == ["crossing_solid_line", "red_light"] and status["found"]["stop_lines"] == 1
    assert "hints only" in status["message"] and status["best_effort"]
    hints = cal.hint_overlay(1280, 720)
    assert {h["violation"] for h in hints} == {"red_light", "crossing_solid_line"} and all(h["hint"] and h["best_effort"] for h in hints)
    assert all(max(p[0] for p in h["polygon"]) <= 1280 for h in hints)           # scaled onto the live frame


def test_the_flag_turns_line_hints_into_rules(tmp_path, monkeypatch):
    monkeypatch.setattr(lc, "FLAG_REFRESH", 0.0)                                 # read it fresh every time in this test
    (tmp_path / "camera_config.json").write_text(json.dumps({"learned_lines_as_rules": True}))
    cal = calibrator(tmp_path, result=lambda: canned(stops=[STOP], lanes=[SOLID]))
    cal.attach("cam")
    feed_seconds(cal, 2.5)
    assert set(cal.active_zones()) == {"pedestrian_lane", "red_light", "crossing_solid_line"}
    assert cal.status()["hints"] == [] and cal.hint_overlay(1280, 720) == []
    saved = json.loads((tmp_path / "camera_config.json").read_text())
    assert saved["learned_lines_as_rules"] is True and "learned_road" in saved            # saving keeps the operator's own settings


# ─── the failure path is safe ────────────────────────────────────────────────

def test_a_refused_read_tries_again_then_gives_up_with_the_reason_and_no_zones(tmp_path):
    cal = calibrator(tmp_path, result=lambda: canned(ok=False))
    cal.attach("cam")
    version = cal.version
    t = feed_seconds(cal, 2.5)
    mid = cal.status()
    assert mid["state"] == "learning" and mid["attempt"] == 2 and "Last try:" in mid["message"] and "traffic" in mid["message"]
    t = feed_seconds(cal, 2.5, start=t)
    t = feed_seconds(cal, 2.5, start=t)
    final = cal.status()
    assert final["state"] == "refused" and final["attempt"] == lc.MAX_ATTEMPTS and "Re-learn" in final["message"]
    assert "Not enough traffic" in final["message"]
    assert cal.active_zones() == {} and cal.version == version                   # nothing was ever installed
    assert not (tmp_path / "camera_config.json").exists()                        # and nothing was saved
    cal.feed(view(), t + 1)                                                      # the live loop keeps feeding: harmless
    assert cal.status()["state"] == "refused"


def test_nothing_clear_after_refused_reads_is_not_remembered_but_a_clean_empty_read_is(tmp_path):
    answers = iter([canned(ok=False), canned(stripes=3, score=0.7)])               # refused, then "read, nothing clear"
    cal = calibrator(tmp_path, result=lambda: next(answers))
    cal.attach("cam")
    t = feed_seconds(cal, 2.5)
    feed_seconds(cal, 2.5, start=t)
    assert cal.status()["state"] == "empty" and not (tmp_path / "camera_config.json").exists()

    clean = calibrator(tmp_path / "second", result=lambda: canned(stripes=3, score=0.7))
    (tmp_path / "second").mkdir()
    clean.attach("cam")
    feed_seconds(clean, 2.5)
    assert clean.status()["state"] == "empty" and (tmp_path / "second" / "camera_config.json").exists()   # first read: believed


def test_a_crash_inside_the_reader_never_reaches_the_live_loop(tmp_path):
    def boom(_clip):
        raise RuntimeError("the road reader fell over")
    cal = calibrator(tmp_path, analyse=boom)
    cal.attach("cam")
    t = 0.0
    for _ in range(lc.MAX_ATTEMPTS):
        t = feed_seconds(cal, 2.5, start=t)
    status = cal.status()
    assert status["state"] == "error" and "fell over" in status["message"] and cal.active_zones() == {}


def test_too_few_pictures_are_refused_not_guessed(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam")
    for t in (0.0, 50.0, 95.0):                                                  # a stream that only delivers 3 frames in 95 s
        cal.feed(view(), t)
    status = cal.status()
    assert cal.active_zones() == {} and cal.seen["clips"] == []                  # the reader was never asked to guess
    assert status["state"] == "learning" and status["attempt"] == 2 and "too few pictures" in status["message"]


# ─── remembering per camera ──────────────────────────────────────────────────

def test_a_saved_road_is_used_at_once_when_the_camera_connects_again(tmp_path):
    first = calibrator(tmp_path)
    first.attach("cam")
    feed_seconds(first, 2.5)
    learned = first.active_zones()

    second = calibrator(tmp_path)                                                # "after a backend restart"
    second.attach("cam")
    status = second.status()
    assert status["state"] == "ready" and status["saved"] is True and "loaded" in status["message"]
    assert second.active_zones() == learned and second.version >= 1              # no waiting, no learning


def test_another_camera_does_not_get_this_cameras_road(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam A")
    feed_seconds(cal, 2.5)
    cal.attach("cam B")
    assert cal.active_zones() == {} and cal.status()["state"] == "learning"
    cal.attach("cam A")                                                          # and A is still remembered
    assert list(cal.active_zones()) == ["pedestrian_lane"]


def test_the_same_view_keeps_its_saved_road_and_a_different_view_makes_it_learn_again(tmp_path):
    seed = calibrator(tmp_path)
    seed.attach("cam")
    feed_seconds(seed, 2.5)

    same = calibrator(tmp_path)
    same.attach("cam")
    feed_seconds(same, 6.0)                                                      # the live view matches what was saved
    assert same.status()["state"] == "ready" and same.active_zones()

    moved = calibrator(tmp_path)
    moved.attach("cam")
    assert moved.active_zones()                                                  # used at once ...
    feed_seconds(moved, 6.0, picture=view(flip=True))                            # ... until the check finds another view
    status = moved.status()
    assert moved.active_zones() == {} and status["state"] == "learning" and "view changed" in status["message"]


def test_reconnecting_to_the_same_address_with_another_picture_learns_again(tmp_path):
    """A different clip on the same camera address must not keep the first clip's zones (seen in the first rehearsal)."""
    cal = calibrator(tmp_path)
    cal.attach("rtsp://cam/cam1")
    feed_seconds(cal, 2.5)
    assert cal.active_zones()

    cal.detach()
    cal.attach("rtsp://cam/cam1")                                                # the loop reconnects to the same address
    assert cal.active_zones()                                                    # still used while the view is being checked
    feed_seconds(cal, 6.0, picture=view(flip=True))                              # but the picture is another one
    assert cal.active_zones() == {} and cal.status()["state"] == "learning" and "view changed" in cal.status()["message"]

    same = calibrator(tmp_path / "other")
    (tmp_path / "other").mkdir()
    same.attach("rtsp://cam/cam1")
    feed_seconds(same, 2.5)
    same.detach()
    same.attach("rtsp://cam/cam1")
    feed_seconds(same, 6.0)                                                      # the same picture again
    assert same.status()["state"] == "ready" and same.active_zones()


def test_a_camera_that_is_moved_while_connected_is_noticed(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam")
    t = feed_seconds(cal, 2.5)
    assert cal.active_zones()
    t = feed_seconds(cal, lc.VERIFY_EVERY + 1, start=t)                          # five quiet minutes: the check passes
    assert cal.active_zones() and cal.status()["state"] == "ready"
    feed_seconds(cal, 5.5, picture=view(flip=True), start=t)                     # then somebody turns the camera
    assert cal.active_zones() == {} and cal.status()["state"] == "learning"


def test_the_view_fingerprint_tells_views_apart_and_ignores_brightness():
    a = view()
    assert hash_distance(view_hash(a[..., 0]), view_hash((a[..., 0] * 0.7).astype(np.uint8))) < 6
    assert hash_distance(view_hash(a[..., 0]), view_hash(view(flip=True)[..., 0])) >= lc.CHANGED_DISTANCE


def test_relearn_and_forget(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam")
    feed_seconds(cal, 2.5)
    assert cal.active_zones()
    version = cal.version

    assert cal.relearn() is True
    assert cal.active_zones() == {} and cal.status()["state"] == "learning" and cal.version > version
    feed_seconds(cal, 2.5)
    assert cal.status()["state"] == "ready"

    assert cal.forget() is True
    assert cal.active_zones() == {} and cal.status()["state"] == "off"
    assert "learned_road" not in json.loads((tmp_path / "camera_config.json").read_text())
    fresh = calibrator(tmp_path)
    fresh.attach("cam")
    assert fresh.status()["state"] == "learning"                                 # nothing saved any more: it learns again
    assert LiveCalibrator(config_path=tmp_path / "x.json").relearn() is False   # no camera, nothing to do


def test_a_reading_that_finishes_after_relearn_is_thrown_away(tmp_path):
    release, started = threading.Event(), threading.Event()

    def slow(_clip):
        started.set()
        release.wait(5)
        return canned(), view()
    cal = calibrator(tmp_path, analyse=slow, background=True)
    cal.attach("cam")
    feed_seconds(cal, 2.5)
    assert started.wait(5) and cal.status()["state"] == "analysing"
    cal.relearn()                                                                # the operator asks again meanwhile
    release.set()
    for thread in threading.enumerate():
        if thread.name == "road-learner":
            thread.join(5)
    assert cal.active_zones() == {} and cal.status()["state"] == "learning"      # the old reading did not sneak in


def test_a_camera_is_named_by_its_profile_or_its_masked_address(tmp_path):
    config = tmp_path / "camera_config.json"
    config.write_text(json.dumps({"camera_profiles": [{"name": "Barangay CCTV", "url": "rtsp://admin:s3cret@10.0.0.5/ch1"}]}))
    assert camera_key("rtsp://admin:s3cret@10.0.0.5/ch1", config) == "profile:Barangay CCTV"
    other = camera_key("rtsp://admin:s3cret@10.0.0.9/ch1", config)
    assert "s3cret" not in other and "***" in other
    assert camera_key("clips/junction.mp4", config) == "clips/junction.mp4"


def test_a_stream_that_changes_size_starts_over_instead_of_mixing_pictures(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam")
    feed_seconds(cal, 1.0)
    big = np.zeros((720, 1280, 3), np.uint8)
    cal.feed(big, 5.0)
    assert len(cal.seen["clips"]) == 0 and cal.status()["state"] == "learning"


# ─── handing the zones to the pipeline ───────────────────────────────────────

def pipeline(active, drawn=None):
    pipe = object.__new__(DecoupledPipeline)
    pipe.rois, pipe.native_w, pipe.native_h = drawn or {}, 0, 0
    pipe.registry = SimpleNamespace(active_violations=list(active))
    pipe.flow_mode = "zones"
    return pipe


WIZARD_BOX = [{"polygon": [[960, 540], [1920, 540], [1920, 1080], [960, 1080]]}]
WIZARD_STOP = [{"polygon": [[0, 900], [1920, 900], [1920, 1000], [0, 1000]], "ui_vector": [[0, 950], [1920, 950]],
                "vector": {"x_dir": 1920.0, "y_dir": 0.0}}]


def test_a_learned_crosswalk_becomes_a_pedestrian_lane_zone_on_the_frame():
    pipe = pipeline(["pedestrian_lane"])
    pipe.set_learned_zones({"pedestrian_lane": WIZARD_BOX})
    key = REGISTRY["pedestrian_lane"].zone_key
    zone, = pipe._get_scaled_rois(1280, 720)[key]
    assert zone["polygon"][0] == [640, 360] and zone["polygon"][2] == [1280, 720] and zone["learned"] is True
    overlay, = pipe.learned_overlay(1280, 720)
    assert overlay["violation"] == "pedestrian_lane" and overlay["best_effort"] is False and overlay["polygon"][0] == [640, 360]


def test_learned_zones_are_used_only_for_violations_that_are_switched_on():
    pipe = pipeline(["no_helmet"])
    pipe.set_learned_zones({"pedestrian_lane": WIZARD_BOX})
    assert pipe._get_scaled_rois(1280, 720)[REGISTRY["pedestrian_lane"].zone_key] == [] and pipe.learned_overlay(1280, 720) == []


def test_a_drawn_zone_always_beats_a_learned_one():
    key = REGISTRY["pedestrian_lane"].zone_key
    drawn = {key: [{"polygon": [[0, 0], [100, 0], [100, 100]]}]}
    pipe = pipeline(["pedestrian_lane"], drawn=drawn)
    pipe.set_learned_zones({"pedestrian_lane": WIZARD_BOX})
    zones = pipe._get_scaled_rois(1280, 720)[key]
    assert len(zones) == 1 and not zones[0].get("learned") and pipe.learned_overlay(1280, 720) == []


def test_no_learned_zones_means_the_pipeline_behaves_exactly_as_before():
    pipe = pipeline(["pedestrian_lane"])
    assert pipe._get_scaled_rois(1280, 720)[REGISTRY["pedestrian_lane"].zone_key] == []
    pipe.set_learned_zones({"pedestrian_lane": WIZARD_BOX})
    pipe.set_learned_zones({})                                                   # a failed or forgotten learn
    assert pipe._get_scaled_rois(1280, 720)[REGISTRY["pedestrian_lane"].zone_key] == []


def test_stop_and_solid_line_zones_carry_their_line_and_are_labelled_best_effort():
    pipe = pipeline(["red_light", "crossing_solid_line"])
    pipe.set_learned_zones({"red_light": WIZARD_STOP, "crossing_solid_line": WIZARD_STOP})
    rois = pipe._get_scaled_rois(1280, 720)
    stop, = rois[REGISTRY["red_light"].zone_key]
    line, = rois[REGISTRY["crossing_solid_line"].zone_key]
    assert stop["stop_line"] == [[0, 633], [1280, 633]] and line["stop_line"] == [[0, 633], [1280, 633]]
    assert stop["light"]["mode"] == "timer"                                      # no real light is invented: the wizard's timer rules
    assert {o["violation"]: o["best_effort"] for o in pipe.learned_overlay(1280, 720)} == {"red_light": True, "crossing_solid_line": True}


def test_a_zone_that_cannot_be_used_is_skipped_not_fatal():
    pipe = pipeline(["pedestrian_lane", "red_light"])
    pipe.set_learned_zones({"red_light": [{"polygon": [[0, 0], [10, 0], [10, 10]]}],      # a stop-line rule without its line
                            "pedestrian_lane": WIZARD_BOX})
    rois = pipe._get_scaled_rois(1280, 720)
    assert rois[REGISTRY["red_light"].zone_key] == [] and len(rois[REGISTRY["pedestrian_lane"].zone_key]) == 1


def test_a_pedestrian_on_a_learned_crosswalk_is_flagged_and_off_it_is_not():
    """The rule itself, fed the learned zone: a stopped vehicle in it is flagged, a stopped one outside it is not."""
    from engine.ledger import ActiveLedgerManager
    from tests.helpers import FPS, H as BH, W as BW, Det
    pipe = pipeline(["pedestrian_lane"])
    pipe.set_learned_zones({"pedestrian_lane": WIZARD_BOX})
    zones = pipe._get_scaled_rois(1280, 720)[REGISTRY["pedestrian_lane"].zone_key]

    def stopped_at(x, y):
        mgr = ActiveLedgerManager()
        flagged = False
        for i in range(int(6 * FPS)):                                            # stopped for 6 s (the limit is 3 s)
            det = Det(1, [int(x - BW / 2), int(y - BH), BW, BH])
            mgr.update([det], i / FPS)
            flagged = REGISTRY["pedestrian_lane"].evaluate(mgr, 1, zones) or flagged
        return flagged
    assert stopped_at(900, 650) and not stopped_at(100, 100)
