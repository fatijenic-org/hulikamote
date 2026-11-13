"""
engine/flow_field.py + the auto mode of counterflow: the legal direction is learned from traffic, no zone drawn.
Synthetic traffic only (no model, no video).
"""
import json
from types import SimpleNamespace

from engine.flow_field import MIN_TRACKS, VOTES_PER_TRACK_AND_CELL, FlowField
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY
from tests.helpers import FPS, H, W, Det

FW, FH = 1280, 720
RIGHT, LEFT, UP, DOWN = (1.0, 0.0), (-1.0, 0.0), (0.0, -1.0), (0.0, 1.0)


def teach(field, direction, cars=6, row_y=360.0, first_id=1, x_from=40, x_to=1240, step=80):
    """`cars` vehicles drive along a row heading `direction`, one vote per cell they cross."""
    for car in range(cars):
        for x in range(x_from, x_to, step):
            field.observe(first_id + car, x, row_y, direction, FW, FH)
    return field


def test_a_one_way_row_is_learned_and_judged():
    field = teach(FlowField(), RIGHT)
    assert field.verdict(640, 360, FW, FH, RIGHT) == "with"
    assert field.verdict(640, 360, FW, FH, LEFT) == "against"
    assert field.verdict(640, 360, FW, FH, (0.7, 0.7)) == "with"      # a bit off the flow is not against it
    assert field.verdict(640, 360, FW, FH, DOWN) == "with"            # sideways is not against either (90 deg)


def test_nothing_is_judged_before_enough_traffic():
    field = FlowField()
    for _ in range(50):                                               # one car, many looks: capped at 3 votes a cell
        field.observe(1, 640, 360, RIGHT, FW, FH)
    assert field.verdict(640, 360, FW, FH, LEFT) == "unknown"
    teach(field, RIGHT, cars=MIN_TRACKS - 2)
    assert field.verdict(640, 360, FW, FH, LEFT) == "unknown"         # too few different vehicles
    teach(field, RIGHT, cars=MIN_TRACKS + 2, first_id=100)
    assert field.verdict(640, 360, FW, FH, LEFT) == "against"


def test_one_vehicle_casts_a_limited_number_of_votes_per_cell():
    field = FlowField()
    for _ in range(20):
        field.observe(1, 640, 360, RIGHT, FW, FH)
    assert field.counts.sum() == VOTES_PER_TRACK_AND_CELL


def test_a_two_way_cell_is_never_judged():
    field = teach(FlowField(), RIGHT, cars=5)
    teach(field, LEFT, cars=5, first_id=100)                           # same cells, opposite direction: 50 / 50
    assert field.verdict(640, 360, FW, FH, RIGHT) == "unknown"
    assert field.verdict(640, 360, FW, FH, LEFT) == "unknown"


def test_a_few_wrong_way_cars_do_not_change_the_flow():
    field = teach(FlowField(), RIGHT, cars=12)
    teach(field, LEFT, cars=1, first_id=100)                           # one offender among twelve
    assert field.verdict(640, 360, FW, FH, LEFT) == "against"
    assert field.verdict(640, 360, FW, FH, RIGHT) == "with"


def test_lanes_in_different_places_have_their_own_direction():
    field = teach(FlowField(), RIGHT, row_y=200)                       # upper road goes right
    teach(field, LEFT, row_y=520, first_id=100)                        # lower road goes left
    assert field.verdict(640, 200, FW, FH, LEFT) == "against"
    assert field.verdict(640, 520, FW, FH, LEFT) == "with"
    assert field.verdict(640, 520, FW, FH, RIGHT) == "against"


def test_cells_are_relative_so_resolution_does_not_matter():
    field = teach(FlowField(), RIGHT)
    assert field.verdict(320, 180, 640, 360, LEFT) == "against"        # the same spot in a half-size picture


def test_cells_never_seen_are_not_judged():
    field = teach(FlowField(), RIGHT, row_y=100)
    assert field.verdict(640, 650, FW, FH, LEFT) == "unknown"


def test_the_flow_survives_saving_and_loading():
    field = teach(FlowField(), RIGHT)
    clone = FlowField.from_dict(json.loads(json.dumps(field.to_dict())))
    assert clone.verdict(640, 360, FW, FH, LEFT) == "against"
    assert clone.verdict(640, 360, FW, FH, RIGHT) == "with"


