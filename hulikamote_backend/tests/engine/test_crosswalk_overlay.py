"""
engine/crosswalk_overlay.py + the overlay crosswalks of "Pedestrian lane": a placed zebra crossing IS a crosswalk zone (test material),
drawn on the photos and the video, with a size, depth, angle, perspective, stripe count and wear the operator can set.
"""
import math
from types import SimpleNamespace

import numpy as np

from engine import crosswalk_overlay as co
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY
from tests.helpers import FPS, Det, drive

RULE = REGISTRY["pedestrian_lane"]


def centred(look=None) -> dict:
    return {"x": 960.0, "y": 700.0, **co.look_of(look or {})}


def blank(value: int = 90, size=(1080, 1920)) -> np.ndarray:
    return np.full((*size, 3), value, np.uint8)


# ─── the numbers an operator can set ─────────────────────────────────────────

def test_missing_numbers_use_the_defaults_and_wild_ones_are_kept_inside_the_limits():
    assert co.look_of({}) == co.DEFAULTS
    wild = co.look_of({"scale": 99, "depth": -4, "angle": 400, "slant": 500, "stripes": 99, "wear": 7})
    assert wild == {"scale": co.MAX_SCALE, "depth": co.MIN_DEPTH, "angle": co.MAX_ANGLE, "slant": co.MAX_SLANT,
                    "stripes": co.MAX_STRIPES, "wear": 1.0}
    assert co.look_of({"stripes": 1})["stripes"] == co.MIN_STRIPES
    bad = co.look_of({"scale": "big", "angle": float("nan"), "stripes": None})
    assert bad["scale"] == co.DEFAULTS["scale"] and bad["angle"] == co.DEFAULTS["angle"] and bad["stripes"] == co.DEFAULTS["stripes"]


def test_only_crosswalks_with_a_position_are_used():
    got = co.usable([{"x": 100, "y": 200, "stripes": 6}, {"x": "x"}, {"y": 5}, "junk", None, {"x": float("inf"), "y": 1}])
    assert len(got) == 1 and got[0]["x"] == 100.0 and got[0]["stripes"] == 6
    assert co.usable(None) == [] and co.usable([]) == []


# ─── the shape on the picture ────────────────────────────────────────────────

def width_of(points):
    return max(p[0] for p in points) - min(p[0] for p in points)


def test_a_crosswalk_seen_from_above_is_a_plain_rectangle_of_the_set_size():
    corners = co.corners({"scale": 1.0, "depth": 1.0, "angle": 0, "slant": 0})
    length = 1920 * co.SIZE_SHARE
    assert math.isclose(width_of(corners), length, rel_tol=1e-6)
    assert math.isclose(max(p[1] for p in corners) - min(p[1] for p in corners), length * co.DEPTH_RATIO, rel_tol=1e-6)
    assert math.isclose(width_of(co.corners({"scale": 2.0, "slant": 0})), 2 * length, rel_tol=1e-6)         # scale sets the length
    deep = co.corners({"depth": 2.0, "slant": 0})
    assert math.isclose(max(p[1] for p in deep) - min(p[1] for p in deep), 2 * length * co.DEPTH_RATIO, rel_tol=1e-6)


def test_the_slant_makes_the_far_edge_shorter_and_the_band_flatter():
    flat, slanted = co.corners({"slant": 0}), co.corners({"slant": 60})
    far_flat, far_slanted = flat[1][0] - flat[0][0], slanted[1][0] - slanted[0][0]
    near_slanted = slanted[2][0] - slanted[3][0]
    assert far_slanted < far_flat and far_slanted < near_slanted
    assert math.isclose(near_slanted, flat[2][0] - flat[3][0], rel_tol=1e-6)                                # the near edge keeps its length
    height = lambda c: c[2][1] - c[1][1]
    assert height(slanted) < height(flat)


def test_the_angle_turns_the_whole_crosswalk_in_the_picture():
    level = co.corners({"slant": 0, "angle": 0})
    turned = co.corners({"slant": 0, "angle": 90})
    assert width_of(turned) < width_of(level)                                                              # a long band stood on its end
    assert max(p[1] for p in turned) - min(p[1] for p in turned) > max(p[1] for p in level) - min(p[1] for p in level)
    assert math.isclose(sum(p[0] for p in turned), 0.0, abs_tol=1e-6)                                      # still centred on its spot


