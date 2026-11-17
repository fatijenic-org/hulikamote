"""
Scripted tests (no model, no video) for the work of 2026-11-15:
overtaking on the right, passengers on a kuliglig, riders counted from the helmet model's boxes,
and "no plate" told apart from "plate not read".
"""
from types import SimpleNamespace

from engine.ledger import ActiveLedgerManager
from engine.specialists import IDX_RIDER_WITH_HELMET, IDX_RIDER_WITHOUT_HELMET
from engine.violations import REGISTRY
from engine.violations.no_plate import plate_evidence, plate_status
from engine.violations.overloading import riders_from_look
from tests.helpers import BIG_ZONE, FPS, H, W, Det

OVERTAKE = REGISTRY["overtaking_on_right"]
KULIGLIG = REGISTRY["kuliglig_passenger"]
OVERLOAD = REGISTRY["overloading"]
NO_PLATE = REGISTRY["no_plate"]


def box(x, y):
    """Vehicle box from its bottom-centre point."""
    return [int(x - W / 2), int(y - H), W, H]


# ─── Overtaking on the right ─────────────────────────────────────────────────

def two_cars(side_dx, frames=34, slow_path=None, zones=None, speed_fast=14):
    """Car 2 drives up the picture at 6 px a frame; car 1 starts 150 px behind it, `side_dx` px to its side, at 14 px a frame."""
    mgr = ActiveLedgerManager()
    zones = zones or [{"polygon": BIG_ZONE, "one_way_lanes": 1}]
    flagged = False
    for i in range(frames):
        sx, sy = slow_path(i) if slow_path else (1000, 1500 - 6 * i)
        fast = Det(1, box(1000 + side_dx, 1650 - speed_fast * i))
        slow = Det(2, box(sx, sy))
        mgr.update([fast, slow], i / FPS)
        flagged = OVERTAKE.evaluate(mgr, 1, zones) or flagged
        assert not OVERTAKE.evaluate(mgr, 2, zones)          # the overtaken car is never the one flagged
    return flagged, mgr


def test_overtaking_flags_a_pass_on_the_right():
    flagged, mgr = two_cars(side_dx=130)                     # driving up the picture: the driver's right is image right
    assert flagged
    assert "overtaking_on_right" in mgr.ledgers[1].violations


def test_overtaking_ignores_a_pass_on_the_left():
    flagged, _ = two_cars(side_dx=-130)
    assert not flagged


def test_overtaking_ignores_two_lanes_at_the_same_speed():
    flagged, _ = two_cars(side_dx=130, speed_fast=6)         # beside each other, nobody passes
    assert not flagged


def test_overtaking_ignores_a_vehicle_that_turns_left():
    def turning(i):                                          # up for 16 frames, then 45 deg to the left
        if i <= 16:
            return 1000, 1500 - 6 * i
        k = i - 16
        return 1000 - 4.3 * k, 1500 - 6 * 16 - 4.3 * k
    flagged, _ = two_cars(side_dx=130, slow_path=turning)
    assert not flagged


def test_overtaking_is_legal_where_the_zone_has_two_one_way_lanes():
    flagged, _ = two_cars(side_dx=130, zones=[{"polygon": BIG_ZONE, "one_way_lanes": 2}])
    assert not flagged


def test_overtaking_ignores_a_stopped_vehicle():
    flagged, _ = two_cars(side_dx=130, slow_path=lambda i: (1000, 1300))      # parked: passing it is not overtaking
    assert not flagged


def test_overtaking_zone_settings_from_the_wizard():
    assert OVERTAKE.from_wizard({"rois": [{"polygon": BIG_ZONE}], "one_way_lanes": 2}) == [{"coordinates": BIG_ZONE, "one_way_lanes": 2}]
    assert OVERTAKE.parse_zone({"coordinates": BIG_ZONE}) == {"polygon": BIG_ZONE, "one_way_lanes": 1}
    assert OVERTAKE.whole_frame


# ─── Passengers on a kuliglig (frame check) ──────────────────────────────────

