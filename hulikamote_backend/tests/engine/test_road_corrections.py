"""
The detected road can be corrected before it is applied, the road and sidewalk areas are saved with the camera and drawn, and the finder
pieces behind them (paint that tightens itself, road and sidewalk from where vehicles and people were, the fast steady-camera test).
"""
import cv2
import numpy as np

from engine import live_calibrator as lc
from engine import road_lines as rl
from tests.engine.test_live_calibrator import H, W, calibrator, canned, feed_seconds
from tests.engine.test_live_detect import walking_stub

ROAD = {"kind": "road", "polygon": [[200, 0], [440, 0], [440, 359], [200, 359]], "seen": 20}
SIDEWALK = {"kind": "sidewalk", "side": "left", "polygon": [[20, 0], [200, 0], [200, 359], [20, 359]], "seen": 9}


def detected(tmp_path, crosswalks=True):
    """A calibrator whose scan found a crosswalk (optionally), a road and a left sidewalk."""
    def result():
        out = canned()
        return {**out, "crosswalks": out["crosswalks"] if crosswalks else [], "regions": [ROAD, SIDEWALK]}
    cal = calibrator(tmp_path, analyse=walking_stub(result=result))
    cal.attach("cam")
    t = feed_seconds(cal, 0.5)
    cal.begin_detect()
    feed_seconds(cal, 3.0, start=t)
    return cal


# ─── correcting the draft ────────────────────────────────────────────────────

def test_the_scan_offers_the_crosswalk_the_road_and_the_sidewalk_to_correct(tmp_path):
    status = detected(tmp_path).detect_status()
    assert status["state"] == "done" and status["edited"] is False
    assert [(z["id"], z["kind"]) for z in status["zones"]] == [("crosswalk-1", "crosswalk"), ("road-1", "road"), ("sidewalk-2", "sidewalk")]
    assert status["zones"][2]["side"] == "left"


def test_corrections_are_refused_before_there_is_a_finished_scan(tmp_path):
    cal = calibrator(tmp_path)
    cal.attach("cam")
    assert cal.set_detect_zones([])["ok"] is False


def test_corrections_are_checked_and_kept_inside_the_picture(tmp_path):
    cal = detected(tmp_path)
    for bad in ({"kind": "swimming pool", "polygon": [[0, 0], [1, 0], [1, 1]]}, {"kind": "road", "polygon": [[0, 0], [1, 1]]},
                {"kind": "road", "polygon": "x"}, {"kind": "road", "polygon": [[0, 0], [1, "a"], [2, 2]]}, "x"):
        assert cal.set_detect_zones([bad])["ok"] is False
    assert cal.set_detect_zones("nonsense")["ok"] is False
    assert cal.detect_status()["edited"] is False                                     # nothing refused changed anything
    fixed = cal.set_detect_zones([{"kind": "road", "polygon": [[-50, -10], [9999, 0], [9999, 9999]]}])
    assert fixed["ok"] and fixed["zones"][0]["polygon"] == [[0.0, 0.0], [W - 1.0, 0.0], [W - 1.0, H - 1.0]]
    assert cal.detect_status()["edited"] is True


def test_apply_uses_the_operators_corrections_and_saves_them_with_the_camera(tmp_path):
    cal = detected(tmp_path)
    moved = [{"id": "crosswalk-1", "kind": "crosswalk", "polygon": [[100, 100], [300, 100], [300, 150], [100, 150]]},
             {"id": "road-1", "kind": "road", "polygon": ROAD["polygon"]}]                # the sidewalk was deleted
    assert cal.set_detect_zones(moved)["ok"]
    assert cal.apply_detect()["ok"]
    lane, = cal.zones["pedestrian_lane"]
    assert lane["polygon"][0] == [round(100 * 1920 / W, 1), round(100 * 1080 / H, 1)]     # in the 1920x1080 reference space
    assert [r["kind"] for r in cal.regions] == ["road"]
    saved = lc.load_saved("cam", tmp_path / "camera_config.json")
    assert saved["edited"] is True and [r["kind"] for r in saved["regions"]] == ["road"]


