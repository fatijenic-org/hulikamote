"""
Track-ID stitching tests: a vehicle that DeepSORT re-issues under a new ID must
keep ONE ledger / ONE ticket, while unrelated vehicles must never be merged.
Uses synthetic detections only (no model, no video).
"""

import numpy as np


from engine.ledger import ActiveLedgerManager  # noqa: E402

FPS = 30.0
W, H = 100, 80


class Det:
    """Minimal stand-in for YoloDetection."""

    def __init__(self, track_id, bbox, cls="car"):
        self.track_id = track_id
        self.bbox = bbox
        self.cls = cls


def car_bbox(i, x=500, y0=600, vy=-3.0):
    """Car moving straight 'up' the image at 3 px/frame (90 px/s)."""
    return [x, int(y0 + vy * i), W, H]


def run(mgr, i, dets, frame=None):
    mgr.update(dets, i / FPS, frame)
    return dets


def warm_up(mgr, raw_id, frames, frame=None, **kw):
    for i in range(frames):
        run(mgr, i, [Det(raw_id, car_bbox(i, **kw))], frame)


def test_occlusion_gap_is_stitched_into_one_ledger():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)
    for i in range(20, 30):                       # 10 frames lost
        run(mgr, i, [])
    dets = run(mgr, 30, [Det(2, car_bbox(30))])    # re-issued as ID 2
    assert dets[0].track_id == 1                   # rewritten to canonical ID
    assert list(mgr.ledgers) == [1]
    assert mgr.aliases == {2: 1}
    assert mgr.ledgers[1].merged_ids == {2}


def test_alias_keeps_applying_on_following_frames():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)
    for i in range(20, 30):
        run(mgr, i, [])
    for i in range(30, 40):
        dets = run(mgr, i, [Det(2, car_bbox(i))])
        assert dets[0].track_id == 1
    assert list(mgr.ledgers) == [1]


def test_one_ticket_with_merged_ids_after_stitch():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)
    mgr.ledgers[1].violations.add("counterflow")
    for i in range(20, 30):
        run(mgr, i, [])
    for i in range(30, 40):
        run(mgr, i, [Det(2, car_bbox(i))])
    for i in range(40, 40 + 65):                   # vehicle leaves
        run(mgr, i, [])
    tickets = mgr.drain_tickets()
    assert len(tickets) == 1
    assert tickets[0]["track_id"] == 1
    assert tickets[0]["merged_track_ids"] == [2]
    assert "counterflow" in tickets[0]["violations"]


def test_vehicle_appearing_behind_moving_car_is_not_stitched():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)                            # last y ~ 543, moving up
    for i in range(20, 30):
        run(mgr, i, [])
    behind = [500, 543 + 40, W, H]                 # back down the road it came from
    dets = run(mgr, 30, [Det(2, behind)])
    assert dets[0].track_id == 2
    assert sorted(mgr.ledgers) == [1, 2]


def test_far_away_new_vehicle_is_not_stitched():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)
    for i in range(20, 30):
        run(mgr, i, [])
    dets = run(mgr, 30, [Det(2, [1500, 900, W, H])])
    assert dets[0].track_id == 2
    assert sorted(mgr.ledgers) == [1, 2]


def test_different_vehicle_class_is_not_stitched():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)                            # class "car"
    for i in range(20, 30):
        run(mgr, i, [])
    dets = run(mgr, 30, [Det(2, car_bbox(30), cls="motorcycle")])
    assert dets[0].track_id == 2


def test_long_occlusion_within_ledger_lifetime_is_stitched():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)
    for i in range(20, 75):                        # 55 frames (~1.8 s) lost
        run(mgr, i, [])
    dets = run(mgr, 75, [Det(2, car_bbox(75))])
    assert dets[0].track_id == 1


def test_gap_longer_than_limit_is_not_stitched():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)
    mgr.ledgers[1].missed_frames = 1               # still alive, but the clock is 4 s later
    mgr.update([Det(2, car_bbox(20))], 4.0 + 19 / FPS)
    assert mgr.aliases == {}


