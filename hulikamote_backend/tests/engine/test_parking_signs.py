"""
Illegal parking with overlay "NO PARKING" signs (box signs, engine/loading_signs.py): a sign placed on the picture and resized is a
no-parking area. Scripted vehicles only (no model, no video).
"""
from types import SimpleNamespace

import numpy as np

from engine import loading_signs, parking_reasons
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY, ZONE_RULES
from routers.forensic import prepare_pipeline_config
from tests.helpers import FPS, drive

PARKING = REGISTRY["illegal_parking"]


def sign(x, y, w, h):
    return {"x": x, "y": y, "w": w, "h": h}


def sign_zones(signs, **cfg):
    """The zones the pipeline reads, made the way the dashboard wizard makes them (no drawn zone)."""
    return [PARKING.parse_zone(raw) for raw in PARKING.from_wizard({"rois": [], "signs": signs, **cfg})]


def stands_at(zones, x, y, cls="car", seconds=12):
    mgr = ActiveLedgerManager()
    return drive(mgr, [(x, y)] * int(seconds * FPS), lambda tid: PARKING.evaluate(mgr, tid, zones), cls=cls)


# ─── what a sign becomes ────────────────────────────────────────────────────

def test_a_sign_becomes_a_zone_with_the_rules_time_limit():
    drawn = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]]}]
    raw = PARKING.from_wizard({"rois": drawn, "signs": [sign(500, 400, 200, 100)], "time_limit": 5})
    assert len(raw) == 2 and not raw[0].get("sign") and raw[1]["sign"] is True
    zones = [PARKING.parse_zone(r) for r in raw]
    assert zones[1]["polygon"] == loading_signs.polygon(sign(500, 400, 200, 100))
    assert zones[0]["time_limit"] == zones[1]["time_limit"] == 5.0
    assert zones[1]["sign"] is True and "sign" not in zones[0]


def test_unusable_signs_are_skipped():
    assert PARKING.from_wizard({"rois": [], "signs": [{"x": 1}, "junk", None, sign(1, 1, 0, 5)]}) == []


def test_without_signs_nothing_changes():
    raw = PARKING.from_wizard({"rois": [{"polygon": [[0, 0], [10, 0], [10, 10]]}], "time_limit": 7})
    assert raw == [{"coordinates": [[0, 0], [10, 0], [10, 10]], "time_limit": 7.0}]
    assert PARKING.from_wizard({"rois": []}) == []
    assert "sign" not in PARKING.parse_zone({"coordinates": [[0, 0], [1, 0], [1, 1]]})


# ─── the sign's box is where parking is banned ──────────────────────────────

def test_a_car_standing_inside_a_sign_is_flagged_and_one_outside_is_not():
    zones = sign_zones([sign(600, 600, 300, 200)])
    assert stands_at(zones, 600, 650)                    # inside the box (the ground point is at the bottom of the vehicle)
    assert not stands_at(zones, 1200, 650)               # the same car further along the road


def test_every_kind_of_vehicle_is_judged():
    zones = sign_zones([sign(600, 600, 300, 200)])
    for cls in ("car", "motorcycle", "truck", "bus"):
        assert stands_at(zones, 600, 650, cls=cls), cls


def test_a_car_driving_through_the_sign_is_not_flagged():
    zones = sign_zones([sign(600, 600, 300, 200)])
    mgr = ActiveLedgerManager()
    path = [(300 + 20 * i, 650) for i in range(80)]      # 200 px per second: far above the stopped speed
    assert not drive(mgr, path, lambda tid: PARKING.evaluate(mgr, tid, zones))


def test_resizing_the_sign_changes_where_parking_is_banned():
    small, wide = sign(600, 600, 200, 200), sign(600, 600, 900, 200)
    assert not stands_at(sign_zones([small]), 1000, 650)
    assert stands_at(sign_zones([wide]), 1000, 650)


def test_two_signs_are_two_places_and_each_one_works():
    zones = sign_zones([sign(300, 300, 200, 200), sign(1500, 800, 200, 200)])
    assert stands_at(zones, 300, 350) and stands_at(zones, 1500, 850) and not stands_at(zones, 900, 500)


def test_a_short_stop_in_a_sign_is_allowed_and_the_rules_time_limit_is_used():
    zones = sign_zones([sign(600, 600, 300, 200)], time_limit=20)
    assert not stands_at(zones, 600, 650, seconds=12)    # 12 s is inside the 20 s limit
    assert stands_at(zones, 600, 650, seconds=25)


# ─── why parking is banned there (RA 4136 Section 46) ───────────────────────