def test_deleting_the_crosswalk_removes_the_rule_but_keeps_the_areas(tmp_path):
    cal = detected(tmp_path)
    cal.set_detect_zones([{"id": "road-1", "kind": "road", "polygon": ROAD["polygon"]}])
    assert cal.apply_detect()["ok"]
    assert "pedestrian_lane" not in cal.zones and cal.found["crosswalks"] == 0 and len(cal.regions) == 1


def test_a_road_with_only_areas_and_no_crosswalk_can_still_be_applied(tmp_path):
    cal = detected(tmp_path, crosswalks=False)
    assert cal.detect_status()["rules"] == []
    assert cal.apply_detect() == {"ok": True, "zones": []}
    assert [r["kind"] for r in cal.regions] == ["road", "sidewalk"]


def test_an_empty_correction_leaves_nothing_to_apply(tmp_path):
    cal = detected(tmp_path, crosswalks=False)
    cal.set_detect_zones([])
    assert cal.apply_detect()["ok"] is False


# ─── saved per camera ────────────────────────────────────────────────────────

def test_a_saved_road_and_sidewalk_come_back_on_the_next_connect_and_are_drawn(tmp_path):
    detected(tmp_path).apply_detect()
    again = calibrator(tmp_path)
    again.attach("cam")                                                                # the same camera, a new session
    assert again.state == "ready" and [r["kind"] for r in again.regions] == ["road", "sidewalk"]
    road, sidewalk = again.region_overlay(1280, 720)
    assert road["violation"] == "road" and road["polygon"][0] == [400, 0]               # 200 px of 640 -> 600 of 1920 -> 400 of 1280
    assert sidewalk["violation"] == "sidewalk" and road["hint"] is False
    assert again.forget() and again.regions == [] and again.region_overlay(1280, 720) == []


def test_another_camera_does_not_get_this_cameras_areas(tmp_path):
    detected(tmp_path).apply_detect()
    other = calibrator(tmp_path)
    other.attach("another camera")
    assert other.regions == []


# ─── the finder pieces ───────────────────────────────────────────────────────

def test_the_road_is_the_band_the_moving_vehicles_used_and_a_sidewalk_is_where_people_walked():
    valid = np.full((rl.TOP_H, rl.TOP_W), 255, np.uint8)
    rng = np.random.default_rng(1)
    moving = np.column_stack([rng.uniform(400, 700, 40), rng.uniform(100, 1100, 40)]).astype(np.float32)
    people = np.vstack([np.column_stack([rng.uniform(100, 250, 8), rng.uniform(100, 1100, 8)]),     # left of the road
                        np.column_stack([rng.uniform(900, 950, 3), rng.uniform(100, 1100, 3)])]).astype(np.float32)   # too few on the right
    regions = rl._regions(moving, people, valid, np.eye(3), (rl.TOP_W, rl.TOP_H))
    road, = [r for r in regions if r["kind"] == "road"]
    assert road["polygon"][0][0] < 420 and road["polygon"][1][0] > 680 and road["seen"] == 40
    sidewalks = [r for r in regions if r["kind"] == "sidewalk"]
    assert [s["side"] for s in sidewalks] == ["left"] and sidewalks[0]["polygon"][1][0] <= road["polygon"][0][0] + 1


def test_without_moving_vehicles_there_is_no_road_to_report():
    valid = np.full((rl.TOP_H, rl.TOP_W), 255, np.uint8)
    few = np.array([[500.0, 500.0]] * 5, np.float32)
    assert rl._regions(few, np.zeros((0, 2), np.float32), valid, np.eye(3), (rl.TOP_W, rl.TOP_H)) == []


