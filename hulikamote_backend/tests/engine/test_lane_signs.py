"""
Restricted lane without a drawn zone, and the overlay signs placed on the roads (engine/lane_signs.py).
Scripted vehicles only (no model, no video).
"""
import json
from types import SimpleNamespace

import numpy as np

from engine import lane_signs
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY, ZONE_RULES
from tests.helpers import BIG_ZONE, drive

LANE = REGISTRY["restricted_lane"]
LEFT = [[0, 0], [1000, 0], [1000, 2000], [0, 2000]]           # two lanes side by side, in the wizard's reference space
RIGHT = [[1000, 0], [2000, 0], [2000, 2000], [1000, 2000]]


def sign(kind, x, y):
    return {"type": kind, "x": x, "y": y}


def run(zones, cls, x=1000):
    mgr = ActiveLedgerManager()
    return drive(mgr, [(x, 1000 - 9 * i) for i in range(20)], lambda tid: LANE.evaluate(mgr, tid, zones), cls=cls)


# ─── a zone is optional ─────────────────────────────────────────────────────

def pipeline(active, cfg=None, drawn=None, flow_mode="zones"):
    pipe = object.__new__(DecoupledPipeline)                      # skip model loading
    pipe.rois = {key: [] for key in ZONE_RULES.values()}
    if drawn is not None:
        pipe.rois["restricted_lane_zones"] = drawn
    pipe.native_w, pipe.native_h = 1920, 1080
    pipe.registry = SimpleNamespace(active_violations=active)
    pipe.violation_cfg = {"restricted_lane": cfg} if cfg is not None else {}
    pipe.flow_mode = flow_mode
    pipe.flow = None                                              # the learned traffic flow: not needed here
    return pipe


def test_with_nothing_drawn_the_whole_picture_is_the_lane():
    for mode in ("zones", "auto"):
        scaled = pipeline(["restricted_lane"], {"allowed_classes": ["bus"]}, flow_mode=mode)._get_scaled_rois(960, 540)
        (zone,) = scaled["restricted_lane_zones"]
        assert zone["polygon"] == [[0, 0], [960, 0], [960, 540], [0, 540]]
        assert zone["allowed_classes"] == ["bus"] and zone["signs"] == []


def test_a_car_is_flagged_and_a_bus_is_not_in_the_whole_picture_lane():
    (zone,) = pipeline(["restricted_lane"], {"allowed_classes": ["bus"]})._get_scaled_rois(1920, 1080)["restricted_lane_zones"]
    assert run([zone], "car") and not run([zone], "bus")


def test_a_drawn_zone_still_limits_the_rule_and_no_whole_picture_zone_is_added():
    drawn = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]], "allowed_classes": ["bus"]}]
    scaled = pipeline(["restricted_lane"], {"allowed_classes": ["bus"]}, drawn=drawn)._get_scaled_rois(1920, 1080)
    assert scaled["restricted_lane_zones"][0]["polygon"] == drawn[0]["polygon"] and len(scaled["restricted_lane_zones"]) == 1
    assert not run(scaled["restricted_lane_zones"], "car")           # the car drives far from that corner


def test_the_rule_does_nothing_when_it_is_not_switched_on():
    assert pipeline(["counterflow"], {"allowed_classes": ["bus"]})._get_scaled_rois(1920, 1080)["restricted_lane_zones"] == []


# ─── signs ──────────────────────────────────────────────────────────────────

def test_the_signs_say_who_may_use_the_road():
    assert lane_signs.SIGNS["bus_only"]["allowed"] == ["bus"]
    assert "truck" not in lane_signs.SIGNS["no_trucks"]["allowed"] and "car" in lane_signs.SIGNS["no_trucks"]["allowed"]
    assert lane_signs.allowed_by(["bus_only", "motorcycle_only"]) == ["bus", "motorcycle"]
    assert all(set(spec["allowed"]) <= set(lane_signs.VEHICLE_TYPES) for spec in lane_signs.SIGNS.values())


def test_unknown_or_broken_signs_are_skipped():
    plain = {**sign("bus_only", 5.0, 6.0), "scale": 1.0, "angle": 0.0, "tilt": 0.0}                    # an upright sign of normal size
    assert lane_signs.usable_signs([sign("bus_only", 5, 6), sign("flying_only", 1, 1), {"type": "bus_only"}, "junk", None]) == [plain]
    assert lane_signs.usable_signs(None) == []


def test_a_sign_inside_a_drawn_zone_sets_that_zones_rule_and_travels_with_it():
    cfg = {"allowed_classes": ["bus"], "rois": [{"polygon": LEFT}, {"polygon": RIGHT}, {"polygon": None}],
           "signs": [sign("motorcycle_only", 500, 500), sign("bus_only", 1500, 500), sign("no_trucks", 5000, 5000)]}
    left, right = LANE.from_wizard(cfg)
    assert left["allowed_classes"] == ["motorcycle"] and left["sign_types"] == ["motorcycle_only"] and left["sign_points"] == [[500.0, 500.0]]
    assert right["allowed_classes"] == ["bus"] and right["sign_types"] == ["bus_only"]
    assert [LANE.parse_zone(z)["allowed_classes"] for z in (left, right)] == [["motorcycle"], ["bus"]]


