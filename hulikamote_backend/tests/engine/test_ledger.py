"""
engine/ledger.py - the movement and zone rules, fed with scripted cars (no model, no video).
Each rule has a must-flag case and must-not-flag cases for the usual false-positive traps.
"""
import math

from engine.ledger import ActiveLedgerManager
from engine.violations import REGISTRY
from engine.violations.geometry import rider_boxes
from engine.violations.swerving import count_swings
from tests.helpers import BIG_ZONE, FPS, H, STOP_LINE, W, Det, drive, go_up_then


CROSSWALK = [{"polygon": BIG_ZONE, "time_limit": 3.0}]


def crosswalk(mgr):
    return lambda tid: REGISTRY["pedestrian_lane"].evaluate(mgr, tid, CROSSWALK)


def test_pedestrian_lane_flags_car_stopped_past_limit():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(500, 500)] * int(5 * FPS), crosswalk(mgr))
    assert "pedestrian_lane" in mgr.ledgers[1].violations


def test_pedestrian_lane_ignores_short_stop():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(500, 500)] * int(2 * FPS), crosswalk(mgr))


def test_pedestrian_lane_ignores_moving_car():
    mgr = ActiveLedgerManager()
    path = [(500, 1500 - 9 * i) for i in range(int(6 * FPS))]  # 90 px/s
    assert not drive(mgr, path, crosswalk(mgr))


def test_pedestrian_lane_ignores_stop_outside_zone():
    mgr = ActiveLedgerManager()
    zones = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]], "time_limit": 3.0}]
    assert not drive(mgr, [(500, 500)] * int(5 * FPS), lambda t: REGISTRY["pedestrian_lane"].evaluate(mgr, t, zones))


NO_LEFT = [{"polygon": BIG_ZONE, "vector": (-1.0, 0.0)}]   # arrow points left


def turn(mgr, zones=NO_LEFT):
    return lambda tid: REGISTRY["illegal_turn"].evaluate(mgr, tid, zones)


def test_illegal_turn_flags_left_turn_in_no_left_zone():
    mgr = ActiveLedgerManager()
    assert drive(mgr, go_up_then(-1), turn(mgr))
    assert "illegal_turn" in mgr.ledgers[1].violations


def test_illegal_turn_ignores_going_straight():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, go_up_then(0), turn(mgr))


def test_illegal_turn_ignores_allowed_right_turn():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, go_up_then(+1), turn(mgr))


def test_illegal_turn_ignores_car_already_heading_that_way():
    """A car driving straight along the arrow direction never turned."""
    mgr = ActiveLedgerManager()
    path = [(1500 - 9 * i, 800) for i in range(40)]
    assert not drive(mgr, path, turn(mgr))


def test_illegal_turn_ignores_box_jitter_when_stopped():
    mgr = ActiveLedgerManager()
    path = [(1000 + (i % 3) * 4 - 4, 1000 + (i % 2) * 4) for i in range(60)]
    assert not drive(mgr, path, turn(mgr))


ROAD = [{"polygon": BIG_ZONE}]


def swerve(mgr):
    return lambda tid: REGISTRY["swerving"].evaluate(mgr, tid, ROAD)


def test_swerving_flags_weaving_car():
    mgr = ActiveLedgerManager()
    # 60 px/s forward, +/-80 px side to side every 2 s
    path = [(1000 + 80 * math.sin(2 * math.pi * (i / FPS) / 2.0), 1800 - 6 * i) for i in range(int(6 * FPS))]
    assert drive(mgr, path, swerve(mgr))
    assert "swerving" in mgr.ledgers[1].violations


def test_swerving_ignores_straight_driving_with_jitter():
    mgr = ActiveLedgerManager()
    path = [(1000 + ((i * 7) % 11) - 5, 1800 - 6 * i) for i in range(int(6 * FPS))]
    assert not drive(mgr, path, swerve(mgr))


def test_swerving_ignores_single_lane_change():
    mgr = ActiveLedgerManager()
    path = []
    for i in range(int(6 * FPS)):
        t = i / FPS
        shift = 0 if t < 2 else (120 if t > 4 else 60 * (t - 2))   # 120 px move over 2 s
        path.append((1000 + shift, 1800 - 6 * i))
    assert not drive(mgr, path, swerve(mgr))


def test_swerving_ignores_stopped_car():
    mgr = ActiveLedgerManager()
    path = [(1000 + (i % 2) * 30, 1000) for i in range(int(6 * FPS))]
    assert not drive(mgr, path, swerve(mgr))


