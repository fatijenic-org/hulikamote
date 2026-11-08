"""
The five violations added after the thesis consultation: illegal U-turn, blocking the intersection,
crossing a solid line (zone rules) and passengers in a pickup bed / riding outside a bus (frame checks).
Scripted vehicles and people only (no model, no video); each rule has a must-flag case and the usual
false-positive traps.
"""
import math
from types import SimpleNamespace

from engine import marks
from engine.ledger import ActiveLedgerManager
from engine.violations import REGISTRY
from engine.violations.onboard import in_trailing_body, moves_with, outside_position
from tests.helpers import BIG_ZONE, FPS, H, STOP_LINE, W, Det, drive

U_TURN = REGISTRY["illegal_u_turn"]
BLOCKING = REGISTRY["blocking_intersection"]
SOLID = REGISTRY["crossing_solid_line"]
PICKUP = REGISTRY["pickup_passengers"]
OUTSIDE = REGISTRY["riding_outside_vehicle"]


# ─── Illegal U-turn ──────────────────────────────────────────────────────────

def u_turn_path(radius=120, lead_in=15, lead_out=15, x=1000, y0=1500, speed=9):
    """Up the image, a half circle to the right, then back down."""
    pts = [(x, y0 - speed * i) for i in range(lead_in)]
    top = pts[-1][1]
    steps = 24
    for k in range(1, steps + 1):
        a = math.pi - math.pi * k / steps
        pts.append((x + radius + radius * math.cos(a), top - radius * math.sin(a)))
    end_x, end_y = pts[-1]
    pts += [(end_x, end_y + speed * i) for i in range(1, lead_out + 1)]
    return pts


def u_turn(mgr, zones=None):
    zones = zones or [{"polygon": BIG_ZONE}]
    return lambda tid: U_TURN.evaluate(mgr, tid, zones)


def test_u_turn_flags_a_vehicle_that_turns_right_round():
    mgr = ActiveLedgerManager()
    assert drive(mgr, u_turn_path(), u_turn(mgr))
    assert "illegal_u_turn" in mgr.ledgers[1].violations


def test_u_turn_flags_a_turn_to_the_left_as_well():
    mgr = ActiveLedgerManager()
    path = [(2000 - x, y) for x, y in u_turn_path(x=1000)]                # the mirror image
    assert drive(mgr, path, u_turn(mgr))


def test_u_turn_ignores_a_vehicle_driving_straight():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(1000, 1500 - 9 * i) for i in range(60)], u_turn(mgr))


def test_u_turn_ignores_an_ordinary_90_degree_turn():
    mgr = ActiveLedgerManager()
    path = [(1000, 1500 - 9 * i) for i in range(20)] + [(1000 + 9 * i, 1320) for i in range(1, 25)]
    assert not drive(mgr, path, u_turn(mgr))


def test_u_turn_ignores_a_vehicle_that_only_reverses_in_a_straight_line():
    mgr = ActiveLedgerManager()
    path = [(1000, 1500 - 9 * i) for i in range(20)] + [(1000, 1320 + 9 * i) for i in range(1, 25)]
    assert not drive(mgr, path, u_turn(mgr))


def test_u_turn_ignores_box_jitter_on_a_stopped_car():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(1000 + (i % 2) * 3, 1000 + (i % 3)) for i in range(60)], u_turn(mgr))


def test_u_turn_outside_the_zone_is_not_judged():
    mgr = ActiveLedgerManager()
    zones = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]]}]
    assert not drive(mgr, u_turn_path(), u_turn(mgr, zones))


# ─── Blocking the intersection ───────────────────────────────────────────────

BOX = [{"polygon": BIG_ZONE, "time_limit": 5.0}]


def blocking(mgr, zones=BOX):
    return lambda tid: BLOCKING.evaluate(mgr, tid, zones)


def test_blocking_flags_a_vehicle_stopped_in_the_junction_box_too_long():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(800, 800)] * int(8 * FPS), blocking(mgr))
    assert "blocking_intersection" in mgr.ledgers[1].violations


def test_blocking_ignores_a_short_stop():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(800, 800)] * int(3 * FPS), blocking(mgr))


