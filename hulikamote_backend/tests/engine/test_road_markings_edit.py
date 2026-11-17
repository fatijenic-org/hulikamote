"""
"Detect road" correction step: the road split into an incoming and an outgoing side (with arrows), found solid and stop lines that can be
edited, drawn with any number of points, switched on as a rule, and the optional Counterflow zones made from the road's directions.
"""
from engine import live_calibrator as lc
from tests.engine.test_live_calibrator import H, SOLID, STOP, W, calibrator, canned, feed_seconds
from tests.engine.test_live_detect import walking_stub

ROAD = {"kind": "road", "polygon": [[200, 0], [440, 0], [440, 359], [200, 359]], "seen": 20}
SIDEWALK = {"kind": "sidewalk", "side": "left", "polygon": [[20, 0], [200, 0], [200, 359], [20, 359]], "seen": 9}
BANDS = [
    {"flow": "in", "polygon": [[200, 0], [320, 0], [320, 359], [200, 359]], "arrow": [[260, 100], [260, 300]], "points": 300, "share": 0.5},
    {"flow": "out", "polygon": [[320, 0], [440, 0], [440, 359], [320, 359]], "arrow": [[380, 300], [380, 100]], "points": 300, "share": 0.5},
]
FLOW = {"state": "two_way", "bands": BANDS, "points": 600, "reason": None}


def detected(tmp_path, flow=FLOW):
    """A calibrator whose scan found a crosswalk, a stop line, a solid line, a road split into two directions and a left sidewalk."""
    def result():
        return {**canned(stops=[STOP], lanes=[SOLID]), "regions": [ROAD, SIDEWALK], "flow": flow}
    cal = calibrator(tmp_path, analyse=walking_stub(result=result))
    cal.attach("cam")
    t = feed_seconds(cal, 0.5)
    cal.begin_detect()
    feed_seconds(cal, 3.0, start=t)
    return cal


def shapes(cal):
    return {z["id"]: z for z in cal.detect_status()["zones"]}


# ─── what the scan offers ─────────────────────────────────────────────────�

def test_the_scan_offers_the_two_sides_of_the_road_and_the_lines_it_found(tmp_path):
    status = detected(tmp_path).detect_status()
    assert [(z["id"], z["kind"]) for z in status["zones"]] == [
        ("crosswalk-1", "crosswalk"), ("sidewalk-2", "sidewalk"), ("road-1", "road"), ("road-2", "road"), ("solid-1", "solid_line"), ("stop-1", "stop_line")]
    by_id = shapes(detected(tmp_path / "again"))
    assert by_id["road-1"]["flow"] == "in" and by_id["road-2"]["flow"] == "out" and len(by_id["road-1"]["arrow"]) == 2
    assert by_id["solid-1"]["rule"] is False and by_id["solid-1"]["style"] == "solid_white" and by_id["solid-1"]["line"] == [[200.0, 50.0], [200.0, 450.0]]
    assert len(by_id["stop-1"]["line"]) == 2
    assert status["flow"] == {"state": "two_way", "bands": 2, "reason": None}


def test_without_a_direction_the_road_is_one_area_as_before(tmp_path):
    cal = detected(tmp_path, flow={"state": "none", "bands": [], "points": 0, "reason": "too little traffic"})
    status = cal.detect_status()
    assert [z["id"] for z in status["zones"] if z["kind"] == "road"] == ["road-1"]
    assert "flow" not in shapes(cal)["road-1"] and status["flow"]["state"] == "none"


def test_the_marks_picture_names_the_two_sides_of_the_road(tmp_path):
    marks = detected(tmp_path)._detect["steps"]["marks"]["info"]["marks"]
    assert {"kind": "road", "flow": "in", "status": "draft"} in marks and {"kind": "road", "flow": "out", "status": "draft"} in marks


# ─── checking what the operator sends ─────────────────────────────────────�

def test_lines_may_have_many_points_and_areas_up_to_the_limit():
    size = (W, H)
    line = {"kind": "solid_line", "line": [[0, 0], [10, 10]], "style": "double_yellow", "rule": True}
    assert lc.clean_zones([line], size) == [{"id": "solid_line-1", "kind": "solid_line", "line": [[0.0, 0.0], [10.0, 10.0]], "style": "double_yellow", "rule": True}]
    assert lc.clean_zones([{"kind": "solid_line", "line": [[0, 0]]}], size) is None                 # a line needs two points
    assert lc.clean_zones([{"kind": "stop_line", "polygon": [[0, 0], [1, 1]]}], size) is None       # and is given as "line"
    curve = [[i * 5.0, float((i * 7) % 300)] for i in range(lc.MAX_POINTS)]
    assert lc.clean_zones([{"kind": "road", "polygon": curve}], size) is not None
    assert lc.clean_zones([{"kind": "road", "polygon": curve + [[1, 1]]}], size) is None            # one point too many
    assert lc.clean_zones([{"kind": "solid_line", "line": curve + [[1, 1]]}], size) is None