def testcount_swings():
    assert count_swings([0, 5, 10, 5, 0, 5, 10], 8) == 2
    assert count_swings([0, 3, -3, 3, -3], 8) == 0          # below amplitude = jitter
    assert count_swings([0, 10, 20, 10, 0], 8) == 1         # one bump = lane change


MOTO = [400, 300, 100, 150]   # x, y, w, h  (lower body y 345..472)


def rider(x):
    """Seated rider: feet around the motorcycle's lower body."""
    return [x, 200, 60, 200]   # feet at y=400


def test_count_riders_counts_people_on_the_motorcycle():
    assert len(rider_boxes(MOTO, [rider(400), rider(420), rider(440)])) == 3


def test_count_riders_ignores_people_off_the_motorcycle():
    pedestrian_beside = [600, 250, 50, 200]      # feet outside the motorcycle's width
    person_behind = [420, 50, 50, 150]           # feet far above the motorcycle (further up the road)
    assert len(rider_boxes(MOTO, [pedestrian_beside, person_behind])) == 0


def overload_run(rider_counts, max_riders=2):
    mgr = ActiveLedgerManager()
    flagged = False
    for i, n in enumerate(rider_counts):
        mgr.update([Det(7, MOTO, "motorcycle")], i / FPS)
        flagged = REGISTRY["overloading"].vote_count(mgr, 7, n, max_riders) or flagged
    return flagged, mgr


def test_overloading_flags_three_riders():
    flagged, mgr = overload_run([3] * 6)
    assert flagged and "overloading" in mgr.ledgers[7].violations


def test_overloading_allows_two_riders():
    assert not overload_run([2] * 10)[0]


def test_overloading_ignores_one_off_extra_person():
    """One duplicated / passing person box must not create a ticket."""
    assert not overload_run([2, 3, 2, 2, 2, 2, 2, 2, 2, 2])[0]


def test_overloading_respects_max_riders_setting():
    assert not overload_run([3] * 6, max_riders=3)[0]


def plate_run(found, cls="car", vy=-9, width=W, warmup=5):
    """Drive a vehicle (vy<0 = moving up the image = rear to the camera), one plate look per frame after warm-up."""
    mgr = ActiveLedgerManager()
    flagged = False
    for i in range(warmup + len(found)):
        mgr.update([Det(3, [1000, int(1500 + vy * i), width, H], cls)], i / FPS)
        if i >= warmup:
            flagged = REGISTRY["no_plate"].record_look(mgr, 3, found[i - warmup])
    return flagged, mgr.ledgers[3]


def test_no_plate_flags_after_enough_looks_with_no_plate():
    pending, ledger = plate_run([False] * 6)
    assert pending and "no_plate" in ledger.pending
    assert "no_plate" not in ledger.violations                 # not a ticket yet: decided when it leaves
    ActiveLedgerManager().decide_end_of_track(ledger)
    assert "no_plate" in ledger.violations and not ledger.pending


def test_no_plate_needs_enough_looks():
    assert not plate_run([False] * 5)[0]


def test_no_plate_cleared_once_a_plate_is_seen():
    """Missed often (far away, blur) but found once: the vehicle has a plate."""
    _, ledger = plate_run([False] * 6 + [True] + [False] * 6)
    ActiveLedgerManager().decide_end_of_track(ledger)
    assert "no_plate" not in ledger.violations


def test_cleared_suspicion_deletes_its_evidence_photos(tmp_path):
    """Photos taken while 'no plate seen yet' are removed when a plate is found later."""
    _, ledger = plate_run([False] * 6)
    photo, crop, clean = tmp_path / "ev1.jpg", tmp_path / "crop1.jpg", tmp_path / "clean1.jpg"
    for f in (photo, crop, clean):
        f.write_bytes(b"x")
    ledger.add_evidence_frame(str(photo), bbox=[0, 0, 1, 1], t=0.0, car_crop=crop.name)
    ledger.evidence_meta[-1]["clean"] = clean.name             # the harvest crop saved with each evidence frame
    ledger.plate_hits = 1                                      # a plate was found after all
    ledger.pending.discard("no_plate")
    ActiveLedgerManager().decide_end_of_track(ledger)
    assert not ledger.violations
    assert not photo.exists() and not crop.exists() and not clean.exists()


def test_video_end_decides_cars_still_on_screen():
    mgr = ActiveLedgerManager()
    for i in range(11):
        mgr.update([Det(3, [1000, int(1500 - 9 * i), W, H])], i / FPS)
        if i >= 5:
            REGISTRY["no_plate"].record_look(mgr, 3, False)
    mgr.finalize_all()
    assert not mgr.ledgers
    assert mgr.pending_tickets[0]["violations"] == ["no_plate"]


