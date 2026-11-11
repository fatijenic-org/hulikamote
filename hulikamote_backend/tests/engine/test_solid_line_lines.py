"""
Crossing a solid line, drawn or found: lines with any number of points (curves, corners), several lines, no road
section needed, and the painted lines the road finder hands over when nothing was drawn (engine/auto_lines.py).
Scripted vehicles only (no model, no video).
"""
import json
from types import SimpleNamespace

import numpy as np

from engine.auto_lines import fill_solid_lines, solid_line_rois
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY
from engine.violations.geometry import line_side
from tests.helpers import BIG_ZONE, STOP_LINE, Det, drive

SOLID = REGISTRY["crossing_solid_line"]

# A line that bends: along the bottom, then up the right side (an "L" that a road curve would also look like).
BEND = [[400, 1000], [1000, 1000], [1000, 400]]


def zone(line, polygon=None):
    return {"polygon": polygon or [], "stop_line": line}


def solid(mgr, zones):
    return lambda tid: SOLID.evaluate(mgr, tid, zones)


# ─── a line with more than two points ───────────────────────────────────────

def test_a_bent_line_is_crossed_at_its_first_piece():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(700, 1300 - 9 * i) for i in range(40)], solid(mgr, [zone(BEND)]))          # up across the bottom piece
    assert "crossing_solid_line" in mgr.ledgers[1].violations


def test_a_bent_line_is_crossed_at_its_second_piece():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(1300 - 9 * i, 700) for i in range(40)], solid(mgr, [zone(BEND)]))          # left across the side piece


def test_driving_round_the_corner_on_one_side_is_not_crossing():
    """Along the line, round its corner and on, always on the same side: nothing is crossed."""
    outside = [(600 + 12 * i, 1150) for i in range(45)] + [(1140, 1150 - 12 * i) for i in range(1, 55)]
    mgr = ActiveLedgerManager()
    assert not drive(mgr, outside, solid(mgr, [zone(BEND)]))
    inside = [(600 + 7 * i, 850) for i in range(45)] + [(915, 850 - 12 * i) for i in range(1, 30)]
    mgr = ActiveLedgerManager()
    assert not drive(mgr, inside, solid(mgr, [zone(BEND)]))


def test_a_vehicle_wobbling_on_a_bend_is_not_crossing():
    mgr = ActiveLedgerManager()
    start = [(1000 - 9 * i, 1100 - 9 * i) for i in range(11)]
    wobble = [(910 + (6 if i % 2 else -6), 1000 + (8 if i % 2 else -8)) for i in range(40)]
    assert not drive(mgr, start + wobble, solid(mgr, [zone(BEND)]))


def test_a_crossing_past_either_end_of_a_bent_line_is_ignored():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(100, 1300 - 9 * i) for i in range(40)], solid(mgr, [zone(BEND)]))      # before the first point
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(1300 - 9 * i, 100) for i in range(40)], solid(mgr, [zone(BEND)]))      # beyond the last point


def test_the_side_of_a_bent_line_does_not_flip_while_driving_round_its_outside():
    sides = [line_side(BEND, 1000 + 120 * np.cos(a), 1000 + 120 * np.sin(a)) for a in np.linspace(-np.pi / 2, 0, 20)]
    assert all(s is not None for s in sides)
    assert len({s > 0 for s in sides}) == 1                       # always the same side: the outside of the corner


def test_two_points_behave_exactly_as_before():
    assert line_side(STOP_LINE, 1000, 1100) == -line_side(STOP_LINE, 1000, 900)                    # opposite sides, same distance
    assert line_side(STOP_LINE, 300, 1100) is None                                                 # beyond the end


# ─── several lines, no road section ──────────────────────────────────────────

TWO_LINES = [zone([[800, 1000], [1200, 1000]]), zone([[800, 600], [900, 560], [1200, 600]])]