def test_blocking_ignores_a_vehicle_moving_through():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(800, 1500 - 9 * i) for i in range(80)], blocking(mgr))


def test_blocking_ignores_a_vehicle_waiting_outside_the_box():
    mgr = ActiveLedgerManager()
    outside = [{"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]], "time_limit": 5.0}]
    assert not drive(mgr, [(800, 800)] * int(8 * FPS), blocking(mgr, outside))


def test_blocking_and_pedestrian_lane_keep_separate_timers():
    mgr = ActiveLedgerManager()
    both = lambda tid: (BLOCKING.evaluate(mgr, tid, [{"polygon": BIG_ZONE, "time_limit": 5.0}]),
                        REGISTRY["pedestrian_lane"].evaluate(mgr, tid, [{"polygon": BIG_ZONE, "time_limit": 3.0}]))[0]
    drive(mgr, [(800, 800)] * int(4 * FPS), both)
    assert mgr.ledgers[1].violations == {"pedestrian_lane"}                # 4 s: past the 3 s crosswalk limit, not the 5 s box limit


# ─── Crossing a solid line ───────────────────────────────────────────────────

LINE_ZONE = [{"polygon": BIG_ZONE, "stop_line": STOP_LINE}]               # a horizontal line at y = 1000, x 800 - 1200


def solid(mgr, zones=LINE_ZONE):
    return lambda tid: SOLID.evaluate(mgr, tid, zones)


def test_solid_line_flags_a_vehicle_that_drives_over_it():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(1000, 1300 - 9 * i) for i in range(40)], solid(mgr))
    assert "crossing_solid_line" in mgr.ledgers[1].violations


def test_solid_line_flags_a_crossing_in_the_other_direction_too():
    mgr = ActiveLedgerManager()
    assert drive(mgr, [(1000, 700 + 9 * i) for i in range(40)], solid(mgr))


def test_solid_line_ignores_a_vehicle_that_stays_on_one_side():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(1000, 1300 - 9 * i) for i in range(30)], solid(mgr))           # stops 70 px short


def test_solid_line_ignores_a_vehicle_wobbling_on_the_line():
    mgr = ActiveLedgerManager()
    start = [(1000, 1100 - 9 * i) for i in range(11)]                                       # arrives at y = 1000
    wobble = [(1000, 1000 + (8 if i % 2 else -8)) for i in range(40)]
    assert not drive(mgr, start + wobble, solid(mgr))


def test_solid_line_ignores_a_crossing_beyond_the_ends_of_the_line():
    mgr = ActiveLedgerManager()
    assert not drive(mgr, [(300, 1300 - 9 * i) for i in range(40)], solid(mgr))


def test_solid_line_zone_needs_its_line():
    assert SOLID.parse_zone({"coordinates": BIG_ZONE}) is None
    assert SOLID.parse_zone({"coordinates": BIG_ZONE, "stop_line": STOP_LINE}) == {"polygon": BIG_ZONE, "stop_line": STOP_LINE}


# ─── Who is riding ON a vehicle (geometry) ───────────────────────────────────

TRUCK = [1000, 800, 200, 220]            # x, y, w, h
UP, DOWN, RIGHT = (0.0, -1.0), (0.0, 1.0), (1.0, 0.0)


def test_bed_is_the_far_end_when_a_truck_comes_toward_the_camera():
    upper_person = [1080, 810, 40, 80]                  # high in the box
    lower_person = [1080, 940, 40, 80]
    assert in_trailing_body(TRUCK, DOWN, upper_person) and not in_trailing_body(TRUCK, DOWN, lower_person)


def test_bed_is_the_near_end_when_a_truck_drives_away_from_the_camera():
    upper_person = [1080, 810, 40, 80]
    lower_person = [1080, 940, 40, 80]
    assert in_trailing_body(TRUCK, UP, lower_person) and not in_trailing_body(TRUCK, UP, upper_person)


def test_bed_is_the_back_end_when_a_truck_drives_sideways():
    truck = [1000, 800, 300, 150]
    back, front = [1020, 820, 40, 90], [1230, 820, 40, 90]
    assert in_trailing_body(truck, RIGHT, back) and not in_trailing_body(truck, RIGHT, front)
    assert in_trailing_body(truck, (-1.0, 0.0), front) and not in_trailing_body(truck, (-1.0, 0.0), back)