def test_a_vehicle_that_stays_put_is_parked_not_part_of_the_road():
    calls = [0]

    def detector(_frame):
        i, calls[0] = calls[0], calls[0] + 1
        return [("car", [100 + 40 * i - 10, 60, 20, 20]),                   # drives on
                ("car", [490, 280, 20, 20]),                                # same place every time
                ("person", [40, 280, 20, 20])]
    clip = {"colours": [np.zeros((100, 200, 3), np.uint8)] * 4, "colour_at": [0, 1, 2, 3], "colour_size": (200, 100)}
    moving, parked, people = rl._foot_points(detector, clip, [np.eye(3)] * 4, np.eye(3))
    assert len(moving) == 4 and len(parked) == 4 and len(people) == 4
    assert sorted(moving[:, 0].tolist()) == [100.0, 140.0, 180.0, 220.0] and set(parked[:, 0].tolist()) == {500.0}


def slab_road(seed=3):
    """A top view of old concrete: mottled grey with bright joints every 120 px. Thin bright specks everywhere, none of them paint."""
    rng = np.random.default_rng(seed)
    mottle = cv2.GaussianBlur(rng.normal(0, 20, (rl.TOP_H, rl.TOP_W)).astype(np.float32), (0, 0), 2.0) * 3
    img = np.clip(120 + mottle + rng.normal(0, 4, mottle.shape), 0, 255).astype(np.uint8)
    img[::120, :] = 150
    img[:, ::120] = 150
    return cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)


def test_joints_in_a_slab_road_do_not_turn_the_road_into_paint():
    top = slab_road()
    full = np.full((rl.TOP_H, rl.TOP_W), 255, np.uint8)
    white, yellow, _loose, _warm, _contrast, level = rl._paint(top, full, full)
    share = float(((white > 0) | (yellow > 0)).sum()) / float((full > 0).sum())
    assert level > rl.PAINT_LEVELS[0] and share <= rl.MAX_PAINT_SHARE + 0.02       # the filter tightened itself instead of giving up


def test_a_faint_line_on_clean_asphalt_is_still_found():
    rng = np.random.default_rng(5)
    img = np.clip(rng.normal(110, 2, (rl.TOP_H, rl.TOP_W)), 0, 255).astype(np.uint8)
    img[:, 600:614] = 126                                                         # paint only 16 grey levels brighter than the road
    top = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    full = np.full((rl.TOP_H, rl.TOP_W), 255, np.uint8)
    white, _yellow, _loose, _warm, _contrast, level = rl._paint(top, full, full)
    assert (white[:, 600:614] > 0).mean() > 0.6 and level <= 1.0


def texture(seed=9):
    rng = np.random.default_rng(seed)
    base = cv2.GaussianBlur(rng.integers(0, 255, (270, 480)).astype(np.float32), (0, 0), 2.0)
    base = cv2.normalize(base, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    cv2.rectangle(base, (60, 60), (160, 140), 255, -1)
    cv2.rectangle(base, (300, 150), (420, 230), 0, -1)
    return base


def test_a_steady_camera_is_recognised_from_a_sample_and_the_rest_are_not_matched(monkeypatch):
    seen = []
    real = rl._align_to
    monkeypatch.setattr(rl, "_align_to", lambda frames, *a: (seen.append(len(frames)), real(frames, *a))[1])
    frames = [texture() for _ in range(36)]
    mats, sway, failed = rl._stabilise(frames)
    assert seen == [len(frames[::max(8, 36 // 12)])] and seen[0] < 36                   # only the sample was matched
    assert all(np.allclose(m, np.eye(3)) for m in mats) and len(mats) == 36 and sway < 1.0 and failed == 0


def test_a_shaking_camera_is_matched_frame_by_frame(monkeypatch):
    seen = []
    real = rl._align_to
    monkeypatch.setattr(rl, "_align_to", lambda frames, *a: (seen.append(len(frames)), real(frames, *a))[1])
    base = texture()
    frames = [np.roll(base, int(round(8 * np.sin(i))), axis=1) for i in range(36)]
    mats, sway, _failed = rl._stabilise(frames)
    assert seen[-1] == 36 and sway > 1.0 and not all(np.allclose(m, np.eye(3)) for m in mats)