def test_a_sign_says_why_and_an_unknown_or_missing_kind_is_an_official_sign():
    kinds = ["hydrant", "fire_station", "corner", "driveway", "sign", "nonsense", None]
    raw = PARKING.from_wizard({"rois": [], "signs": [{**sign(100 + 50 * i, 100, 40, 40), **({"kind": k} if k else {})} for i, k in enumerate(kinds)]})
    assert [z["reason"] for z in raw] == ["hydrant", "fire_station", "corner", "driveway", "sign", "sign", "sign"]
    assert [PARKING.parse_zone(z)["reason"] for z in raw] == [z["reason"] for z in raw]


def test_a_drawn_zone_has_no_reason_and_the_kind_survives_usable_signs():
    (raw,) = PARKING.from_wizard({"rois": [{"polygon": [[0, 0], [10, 0], [10, 10]]}]})
    assert "reason" not in raw and "reason" not in PARKING.parse_zone(raw)
    assert loading_signs.usable_signs([{**sign(1, 1, 50, 50), "kind": "hydrant"}])[0]["kind"] == "hydrant"
    assert "kind" not in loading_signs.usable_signs([sign(1, 1, 50, 50)])[0]


def test_the_wizard_payload_carries_the_kind_into_the_saved_rules():
    cfg = {"per_violation_configs": {"illegal_parking": {"rois": [], "signs": [{**sign(960, 540, 400, 200), "kind": "corner"}], "time_limit": 6}}}
    (raw,) = prepare_pipeline_config(cfg)["regions_of_interest"]["illegal_parking_zones"]
    assert raw["reason"] == "corner"


def test_the_five_places_marked_on_the_picture_are_the_section_46_items_c_d_e_f_h_with_their_distances():
    r = parking_reasons.REASONS
    assert {k: v["item"] for k, v in r.items()} == {"hydrant": "e", "fire_station": "d", "corner": "c", "driveway": "f", "sign": "h"}
    assert (r["hydrant"]["meters"], r["fire_station"]["meters"], r["corner"]["meters"]) == (4, 4, 6)
    assert all(len(v["lines"]) == 2 and v["mark"] and v["label"] for v in r.values())


def test_the_other_three_items_are_judged_by_rules_that_exist():
    assert [item for item, _text, _rule in parking_reasons.OTHER_RULES] == ["a", "b", "g"]
    for _item, _text, rule in parking_reasons.OTHER_RULES:
        assert rule in REGISTRY


def test_each_kind_draws_its_own_words():
    frames = {}
    for kind in parking_reasons.REASONS:
        frame = np.full((540, 960, 3), 120, dtype=np.uint8)
        (zone,) = [PARKING.parse_zone(z) for z in PARKING.from_wizard({"rois": [], "signs": [{**sign(480, 270, 400, 200), "kind": kind}]})]
        PARKING.draw_zone(None, frame, 0, zone)
        frames[kind] = frame
    kinds = list(frames)
    for i, a in enumerate(kinds):
        for b in kinds[i + 1:]:
            assert (frames[a] != frames[b]).any(), (a, b)


def test_a_flagged_vehicle_carries_the_reason_on_its_evidence_and_an_unflagged_one_does_not():
    zones = sign_zones([{**sign(600, 600, 300, 200), "kind": "hydrant"}])
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(600, 650)] * int(12 * FPS), lambda tid: PARKING.evaluate(mgr, tid, zones))
    ledger = mgr.ledgers[1]
    ((_rel, label, _colour),) = ledger.marks["illegal_parking"]["items"]
    assert label == "Within 4 m of fire hydrant"
    quick = ActiveLedgerManager()
    assert not drive(quick, [(600, 650)] * int(3 * FPS), lambda tid: PARKING.evaluate(quick, tid, zones))
    assert "illegal_parking" not in quick.ledgers[1].marks


def test_a_zone_without_a_reason_flags_without_a_label():
    mgr = ActiveLedgerManager()
    zones = [PARKING.parse_zone(z) for z in PARKING.from_wizard({"rois": [{"polygon": [[0, 0], [2000, 0], [2000, 2000], [0, 2000]]}]})]
    assert drive(mgr, [(600, 650)] * int(12 * FPS), lambda tid: PARKING.evaluate(mgr, tid, zones))
    assert "illegal_parking" not in mgr.ledgers[1].marks


# ─── in the pipeline ────────────────────────────────────────────────────────

def pipeline(zones, flow_mode="zones", cfg=None):
    pipe = object.__new__(DecoupledPipeline)             # skip model loading
    pipe.rois = {key: [] for key in ZONE_RULES.values()}
    pipe.rois["illegal_parking_zones"] = zones
    pipe.native_w, pipe.native_h = 1920, 1080
    pipe.registry = SimpleNamespace(active_violations=["illegal_parking"])
    pipe.violation_cfg = {"illegal_parking": cfg or {}}
    pipe.flow_mode = flow_mode
    pipe.flow = None
    return pipe