def test_learned_flow_can_be_scored_against_a_drawn_arrow():
    field = teach(FlowField(), RIGHT)
    box = [[0, 300], [FW, 300], [FW, 420], [0, 420]]
    assert field.compare_with_zones([{"polygon": box, "vector": RIGHT}], FW, FH)["agreement"] == 1.0
    assert field.compare_with_zones([{"polygon": box, "vector": LEFT}], FW, FH)["agreement"] == 0.0
    assert field.compare_with_zones([{"polygon": [[0, 0], [10, 0], [10, 10]], "vector": LEFT}], FW, FH)["agreement"] is None


def test_the_learned_flow_can_be_drawn():
    import numpy as np
    frame = np.zeros((FH, FW, 3), dtype=np.uint8)
    teach(FlowField(), RIGHT).draw(frame)
    assert frame.any()
    blank = np.zeros((FH, FW, 3), dtype=np.uint8)
    FlowField().draw(blank)
    assert not blank.any()                                             # nothing learned, nothing drawn


# ─── the vehicles teach the field ────────────────────────────────────────────

def drive(mgr, field, points, tid=1, cls="car"):
    """Move one vehicle along `points` (bottom-centre), letting the field learn from each frame."""
    for i, (x, y) in enumerate(points):
        det = Det(tid, [int(x - W / 2), int(y - H), W, H], cls)
        mgr.update([det], i / FPS)
        field.observe_frame(mgr, [det], FW, FH)


def test_moving_vehicles_teach_but_parked_ones_and_people_do_not():
    mgr, field = ActiveLedgerManager(), FlowField()
    drive(mgr, field, [(640 + 9 * i, 400) for i in range(30)], tid=1)
    taught = field.samples
    assert taught > 0
    drive(mgr, field, [(300, 300)] * 30, tid=2)                        # parked: no heading, no votes
    drive(mgr, field, [(300 + 9 * i, 500) for i in range(30)], tid=3, cls="person")
    assert field.samples == taught


def test_a_vehicle_flagged_wrong_way_stops_teaching():
    mgr, field = ActiveLedgerManager(), FlowField()
    drive(mgr, field, [(640 + 9 * i, 400) for i in range(10)], tid=1)
    mgr.ledgers[1].violations.add("counterflow")
    before = field.samples
    drive(mgr, field, [(730 + 9 * i, 400) for i in range(10)], tid=1)
    assert field.samples == before


# ─── counterflow on the whole picture ────────────────────────────────────────────────

def whole_zone(field):
    return {"polygon": [[0, 0], [FW, 0], [FW, FH], [0, FH]], "whole_frame": True, "field": field, "frame_size": (FW, FH)}


def run_counterflow(points, field, tid=1):
    mgr = ActiveLedgerManager()
    flagged = False
    for i, (x, y) in enumerate(points):
        det = Det(tid, [int(x - W / 2), int(y - H), W, H])
        mgr.update([det], i / FPS)
        flagged = REGISTRY["counterflow"].evaluate(mgr, tid, [whole_zone(field)]) or flagged
    return flagged, mgr


def test_auto_counterflow_flags_a_car_that_keeps_going_the_wrong_way():
    field = teach(FlowField(), RIGHT)
    flagged, mgr = run_counterflow([(1100 - 9 * i, 360) for i in range(40)], field)          # drives LEFT for 4 s
    assert flagged and "counterflow" in mgr.ledgers[1].violations


def test_auto_counterflow_ignores_traffic_going_with_the_flow():
    field = teach(FlowField(), RIGHT)
    assert not run_counterflow([(200 + 9 * i, 360) for i in range(40)], field)[0]


def test_auto_counterflow_needs_the_wrong_way_to_last():
    field = teach(FlowField(), RIGHT)
    short_wrong_way = [(700 - 9 * i, 360) for i in range(10)] + [(610 + 9 * i, 360) for i in range(30)]   # 1 s wrong, then fine
    assert not run_counterflow(short_wrong_way, field)[0]


def test_auto_counterflow_never_judges_what_has_not_been_learned():
    assert not run_counterflow([(1100 - 9 * i, 360) for i in range(40)], FlowField())[0]


def test_auto_counterflow_ignores_a_parked_car():
    field = teach(FlowField(), RIGHT)
    assert not run_counterflow([(640 + (i % 2), 360) for i in range(40)], field)[0]