def test_each_line_is_watched_on_its_own():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(1000, 900 - 5 * i) for i in range(40)], solid(mgr, TWO_LINES))         # stays between the two lines
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(1000, 800 - 9 * i) for i in range(40)], solid(mgr, TWO_LINES))             # starts between them: crosses the upper (bent) line
    assert "crossing_solid_line" in mgr.ledgers[1].violations


def test_a_line_alone_needs_no_road_section():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(1000, 1300 - 9 * i) for i in range(40)], solid(mgr, [zone(STOP_LINE)]))


def test_a_road_section_still_limits_the_line_when_one_was_drawn():
    mgr = ActiveLedgerManager()
    far_away = [[0, 0], [100, 0], [100, 100], [0, 100]]
    assert not drive(mgr, [(1000, 1300 - 9 * i) for i in range(40)], solid(mgr, [zone(STOP_LINE, far_away)]))
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(1000, 1300 - 9 * i) for i in range(40)], solid(mgr, [zone(STOP_LINE, BIG_ZONE)]))


# ─── what the wizard writes, what the pipeline reads ─────────────────────────

def test_the_wizard_line_with_many_points_and_no_polygon_becomes_a_zone():
    cfg = {"rois": [{"line": BEND}, {"polygon": BIG_ZONE, "line": STOP_LINE}, {"polygon": BIG_ZONE}, {"line": [[1, 1]]}]}
    zones = SOLID.from_wizard(cfg)
    assert zones == [{"coordinates": [], "stop_line": BEND}, {"coordinates": BIG_ZONE, "stop_line": STOP_LINE}]
    assert [SOLID.parse_zone(z) for z in zones] == [zone(BEND), zone(STOP_LINE, BIG_ZONE)]


def test_older_drawings_with_a_polygon_and_two_points_still_load():
    old = SOLID.from_wizard({"rois": [{"polygon": BIG_ZONE, "ui_vector": STOP_LINE}]})
    assert old == [{"coordinates": BIG_ZONE, "stop_line": STOP_LINE}]
    assert SOLID.parse_zone({"coordinates": BIG_ZONE, "stop_line": STOP_LINE}) == zone(STOP_LINE, BIG_ZONE)
    assert SOLID.parse_zone({"coordinates": BIG_ZONE}) is None


def test_a_bent_line_is_scaled_point_by_point_to_the_video(tmp_path):
    cfg = {"video_native_width": 1920, "video_native_height": 1080,
           "regions_of_interest": {"solid_line_zones": [{"stop_line": [[0, 1080], [960, 540], [1920, 540]]}]}}
    path = tmp_path / "cfg.json"
    path.write_text(json.dumps(cfg))
    pipe = object.__new__(DecoupledPipeline)
    pipe.rois = pipe._parse_rois(str(path))
    pipe.native_w, pipe.native_h = 1920, 1080
    scaled = pipe._get_scaled_rois(960, 540)["solid_line_zones"][0]
    assert scaled["polygon"] == []
    assert scaled["stop_line"] == [[0, 540], [480, 270], [960, 270]]


def test_a_line_without_a_road_section_does_not_cut_other_rules_vehicles_away():
    pipe = object.__new__(DecoupledPipeline)
    pipe.registry = SimpleNamespace(active_violations=["illegal_parking", "crossing_solid_line"])
    far = {"polygon": [[0, 0], [10, 0], [10, 10], [0, 10]]}
    cars = [Det(1, [900, 900, 100, 80]), Det(2, [5, 5, 4, 4])]
    scaled = {"illegal_parking_zones": [far], "solid_line_zones": [{"polygon": [], "stop_line": STOP_LINE}]}
    assert pipe._filter_to_roi(cars, scaled) == cars                                              # the line sees every vehicle
    only_parking = {"illegal_parking_zones": [far], "solid_line_zones": []}
    assert [d.track_id for d in pipe._filter_to_roi(cars, only_parking)] == [2]                   # unchanged for polygon-only rules