def test_a_sign_is_scaled_to_the_frame_like_a_drawn_zone_and_replaces_the_whole_picture_zone():
    zones = sign_zones([sign(960, 540, 400, 200)])
    for mode in ("zones", "auto"):
        (zone,) = pipeline(zones, flow_mode=mode)._get_scaled_rois(960, 540)["illegal_parking_zones"]
        assert zone["polygon"] == [[380, 220], [580, 220], [580, 320], [380, 320]]
        assert zone["sign"] is True and not zone.get("whole_frame")


def test_with_no_zone_and_no_sign_the_whole_picture_is_watched():
    for mode in ("zones", "auto"):
        (zone,) = pipeline([], flow_mode=mode)._get_scaled_rois(960, 540)["illegal_parking_zones"]
        assert zone["whole_frame"] is True


def test_the_wizard_payload_carries_signs_into_the_saved_rules():
    config = prepare_pipeline_config({"per_violation_configs": {"illegal_parking": {"rois": [], "signs": [sign(960, 540, 400, 200)], "time_limit": 6}}})
    (raw,) = config["regions_of_interest"]["illegal_parking_zones"]
    assert raw["sign"] is True and raw["time_limit"] == 6.0 and raw["coordinates"][0] == [760.0, 440.0]


# ─── drawing ────────────────────────────────────────────────────────────────

def test_the_object_stands_in_the_box_and_the_rest_of_the_picture_is_left_alone():
    frame = np.full((540, 960, 3), 120, dtype=np.uint8)
    original = frame.copy()
    (zone,) = sign_zones([sign(480, 270, 400, 200)])                                         # box x 280..680, y 170..370, sign on a pole at (480, 270)
    PARKING.draw_zone(None, frame, 0, zone)
    changed = np.argwhere((frame != original).any(axis=2))
    assert len(changed) > 0
    assert changed[:, 1].min() >= 280 - 6 and changed[:, 1].max() <= 680 + 6 and changed[:, 0].max() <= 370 + 6 and changed[:, 0].min() >= 270 - 200
    assert (frame[0, 0] == original[0, 0]).all()
    assert (frame[200, 300] != original[200, 300]).any()                                        # the area is tinted
    assert (frame[220:268, 480] != original[220:268, 480]).any()                                # the pole stands at the middle of the box


def test_a_hydrant_is_a_red_object_with_no_pole_and_a_sign_stands_on_a_pole():
    hydrant, sign_on_pole = (np.full((540, 960, 3), 120, dtype=np.uint8) for _ in range(2))
    (h_zone,) = sign_zones([{**sign(480, 300, 400, 200), "kind": "hydrant"}])
    (s_zone,) = sign_zones([{**sign(480, 300, 400, 200), "kind": "sign"}])
    PARKING.draw_zone(None, hydrant, 0, h_zone)
    PARKING.draw_zone(None, sign_on_pole, 0, s_zone)
    patch = hydrant[270:300, 465:495].reshape(-1, 3).astype(int)
    assert (patch[:, 2] > patch[:, 0] + 60).any()                                                # red: much more red than blue
    assert h_zone["look"]["stand"] == "none" and s_zone["look"]["stand"] == "post"
    assert (hydrant != sign_on_pole).any()


def test_the_look_of_a_box_changes_what_is_drawn():
    base = np.full((540, 960, 3), 120, dtype=np.uint8)
    frames = {}
    for name, extra in (("plain", {}), ("big", {"scale": 2.0}), ("turned", {"angle": 25}), ("away", {"tilt": 40}), ("tripod", {"stand": "tripod"})):
        frame = base.copy()
        (zone,) = sign_zones([{**sign(480, 300, 400, 200), "kind": "sign", **extra}])
        PARKING.draw_zone(None, frame, 0, zone)
        frames[name] = frame
    for name in ("big", "turned", "away", "tripod"):
        assert (frames[name] != frames["plain"]).any(), name


def test_a_sign_zone_is_drawn_as_a_sign_and_a_drawn_zone_as_an_outline():
    shape = (540, 960, 3)
    signed, outlined = np.zeros(shape, dtype=np.uint8), np.zeros(shape, dtype=np.uint8)
    (sign_zone,) = sign_zones([sign(480, 270, 400, 200)])
    PARKING.draw_zone(None, signed, 0, sign_zone)
    PARKING.draw_zone(SimpleNamespace(), outlined, 0, {"polygon": sign_zone["polygon"]})
    assert (signed[200, 400] != 0).any()                  # the tint inside the box
    assert (outlined[200, 400] == 0).all()                # an outline only touches the edge
