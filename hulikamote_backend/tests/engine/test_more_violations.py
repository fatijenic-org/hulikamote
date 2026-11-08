"""
The five Philippine road rules added after the first 20: illegal loading / unloading, truck ban, tricycle on a
national highway, driving on the sidewalk (zone rules) and double parking (a rule that also looks at the other
vehicles). Scripted vehicles only (no model, no video); each rule has a must-flag case and the false-positive traps.
"""
from engine.ledger import ActiveLedgerManager
from engine.violations import REGISTRY
from tests.helpers import BIG_ZONE, FPS, H, W, Det, drive

LOADING = REGISTRY["illegal_loading"]
TRUCK_BAN = REGISTRY["truck_ban"]
TRICYCLE = REGISTRY["tricycle_on_highway"]
SIDEWALK = REGISTRY["sidewalk_driving"]
DOUBLE = REGISTRY["double_parking"]

SMALL_ZONE = [[0, 0], [100, 0], [100, 100], [0, 100]]


def zones(violation, cfg=None, polygon=BIG_ZONE):
    """The zones the pipeline reads, made the way the dashboard wizard makes them."""
    raw = violation.from_wizard({"rois": [{"polygon": polygon}], **(cfg or {})})
    return [violation.parse_zone(r) for r in raw]


def run(violation, points, cls, cfg=None, polygon=BIG_ZONE):
    mgr = ActiveLedgerManager()
    z = zones(violation, cfg, polygon)
    return drive(mgr, points, lambda tid: violation.evaluate(mgr, tid, z), cls=cls), mgr


def standing(x=800, y=800, seconds=12):
    return [(x, y)] * int(seconds * FPS)


def driving_up(seconds=6, x=800, y0=1500, speed=9):
    return [(x, y0 - speed * i) for i in range(int(seconds * FPS))]


# ─── Illegal loading / unloading ─────────────────────────────────────────────

def test_loading_flags_a_bus_standing_in_the_no_loading_zone():
    flagged, mgr = run(LOADING, standing(seconds=12), "bus")
    assert flagged and "illegal_loading" in mgr.ledgers[1].violations


def test_loading_judges_tricycles_and_trucks_too():
    for cls in ("tricycle", "truck"):
        assert run(LOADING, standing(seconds=12), cls)[0], cls


def test_loading_ignores_a_car_left_standing_that_is_illegal_parking():
    assert not run(LOADING, standing(seconds=12), "car")[0]


def test_loading_ignores_a_short_stop():
    assert not run(LOADING, standing(seconds=4), "bus")[0]


def test_loading_ignores_a_bus_driving_through():
    assert not run(LOADING, driving_up(seconds=8), "bus")[0]


def test_loading_ignores_a_bus_standing_outside_the_zone():
    assert not run(LOADING, standing(seconds=12), "bus", polygon=SMALL_ZONE)[0]


def test_loading_follows_the_wizard_time_limit_and_vehicle_types():
    cfg = {"time_limit": 20, "banned_classes": ["car"]}
    assert not run(LOADING, standing(seconds=12), "bus", cfg)[0]          # bus no longer judged
    assert not run(LOADING, standing(seconds=12), "car", cfg)[0]          # 12 s is under the 20 s limit
    assert run(LOADING, standing(seconds=24), "car", cfg)[0]


def test_loading_defaults_when_the_wizard_sends_no_types():
    zone = zones(LOADING)[0]
    assert zone["time_limit"] == 8.0 and zone["classes"] == ["bus", "tricycle", "truck"]


# ─── Truck ban, tricycle on a highway, sidewalk (banned types in a zone) ────

def test_truck_ban_flags_a_truck_that_stays_in_the_zone():
    flagged, mgr = run(TRUCK_BAN, driving_up(seconds=4), "truck")
    assert flagged and "truck_ban" in mgr.ledgers[1].violations


def test_truck_ban_ignores_other_vehicle_types():
    for cls in ("car", "motorcycle", "bus", "tricycle"):
        assert not run(TRUCK_BAN, driving_up(seconds=4), cls)[0], cls


def test_truck_ban_ignores_a_truck_outside_the_zone():
    assert not run(TRUCK_BAN, driving_up(seconds=4), "truck", polygon=SMALL_ZONE)[0]


def test_truck_ban_ignores_a_truck_that_only_clips_the_zone():
    clipped = [{"coordinates": [[0, 1400], [2000, 1400], [2000, 1450], [0, 1450]]}]    # a 50 px strip: ~0.5 s to cross
    mgr = ActiveLedgerManager()
    z = [TRUCK_BAN.parse_zone(c) for c in clipped]
    assert not drive(mgr, driving_up(seconds=6), lambda tid: TRUCK_BAN.evaluate(mgr, tid, z), cls="truck")