def test_no_plate_skips_vehicles_too_small_to_judge():
    assert not plate_run([False] * 12, width=40)[0]


def test_no_plate_motorcycle_only_judged_from_the_rear():
    assert plate_run([False] * 6, cls="motorcycle", vy=-9)[0]          # moving away: rear plate visible
    assert not plate_run([False] * 12, cls="motorcycle", vy=+9)[0]     # coming toward camera: front has no plate


def test_no_plate_waits_for_settled_class():
    """Looks taken before the vehicle class settles (first 5 frames) do not count."""
    mgr = ActiveLedgerManager()
    mgr.update([Det(3, [1000, 1500, W, H])], 0.0)
    assert not REGISTRY["no_plate"].record_look(mgr, 3, False) and mgr.ledgers[3].plate_checks == 0


def drive_up(mgr, y_from, y_to, light_at, speed=9, stop_frames=None):
    """Drive straight up from y_from to y_to; `light_at(i)` gives the light each frame. Returns True if flagged."""
    zone = {"polygon": BIG_ZONE, "stop_line": STOP_LINE, "light": "unknown"}
    ys = []
    y = y_from
    while y > y_to:
        ys.append(y)
        y -= speed
    if stop_frames:   # pause at a given y for N frames
        at, n = stop_frames
        idx = next(k for k, v in enumerate(ys) if v <= at)
        ys = ys[:idx] + [ys[idx]] * n + ys[idx:]
    flagged = False
    for i, y in enumerate(ys):
        zone["light"] = light_at(i)
        mgr.update([Det(1, [1000 - W // 2, int(y - H), W, H])], i / FPS)
        flagged = REGISTRY["red_light"].evaluate(mgr, 1, [zone]) or flagged
    return flagged


def test_red_light_flags_crossing_on_red():
    mgr = ActiveLedgerManager()
    assert drive_up(mgr, 1300, 700, lambda i: "red")
    assert "red_light" in mgr.ledgers[1].violations


def test_red_light_ignores_crossing_on_green_or_yellow():
    assert not drive_up(ActiveLedgerManager(), 1300, 700, lambda i: "green")
    assert not drive_up(ActiveLedgerManager(), 1300, 700, lambda i: "yellow")


def test_red_light_ignores_car_that_crossed_before_it_turned_red():
    # crossing happens around frame 34 (300 px / 9 px); light turns red at frame 40
    assert not drive_up(ActiveLedgerManager(), 1300, 700, lambda i: "red" if i >= 40 else "green")


def test_red_light_ignores_car_waiting_at_the_line():
    """Stopped just before the line on red, box wobbling: no crossing."""
    mgr = ActiveLedgerManager()
    zone = {"polygon": BIG_ZONE, "stop_line": STOP_LINE, "light": "red"}
    flagged = False
    for i in range(60):
        y = 1300 - min(i, 30) * 9 + (i % 2) * 6     # drives up to y=1030, then wobbles there
        mgr.update([Det(1, [950, int(y - H), W, H])], i / FPS)
        flagged = REGISTRY["red_light"].evaluate(mgr, 1, [zone]) or flagged
    assert not flagged


def test_red_light_unknown_light_never_tickets():
    assert not drive_up(ActiveLedgerManager(), 1300, 700, lambda i: "unknown")


def sign(mgr, **zone):
    zones = [{"polygon": BIG_ZONE, **zone}]
    return lambda tid: REGISTRY["disregarding_signs"].evaluate(mgr, tid, zones)


def test_sign_no_entry():
    up = [(1000, 1500 - 9 * i) for i in range(30)]
    down = [(1000, 500 + 9 * i) for i in range(30)]
    mgr = ActiveLedgerManager()
    assert drive(mgr, up, sign(mgr, sign="no_entry", vector=(0.0, -1.0)))
    assert "disregarding_signs" in mgr.ledgers[1].violations
    mgr = ActiveLedgerManager()
    assert not drive(mgr, down, sign(mgr, sign="no_entry", vector=(0.0, -1.0)))


def test_sign_no_turn():
    mgr = ActiveLedgerManager()
    assert drive(mgr, go_up_then(-1), sign(mgr, sign="no_turn", vector=(-1.0, 0.0)))
    mgr = ActiveLedgerManager()
    assert not drive(mgr, go_up_then(0), sign(mgr, sign="no_turn", vector=(-1.0, 0.0)))


def test_sign_no_stopping():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(500, 500)] * int(7 * FPS), sign(mgr, sign="no_stopping", time_limit=5.0))
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(500, 500)] * int(3 * FPS), sign(mgr, sign="no_stopping", time_limit=5.0))