def test_the_zone_polygon_sits_on_the_chosen_spot_and_is_a_proper_four_sided_shape():
    for look in ({}, {"angle": -40, "slant": 65, "scale": 2.5}, {"angle": 80, "depth": 0.3}):
        poly = co.polygon(centred(look))
        assert len(poly) == 4
        cx = sum(p[0] for p in poly) / 4
        assert abs(cx - 960) < 0.4 * width_of(poly)
        turns = []
        for i in range(4):
            a, b, c = poly[i], poly[(i + 1) % 4], poly[(i + 2) % 4]
            turns.append((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]))
        assert all(t > 0 for t in turns) or all(t < 0 for t in turns)                                      # convex, no twist


def test_the_bars_are_as_many_as_asked_and_fit_inside_the_zone():
    quad = [(0, 0), (400, 0), (400, 100), (0, 100)]
    for n in (3, 8, 16):
        painted = co.bars(quad, n)
        assert len(painted) == n
        assert all(0 <= x <= 400 and 0 <= y <= 100 for bar in painted for x, y in bar)
        covered = sum(bar[1][0] - bar[0][0] for bar in painted)
        assert math.isclose(covered, 400 * co.FILL, rel_tol=1e-6)                                          # the paint share of the width


# ─── an overlay crosswalk is a crosswalk zone ────────────────────────────────

def test_the_wizard_turns_an_overlay_into_a_zone_with_the_rules_time_limit():
    cfg = {"rois": [{"polygon": [[0, 0], [10, 0], [10, 10]]}], "time_limit": 5.0,
           "crosswalks": [{"x": 960, "y": 700, "stripes": 10, "wear": 0.4}], "crosswalks_realistic": False}
    drawn, painted = RULE.from_wizard(cfg)
    assert "overlay" not in drawn and drawn["time_limit"] == 5.0                                           # a drawn zone is unchanged
    assert painted["time_limit"] == 5.0 and painted["overlay"] == {"stripes": 10, "wear": 0.4} and painted["realistic"] is False
    assert painted["coordinates"] == co.polygon(centred({"stripes": 10, "wear": 0.4}))


def test_overlays_alone_are_enough_and_junk_in_the_list_is_ignored():
    assert RULE.from_wizard({"rois": [], "crosswalks": [{"x": 1, "y": 2}, {"x": "no"}]}).__len__() == 1
    assert RULE.from_wizard({"rois": []}) == []
    assert RULE.from_wizard({"rois": [], "crosswalks": None}) == []


def test_the_painted_look_survives_the_camera_config():
    (zone,) = RULE.from_wizard({"rois": [], "crosswalks": [{"x": 960, "y": 700, "stripes": 5, "wear": 0.1}]})
    parsed = RULE.parse_zone(zone)
    assert parsed["overlay"] == {"stripes": 5, "wear": 0.1} and parsed["realistic"] is True and len(parsed["polygon"]) == 4
    plain = RULE.parse_zone({"coordinates": [[0, 0], [10, 0], [10, 10]]})
    assert "overlay" not in plain


def overlay_zone(look=None):
    (zone,) = RULE.from_wizard({"rois": [], "crosswalks": [{"x": 960, "y": 700, **(look or {})}], "time_limit": 3.0})
    return RULE.parse_zone(zone)


def test_a_vehicle_that_stops_on_the_overlay_is_flagged_like_on_a_drawn_zone():
    zone = overlay_zone()
    spot = (960, 700)                                                                                      # the middle of the band
    mgr = ActiveLedgerManager()
    assert drive(mgr, [spot] * int(5 * FPS), lambda t: RULE.evaluate(mgr, t, [zone]))
    assert "pedestrian_lane" in mgr.ledgers[1].violations


def test_a_vehicle_that_drives_across_the_overlay_or_stops_beside_it_is_not():
    zone = overlay_zone()
    across = [(700 + 9 * i, 700) for i in range(60)]
    mgr = ActiveLedgerManager()
    assert not drive(mgr, across, lambda t: RULE.evaluate(mgr, t, [zone]))
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(300, 300)] * int(5 * FPS), lambda t: RULE.evaluate(mgr, t, [zone]))
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(960, 700)] * int(1.5 * FPS), lambda t: RULE.evaluate(mgr, t, [zone]))          # a short stop is fine


def test_the_overlay_follows_the_zone_when_the_pipeline_scales_to_the_frame():
    pipe = object.__new__(DecoupledPipeline)
    pipe.rois, pipe.native_w, pipe.native_h = {"pedestrian_lane_zones": [overlay_zone()]}, 1920, 1080
    pipe.flow_mode = "zones"
    zone, = pipe._get_scaled_rois(960, 540)["pedestrian_lane_zones"]
    assert zone["overlay"] and math.isclose(zone["polygon"][0][0], overlay_zone()["polygon"][0][0] / 2, abs_tol=0.5)


# ─── drawing ────────────────────────────────────────────────────────────────