def test_auto_counterflow_ignores_a_creeping_car():
    field = teach(FlowField(), RIGHT)
    assert not run_counterflow([(640 - i, 360) for i in range(60)], field)[0]      # drifts LEFT at 10 px/s for 6 s


# ─── the pipeline hands out the whole-frame zone only when asked ─────────────

def pipeline_with(rois, mode, active=("counterflow", "swerving")):
    pipe = object.__new__(DecoupledPipeline)
    pipe.rois, pipe.native_w, pipe.native_h = rois, 0, 0
    pipe.flow_mode, pipe.flow = mode, FlowField()
    pipe.registry = SimpleNamespace(active_violations=list(active))
    return pipe


def test_a_rule_with_nothing_drawn_gets_a_whole_frame_zone_in_any_flow_mode():
    for mode in ("auto", "zones"):
        scaled = pipeline_with({}, mode)._get_scaled_rois(FW, FH)
        for key in ("counterflow_zones", "swerving_zones"):
            zone = scaled[key][0]
            assert zone["whole_frame"] and zone["polygon"] == [[0, 0], [FW, 0], [FW, FH], [0, FH]]
        assert scaled["red_light_zones"] == []                                             # other rules still need drawn zones


def test_drawn_zones_take_priority_over_the_whole_frame_zone():
    drawn = {"counterflow_zones": [{"polygon": [[0, 0], [100, 0], [100, 100]], "vector": (1.0, 0.0)}]}
    scaled = pipeline_with(drawn, "auto")._get_scaled_rois(FW, FH)
    assert len(scaled["counterflow_zones"]) == 1 and not scaled["counterflow_zones"][0].get("whole_frame")


def test_a_rule_that_is_not_on_gets_no_zone():
    scaled = pipeline_with({}, "zones", active=("swerving",))._get_scaled_rois(FW, FH)
    assert scaled["counterflow_zones"] == [] and scaled["swerving_zones"][0]["whole_frame"]


def test_the_flow_is_learned_only_when_a_rule_needs_it_and_nothing_is_drawn():
    drawn = {"counterflow_zones": [{"polygon": [[0, 0], [100, 0], [100, 100]], "vector": (1.0, 0.0)}]}
    assert pipeline_with({}, "zones", active=("counterflow",)).learns_flow                # direction is learned from the traffic
    assert pipeline_with({}, "zones", active=("illegal_parking",)).learns_flow            # the "traffic drives past" check
    assert not pipeline_with({}, "zones", active=("truck_ban", "swerving", "illegal_turn")).learns_flow
    assert not pipeline_with(drawn, "zones", active=("counterflow",)).learns_flow         # a drawn arrow is used instead
    assert pipeline_with({}, "auto", active=("truck_ban",)).learns_flow                   # the config can still ask for it


def test_the_rules_that_need_the_flow_are_exactly_these():
    from engine.violations import ZONE_VIOLATIONS
    assert {v.key for v in ZONE_VIOLATIONS if v.needs_flow} == {"counterflow", "illegal_parking", "illegal_loading", "blocking_intersection"}


def test_the_flow_mode_is_read_from_the_config(tmp_path, monkeypatch):
    import engine.pipeline as pipeline_mod
    monkeypatch.setattr(pipeline_mod, "ModelRegistry", lambda path: SimpleNamespace(active_violations=["counterflow"]))
    monkeypatch.setattr("yolo_inference.get_inference", lambda **kw: None)
    for value, expected in (("auto", "auto"), ("zones", "zones"), (None, "zones"), ("nonsense", "zones")):
        cfg = tmp_path / "cfg.json"
        cfg.write_text(json.dumps({"flow_mode": value} if value else {}))
        assert DecoupledPipeline(str(cfg)).flow_mode == expected


# ─── the road axis (used by the automatic parking rules) and the "must be driving" learning gate ─────────────

def test_the_road_axis_ignores_which_way_traffic_goes():
    one_way = teach(FlowField(), RIGHT)
    assert abs(one_way.road_axis(640, 360, FW, FH)[0]) > 0.99
    two_way = teach(teach(FlowField(), RIGHT, cars=5), LEFT, cars=5, first_id=100)
    assert two_way.verdict(640, 360, FW, FH, RIGHT) == "unknown"          # no legal side can be named ...
    assert abs(two_way.road_axis(640, 360, FW, FH)[0]) > 0.99             # ... but the road still runs left-right


