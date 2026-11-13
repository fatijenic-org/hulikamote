"""
Illegal loading / unloading with overlay signs (engine/loading_signs.py): a sign placed on the picture and resized is a no-loading area.
Scripted vehicles only (no model, no video).
"""
from types import SimpleNamespace

import numpy as np

from engine import loading_signs, overlay_objects
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY, ZONE_RULES
from routers.forensic import prepare_pipeline_config
from tests.helpers import FPS, drive

LOADING = REGISTRY["illegal_loading"]


def sign(x, y, w, h):
    return {"x": x, "y": y, "w": w, "h": h}


def sign_zones(signs, **cfg):
    """The zones the pipeline reads, made the way the dashboard wizard makes them (no drawn zone)."""
    return [LOADING.parse_zone(raw) for raw in LOADING.from_wizard({"rois": [], "signs": signs, **cfg})]


def stands_at(zones, x, y, cls="bus", seconds=12):
    mgr = ActiveLedgerManager()
    return drive(mgr, [(x, y)] * int(seconds * FPS), lambda tid: LOADING.evaluate(mgr, tid, zones), cls=cls)


# ─── what a sign is ─────────────────────────────────────────────────────────

def test_unusable_signs_are_skipped_and_a_tiny_one_is_made_readable():
    raw = [sign(10, 20, 300, 200), {"x": 1, "y": 2}, "junk", None, sign(1, 1, 0, 50), sign(1, 1, -5, 50), sign(float("nan"), 1, 5, 5),
           {"x": "a", "y": 1, "w": 1, "h": 1}, sign(500, 500, 3, 4)]
    signs = loading_signs.usable_signs(raw)
    assert signs[0] == sign(10.0, 20.0, 300.0, 200.0)
    assert len(signs) == 2 and signs[1]["w"] == loading_signs.MIN_SIDE and signs[1]["h"] == loading_signs.MIN_SIDE
    assert loading_signs.usable_signs(None) == []


def test_the_sign_box_is_the_zone_polygon():
    assert loading_signs.polygon(sign(500, 400, 200, 100)) == [[400, 350], [600, 350], [600, 450], [400, 450]]


def test_a_sign_becomes_a_zone_with_the_same_time_limit_and_vehicle_types_as_a_drawn_one():
    drawn = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]]}]
    raw = LOADING.from_wizard({"rois": drawn, "signs": [sign(500, 400, 200, 100)], "time_limit": 5, "banned_classes": ["bus"]})
    assert len(raw) == 2 and not raw[0].get("sign") and raw[1]["sign"] is True
    zones = [LOADING.parse_zone(r) for r in raw]
    assert zones[1]["polygon"] == loading_signs.polygon(sign(500, 400, 200, 100))
    assert zones[0]["time_limit"] == zones[1]["time_limit"] == 5.0 and zones[0]["classes"] == zones[1]["classes"] == ["bus"]
    assert zones[1]["sign"] is True and "sign" not in zones[0]


def test_without_signs_nothing_changes():
    raw = LOADING.from_wizard({"rois": [{"polygon": [[0, 0], [10, 0], [10, 10]]}]})
    assert len(raw) == 1 and "sign" not in raw[0]
    assert LOADING.from_wizard({"rois": []}) == []


# ─── the sign's box is where loading is banned ──────────────────────────────

def test_a_bus_standing_inside_a_sign_is_flagged_and_one_outside_is_not():
    zones = sign_zones([sign(600, 600, 300, 200)])
    assert stands_at(zones, 600, 650)                    # inside the box (its ground point is at the bottom of the vehicle)
    assert not stands_at(zones, 1200, 650)               # the same bus further along the road


def test_a_car_standing_in_a_sign_is_not_flagged_that_is_parking():
    assert not stands_at(sign_zones([sign(600, 600, 300, 200)]), 600, 650, cls="car")


def test_resizing_the_sign_changes_where_loading_is_banned():
    small, wide = sign(600, 600, 200, 200), sign(600, 600, 900, 200)
    assert not stands_at(sign_zones([small]), 1000, 650)
    assert stands_at(sign_zones([wide]), 1000, 650)


def test_two_signs_are_two_places_and_each_one_works():
    zones = sign_zones([sign(300, 300, 200, 200), sign(1500, 800, 200, 200)])
    assert stands_at(zones, 300, 350) and stands_at(zones, 1500, 850) and not stands_at(zones, 900, 500)


def test_a_short_stop_in_a_sign_is_allowed_and_the_signs_own_time_limit_is_used():
    zones = sign_zones([sign(600, 600, 300, 200)], time_limit=20)
    assert not stands_at(zones, 600, 650, seconds=12)    # 12 s is inside the 20 s limit
    assert stands_at(zones, 600, 650, seconds=25)


# ─── in the pipeline ────────────────────────────────────────────────────────

