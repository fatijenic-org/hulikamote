"""
Road and traffic overlays (engine/scene_overlays.py): what is painted on an empty road is read back by the road finder
and becomes the zones of the selected rules. A plain grey road picture, no video and no model.
"""
import numpy as np

from engine import scene_overlays
from engine.violations import REGISTRY

ITEMS = [
    {"kind": "line", "style": "solid_yellow", "points": [[520, 420], [330, 1060]]},
    {"kind": "line", "style": "dashed_white", "points": [[960, 420], [960, 1060]]},
    {"kind": "crosswalk", "polygon": [[1150, 640], [1750, 640], [1750, 860], [1150, 860]]},
    {"kind": "lane", "type": "bicycle", "polygon": [[60, 500], [230, 500], [150, 1060], [10, 1060]]},
    {"kind": "object", "type": "stop_sign", "at": [1800, 600]},
    {"kind": "nonsense"}, {"kind": "line", "style": "pink", "points": [[0, 0], [1, 1]]},
]


def road() -> np.ndarray:
    rng = np.random.default_rng(5)
    img = np.zeros((720, 1280, 3), np.uint8)
    img[:180] = (235, 225, 215)
    img[180:260] = rng.integers(0, 255, (80, 1280, 3), dtype=np.uint8)
    img[260:] = np.clip(112 + rng.integers(-4, 5, (460, 1280, 1)), 0, 255).astype(np.uint8)
    return img


def test_usable_keeps_only_well_formed_items():
    kinds = [it["kind"] for it in scene_overlays.usable(ITEMS)]
    assert kinds == ["line", "line", "crosswalk", "lane", "object"]
    assert scene_overlays.usable(None) == [] and scene_overlays.usable("x") == []


def test_painted_overlays_are_read_back_from_the_picture():
    picture = road()
    before = picture.copy()
    scene_overlays.paint(picture, scene_overlays.usable(ITEMS))
    assert (picture != before).any()
    found = scene_overlays.find(picture)["found"]
    assert found["solid_lines"] == 1 and found["dashed_lines"] >= 1
    assert found["crosswalks"] == 1 and found["bicycle_lanes"] == 1 and found["bus_lanes"] == 0


def test_an_empty_road_reads_nothing():
    found = scene_overlays.find(road())["found"]
    assert not any(found.values())


def test_a_vehicle_stays_on_top_of_the_paint():
    picture = road()
    car = [1300 * 1280 // 1920, 700 * 720 // 1080, 120, 80]               # a box in the middle of the crosswalk
    clean = picture[car[1]:car[1] + car[3], car[0]:car[0] + car[2]].copy()
    scene_overlays.paint(picture, scene_overlays.usable(ITEMS), [car])
    assert (picture[car[1]:car[1] + car[3], car[0]:car[0] + car[2]] == clean).all()


def test_apply_gives_the_read_markings_to_the_selected_rules(monkeypatch):
    monkeypatch.setattr(scene_overlays, "empty_road", lambda path, count=12: road())
    config = {"active_violations": ["crossing_solid_line", "pedestrian_lane", "restricted_lane", "counterflow"],
              "scene_overlays": ITEMS, "per_violation_configs": {}}
    message = scene_overlays.apply(config, "any.mp4")
    per = config["per_violation_configs"]
    assert "1 solid" in message and len(per["crossing_solid_line"]["rois"]) == 1 and len(per["crossing_solid_line"]["rois"][0]["line"]) >= 2
    assert len(per["pedestrian_lane"]["rois"]) == 1 and len(per["pedestrian_lane"]["rois"][0]["polygon"]) == 4
    assert len(per["restricted_lane"]["rois"]) == 1 and per["restricted_lane"]["signs"][0]["type"] == "bicycle_only"
    # the rules accept those zones as if the operator had drawn them, and the bicycle lane allows bicycles only
    assert REGISTRY["crossing_solid_line"].from_wizard(per["crossing_solid_line"])
    assert REGISTRY["pedestrian_lane"].from_wizard(per["pedestrian_lane"])
    lanes = REGISTRY["restricted_lane"].from_wizard(per["restricted_lane"])
    assert len(lanes) == 1 and lanes[0]["allowed_classes"] == ["bicycle"]


def test_apply_leaves_drawn_zones_alone_and_does_nothing_without_overlays(monkeypatch):
    monkeypatch.setattr(scene_overlays, "empty_road", lambda path, count=12: road())
    drawn = [{"line": [[1, 1], [2, 2]]}]
    config = {"active_violations": ["crossing_solid_line"], "scene_overlays": ITEMS,
              "per_violation_configs": {"crossing_solid_line": {"rois": drawn}}}
    scene_overlays.apply(config, "any.mp4")
    assert config["per_violation_configs"]["crossing_solid_line"]["rois"] is drawn
    assert scene_overlays.apply({"active_violations": ["crossing_solid_line"]}, "any.mp4") is None