def test_sign_vehicle_ban():
    path = [(1000, 1500 - 9 * i) for i in range(10)]
    mgr = ActiveLedgerManager()
    assert drive(mgr, path, sign(mgr, sign="vehicle_ban", banned_classes=["truck"]), cls="truck")
    mgr = ActiveLedgerManager()
    assert not drive(mgr, path, sign(mgr, sign="vehicle_ban", banned_classes=["truck"]), cls="car")


def test_sign_stop_requires_full_stop_before_line():
    rolling = [(1000, 1300 - 9 * i) for i in range(60)]                     # never stops, crosses y=1000
    stopping = [(1000, 1300 - 9 * i) for i in range(30)] + [(1000, 1030)] * 20 + \
               [(1000, 1030 - 9 * i) for i in range(1, 30)]                 # stops 2 s at the line, then goes
    mgr = ActiveLedgerManager()
    assert drive(mgr, rolling, sign(mgr, sign="stop", stop_line=STOP_LINE))
    mgr = ActiveLedgerManager()
    assert not drive(mgr, stopping, sign(mgr, sign="stop", stop_line=STOP_LINE))


def test_rider_boxes_widen_helmet_crop():
    riders = rider_boxes(MOTO, [rider(400), [900, 0, 50, 50]])
    assert riders == [rider(400)]


def signal_run(path, blinking):
    mgr = ActiveLedgerManager()
    zones = [{"polygon": BIG_ZONE}]
    flagged = False
    for i, (x, y) in enumerate(path):
        mgr.update([Det(1, [int(x - W / 2), int(y - H), W, H])], i / FPS)
        left = (0.05 if (i / FPS) % 0.8 < 0.4 else 0.0) if blinking else 0.0
        mgr.ledgers[1].blink.append((i / FPS, left, 0.0))
        flagged = REGISTRY["signal_light"].evaluate(mgr, 1, zones) or flagged
    return flagged


def test_signal_light_turn_without_indicator():
    assert signal_run(go_up_then(-1), blinking=False)


def test_signal_light_turn_with_indicator_is_fine():
    assert not signal_run(go_up_then(-1), blinking=True)


def test_signal_light_going_straight_needs_no_indicator():
    assert not signal_run(go_up_then(0), blinking=False)


# ─── Counterflow, illegal parking, restricted lane (the three zone rules every camera starts with) ──

UP = (0.0, -1.0)   # legal flow: up the image (y gets smaller)
FLOW_UP = [{"polygon": BIG_ZONE, "vector": UP}]


def counterflow(mgr, zones=FLOW_UP):
    return lambda tid: REGISTRY["counterflow"].evaluate(mgr, tid, zones)


def test_counterflow_flags_car_driving_against_the_arrow():
    mgr = ActiveLedgerManager()
    path = [(1000, 500 + 9 * i) for i in range(30)]          # drives DOWN the image
    assert drive(mgr, path, counterflow(mgr))
    assert "counterflow" in mgr.ledgers[1].violations


def test_counterflow_ignores_car_driving_with_the_arrow():
    mgr = ActiveLedgerManager()
    path = [(1000, 1500 - 9 * i) for i in range(30)]
    assert not drive(mgr, path, counterflow(mgr))


def test_counterflow_ignores_a_parked_car_with_box_jitter():
    mgr = ActiveLedgerManager()
    path = [(1000 + (i % 2), 800 + (i % 3)) for i in range(30)]
    assert not drive(mgr, path, counterflow(mgr))


def test_counterflow_ignores_a_parked_car_whose_box_creeps_against_the_arrow():
    mgr = ActiveLedgerManager()
    path = [(1000, 800 + i) for i in range(40)]              # 10 px/s of box drift (not driving) for 4 s
    assert not drive(mgr, path, counterflow(mgr))


def test_counterflow_needs_the_wrong_way_to_last():
    mgr = ActiveLedgerManager()
    path = [(1000, 500 + 9 * i) for i in range(10)] + [(1000, 581 - 9 * i) for i in range(30)]   # 1 s wrong, then fine
    assert not drive(mgr, path, counterflow(mgr))


def test_counterflow_ignores_a_car_going_mostly_sideways():
    mgr = ActiveLedgerManager()
    path = [(1000 + 9 * i, 500 + 2 * i) for i in range(40)]  # about 102 deg off the arrow: across the road, not against it
    assert not drive(mgr, path, counterflow(mgr))


def test_counterflow_ignores_wrong_way_outside_the_zone():
    mgr = ActiveLedgerManager()
    zones = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]], "vector": UP}]
    path = [(1000, 500 + 9 * i) for i in range(30)]
    assert not drive(mgr, path, counterflow(mgr, zones))


