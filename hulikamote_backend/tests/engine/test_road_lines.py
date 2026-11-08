"""
The road line finder's geometry and rules, on made-up pictures (no video needed).

The top view is where the rules live: lane lines are vertical, crosswalk stripes are evenly spaced vertical bars, a stop line is a
long thin horizontal line. The matrix that makes that view comes from the road's vanishing point.
"""
import numpy as np

from engine import road_lines as rl


def test_the_top_view_makes_lines_through_the_vanishing_point_vertical():
    size = (1280, 720)
    vp = np.array([700.0, 250.0])
    matrix = rl._top_homography({"kind": "finite", "vp": vp, "angle": None}, size)
    # three points on each of two lines that run into the vanishing point: in the top view each line must have one column
    for slope in (-0.9, 0.35):
        ys = np.array([400.0, 520.0, 700.0])
        pts = np.stack([vp[0] + slope * (ys - vp[1]), ys], 1).astype(np.float32).reshape(-1, 1, 2)
        top = rl.cv2.perspectiveTransform(pts, matrix).reshape(-1, 2)
        assert np.ptp(top[:, 0]) < 0.5, top
        assert top[0, 1] < top[1, 1] < top[2, 1]                      # farther is higher up


def test_a_parallel_road_direction_is_turned_upright():
    matrix = rl._top_homography({"kind": "parallel", "vp": None, "angle": 20.0}, (1280, 720))
    ends = np.float32([[100, 100], [100 + 400 * np.cos(np.radians(20)), 100 + 400 * np.sin(np.radians(20))]]).reshape(-1, 1, 2)
    top = rl.cv2.perspectiveTransform(ends, matrix).reshape(-1, 2)
    assert abs(top[1, 0] - top[0, 0]) < 0.5


def _bars(count: int, period: int = 90, width: int = 40, left: int = 200, v0: int = 500, v1: int = 700) -> np.ndarray:
    mask = np.zeros((rl.TOP_H, rl.TOP_W), np.uint8)
    for i in range(count):
        mask[v0:v1, left + i * period:left + i * period + width] = 255
    return mask


def test_evenly_spaced_bars_are_a_crosswalk():
    mask = _bars(6)
    road = np.full_like(mask, 255)
    found = rl._crosswalks(mask, road, mask, np.zeros(mask.shape, np.float32))
    assert len(found) == 1
    c = found[0]
    assert c["stripes"] == 6 and 190 <= c["u0"] <= 210 and 680 <= c["u1"] <= 700 and 490 <= c["v0"] and c["v1"] <= 710


def test_three_bars_or_a_pavement_are_not_a_crosswalk():
    road = np.full((rl.TOP_H, rl.TOP_W), 255, np.uint8)
    assert rl._crosswalks(_bars(3), road, _bars(3), np.zeros(road.shape, np.float32)) == []
    reddish = np.ones(road.shape, np.float32)                         # brick-coloured: not a road marking
    assert rl._crosswalks(_bars(6), road, _bars(6), reddish) == []


def test_a_faint_stripe_beside_a_certain_crosswalk_is_added():
    certain = _bars(6)
    loose = _bars(7)                                                   # the loose mask also sees a seventh stripe
    road = np.full_like(certain, 255)
    found = rl._crosswalks(certain, road, loose, np.zeros(certain.shape, np.float32))
    assert found and found[0]["stripes"] == 7


def test_a_long_thick_horizontal_line_is_a_stop_line_and_a_hairline_is_not():
    white = np.zeros((rl.TOP_H, rl.TOP_W), np.uint8)
    white[600:630, 200:900] = 255
    road = np.full_like(white, 255)
    contrast = np.full(white.shape, 40.0, np.float32)
    assert len(rl._stop_lines(white, road, contrast, [])) == 1
    thin = np.zeros_like(white)
    thin[600:603, 200:900] = 255
    assert rl._stop_lines(thin, road, contrast, []) == []


def test_a_solid_vertical_line_is_solid_and_a_dashed_one_is_dashed():
    road = np.full((rl.TOP_H, rl.TOP_W), 255, np.uint8)
    white = np.zeros_like(road)
    white[200:1000, 300:315] = 255                                      # one solid line
    for v in range(200, 1000, 120):                                     # one dashed line: 60 painted, 60 empty
        white[v:v + 60, 700:715] = 255
    lines = rl._lane_lines(white, np.zeros_like(white), road)
    styles = sorted(ln["style"] for ln in lines)
    assert styles == ["dashed", "solid"]


def test_zone_suggestions_follow_the_wizards_shape():
    top = {"u0": 300.0, "u1": 900.0, "v0": 500.0, "v1": 640.0}
    result = {"ok": True, "video_size": [1920, 1080], "rectifier": {"top_to_video": np.eye(3).tolist(), "top_size": [rl.TOP_W, rl.TOP_H]},
              "crosswalks": [{"polygon": [], "stripes": 6, "score": 0.9, "top": top}],
              "stop_lines": [{"p0": [300.0, 700.0], "p1": [900.0, 700.0], "top": {"u0": 300.0, "v0": 700.0, "u1": 900.0, "v1": 700.0}}],
              "lane_lines": [{"p0": [600.0, 200.0], "p1": [600.0, 800.0], "style": "solid", "colour": "yellow", "coverage": 1.0,
                              "top": {"u0": 600.0, "v0": 200.0, "u1": 600.0, "v1": 800.0}}]}
    zones = rl.reference_zones(result)
    assert set(zones) == {"pedestrian_lane", "red_light", "crossing_solid_line"}
    assert len(zones["pedestrian_lane"][0]["polygon"]) == 4 and "ui_vector" not in zones["pedestrian_lane"][0]
    for key in ("red_light", "crossing_solid_line"):
        zone = zones[key][0]
        assert len(zone["polygon"]) == 4 and len(zone["ui_vector"]) == 2 and set(zone["vector"]) == {"x_dir", "y_dir"}
    assert rl.zone_hints({"ok": False}) == []