def test_a_person_beside_or_far_from_the_truck_is_not_on_it():
    assert not in_trailing_body(TRUCK, UP, [1300, 940, 40, 80])             # beside it
    assert not in_trailing_body(TRUCK, UP, [1080, 1100, 40, 80])            # feet well below it: on the road behind
    assert not in_trailing_body(TRUCK, UP, [1080, 940, 40, 10])             # a speck, not a person


def test_outside_positions_on_a_bus():
    bus = [1000, 800, 220, 200]
    assert outside_position(bus, [1090, 760, 40, 80]) == "roof"            # feet at the roof line, head above it
    assert outside_position(bus, [1200, 890, 40, 100]) == "hanging"        # half over the right edge, low down
    assert outside_position(bus, [1240, 890, 40, 100]) is None             # beside the bus
    assert outside_position(bus, [1090, 900, 40, 90]) is None              # inside, a passenger in the cabin


def moving(ledger_xy):
    """A ledger fed with a straight path (for moves_with)."""
    mgr = ActiveLedgerManager()
    for i, (x, y) in enumerate(ledger_xy):
        mgr.update([Det(1, [int(x - 20), int(y - 80), 40, 80])], i / FPS)
    return mgr.ledgers[1]


def test_moves_with_needs_the_same_direction_and_a_similar_distance():
    up = moving([(1000, 1500 - 9 * i) for i in range(12)])
    same = moving([(1100, 1500 - 9 * i) for i in range(12)])
    slower_but_close = moving([(1100, 1500 - 6 * i) for i in range(12)])
    opposite = moving([(1100, 1400 + 9 * i) for i in range(12)])
    standing = moving([(1100, 1500)] * 12)
    far_faster = moving([(1100, 1500 - 40 * i) for i in range(12)])
    assert moves_with(up, same) and moves_with(up, slower_but_close)
    assert not moves_with(up, opposite) and not moves_with(up, standing) and not moves_with(up, far_faster)


def test_moves_with_waits_for_enough_history():
    short = moving([(1000, 1500 - 9 * i) for i in range(5)])
    assert not moves_with(short, short)


# ─── Passengers in a pickup bed (frame check) ────────────────────────────────

def fake_pipe(config=None):
    return SimpleNamespace(ledger_manager=ActiveLedgerManager(), config=config or {})


def run_frames(pipe, check, build, frames=30, cls="truck"):
    """`build(i, ytop)` returns the extra detections of frame i; the truck drives up the image at 90 px/s.
    A 200 px wide truck needs ~100 px of travel (12 frames) before its heading is known, then every frame is a look."""
    for i in range(frames):
        ytop = 1200 - 9 * i
        truck = Det(1, [1000, ytop, 200, 220], cls)
        dets = [truck] + build(i, ytop)
        pipe.ledger_manager.update(dets, i / FPS)
        check.check_frame(pipe, dets)
    return pipe.ledger_manager.ledgers[1]


def passenger(ytop, track_id=50, dy=120):
    return Det(track_id, [1080, ytop + dy, 40, 80], "person")


def test_pickup_flags_a_passenger_riding_in_the_back():
    pipe = fake_pipe()
    ledger = run_frames(pipe, PICKUP, lambda i, y: [passenger(y)])
    assert "pickup_passengers" in ledger.violations
    assert {label for box, label, _c in marks.current_marks(ledger, [1000, 1200 - 9 * 29, 200, 220]) if box} == {"passenger"}


def test_pickup_ignores_the_driver_in_the_cab():
    pipe = fake_pipe()
    driver = lambda i, y: [Det(50, [1080, y + 20, 40, 70], "person")]
    assert "pickup_passengers" not in run_frames(pipe, PICKUP, driver).violations


def test_pickup_ignores_a_pedestrian_standing_where_the_bed_would_be():
    pipe = fake_pipe()
    still = lambda i, y: [Det(50, [1080, 1320, 40, 80], "person")]           # not moving with the truck
    assert "pickup_passengers" not in run_frames(pipe, PICKUP, still).violations


