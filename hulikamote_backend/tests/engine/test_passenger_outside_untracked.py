"""
Passengers outside (2026-11-19): people the detector is unsure of have no stable track number and show on some looks only.
The rule must still find them (same place on the vehicle over time), and the ledger must not turn a fast person carried by a
bus / jeepney into a "motorcycle".
"""
from types import SimpleNamespace

from engine.ledger import ActiveLedgerManager
from engine.violations import REGISTRY
from tests.helpers import FPS, Det

RULE = REGISTRY["passenger_outside"]


def run(vehicle_cls, build, frames=40, size=(220, 200), step=9, ids=True):
    """The vehicle drives up the picture; build(i, ytop) gives the person detections of frame i."""
    pipe = SimpleNamespace(ledger_manager=ActiveLedgerManager(), config={})
    for i in range(frames):
        ytop = 1300 - step * i
        dets = [Det(1, [1000, ytop, *size], vehicle_cls)] + build(i, ytop)
        pipe.ledger_manager.update(dets, i / FPS)
        RULE.check_frame(pipe, dets)
    return pipe.ledger_manager.ledgers[1]


def test_a_jeepney_roof_rider_without_a_track_number_is_found():
    ledger = run("jeepney", lambda i, y: [Det(-1, [1090, y - 40, 40, 80], "person")])
    assert "passenger_outside" in ledger.violations


def test_a_rider_the_detector_sees_only_every_third_look_is_found():
    ledger = run("jeepney", lambda i, y: [Det(-1, [1090, y - 40, 40, 80], "person")] if i % 3 == 0 else [], frames=60)
    assert "passenger_outside" in ledger.violations


def test_a_person_standing_on_the_back_step_seen_from_behind_is_found():
    # the jeepney drives away from the camera; the person stands at the bottom edge of its box, tall, wholly inside it
    ledger = run("jeepney", lambda i, y: [Det(-1, [1090, y + 80, 40, 120], "person")])
    assert "passenger_outside" in ledger.violations


def test_a_seated_passenger_seen_through_the_back_is_not_outside():
    ledger = run("jeepney", lambda i, y: [Det(-1, [1090, y + 60, 40, 70], "person")])
    assert "passenger_outside" not in ledger.violations


def test_every_class_but_the_motorcycle_is_judged():
    for cls in ("bus", "jeepney", "truck", "pickup", "car", "tricycle"):
        ledger = run(cls, lambda i, y: [Det(-1, [1090, y - 40, 40, 80], "person")])
        assert "passenger_outside" in ledger.violations, cls
    assert "passenger_outside" not in run("motorcycle", lambda i, y: [Det(-1, [1090, y - 40, 40, 80], "person")]).violations


def test_a_pedestrian_walking_by_without_a_track_number_is_not_flagged():
    ledger = run("jeepney", lambda i, y: [Det(-1, [1090, 1100 - 2 * i, 40, 80], "person")])      # feet on the jeepney's box for a moment
    assert "passenger_outside" not in ledger.violations


def test_a_person_the_jeepney_carries_stays_a_person_even_when_fast():
    mgr = ActiveLedgerManager()
    for i in range(30):                                      # 25 px a look = 250 px/s: 3 body heights a second
        ytop = 1500 - 25 * i
        jeepney = Det(1, [1000, ytop, 220, 200], "jeepney")
        rider = Det(1_000_050, [1090, ytop - 70, 40, 80], "person")      # on the roof: feet at the roof line, the box almost wholly above the jeepney's
        mgr.update([jeepney, rider], i / FPS)
    assert not mgr.ledgers[1_000_050].rides
    assert rider.cls == "person"


def test_a_fast_person_with_no_vehicle_under_it_is_still_a_rider():
    mgr = ActiveLedgerManager()
    for i in range(30):
        mgr.update([Det(1_000_050, [1090, 1500 - 25 * i, 40, 80], "person")], i / FPS)
    assert mgr.ledgers[1_000_050].rides


def test_a_passenger_on_the_far_back_step_shows_only_over_the_roof_edge():
    from engine.violations.onboard import outside_position
    jeepney = [1204, 723, 494, 716]                                  # drives toward the camera: its back is the top of the box
    assert outside_position(jeepney, [1319, 640, 76, 70], (0.0, 1.0)) == "roof"      # head and shoulders over the roof's back edge
    assert outside_position(jeepney, [1319, 690, 76, 10], (0.0, 1.0)) is None        # a speck is no person