def test_counterflow_needs_a_few_frames_first():
    mgr = ActiveLedgerManager()
    path = [(1000, 500 + 9 * i) for i in range(3)]
    assert not drive(mgr, path, counterflow(mgr))


def test_counterflow_uses_each_zones_own_arrow():
    mgr = ActiveLedgerManager()
    left_half = [[0, 0], [1000, 0], [1000, 2000], [0, 2000]]
    right_half = [[1000, 0], [2000, 0], [2000, 2000], [1000, 2000]]
    zones = [{"polygon": left_half, "vector": UP}, {"polygon": right_half, "vector": (0.0, 1.0)}]
    going_down_right = [(1500, 500 + 9 * i) for i in range(30)]    # fine in the right zone (arrow points down)
    assert not drive(mgr, going_down_right, counterflow(mgr, zones))
    going_down_left = [(500, 500 + 9 * i) for i in range(30)]      # wrong way in the left zone
    assert drive(mgr, going_down_left, counterflow(mgr, zones), tid=2)


NO_PARKING = [{"polygon": BIG_ZONE, "time_limit": 5.0}]


def parking(mgr, zones=NO_PARKING):
    return lambda tid: REGISTRY["illegal_parking"].evaluate(mgr, tid, zones)


def test_illegal_parking_flags_car_stopped_past_the_limit():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(500, 500)] * int(8 * FPS), parking(mgr))
    assert "illegal_parking" in mgr.ledgers[1].violations


def test_illegal_parking_ignores_a_short_stop():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(500, 500)] * int(3 * FPS), parking(mgr))


def test_illegal_parking_ignores_a_moving_car():
    mgr = ActiveLedgerManager()
    path = [(500, 1500 - 9 * i) for i in range(int(8 * FPS))]
    assert not drive(mgr, path, parking(mgr))


def test_illegal_parking_ignores_a_stop_outside_the_zone():
    mgr = ActiveLedgerManager()
    zones = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]], "time_limit": 5.0}]
    assert not drive(mgr, [(500, 500)] * int(8 * FPS), parking(mgr, zones))


def test_illegal_parking_timer_restarts_after_the_car_moves():
    mgr = ActiveLedgerManager()
    stop_a = [(500, 500)] * int(3 * FPS)
    drive_off = [(500 - 20 * i, 500) for i in range(1, 6)]
    stop_b = [(400, 500)] * int(3 * FPS)                        # 3 s + 3 s, never 5 s in a row
    assert not drive(mgr, stop_a + drive_off + stop_b, parking(mgr))


def test_illegal_parking_uses_the_zones_own_limit():
    mgr = ActiveLedgerManager()
    quick = [{"polygon": BIG_ZONE, "time_limit": 1.0}]
    assert drive(mgr, [(500, 500)] * int(3 * FPS), parking(mgr, quick))


BUS_LANE = [{"polygon": BIG_ZONE, "allowed_classes": ["bus"]}]


def restricted(mgr, zones=BUS_LANE):
    return lambda tid: REGISTRY["restricted_lane"].evaluate(mgr, tid, zones)


def test_restricted_lane_flags_a_car_in_a_bus_lane():
    mgr = ActiveLedgerManager()
    path = [(1000, 1500 - 9 * i) for i in range(20)]
    assert drive(mgr, path, restricted(mgr), cls="car")
    assert "restricted_lane" in mgr.ledgers[1].violations


def test_restricted_lane_allows_a_bus():
    mgr = ActiveLedgerManager()
    path = [(1000, 1500 - 9 * i) for i in range(20)]
    assert not drive(mgr, path, restricted(mgr), cls="bus")


def test_restricted_lane_ignores_a_car_outside_the_lane():
    mgr = ActiveLedgerManager()
    zones = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]], "allowed_classes": ["bus"]}]
    path = [(1000, 1500 - 9 * i) for i in range(20)]
    assert not drive(mgr, path, restricted(mgr, zones), cls="car")


def test_restricted_lane_waits_until_the_vehicle_class_is_settled():
    mgr = ActiveLedgerManager()
    path = [(1000, 1500 - 9 * i) for i in range(4)]      # fewer than 5 looks: class still "unknown"
    assert not drive(mgr, path, restricted(mgr), cls="car")


def test_restricted_lane_with_no_allowed_classes_closes_the_lane_to_everyone():
    mgr = ActiveLedgerManager()
    closed = [{"polygon": BIG_ZONE, "allowed_classes": []}]
    path = [(1000, 1500 - 9 * i) for i in range(20)]
    assert drive(mgr, path, restricted(mgr, closed), cls="bus")