def test_a_drawn_line_is_painted_on_the_picture_bent_and_without_a_polygon():
    frame = np.zeros((1200, 1400, 3), np.uint8)
    SOLID.draw_zone(None, frame, 0, zone(BEND))
    assert frame[1000, 700].any() and frame[700, 1000].any()                                       # both pieces of the line
    assert not frame[200, 200].any()


# ─── painted lines found when nothing was drawn ──────────────────────────────

def found(lines, ok=True, reason=None):
    return {"ok": ok, "reason": reason, "video_size": [1280, 720], "lane_lines": lines}


YELLOW = {"style": "solid", "colour": "yellow", "p0": [640.0, 100.0], "p1": [320.0, 700.0]}
DASHED = {"style": "dashed", "colour": "white", "p0": [900.0, 100.0], "p1": [950.0, 700.0]}


def test_only_solid_lines_are_taken_and_scaled_to_the_wizards_space():
    rois = solid_line_rois(found([YELLOW, DASHED]))
    assert [r["line"] for r in rois] == [[[960.0, 150.0], [480.0, 1050.0]]]
    assert solid_line_rois(found([YELLOW], ok=False)) == []


def test_a_short_line_is_not_trusted():
    short = {"style": "solid", "colour": "white", "p0": [400.0, 100.0], "p1": [380.0, 150.0]}       # 7% of the picture's height
    assert solid_line_rois(found([short])) == []
    assert len(solid_line_rois(found([short, YELLOW]))) == 1


def config(rois=None, **extra):
    settings = {"rois": rois or [], **extra}
    return {"active_violations": ["crossing_solid_line"], "per_violation_configs": {"crossing_solid_line": settings}}


def finder(result):
    return lambda _path: (result, None)


def test_found_lines_are_handed_to_the_rule_when_nothing_was_drawn():
    cfg = config()
    assert fill_solid_lines(cfg, "clip.mp4", analyse=finder(found([YELLOW]))) is None
    rois = cfg["per_violation_configs"]["crossing_solid_line"]["rois"]
    assert SOLID.from_wizard({"rois": rois}) == [{"coordinates": [], "stop_line": [[960.0, 150.0], [480.0, 1050.0]]}]


def test_a_drawn_line_always_wins_and_the_finder_is_not_even_run():
    drawn = [{"line": BEND}]
    cfg = config(drawn)
    def never(_path):
        raise AssertionError("the finder must not run when a line was drawn")
    assert fill_solid_lines(cfg, "clip.mp4", analyse=never) is None
    assert cfg["per_violation_configs"]["crossing_solid_line"]["rois"] == drawn


def test_it_can_be_turned_off_and_then_says_the_rule_checks_nothing():
    cfg = config(auto_lines=False)
    note = fill_solid_lines(cfg, "clip.mp4", analyse=finder(found([YELLOW])))
    assert "checks nothing" in note and not cfg["per_violation_configs"]["crossing_solid_line"]["rois"]


def test_nothing_found_or_unreadable_is_said_in_plain_words_and_never_raises():
    cfg = config()
    assert "No painted solid lane line was found" in fill_solid_lines(cfg, "c.mp4", analyse=finder(found([DASHED])))
    cfg = config()
    note = fill_solid_lines(cfg, "c.mp4", analyse=finder(found([], ok=False, reason="Not enough traffic movement to find the road")))
    assert note.startswith("Not enough traffic movement to find the road. ") and "draw the line" in note
    cfg = config()

    def broken(_path):
        raise ValueError("ffmpeg is needed to read the video but was not found")
    assert "ffmpeg is needed" in fill_solid_lines(cfg, "c.mp4", analyse=broken)
    assert not cfg["per_violation_configs"]["crossing_solid_line"]["rois"]


def test_it_does_nothing_when_the_rule_is_not_selected():
    cfg = {"active_violations": ["counterflow"], "per_violation_configs": {}}
    assert fill_solid_lines(cfg, "c.mp4", analyse=finder(found([YELLOW]))) is None
    assert cfg["per_violation_configs"] == {}