def test_truck_ban_takes_the_banned_types_from_the_wizard():
    cfg = {"banned_classes": ["car"]}
    assert run(TRUCK_BAN, driving_up(seconds=4), "car", cfg)[0]
    assert not run(TRUCK_BAN, driving_up(seconds=4), "truck", cfg)[0]


def test_tricycle_on_highway_flags_only_a_tricycle():
    flagged, mgr = run(TRICYCLE, driving_up(seconds=4), "tricycle")
    assert flagged and "tricycle_on_highway" in mgr.ledgers[1].violations
    for cls in ("motorcycle", "car", "bus", "truck"):
        assert not run(TRICYCLE, driving_up(seconds=4), cls)[0], cls


def test_sidewalk_flags_a_moving_vehicle_of_any_type():
    for cls in ("car", "motorcycle", "bus", "truck", "tricycle"):
        flagged, mgr = run(SIDEWALK, driving_up(seconds=4), cls)
        assert flagged and "sidewalk_driving" in mgr.ledgers[1].violations, cls


def test_sidewalk_ignores_a_vehicle_that_is_only_standing_there():
    assert not run(SIDEWALK, standing(seconds=12), "car")[0]


def test_sidewalk_ignores_a_vehicle_that_only_crosses_it_to_a_driveway():
    strip = [[0, 1400], [2000, 1400], [2000, 1480], [0, 1480]]                 # ~80 px: under a second at 90 px/s
    assert not run(SIDEWALK, driving_up(seconds=6), "car", polygon=strip)[0]


def test_sidewalk_ignores_a_vehicle_on_the_road():
    assert not run(SIDEWALK, driving_up(seconds=4), "car", polygon=SMALL_ZONE)[0]


def test_an_unknown_class_is_never_judged_by_a_banned_type_rule():
    mgr = ActiveLedgerManager()
    z = zones(TRUCK_BAN)
    assert not drive(mgr, driving_up(seconds=0.4), lambda tid: TRUCK_BAN.evaluate(mgr, tid, z), cls="truck")   # fewer than 5 looks


# ─── Double parking ──────────────────────────────────────────────────────────

def play(tracks, polygon=BIG_ZONE, frames=200):
    """tracks: {id: (class, first_frame, point_for(i))}. Returns the ids the double parking rule ever flagged."""
    mgr = ActiveLedgerManager()
    z = zones(DOUBLE, polygon=polygon)
    flagged = set()
    for i in range(frames):
        alive = {tid: spec for tid, spec in tracks.items() if i >= spec[1]}
        dets = []
        for tid, (cls, _first, point) in alive.items():
            x, y = point(i)
            dets.append(Det(tid, [int(x - W / 2), int(y - H), W, H], cls))
        mgr.update(dets, i / FPS)
        for tid in alive:
            if DOUBLE.evaluate(mgr, tid, z):
                flagged.add(tid)
    return flagged


KERB = ("car", 0, lambda i: (1000, 800))                       # stands at the kerb from the start
DOUBLE_PARKER = ("car", 50, lambda i: (1130, 800))             # stops beside it, across the lane, 5 s later
TRAFFIC = ("car", 0, lambda i: (1500, 1900 - 9 * i))           # drives up the image the whole time


def test_double_parking_flags_the_later_vehicle_beside_a_kerb_vehicle_while_traffic_flows():
    assert play({1: KERB, 2: DOUBLE_PARKER, 3: TRAFFIC}) == {2}


def test_double_parking_needs_traffic_moving_past():
    assert play({1: KERB, 2: DOUBLE_PARKER}) == set()           # nobody passes: could be a queue or a jam


def test_double_parking_ignores_a_vehicle_queued_behind_another():
    behind = ("car", 50, lambda i: (1000, 920))                 # 120 px behind the stopped car, same line
    assert play({1: KERB, 2: behind, 3: TRAFFIC}) == set()


def test_double_parking_ignores_a_vehicle_standing_alone():
    assert play({2: DOUBLE_PARKER, 3: TRAFFIC}) == set()        # that is illegal_parking, not double parking


def test_double_parking_ignores_a_vehicle_that_has_not_stood_long_enough():
    brief = ("car", 150, lambda i: (1130, 800))                 # only 5 s by frame 200
    assert play({1: KERB, 2: brief, 3: TRAFFIC}) == set()


def test_double_parking_ignores_vehicles_outside_the_zone():
    assert play({1: KERB, 2: DOUBLE_PARKER, 3: TRAFFIC}, polygon=SMALL_ZONE) == set()


def test_double_parking_follows_the_wizard_time_limit():
    z = zones(DOUBLE, {"time_limit": 30})[0]
    assert z["time_limit"] == 30.0 and zones(DOUBLE)[0]["time_limit"] == 8.0