def test_two_lost_two_born_pair_up_correctly():
    mgr = ActiveLedgerManager()
    for i in range(20):                            # car A left lane, car B right lane
        run(mgr, i, [Det(1, car_bbox(i, x=300)), Det(2, car_bbox(i, x=1200))])
    for i in range(20, 30):
        run(mgr, i, [])
    dets = run(mgr, 30, [Det(8, car_bbox(30, x=1200)), Det(7, car_bbox(30, x=300))])
    assert {d.bbox[0]: d.track_id for d in dets} == {1200: 2, 300: 1}


def test_original_track_returning_drops_alias_and_ids_stay_unique():
    mgr = ActiveLedgerManager()
    warm_up(mgr, 1, 20)
    for i in range(20, 25):
        run(mgr, i, [])
    run(mgr, 25, [Det(2, car_bbox(25))])           # stitched 2 -> 1
    assert mgr.aliases == {2: 1}
    dets = run(mgr, 26, [Det(1, car_bbox(26)), Det(2, car_bbox(26, x=650))])
    ids = [d.track_id for d in dets]
    assert len(set(ids)) == 2                      # never two boxes with the same ID
    assert 2 not in mgr.aliases


def _frame_with_color(bgr, bbox):
    frame = np.zeros((1080, 1920, 3), dtype=np.uint8)
    x, y, w, h = bbox
    frame[y:y + h, x:x + w] = bgr
    return frame


RED, BLUE = (0, 0, 255), (255, 0, 0)


def test_colour_mismatch_blocks_stitch():
    mgr = ActiveLedgerManager()
    for i in range(20):
        b = car_bbox(i)
        run(mgr, i, [Det(1, b)], _frame_with_color(RED, b))
    for i in range(20, 30):
        run(mgr, i, [])
    b = car_bbox(30)
    dets = run(mgr, 30, [Det(2, b)], _frame_with_color(BLUE, b))
    assert dets[0].track_id == 2
    assert sorted(mgr.ledgers) == [1, 2]


def test_colour_match_allows_stitch():
    mgr = ActiveLedgerManager()
    for i in range(20):
        b = car_bbox(i)
        run(mgr, i, [Det(1, b)], _frame_with_color(RED, b))
    for i in range(20, 30):
        run(mgr, i, [])
    b = car_bbox(30)
    dets = run(mgr, 30, [Det(2, b)], _frame_with_color(RED, b))
    assert dets[0].track_id == 1


def test_untracked_detections_are_ignored():
    mgr = ActiveLedgerManager()
    dets = run(mgr, 0, [Det(-1, car_bbox(0))])
    assert dets[0].track_id == -1
    assert mgr.ledgers == {}


# ─── people and vehicles are never stitched together ─────────────────────────

def lose_then_reappear(first_cls, second_cls, looks=3):
    """A track seen for `looks` frames (too few for its class to settle), lost for 5 frames, then a new track of another class."""
    mgr = ActiveLedgerManager()
    for i in range(looks):
        run(mgr, i, [Det(1, car_bbox(i), first_cls)])
    for i in range(looks, looks + 5):
        run(mgr, i, [])
    dets = run(mgr, looks + 5, [Det(2, car_bbox(looks + 5), second_cls)])
    return mgr, dets


def test_a_riders_short_record_is_not_stitched_onto_its_motorcycle():
    mgr, dets = lose_then_reappear("person", "motorcycle")
    assert dets[0].track_id == 2 and sorted(mgr.ledgers) == [1, 2]            # two separate ledgers
    assert mgr.aliases == {}


def test_a_motorcycles_short_record_is_not_stitched_onto_a_person_either():
    mgr, dets = lose_then_reappear("motorcycle", "person")
    assert dets[0].track_id == 2 and sorted(mgr.ledgers) == [1, 2]


def test_a_person_that_comes_back_is_still_stitched_to_the_same_person():
    mgr, dets = lose_then_reappear("person", "person")
    assert dets[0].track_id == 1 and list(mgr.ledgers) == [1]
    mgr, dets = lose_then_reappear("car", "car")                               # and vehicles keep stitching as before
    assert dets[0].track_id == 1 and list(mgr.ledgers) == [1]
