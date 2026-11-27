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
    for cls in ("bus", "jeepney", "truck", "pickup"):
        ledger = run(cls, lambda i, y: [Det(-1, [1090, y - 40, 40, 80], "person")])      # on the roof
        assert "passenger_outside" in ledger.violations, cls
    ledger = run("car", lambda i, y: [Det(-1, [1200, y + 90, 40, 100], "person")], size=(220, 200))      # hanging off the side of a car
    assert "passenger_outside" in ledger.violations
    for cls in ("car", "tricycle"):                                      # a head over the roof is the rider of the bike behind it
        assert "passenger_outside" not in run(cls, lambda i, y: [Det(-1, [1090, y - 40, 40, 80], "person")]).violations, cls
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


# ─── people searched close to each vehicle ───────────────────────────────────

def test_people_near_looks_around_every_vehicle_but_the_motorcycle():
    import numpy as np
    from yolo_inference import YoloDetection, YoloInference
    yolo = YoloInference.__new__(YoloInference)
    seen = []

    def fake(img, x0=0, y0=0):                                # the people model: the jeepney's cut shows the person that is already known, the car's a new one
        seen.append((x0, y0, img.shape[1], img.shape[0]))
        box = [110.0, 310.0, 150.0, 390.0] if x0 < 300 else [520.0, 120.0, 560.0, 200.0]
        return np.array([box]), np.array([0.6]), np.array([4])

    yolo._people_in = fake
    yolo._people_session = None                               # no COCO people model in this test: the fake stands in for the people search
    frame = np.zeros((1000, 1000, 3), np.uint8)
    found = [YoloDetection("jeepney", 0.9, [100, 300, 300, 400], "jeepney"), YoloDetection("motorcycle", 0.9, [600, 600, 100, 150], "motorcycle"),
             YoloDetection("car", 0.9, [500, 100, 200, 200], "car"), YoloDetection("person", 0.9, [110, 310, 40, 80], "person")]
    people = yolo.people_near(frame, found)
    assert len(seen) == 2                                     # jeepney and car, not the motorcycle
    assert all(p.cls == "person" and p.track_id == -1 for p in people)
    assert len(people) == 1                                   # the known person is not added twice; the car's person is new
    assert seen[0][1] == 300 - int(0.45 * 400)                # the cut starts well above the roof


# ─── riders behind or ahead of a vehicle are no passengers ───────────────────

def test_a_person_the_people_search_saw_on_a_bike_is_never_a_passenger():
    def rider(i, y):
        d = Det(-1, [1090, y - 40, 40, 80], "person")
        d.on_bike = True
        return [d]
    assert "passenger_outside" not in run("jeepney", rider).violations


def test_a_rider_seen_on_its_bike_a_moment_ago_stays_a_rider_when_the_bike_is_hidden():
    def rider(i, y):
        d = Det(-1, [1090, y - 40, 40, 80], "person")
        d.on_bike = i < 22                                   # the bike is seen for a while, then the jeepney's roof hides it
        return [d]
    assert "passenger_outside" not in run("jeepney", rider, frames=34).violations


def test_on_bike_reads_the_boxes():
    from yolo_inference import _on_bike
    assert _on_bike([100, 100, 40, 90], [90, 150, 70, 60])            # seated on it
    assert not _on_bike([100, 100, 40, 90], [300, 150, 70, 60])       # a bike elsewhere


def test_a_box_a_passenger_could_not_have_is_dropped():
    from engine.violations.onboard import reasonable_box
    jeepney = [1000, 700, 500, 700]
    assert reasonable_box(jeepney, [1300, 640, 70, 120])
    assert not reasonable_box(jeepney, [1100, 600, 400, 150])         # wider than a person, nearly as wide as the vehicle
    assert not reasonable_box(jeepney, [1100, 600, 100, 40])          # lying flat: not a person
    assert not reasonable_box(jeepney, [1100, 600, 150, 600])         # as tall as the vehicle itself
