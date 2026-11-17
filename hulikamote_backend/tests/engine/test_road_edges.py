"""
The edge finder (engine/road_edges.py) on painted test pictures: a grey road with a solid line, a dashed line and a
crosswalk, under a textured "city" and a bright sky. No video and no model.
"""
import cv2
import numpy as np

from engine import road_edges
from engine.auto_lines import solid_line_rois
from engine.road_lines import _across_traffic, _add_edges, zone_hints

W, H = 1280, 720


def scene(solid=True, dashed=True, zebra=True) -> np.ndarray:
    rng = np.random.default_rng(3)
    img = np.zeros((H, W, 3), np.uint8)
    img[:200] = (235, 225, 215)                                             # sky
    img[200:300] = rng.integers(0, 255, (100, W, 3), dtype=np.uint8)        # buildings: colour and texture
    img[300:] = (112, 112, 112)                                             # road
    img[300:] = np.clip(img[300:].astype(int) + rng.integers(-4, 5, (H - 300, W, 1)), 0, 255).astype(np.uint8)
    if solid:
        cv2.line(img, (300, 310), (200, 715), (240, 240, 240), 7)
    if dashed:
        for y in range(320, 700, 70):
            x = 640 - (y - 320) * 0.05
            cv2.line(img, (int(x), y), (int(x - 1), y + 26), (240, 240, 240), 6)
    if zebra:
        for i in range(6):
            cv2.rectangle(img, (850, 480 + i * 34), (1150, 480 + i * 34 + 13), (240, 240, 240), -1)
    return img


def test_the_road_is_found_without_the_sky_or_the_buildings():
    found = road_edges.find(scene())
    road = found["road"] > 0
    assert road[320:, :].mean() > 0.9
    assert road[:190, :].mean() < 0.02 and road[210:290, :].mean() < 0.1
    assert found["road_polygons"]


def test_a_solid_and_a_dashed_line_and_a_crosswalk_are_found():
    found = road_edges.find(scene())
    styles = sorted(ln["style"] for ln in found["lane_lines"])
    assert styles == ["dashed", "solid"]
    solid = next(ln for ln in found["lane_lines"] if ln["style"] == "solid")
    assert solid["length"] > 350 and abs(solid["points"][0][0] - 300) < 15 or abs(solid["points"][-1][0] - 300) < 15
    assert len(found["crosswalks"]) == 1 and found["crosswalks"][0]["stripes"] == 6
    xs = [p[0] for p in found["crosswalks"][0]["polygon"]]
    assert min(xs) < 870 and max(xs) > 1130


def test_an_empty_road_gives_no_markings():
    found = road_edges.find(scene(solid=False, dashed=False, zebra=False))
    assert not found["lane_lines"] and not found["crosswalks"] and not found["stop_lines"]


def test_a_bright_wall_beside_the_road_is_not_a_painted_line():
    img = scene(solid=False, dashed=False, zebra=False)
    img[300:, 1200:] = (60, 140, 60)                         # grass on the right
    cv2.line(img, (1196, 300), (1196, 719), (245, 245, 245), 7)      # a white curb between road and grass
    assert not road_edges.find(img)["lane_lines"]


def blank_result() -> dict:
    return {"ok": False, "reason": "Not enough traffic movement to find the road direction.", "video_size": [W * 2, H * 2],
            "stop_lines": [], "lane_lines": [], "crosswalks": []}


def test_the_edges_carry_the_result_when_the_top_view_finder_gave_up():
    result = blank_result()
    _add_edges(result, scene(), None)
    assert result["ok"] and result["method"] == "edges" and result["reason"] is None
    assert result["edges"] == {"lane_lines": 2, "stop_lines": 0, "crosswalks": 1}
    solid = next(ln for ln in result["lane_lines"] if ln["style"] == "solid")
    assert solid["source"] == "edges" and abs(solid["p0"][1] - solid["p1"][1]) > 700       # video pixels (twice the picture)
    hints = {h["violation"] for h in zone_hints(result)}
    assert hints == {"crossing_solid_line", "pedestrian_lane"}
    rois = solid_line_rois(result)
    assert len(rois) == 1 and 2 <= len(rois[0]["line"]) <= 12 and rois[0]["auto"]


def test_nothing_found_leaves_the_failed_result_as_it_was():
    result = blank_result()
    _add_edges(result, scene(solid=False, dashed=False, zebra=False), None)
    assert not result["ok"] and result["reason"]


def test_a_line_the_traffic_drives_across_is_a_stop_line():
    line = [[100.0, 500.0], [600.0, 500.0]]
    xs = np.linspace(120, 580, 30)
    moving = np.stack([xs, np.full(30, 495.0)], axis=1)
    assert _across_traffic(line, moving, np.tile([0.0, -1.0], (30, 1)), 80.0) is True       # driving up, over the line
    assert _across_traffic(line, moving, np.tile([1.0, 0.0], (30, 1)), 80.0) is False       # driving along it
    assert _across_traffic(line, moving[:3], np.tile([0.0, -1.0], (3, 1)), 80.0) is None    # too little traffic to tell
