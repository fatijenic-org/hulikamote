"""
The look of the overlay signs: size, angle (in the picture), tilt (turned away from the camera) and the realistic filter (engine/lane_signs.py).
Pictures are made of plain grey and measured: no model, no video.
"""
import math

import numpy as np

from engine import lane_signs
from engine.violations import REGISTRY

LANE = REGISTRY["restricted_lane"]
GREY = 128


def frame(brightness=GREY, w=1920, h=1080):
    return np.full((h, w, 3), brightness, np.uint8)


def changed(img, base):
    return (img != base).any(axis=2)


def box_of(mask):
    ys, xs = np.nonzero(mask)
    return xs.min(), ys.min(), xs.max(), ys.max()


def drawn(brightness=GREY, **look):
    base = frame(brightness)
    img = base.copy()
    lane_signs.draw_sign(img, (960, 540), "bus_only", **look)
    return img, base


# ─── what a sign may look like ──────────────────────────────────────────────

def test_a_look_is_kept_inside_what_makes_sense_and_missing_means_plain():
    assert lane_signs.look_of({}) == {"scale": 1.0, "angle": 0.0, "tilt": 0.0}
    assert lane_signs.look_of({"scale": 99, "angle": -500, "tilt": 500}) == {"scale": 3.0, "angle": -90.0, "tilt": 70.0}
    assert lane_signs.look_of({"scale": 0.0001})["scale"] == 0.3
    assert lane_signs.look_of({"scale": "big", "angle": float("nan"), "tilt": None}) == {"scale": 1.0, "angle": 0.0, "tilt": 0.0}


def test_the_look_travels_with_the_sign_from_the_wizard():
    signs = lane_signs.usable_signs([{"type": "no_trucks", "x": 1, "y": 2, "scale": 1.5, "angle": 12, "tilt": -20}])
    assert (signs[0]["scale"], signs[0]["angle"], signs[0]["tilt"]) == (1.5, 12.0, -20.0)


def test_corners_of_a_plain_sign_are_a_rectangle_round_the_spot():
    (tlx, tly), (trx, try_), (brx, bry), (blx, bly) = lane_signs.sign_corners(200)
    assert (tlx, trx, brx, blx) == (-100, 100, 100, -100)
    assert math.isclose(bry - try_, 200 * lane_signs.HEIGHT_RATIO)


def test_angle_turns_the_sign_in_the_picture_clockwise():
    top_left = lane_signs.sign_corners(200, angle=90)[0]
    h = 200 * lane_signs.HEIGHT_RATIO
    assert math.isclose(top_left[0], h / 2, abs_tol=1e-6) and math.isclose(top_left[1], -100, abs_tol=1e-6)


def test_tilt_makes_the_far_edge_smaller_and_the_other_way_round_for_a_negative_tilt():
    def edges(tilt):
        tl, tr, br, bl = lane_signs.sign_corners(200, tilt=tilt)
        return br[1] - tr[1], bl[1] - tl[1]                              # the right and the left edge
    right, left = edges(40)
    assert right < left                                                  # positive: the right edge is farther
    right, left = edges(-40)
    assert right > left
    assert edges(0)[0] == edges(0)[1]


# ─── what is painted ────────────────────────────────────────────────────────

def test_a_bigger_scale_paints_a_bigger_sign():
    small, base = drawn(scale=1.0)
    big, _ = drawn(scale=2.0)
    assert np.count_nonzero(changed(big, base)) > 2.5 * np.count_nonzero(changed(small, base))
    tiny, _ = drawn(scale=0.4)
    assert np.count_nonzero(changed(tiny, base)) < np.count_nonzero(changed(small, base))


def test_the_sign_stays_centred_on_its_spot_whatever_its_size_and_angle():
    for look in ({"scale": 0.5}, {"scale": 2.0}, {"angle": 30}, {"tilt": 25}):
        img, base = drawn(realistic=False, **look)
        x0, y0, x1, y1 = box_of(changed(img, base))
        assert abs((x0 + x1) / 2 - 960) < 0.1 * (x1 - x0) and abs((y0 + y1) / 2 - 540) < 0.1 * (y1 - y0), look


def test_angle_turns_what_is_painted():
    flat, base = drawn(realistic=False)
    turned, _ = drawn(realistic=False, angle=90)
    fx0, fy0, fx1, fy1 = box_of(changed(flat, base))
    tx0, ty0, tx1, ty1 = box_of(changed(turned, base))
    assert (fx1 - fx0) > (fy1 - fy0)                                     # a wide sign ...
    assert (tx1 - tx0) < (ty1 - ty0)                                     # ... turned a quarter is a tall one
    assert abs((fx1 - fx0) - (ty1 - ty0)) < 6