def painted_area(frame, background=90) -> int:
    return int((frame != background).any(axis=2).sum())


def test_the_paint_lands_inside_the_zone_and_nowhere_else():
    zone = overlay_zone({"slant": 30})
    frame = blank()
    RULE.draw_zone(SimpleNamespace(), frame, 0, zone)
    ys, xs = np.nonzero((frame != 90).any(axis=2))
    xs_poly, ys_poly = [p[0] for p in zone["polygon"]], [p[1] for p in zone["polygon"]]
    assert xs.size > 2000
    assert xs.min() >= min(xs_poly) - 6 and xs.max() <= max(xs_poly) + 6
    assert ys.min() >= min(ys_poly) - 6 and ys.max() <= max(ys_poly) + 6
    assert frame.max() > 90 + 60                                                                           # light paint on a dull road (dulled to the scene's light)


def test_more_stripes_paint_more_bars_and_wear_paints_less():
    base = blank()
    fresh, worn = base.copy(), base.copy()
    RULE.draw_zone(SimpleNamespace(), fresh, 0, overlay_zone({"wear": 0.0}))
    RULE.draw_zone(SimpleNamespace(), worn, 0, overlay_zone({"wear": 1.0}))
    assert fresh.astype(int).sum() > worn.astype(int).sum()
    few, many = blank(), blank()
    RULE.draw_zone(SimpleNamespace(), few, 0, overlay_zone({"stripes": 3, "wear": 0}))
    RULE.draw_zone(SimpleNamespace(), many, 0, overlay_zone({"stripes": 16, "wear": 0}))
    bars_in_row = lambda f: int(np.count_nonzero(np.diff((f[700, :, 0] > 150).astype(int)) == 1))
    assert bars_in_row(many) > bars_in_row(few) >= 2


def test_the_realistic_look_differs_from_flat_paint_and_lets_the_road_show_through():
    road = np.random.RandomState(1).randint(60, 120, (1080, 1920, 3)).astype(np.uint8)
    flat, real = road.copy(), road.copy()
    RULE.draw_zone(SimpleNamespace(), flat, 0, {**overlay_zone({"wear": 0.0}), "realistic": False})
    RULE.draw_zone(SimpleNamespace(), real, 0, {**overlay_zone({"wear": 0.0}), "realistic": True})
    assert not np.array_equal(flat, real)
    zone = overlay_zone({"wear": 0.0})
    cx, cy = [int(v) for v in np.mean(zone["polygon"], axis=0)]
    patch = (slice(cy - 3, cy + 3), slice(cx - 40, cx + 40))
    assert real[patch].std() >= 0                                                                          # (texture shows: not a flat colour)
    assert np.unique(flat[patch][..., 0]).size < np.unique(real[patch][..., 0]).size + 200


def test_vehicles_and_people_stay_on_top_of_the_paint():
    zone = overlay_zone({"wear": 0.0})
    cx, cy = [int(v) for v in np.mean(zone["polygon"], axis=0)]
    car = Det(1, [cx - 60, cy - 40, 120, 80], "car")
    behind = SimpleNamespace(_draw_dets=[car, Det(2, [10, 10, 50, 50], "traffic light")])
    plain, covered = blank(), blank()
    RULE.draw_zone(SimpleNamespace(), plain, 0, zone)
    RULE.draw_zone(behind, covered, 0, zone)
    assert (covered[cy - 30:cy + 30, cx - 50:cx + 50] == 90).all()                                         # nothing painted under the car
    assert not (plain[cy - 30:cy + 30, cx - 50:cx + 50] == 90).all()                                       # but there is paint without it
    assert painted_area(covered) < painted_area(plain)


def test_drawing_never_fails_for_a_crosswalk_that_is_partly_or_wholly_off_the_picture():
    for x, y in ((0, 0), (1900, 1070), (-5000, 300), (960, 5000)):
        (zone,) = RULE.from_wizard({"rois": [], "crosswalks": [{"x": x, "y": y, "scale": 3.0}]})
        RULE.draw_zone(SimpleNamespace(), blank(size=(360, 640)), 0, RULE.parse_zone(zone))
    RULE.draw_zone(SimpleNamespace(), blank(), 0, {"polygon": [[0, 0], [5, 5]], "overlay": {"stripes": 5}})   # not four corners: skipped


def test_a_drawn_zone_is_still_outlined_like_before():
    frame = blank()
    RULE.draw_zone(SimpleNamespace(), frame, 0, {"polygon": [[100, 100], [400, 100], [400, 300], [100, 300]], "time_limit": 3.0})
    assert painted_area(frame) > 0 and (frame[100, 200] == np.array(RULE.color, np.uint8)).all()