def pipeline(zones, flow_mode="zones", cfg=None):
    pipe = object.__new__(DecoupledPipeline)             # skip model loading
    pipe.rois = {key: [] for key in ZONE_RULES.values()}
    pipe.rois["loading_zones"] = zones
    pipe.native_w, pipe.native_h = 1920, 1080
    pipe.registry = SimpleNamespace(active_violations=["illegal_loading"])
    pipe.violation_cfg = {"illegal_loading": cfg or {}}
    pipe.flow_mode = flow_mode
    pipe.flow = None
    return pipe


def test_a_sign_is_scaled_to_the_frame_like_a_drawn_zone_and_replaces_the_whole_picture_zone():
    zones = sign_zones([sign(960, 540, 400, 200)])
    for mode in ("zones", "auto"):
        (zone,) = pipeline(zones, flow_mode=mode)._get_scaled_rois(960, 540)["loading_zones"]
        assert zone["polygon"] == [[380, 220], [580, 220], [580, 320], [380, 320]]
        assert zone["sign"] is True and not zone.get("whole_frame")


def test_with_no_zone_and_no_sign_the_whole_picture_is_watched():
    for mode in ("zones", "auto"):
        (zone,) = pipeline([], flow_mode=mode)._get_scaled_rois(960, 540)["loading_zones"]
        assert zone["whole_frame"] is True


def test_the_wizard_payload_carries_signs_into_the_saved_rules():
    config = prepare_pipeline_config({"per_violation_configs": {"illegal_loading": {"rois": [], "signs": [sign(960, 540, 400, 200)], "time_limit": 6}}})
    (raw,) = config["regions_of_interest"]["loading_zones"]
    assert raw["sign"] is True and raw["time_limit"] == 6.0 and raw["coordinates"][0] == [760.0, 440.0]


# ─── drawing ────────────────────────────────────────────────────────────────

def test_the_plate_stands_in_the_box_and_the_rest_of_the_picture_is_left_alone():
    frame = np.full((540, 960, 3), 120, dtype=np.uint8)
    original = frame.copy()
    (zone,) = sign_zones([sign(480, 270, 400, 200)])                                         # box x 280..680, y 170..370, plate on a pole at (480, 270)
    LOADING.draw_zone(None, frame, 0, zone)
    changed = np.argwhere((frame != original).any(axis=2))
    assert len(changed) > 0
    assert changed[:, 1].min() >= 280 - 6 and changed[:, 1].max() <= 680 + 6 and changed[:, 0].max() <= 370 + 6 and changed[:, 0].min() >= 270 - 200
    assert (frame[0, 0] == original[0, 0]).all()
    assert (frame[200, 300] != original[200, 300]).any()                                        # the area is tinted
    assert (frame[220:268, 480] != original[220:268, 480]).any()                                # the pole stands at the middle of the box


def test_drawing_never_fails_for_a_sign_partly_or_wholly_off_the_picture_or_very_small():
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    for polygon, points in ((loading_signs.polygon(sign(-50, 50, 300, 300)), [[-50, 50]]), (loading_signs.polygon(sign(500, 500, 40, 40)), [[500, 500]]),
                            (loading_signs.polygon(sign(50, 50, 24, 24)), [[50, 50]]), ([[10, 10], [12, 12]], [[11, 11]]), ([], None)):
        overlay_objects.draw_zone_object(frame, {"polygon": polygon, "sign_points": points}, "no_loading")


def test_a_sign_carries_its_look_and_an_older_zone_without_one_gets_the_plain_look():
    (zone,) = sign_zones([{**sign(960, 540, 400, 200), "scale": 2.5, "angle": 12, "tilt": -20, "stand": "tripod"}])
    assert zone["sign_points"] == [[960.0, 540.0]]
    assert zone["look"] == {"scale": 2.5, "angle": 12.0, "tilt": -20.0, "stand": "tripod"} and zone["realistic"] is True
    older = LOADING.parse_zone({"coordinates": loading_signs.polygon(sign(500, 400, 200, 100)), "sign": True})
    assert older["sign_points"] == [[500.0, 400.0]] and older["look"]["stand"] == "post" and older["look"]["scale"] == 1.0
    (flat,) = [LOADING.parse_zone(r) for r in LOADING.from_wizard({"rois": [], "signs": [sign(500, 400, 200, 100)], "signs_realistic": False})]
    assert flat["realistic"] is False


def test_the_violation_draws_a_sign_zone_as_a_sign_and_a_drawn_zone_as_an_outline():
    shape = (540, 960, 3)
    signed, outlined = np.zeros(shape, dtype=np.uint8), np.zeros(shape, dtype=np.uint8)
    (sign_zone,) = sign_zones([sign(480, 270, 400, 200)])
    LOADING.draw_zone(None, signed, 0, sign_zone)
    LOADING.draw_zone(SimpleNamespace(), outlined, 0, {"polygon": sign_zone["polygon"]})
    assert (signed[200, 400] != 0).any()                  # the tint inside the box
    assert (outlined[200, 400] == 0).all()                # an outline only touches the edge