def test_a_zone_without_a_sign_keeps_the_tick_boxes_and_the_old_shape():
    cfg = {"allowed_classes": ["bus", "car"], "rois": [{"polygon": LEFT}], "signs": [sign("bus_only", 1500, 500)]}   # the sign is on another road
    assert LANE.from_wizard(cfg) == [{"coordinates": LEFT, "allowed_classes": ["bus", "car"]}]
    assert LANE.parse_zone({"coordinates": LEFT, "allowed_classes": ["bus"]}) == {"polygon": LEFT, "allowed_classes": ["bus"]}


def test_several_signs_in_one_zone_allow_what_all_of_them_allow():
    cfg = {"rois": [{"polygon": BIG_ZONE}], "signs": [sign("bus_only", 100, 100), sign("motorcycle_only", 200, 200)]}
    assert LANE.from_wizard(cfg)[0]["allowed_classes"] == ["bus", "motorcycle"]


def test_a_vehicle_follows_the_nearest_sign_when_no_zone_is_drawn():
    cfg = {"allowed_classes": ["bus"], "signs": [sign("bus_only", 480, 540), sign("motorcycle_only", 1440, 540)]}
    (zone,) = pipeline(["restricted_lane"], cfg)._get_scaled_rois(1920, 1080)["restricted_lane_zones"]
    assert not run([zone], "bus", x=300) and run([zone], "motorcycle", x=300)             # left road: bus only
    assert not run([zone], "motorcycle", x=1600) and run([zone], "bus", x=1600)           # right road: motorcycles only


def test_one_sign_covers_the_whole_picture_and_beats_the_tick_boxes():
    (zone,) = pipeline(["restricted_lane"], {"allowed_classes": ["bus"], "signs": [sign("no_trucks", 100, 100)]})._get_scaled_rois(1920, 1080)["restricted_lane_zones"]
    assert not run([zone], "car") and run([zone], "truck")


def test_the_signs_are_moved_onto_the_processed_frame(tmp_path):
    cfg = {"signs": [sign("bus_only", 960, 540)]}
    (zone,) = pipeline(["restricted_lane"], cfg)._get_scaled_rois(960, 540)["restricted_lane_zones"]
    assert zone["signs"][0]["at"] == (480.0, 270.0)
    drawn = [{"coordinates": [[0, 0], [100, 0], [100, 100], [0, 100]], "allowed_classes": ["bus"], "sign_points": [[50, 50]], "sign_types": ["bus_only"]}]
    path = tmp_path / "cfg.json"
    path.write_text(json.dumps({"video_native_width": 1920, "video_native_height": 1080, "regions_of_interest": {"restricted_lane_zones": drawn}}))
    pipe = object.__new__(DecoupledPipeline)
    pipe.rois = pipe._parse_rois(str(path))
    pipe.native_w, pipe.native_h = 1920, 1080
    assert pipe._get_scaled_rois(960, 540)["restricted_lane_zones"][0]["sign_points"] == [[25, 25]]


# ─── drawing ────────────────────────────────────────────────────────────────

def test_a_sign_is_painted_on_the_picture_where_it_was_placed_and_nowhere_else():
    frame = np.zeros((1080, 1920, 3), np.uint8)
    lane_signs.draw_sign(frame, (960, 540), "bus_only")
    assert frame[540, 960 - 40].any() or frame[540, 960].any()
    assert frame[540, 960 - 70:960 + 70].any()
    assert not frame[100, 100].any()
    off = np.zeros((1080, 1920, 3), np.uint8)
    lane_signs.draw_sign(off, (-900, -900), "bus_only")                                  # far outside the picture: nothing, no error
    lane_signs.draw_sign(off, (10, 10), "no_such_sign")
    assert not off.any()


def test_the_lane_paints_its_signs_for_a_drawn_zone_and_for_the_whole_picture():
    frame = np.zeros((1080, 1920, 3), np.uint8)
    drawn = LANE.parse_zone({"coordinates": [[0, 0], [10, 0], [10, 10], [0, 10]], "sign_points": [[960, 540]], "sign_types": ["bus_only"]})
    LANE.draw_zone(None, frame, 0, drawn)
    assert frame[540, 900:1020].any()
    whole = np.zeros((1080, 1920, 3), np.uint8)
    (zone,) = pipeline(["restricted_lane"], {"signs": [sign("puv_only", 400, 300)]})._get_scaled_rois(1920, 1080)["restricted_lane_zones"]
    LANE.draw_zone(None, whole, 0, zone)
    assert whole[300, 340:460].any() and not whole[900, 900].any()