def test_pickup_ignores_people_loading_a_parked_truck():
    pipe = fake_pipe()
    for i in range(30):
        dets = [Det(1, [1000, 1000, 200, 220], "truck"), Det(50, [1080 + (i % 2), 1120, 40, 80], "person")]
        pipe.ledger_manager.update(dets, i / FPS)
        PICKUP.check_frame(pipe, dets)
    assert "pickup_passengers" not in pipe.ledger_manager.ledgers[1].violations


def test_pickup_does_not_count_a_motorcycle_rider_beside_the_truck():
    pipe = fake_pipe()

    def rider_on_bike(i, y):
        bike = Det(60, [1070, y + 140, 70, 80], "motorcycle")
        person = Det(50, [1085, y + 130, 40, 80], "person")                  # feet on the bike, inside the truck's box
        return [bike, person]

    assert "pickup_passengers" not in run_frames(pipe, PICKUP, rider_on_bike).violations

    # the same person on something that is NOT a motorcycle is a passenger: it is the claim that excludes the rider
    def person_on_a_car(i, y):
        return [Det(60, [1070, y + 140, 70, 80], "car"), Det(50, [1085, y + 130, 40, 80], "person")]

    assert "pickup_passengers" in run_frames(fake_pipe(), PICKUP, person_on_a_car).violations


def test_pickup_tolerates_the_number_of_people_the_config_allows():
    pipe = fake_pipe({"bed_passengers_allowed": 1})
    assert "pickup_passengers" not in run_frames(pipe, PICKUP, lambda i, y: [passenger(y)]).violations
    pipe = fake_pipe({"bed_passengers_allowed": 1})
    two = lambda i, y: [passenger(y), Det(51, [1130, y + 120, 40, 80], "person")]
    assert "pickup_passengers" in run_frames(pipe, PICKUP, two).violations


def test_pickup_needs_a_few_looks_and_only_judges_trucks():
    pipe = fake_pipe()
    assert "pickup_passengers" not in run_frames(pipe, PICKUP, lambda i, y: [passenger(y)], frames=15).violations   # only ~3 looks so far
    pipe = fake_pipe()
    assert "pickup_passengers" not in run_frames(pipe, PICKUP, lambda i, y: [passenger(y)], cls="car").violations    # a car is not a pickup


# ─── Riding on the roof / hanging on (frame check) ───────────────────────────

def run_bus(pipe, build, frames=30):
    for i in range(frames):
        ytop = 1200 - 9 * i
        bus = Det(1, [1000, ytop, 220, 200], "bus")
        dets = [bus] + build(i, ytop)
        pipe.ledger_manager.update(dets, i / FPS)
        OUTSIDE.check_frame(pipe, dets)
    return pipe.ledger_manager.ledgers[1]


def test_outside_flags_a_roof_rider():
    ledger = run_bus(fake_pipe(), lambda i, y: [Det(50, [1090, y - 40, 40, 80], "person")])
    assert "riding_outside_vehicle" in ledger.violations


def test_outside_flags_someone_hanging_off_the_side():
    ledger = run_bus(fake_pipe(), lambda i, y: [Det(50, [1200, y + 90, 40, 100], "person")])
    assert "riding_outside_vehicle" in ledger.violations


def test_outside_ignores_a_pedestrian_standing_beside_the_bus():
    ledger = run_bus(fake_pipe(), lambda i, y: [Det(50, [1200, 1250, 40, 100], "person")])      # straddles the edge but stands still
    assert "riding_outside_vehicle" not in ledger.violations


def test_outside_ignores_a_passenger_inside_the_cabin():
    ledger = run_bus(fake_pipe(), lambda i, y: [Det(50, [1090, y + 100, 40, 90], "person")])
    assert "riding_outside_vehicle" not in ledger.violations


def test_outside_ignores_a_stopped_bus():
    pipe = fake_pipe()
    for i in range(30):
        dets = [Det(1, [1000, 1000, 220, 200], "bus"), Det(50, [1090, 960, 40, 80], "person")]
        pipe.ledger_manager.update(dets, i / FPS)
        OUTSIDE.check_frame(pipe, dets)
    assert "riding_outside_vehicle" not in pipe.ledger_manager.ledgers[1].violations
