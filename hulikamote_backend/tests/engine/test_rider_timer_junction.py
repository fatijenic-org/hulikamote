"""A person who moves like a vehicle is a motorcycle; the parking stopwatch on the box; free crosswalk corners; the junction found from the flow."""
from types import SimpleNamespace

import numpy as np

from engine import crosswalk_overlay, marks
from engine.flow_field import FlowField
from engine.intersection_finder import find_junction
from engine.ledger import ActiveLedgerManager, TrackLedger
from engine.violations.illegal_parking import IllegalParking


def det(cls, box, tid):
    return SimpleNamespace(cls=cls, bbox=list(box), track_id=tid, confidence=0.9)


def run(manager, per_frame, seconds=2.0, fps=10):
    for i in range(int(seconds * fps)):
        manager.update(per_frame(i), timestamp=i / fps)


# ── fast "person" = motorcycle ──
def test_a_person_who_moves_too_fast_to_walk_becomes_a_motorcycle():
    mgr = ActiveLedgerManager()
    seen = []

    def frame(i):
        d = det("person", (100 + i * 30, 300, 40, 100), 1)      # 300 px/s = 3 body heights a second
        seen.append(d)
        return [d]

    run(mgr, frame)
    assert mgr.ledgers[1].vclass == "motorcycle" and mgr.ledgers[1].rides
    assert seen[-1].cls == "motorcycle"


def test_a_walking_person_stays_a_person():
    mgr = ActiveLedgerManager()
    run(mgr, lambda i: [det("person", (100 + i * 8, 300, 40, 100), 1)])     # 80 px/s = 0.8 body heights a second
    assert mgr.ledgers[1].vclass == "person" and not mgr.ledgers[1].rides


def test_a_person_inside_a_vehicle_box_is_left_alone():
    mgr = ActiveLedgerManager()
    run(mgr, lambda i: [det("person", (110 + i * 30, 300, 40, 100), 1), det("motorcycle", (100 + i * 30, 280, 80, 140), 2)])
    assert not mgr.ledgers[1].rides


# ── the parking stopwatch ──
def test_the_parking_timer_runs_on_the_box_and_turns_red_over_the_limit():
    ledger, mgr = TrackLedger(1), SimpleNamespace()
    mgr.ledgers = {1: ledger}
    rule, zones = IllegalParking(), [{"polygon": [[0, 0], [400, 0], [400, 400], [0, 400]], "time_limit": 2.0}]
    texts = []
    for i in range(0, 61):
        t = i * 0.1
        ledger.update_position([100, 100, 80, 60], t)
        rule.evaluate(mgr, 1, zones)
        texts.append(marks.current_timers(ledger))
    assert texts[10][0][0].startswith("PARKED 0:0") and texts[10][0][1] == marks.AMBER
    assert texts[-1][0][1] == marks.RED and "/ 0:02" in texts[-1][0][0]
    assert "illegal_parking" in ledger.violations
    frame = np.zeros((300, 400, 3), np.uint8)
    marks.draw_marks(frame, ledger, [100, 100, 80, 60])
    assert frame.any()                                              # the chip is on the picture, with no mark or label needed
    spec = marks.mark_specs(ledger, [100, 100, 80, 60])[0]
    assert spec["timer"].startswith("PARKED") and spec["box"] == [100, 100, 80, 60]
    ledger.update_position([300, 100, 80, 60], 7.0)                 # it drives off
    rule.evaluate(mgr, 1, zones)
    assert marks.current_timers(ledger) == []


# ── free crosswalk corners ──
def test_crosswalk_corners_placed_by_hand_are_the_shape():
    pts = [[-100, -50], [100, -50], [150, 60], [-150, 60]]
    poly = crosswalk_overlay.polygon({"x": 960, "y": 540, "pts": pts, "stripes": 25})
    assert poly == [[860.0, 490.0], [1060.0, 490.0], [1110.0, 600.0], [810.0, 600.0]]
    assert crosswalk_overlay.look_of({"stripes": 25})["stripes"] == 25
    assert "pts" not in crosswalk_overlay.look_of({"pts": [[1, 2]]})                 # not four corners: the simple shape
    assert "pts" not in crosswalk_overlay.look_of({"pts": [[1, 2]] * 3 + [["x", 1]]})


# ── junction from the flow ──
def road_flow():
    """A wide road across (rows 3-5) and a wide road down (columns 7-9): they cross in a 3 x 3 block."""
    flow, w, h, car = FlowField(), 1600.0, 900.0, [0]
    for row in (3, 4, 5):
        for k in range(12):
            car[0] += 1
            for col in range(16):
                for _ in range(2):
                    flow.observe(car[0], (col + 0.5) * 100, (row + 0.5) * 100, (1.0, 0.0) if k % 2 else (-1.0, 0.0), w, h)
    for col in (7, 8, 9):
        for k in range(12):
            car[0] += 1
            for row in range(9):
                for _ in range(2):
                    flow.observe(car[0], (col + 0.5) * 100, (row + 0.5) * 100, (0.0, 1.0), w, h)
    return flow


def test_the_junction_is_where_two_roads_cross():
    poly = find_junction(road_flow(), 1600, 900)
    assert poly is not None
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    assert min(xs) <= 800 <= max(xs) and min(ys) <= 450 <= max(ys)               # the crossing is inside
    assert max(xs) - min(xs) <= 500 and max(ys) - min(ys) <= 500                 # and it is not the whole picture


def test_a_straight_two_way_road_has_no_junction():
    flow = FlowField()
    for k in range(14):
        for col in range(16):
            for _ in range(2):
                flow.observe(k + 1, (col + 0.5) * 100, 450, (1.0, 0.0) if k % 2 else (-1.0, 0.0), 1600.0, 900.0)
    assert find_junction(flow, 1600, 900) is None
    assert find_junction(None, 1600, 900) is None