def test_there_is_no_road_axis_where_traffic_goes_every_which_way_or_is_unlearned():
    crossing = teach(teach(FlowField(), RIGHT, cars=5), DOWN, cars=5, first_id=100)
    assert crossing.road_axis(640, 360, FW, FH) is None
    assert FlowField().road_axis(640, 360, FW, FH) is None


def test_a_creeping_car_does_not_teach_a_direction():
    mgr, field = ActiveLedgerManager(), FlowField()
    drive(mgr, field, [(640 - i, 360) for i in range(80)], tid=1)         # drifts left at 10 px/s for 8 s: not driving
    assert field.samples == 0


# ─── the test options: show / hide the arrows, and the reversed flow ─────────

def reversed_zone(field):
    return {**whole_zone(field), "invert": True}


def run_reversed(points, field, tid=1):
    mgr = ActiveLedgerManager()
    flagged = False
    for i, (x, y) in enumerate(points):
        det = Det(tid, [int(x - W / 2), int(y - H), W, H])
        mgr.update([det], i / FPS)
        flagged = REGISTRY["counterflow"].evaluate(mgr, tid, [reversed_zone(field)]) or flagged
    return flagged


def test_the_reversed_flow_test_flags_ordinary_traffic_and_spares_the_opposite():
    field = teach(FlowField(), RIGHT)
    assert run_reversed([(200 + 9 * i, 360) for i in range(40)], field)           # drives WITH the learned flow: flagged
    assert not run_reversed([(1100 - 9 * i, 360) for i in range(40)], field)      # drives the learned wrong way: now legal


def test_the_reversed_flow_test_still_never_judges_what_is_not_learned():
    assert not run_reversed([(200 + 9 * i, 360) for i in range(40)], FlowField())


def test_the_whole_frame_zone_carries_the_two_settings_and_defaults_to_normal():
    counterflow = REGISTRY["counterflow"]
    plain = counterflow.whole_frame_zone({}, [[0, 0]], (FW, FH), FlowField())
    assert plain["show_flow"] is True and plain["invert"] is False
    test = counterflow.whole_frame_zone({"show_flow": False, "invert_flow": True}, [[0, 0]], (FW, FH), FlowField())
    assert test["show_flow"] is False and test["invert"] is True


def test_a_drawn_arrow_is_flipped_in_the_reversed_flow_test():
    counterflow = REGISTRY["counterflow"]
    cfg = {"rois": [{"polygon": [[0, 0], [10, 0], [10, 10]], "vector": {"x_dir": 1.0, "y_dir": 0.0}}]}
    (normal,) = counterflow.from_wizard(cfg)
    (flipped,) = counterflow.from_wizard({**cfg, "invert_flow": True})
    assert normal["legal_flow_vector"] == {"x_dir": 1.0, "y_dir": 0.0} and not normal["test_reversed"]
    assert flipped["legal_flow_vector"] == {"x_dir": -1.0, "y_dir": 0.0} and flipped["test_reversed"]
    assert counterflow.parse_zone(flipped)["test_reversed"] is True


def test_the_flow_arrows_can_be_hidden_and_the_test_always_carries_its_label():
    import numpy as np
    counterflow = REGISTRY["counterflow"]
    field = teach(FlowField(), RIGHT)
    black = lambda: np.zeros((FH, FW, 3), dtype=np.uint8)

    shown = black()
    counterflow.draw_zone(None, shown, 0, {**whole_zone(field), "show_flow": True})
    assert shown.any()

    hidden = black()
    counterflow.draw_zone(None, hidden, 0, {**whole_zone(field), "show_flow": False})
    assert not hidden.any()                                                      # nothing drawn at all

    hidden_test = black()
    counterflow.draw_zone(None, hidden_test, 0, {**whole_zone(field), "show_flow": False, "invert": True})
    assert hidden_test[:60, :400].any() and not hidden_test[400:].any()          # only the TEST label, top-left


def test_the_reversed_arrows_are_amber_not_teal():
    import numpy as np
    field = teach(FlowField(), RIGHT)
    normal, flipped = (np.zeros((FH, FW, 3), dtype=np.uint8) for _ in range(2))
    field.draw(normal)
    field.draw(flipped, invert=True)
    b_n, g_n, r_n = (normal[..., i].sum() for i in range(3))
    b_f, g_f, r_f = (flipped[..., i].sum() for i in range(3))
    assert b_n > r_n and r_f > b_f                                               # teal leans blue/green, amber leans red