def kuliglig_frames(people_at, frames=30):
    """A kuliglig (200 x 220 box) drives up the picture at 90 px/s; `people_at(ytop)` gives the person detections of a frame."""
    pipe = SimpleNamespace(ledger_manager=ActiveLedgerManager(), config={})
    for i in range(frames):
        ytop = 1200 - 9 * i
        dets = [Det(1, [1000, ytop, 200, 220], "kuliglig")] + people_at(ytop)
        pipe.ledger_manager.update(dets, i / FPS)
        KULIGLIG.check_frame(pipe, dets)
    return pipe.ledger_manager.ledgers[1]


def person(ytop, track_id, dx, dy):
    return Det(track_id, [1000 + dx, ytop + dy, 40, 80], "person")


def test_kuliglig_flags_a_passenger_besides_the_driver():
    ledger = kuliglig_frames(lambda y: [person(y, 50, 80, 10), person(y, 51, 80, 120)])
    assert "kuliglig_passenger" in ledger.violations


def test_kuliglig_with_only_its_driver_is_fine():
    ledger = kuliglig_frames(lambda y: [person(y, 50, 80, 10)])
    assert "kuliglig_passenger" not in ledger.violations


def test_kuliglig_ignores_a_pedestrian_standing_beside_it():
    pipe_people = lambda y: [person(y, 50, 80, 10), Det(51, [1080, 900, 40, 80], "person")]     # the second one does not move
    assert "kuliglig_passenger" not in kuliglig_frames(pipe_people).violations


# ─── Riders counted from the helmet model's boxes (overloading) ──────────────

MOTO = [1000, 1000, 80, 120]


def rider(x, y, cls=IDX_RIDER_WITH_HELMET, conf=0.8, w=40, h=60):
    return {"class_id": cls, "confidence": conf, "box": [x, y, w, h]}


def test_riders_from_look_counts_each_rider_once():
    dets = [rider(1005, 950), rider(1035, 955), rider(1020, 990, IDX_RIDER_WITHOUT_HELMET),
            rider(1006, 951, IDX_RIDER_WITHOUT_HELMET, conf=0.5),      # the same rider as the first, other class
            rider(1300, 950),                                           # a neighbour's rider in the crop
            rider(1010, 960, conf=0.2)]                                 # too weak
    assert len(riders_from_look(MOTO, dets)) == 3


def test_overloading_uses_the_helmet_boxes_when_person_boxes_merge():
    """One merged person box (three riders hidden in it) never flags; the helmet model's three rider boxes do."""
    pipe = SimpleNamespace(ledger_manager=ActiveLedgerManager(), max_riders=2)
    look = SimpleNamespace(dets=[rider(1005, 950), rider(1035, 955), rider(1020, 990)])
    for i in range(12):
        moto = Det(1, list(MOTO), "motorcycle")
        merged = Det(-1, [1010, 950, 60, 150], "person")
        dets = [moto, merged]
        pipe.ledger_manager.update(dets, i / FPS)
        OVERLOAD.judge(pipe, moto, look)
        OVERLOAD.check_frame(pipe, dets)
    assert "overloading" in pipe.ledger_manager.ledgers[1].violations


def test_overloading_without_a_helmet_look_counts_person_boxes_as_before():
    pipe = SimpleNamespace(ledger_manager=ActiveLedgerManager(), max_riders=2)
    for i in range(12):
        dets = [Det(1, list(MOTO), "motorcycle"), Det(-1, [1010, 950, 60, 150], "person")]
        pipe.ledger_manager.update(dets, i / FPS)
        OVERLOAD.check_frame(pipe, dets)
    assert "overloading" not in pipe.ledger_manager.ledgers[1].violations


# ─── No plate versus plate not read ──────────────────────────────────────────

def plate_ledger(looks):
    """A car that gets one plate look per entry: None = the model found nothing, a number = its confidence."""
    pipe = SimpleNamespace(ledger_manager=ActiveLedgerManager())
    for i in range(10):                                   # settle the class and the path first
        pipe.ledger_manager.update([Det(1, [500, 900 - 9 * i, 120, 90], "car")], i / FPS)
    det = Det(1, [500, 810, 120, 90], "car")
    for conf in looks:
        NO_PLATE.judge(pipe, det, SimpleNamespace(found=conf is not None, confidence=conf or 0.0, search_box=[500, 810, 120, 90]))
    return pipe.ledger_manager.ledgers[1]