def test_style_flow_and_arrow_are_kept_only_when_they_make_sense():
    size = (W, H)
    odd = lc.clean_zones([{"kind": "solid_line", "line": [[0, 0], [5, 5]], "style": "neon"},
                          {"kind": "stop_line", "line": [[0, 0], [5, 5]], "style": "solid_yellow", "rule": True}], size)
    assert odd[0]["style"] == "solid_white" and odd[0]["rule"] is False
    assert "style" not in odd[1] and "rule" not in odd[1]                                            # a stop line is only ever a mark
    road = {"kind": "road", "polygon": [[0, 0], [9, 0], [9, 9]], "flow": "in", "arrow": [[3, 1], [3, 8]]}
    kept, = lc.clean_zones([road], size)
    assert kept["flow"] == "in" and kept["arrow"] == [[3.0, 1.0], [3.0, 8.0]]
    sideways, = lc.clean_zones([{**road, "flow": "sideways"}], size)
    assert "flow" not in sideways and "arrow" not in sideways
    three, = lc.clean_zones([{**road, "arrow": [[0, 0], [1, 1], [2, 2]]}], size)
    assert three["flow"] == "in" and "arrow" not in three
    on_sidewalk, = lc.clean_zones([{"kind": "sidewalk", "polygon": [[0, 0], [9, 0], [9, 9]], "flow": "in"}], size)
    assert "flow" not in on_sidewalk


# ─── applying ────────────────────────────────────────────────────────────�

def test_a_solid_line_switched_on_is_a_rule_and_the_others_stay_hints(tmp_path):
    cal = detected(tmp_path)
    edited = [{**z, "rule": True} if z["id"] == "solid-1" else z for z in cal.detect_status()["zones"]]
    edited.append({"id": "solid-new", "kind": "solid_line", "line": [[10, 10], [20, 50], [30, 120], [60, 300]], "style": "solid_yellow", "rule": False})
    assert cal.set_detect_zones(edited)["ok"] and cal.apply_detect()["ok"]
    confirmed, = cal.active_zones()["crossing_solid_line"]
    # the finder's line runs past the picture's bottom edge; a corrected shape is kept inside the picture (360 px -> 1080 in the reference space)
    assert confirmed["confirmed"] is True and confirmed["polygon"] == [] and confirmed["line"] == [[600.0, 150.0], [600.0, 1077.0]]
    hints = [h for h in cal.hint_overlay(1280, 720) if h["violation"] == "crossing_solid_line"]
    assert len(hints) == 1 and len(hints[0]["line"]) == 4                         # the bent line, all four points, only a hint
    assert cal.found["solid_lines"] == 2 and cal.found["crosswalks"] == 1


def test_a_stop_line_is_only_ever_a_mark(tmp_path):
    cal = detected(tmp_path)
    edited = [{**z, "rule": True} if z["kind"] == "solid_line" else z for z in cal.detect_status()["zones"]]
    assert cal.set_detect_zones(edited)["ok"] and cal.apply_detect()["ok"]
    assert "red_light" in cal.zones and "red_light" not in cal.active_zones()
    assert [h["violation"] for h in cal.hint_overlay(1280, 720)] == ["red_light"]


def test_an_unedited_apply_keeps_the_finders_lines_as_hints(tmp_path):
    cal = detected(tmp_path)
    assert cal.apply_detect()["ok"]
    assert set(cal.active_zones()) == {"pedestrian_lane"}                         # the lines are hints, as before
    assert {h["violation"] for h in cal.hint_overlay(1280, 720)} == {"crossing_solid_line", "red_light"}


def test_the_two_sides_of_the_road_are_saved_with_their_arrows_and_drawn(tmp_path):
    cal = detected(tmp_path)
    assert cal.apply_detect()["ok"]
    sides = [r for r in cal.regions if r["kind"] == "road"]
    assert [r["flow"] for r in sides] == ["in", "out"] and sides[0]["arrow"] == [[780.0, 300.0], [780.0, 900.0]]
    overlay = [r for r in cal.region_overlay(1280, 720) if r["violation"] == "road"]
    assert [r["flow"] for r in overlay] == ["in", "out"] and overlay[0]["arrow"] == [[520, 200], [520, 600]]
    again = calibrator(tmp_path)                                                   # the same camera, a new session
    again.attach("cam")
    assert [r.get("flow") for r in again.regions if r["kind"] == "road"] == ["in", "out"]


def test_the_directions_become_counterflow_zones_only_when_asked_for(tmp_path):
    plain = detected(tmp_path / "plain")
    assert "counterflow" not in plain.apply_detect().get("zones", [])
    asked = detected(tmp_path / "asked")
    result = asked.apply_detect(counterflow=True)
    assert "counterflow" in result["zones"]
    incoming, outgoing = asked.active_zones()["counterflow"]
    assert incoming["vector"] == {"x_dir": 0.0, "y_dir": 1.0} and outgoing["vector"] == {"x_dir": 0.0, "y_dir": -1.0}
    assert incoming["polygon"][0] == [600.0, 0.0]
    no_flow = detected(tmp_path / "none", flow={"state": "none", "bands": [], "points": 0, "reason": "x"})
    assert "counterflow" not in no_flow.apply_detect(counterflow=True)["zones"]


def test_a_moved_side_keeps_its_direction_and_flipping_it_flips_the_arrow(tmp_path):
    cal = detected(tmp_path)
    edited = []
    for z in cal.detect_status()["zones"]:
        if z["id"] == "road-1":
            z = {**z, "flow": "out", "arrow": list(reversed(z["arrow"]))}            # the operator flipped it
        edited.append(z)
    assert cal.set_detect_zones(edited)["ok"] and cal.apply_detect(counterflow=True)["ok"]
    first = cal.active_zones()["counterflow"][0]
    assert first["vector"]["y_dir"] == -1.0                                          # now going away from the camera