def test_a_tilted_sign_is_narrower_than_a_flat_one():
    flat, base = drawn(realistic=False)
    tilted, _ = drawn(realistic=False, tilt=60)
    assert np.count_nonzero(changed(tilted, base)) < 0.8 * np.count_nonzero(changed(flat, base))


def test_a_sign_partly_off_the_picture_is_cut_not_dropped_and_far_off_is_nothing():
    img = frame()
    lane_signs.draw_sign(img, (0, 0), "bus_only", scale=2.0)
    assert changed(img, frame())[:5, :5].any()
    far = frame()
    lane_signs.draw_sign(far, (50000, 50000), "bus_only", angle=40, tilt=30)
    assert not changed(far, frame()).any()


# ─── the realistic filter ───────────────────────────────────────────────────

def test_the_realistic_look_has_soft_edges_a_shadow_and_a_little_grain_the_flat_one_does_not():
    flat, base = drawn(realistic=False)
    real, _ = drawn(realistic=True)
    # a soft shadow falls on the road below and to the right of the sign: darker than the road, outside the flat sign's footprint
    x0, y0, x1, y1 = box_of(changed(flat, base))
    below = real[y1 + 3, x0 + (x1 - x0) // 2]
    assert below.mean() < GREY and flat[y1 + 3, x0 + (x1 - x0) // 2].mean() == GREY
    # the flat sign is crisp: few different grey values on its edge row; the realistic one is soft and grainy
    assert len(np.unique(real[y0 + 2:y1 - 2, x0 + 4:x1 - 4].reshape(-1, 3), axis=0)) > 3 * len(np.unique(flat[y0 + 2:y1 - 2, x0 + 4:x1 - 4].reshape(-1, 3), axis=0))


def test_the_realistic_sign_follows_the_light_of_the_scene():
    bright, _ = drawn(brightness=235)
    dull, _ = drawn(brightness=25)
    x0, y0, x1, y1 = 940, 520, 980, 560                                  # inside the sign (white text and blue board)
    assert bright[y0:y1, x0:x1].mean() > dull[y0:y1, x0:x1].mean() + 20


def test_drawing_is_the_same_every_time_so_the_video_does_not_flicker():
    a, _ = drawn(angle=12, tilt=15, scale=1.3)
    b, _ = drawn(angle=12, tilt=15, scale=1.3)
    assert np.array_equal(a, b)
    before = lane_signs._sprite.cache_info().hits
    drawn(angle=12, tilt=15, scale=1.3)
    assert lane_signs._sprite.cache_info().hits > before                 # the finished sign is made once and reused on every frame


# ─── through the rule ───────────────────────────────────────────────────────

def test_a_zones_signs_keep_their_look_and_the_realism_switch():
    cfg = {"rois": [{"polygon": [[0, 0], [2000, 0], [2000, 2000], [0, 2000]]}], "signs_realistic": False,
           "signs": [{"type": "bus_only", "x": 100, "y": 100, "scale": 2.0, "angle": 15, "tilt": -10}]}
    (zone,) = LANE.from_wizard(cfg)
    assert zone["sign_looks"] == [{"scale": 2.0, "angle": 15.0, "tilt": -10.0}] and zone["sign_realistic"] is False
    parsed = LANE.parse_zone(zone)
    assert parsed["sign_looks"] == zone["sign_looks"] and parsed["sign_realistic"] is False
    plain = LANE.from_wizard({**cfg, "signs": [{"type": "bus_only", "x": 100, "y": 100}], "signs_realistic": True})[0]
    assert plain["sign_looks"] == [{"scale": 1.0, "angle": 0.0, "tilt": 0.0}] and plain["sign_realistic"] is True


def test_the_whole_picture_zone_draws_its_signs_with_their_look():
    cfg = {"signs": [{"type": "bus_only", "x": 960, "y": 540, "angle": 90}], "signs_realistic": False}
    zone = LANE.auto_zone(cfg, [[0, 0], [1920, 0], [1920, 1080], [0, 1080]], (1920, 1080), None)
    assert zone["signs"][0]["look"] == {"scale": 1.0, "angle": 90.0, "tilt": 0.0} and zone["sign_realistic"] is False
    img, base = frame(), frame()
    LANE.draw_zone(None, img, 0, zone)
    x0, y0, x1, y1 = box_of(changed(img, base))
    assert (x1 - x0) < (y1 - y0)                                         # turned a quarter: tall, not wide