def test_plate_status_no_plate_when_the_model_never_fired():
    ledger = plate_ledger([None] * 6)
    assert plate_status(ledger) == "no_plate"
    assert "no_plate" in ledger.pending


def test_plate_status_not_read_when_a_plate_was_clearly_seen():
    assert plate_status(plate_ledger([None, 0.7, None])) == "not_read"
    assert plate_status(plate_ledger([0.2, 0.25, 0.2, 0.2])) == "not_read"      # weak looks that add up


def test_plate_status_unclear_on_one_weak_look():
    ledger = plate_ledger([None] * 6 + [0.15])
    assert plate_status(ledger) == "unclear"
    assert plate_evidence(ledger)["plate_looks"] == 1 and plate_evidence(ledger)["best_conf"] == 0.15


def test_plate_status_not_checked_with_too_few_looks():
    assert plate_status(plate_ledger([None, None])) == "not_checked"


def test_ticket_carries_the_plate_status():
    pipe = SimpleNamespace(ledger_manager=ActiveLedgerManager())
    mgr = pipe.ledger_manager
    for i in range(10):
        mgr.update([Det(1, [500, 900 - 9 * i, 120, 90], "car")], i / FPS)
    det = Det(1, [500, 810, 120, 90], "car")
    for _ in range(6):
        NO_PLATE.judge(pipe, det, SimpleNamespace(found=False, confidence=0.0, search_box=[500, 810, 120, 90]))
    mgr.finalize_all()
    ticket = mgr.drain_tickets()[0]
    assert ticket["violations"] == ["no_plate"] and ticket["plate_status"] == "no_plate"
    assert ticket["plate_evidence"]["fair_looks"] == 6


# ─── Stop sign reader linked to the stop-line rule ───────────────────────────

SIGNS = REGISTRY["disregarding_signs"]
STOP_LINE = [[800, 1000], [1200, 1000]]


def run_the_stop_line(zone):
    """A car drives up the picture over the stop line without stopping."""
    mgr = ActiveLedgerManager()
    flagged = False
    for i in range(40):
        mgr.update([Det(1, box(1000, 1300 - 15 * i))], i / FPS)
        flagged = SIGNS.evaluate(mgr, 1, [zone]) or flagged
    return flagged


def stop_zone(**extra):
    return SIGNS.parse_zone({"coordinates": BIG_ZONE, "sign": "stop", "stop_line": STOP_LINE, **extra})


def test_stop_zone_without_sign_reading_works_as_before():
    assert run_the_stop_line(stop_zone())


def test_stop_zone_waits_for_a_real_sign_when_asked_to_read_it():
    assert not run_the_stop_line(stop_zone(read_sign=True))


def test_stop_zone_is_judged_after_the_reader_found_a_sign(monkeypatch):
    from engine import sign_reader
    zone = stop_zone(read_sign=True)
    monkeypatch.setattr(sign_reader, "find_stop_signs", lambda frame: [{"box": [1250, 900, 60, 60], "confidence": 0.8}])
    pipe = SimpleNamespace()
    SIGNS.prepare(pipe, None, [], [zone], 0.0)
    assert zone["sign_confirmed"] and zone["sign_confidence"] == 0.8
    assert run_the_stop_line(zone)


def test_a_sign_far_from_the_zone_does_not_confirm_it(monkeypatch):
    from engine import sign_reader
    small = SIGNS.parse_zone({"coordinates": [[800, 900], [1200, 900], [1200, 1100], [800, 1100]], "sign": "stop",
                              "stop_line": STOP_LINE, "read_sign": True})
    monkeypatch.setattr(sign_reader, "find_stop_signs", lambda frame: [{"box": [50, 50, 40, 40], "confidence": 0.9}])
    SIGNS.prepare(SimpleNamespace(), None, [], [small], 0.0)
    assert not small.get("sign_confirmed")
