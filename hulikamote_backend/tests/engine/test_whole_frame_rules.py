"""
The rules that need no drawing: every rule marked `whole_frame` that is on, with nothing drawn, gets one zone, the whole
picture, built from the wizard's own settings for it. Synthetic traffic only (no model, no video).
"""
import math
from types import SimpleNamespace

from engine.flow_field import FlowField
from engine.ledger import ActiveLedgerManager
from engine.pipeline import WHOLE_FRAME_ZONE_KEYS, DecoupledPipeline
from engine.violations import REGISTRY, ZONE_VIOLATIONS
from tests.engine.test_flow_field import FH, FW, RIGHT, teach
from tests.helpers import FPS, H, W, Det, go_up_then

WHOLE = [[0, 0], [FW, 0], [FW, FH], [0, FH]]
BIG = (2000, 2000)                    # the picture the go_up_then / U-turn paths live in
WHOLE_FRAME_KEYS = {"counterflow", "swerving", "illegal_u_turn", "illegal_turn", "signal_light", "truck_ban",
                    "tricycle_on_highway", "restricted_lane", "illegal_loading", "double_parking", "illegal_parking", "blocking_intersection"}


def zone_of(key, cfg=None, field=None, size=(FW, FH)):
    whole = [[0, 0], [size[0], 0], [size[0], size[1]], [0, size[1]]]
    return REGISTRY[key].whole_frame_zone(cfg or {}, whole, size, field or FlowField())


def pipeline_with(rois, settings=None, active=None, flow_mode="zones"):
    pipe = object.__new__(DecoupledPipeline)
    pipe.rois, pipe.native_w, pipe.native_h = rois, 0, 0
    pipe.flow_mode, pipe.flow = flow_mode, FlowField()
    pipe.violation_cfg = settings or {}
    pipe.registry = SimpleNamespace(active_violations=list(WHOLE_FRAME_KEYS if active is None else active))
    return pipe


def run_scene(cars, frames, rule, zone, watch=1):
    """cars: {id: (class, fn(frame) -> (x, y) bottom-centre, or None when off screen)}. True if `rule` flags `watch`."""
    mgr, flagged = ActiveLedgerManager(), False
    for i in range(frames):
        dets = []
        for tid, (cls, where) in cars.items():
            spot = where(i)
            if spot is not None:
                dets.append(Det(tid, [int(spot[0] - W / 2), int(spot[1] - H), W, H], cls))
        mgr.update(dets, i / FPS)
        if watch in mgr.ledgers:
            flagged = rule.evaluate(mgr, watch, [zone]) or flagged
    return flagged


def parked(i):
    return 640, 380


def passing(i):                       # drives along the learned road (to the right), 90 px/s
    return 100 + 9 * i, 360


def crossing(i):                      # drives across it (down the picture)
    return 640, 40 + 6 * i


def standing(i):
    return 900, 360


# ─── which rules need no drawing, and what zone they get ─────────────────────

def test_the_rules_that_need_no_drawing_are_exactly_these():
    assert {v.key for v in ZONE_VIOLATIONS if v.whole_frame} == WHOLE_FRAME_KEYS
    assert set(WHOLE_FRAME_ZONE_KEYS) == {v.zone_key for v in ZONE_VIOLATIONS if v.whole_frame}


def test_every_rule_that_is_on_gets_the_whole_frame_whatever_the_flow_mode_and_the_others_are_left_alone():
    for mode in ("zones", "auto"):
        scaled = pipeline_with({}, active=[v.key for v in ZONE_VIOLATIONS], flow_mode=mode)._get_scaled_rois(FW, FH)
        for v in ZONE_VIOLATIONS:
            if v.key == "blocking_intersection":
                assert scaled[v.zone_key] == []                  # the junction is found from the traffic: none learned yet, nothing to judge
            elif v.whole_frame:
                assert scaled[v.zone_key][0]["whole_frame"] and scaled[v.zone_key][0]["polygon"] == WHOLE, v.key
            else:
                assert scaled[v.zone_key] == [], v.key          # pedestrian lane, red light, signs ... still need a drawing


def test_a_rule_that_is_off_gets_no_zone():
    scaled = pipeline_with({}, active=["truck_ban"])._get_scaled_rois(FW, FH)
    assert scaled["truck_ban_zones"][0]["whole_frame"] and scaled["illegal_turn_zones"] == []


def test_the_zone_carries_the_settings_the_enforcer_chose():
    pipe = pipeline_with({}, {"illegal_turn": {"banned_turns": ["right"]},
                              "truck_ban": {"banned_classes": ["bus", "truck"]},
                              "illegal_parking": {"time_limit": 12},
                              "illegal_loading": {"time_limit": 20, "banned_classes": ["bus"]}})
    scaled = pipe._get_scaled_rois(FW, FH)
    assert scaled["illegal_turn_zones"][0]["banned_turns"] == ["right"]
    assert scaled["truck_ban_zones"][0]["banned_classes"] == ["bus", "truck"]
    assert scaled["illegal_parking_zones"][0]["time_limit"] == 12.0
    assert scaled["loading_zones"][0]["time_limit"] == 20.0 and scaled["loading_zones"][0]["classes"] == ["bus"]


def test_without_settings_the_rules_use_their_own_defaults():
    assert zone_of("illegal_turn")["banned_turns"] == ["left"]
    assert zone_of("truck_ban")["banned_classes"] == ["truck"]
    assert zone_of("tricycle_on_highway")["banned_classes"] == ["tricycle"]
    assert zone_of("illegal_loading")["classes"] == ["bus", "jeepney", "tricycle", "truck"]
    assert zone_of("illegal_turn", {"banned_turns": ["up"]})["banned_turns"] == ["left"]     # nonsense is ignored


def test_a_drawn_zone_always_wins_over_the_whole_frame():
    drawn = {"truck_ban_zones": [{"polygon": [[0, 0], [100, 0], [100, 100]], "banned_classes": ["truck"]}]}
    scaled = pipeline_with(drawn)._get_scaled_rois(FW, FH)
    assert len(scaled["truck_ban_zones"]) == 1 and not scaled["truck_ban_zones"][0].get("whole_frame")


# ─── U-turn and turns: no zone, no arrow ─────────────────────────────────────

def u_turn_path():
    right = [(200 + 9 * i, 500) for i in range(26)]
    arc = [(416 + 80 * math.cos(-math.pi / 2 + math.pi * k / 20), 580 + 80 * math.sin(-math.pi / 2 + math.pi * k / 20))
           for k in range(1, 21)]
    back = [(416 - 9 * j, 660) for j in range(1, 21)]
    return right + arc + back


def test_auto_u_turn_flags_a_car_that_turns_right_round():
    path = u_turn_path()
    assert run_scene({1: ("car", lambda i: path[min(i, len(path) - 1)])}, len(path), REGISTRY["illegal_u_turn"], zone_of("illegal_u_turn"))


def test_auto_u_turn_ignores_a_car_going_straight():
    assert not run_scene({1: ("car", lambda i: (200 + 9 * i, 500))}, 70, REGISTRY["illegal_u_turn"], zone_of("illegal_u_turn"))


def turn_flagged(dx, banned):
    path = go_up_then(dx)
    zone = zone_of("illegal_turn", {"banned_turns": banned}, size=BIG)
    return run_scene({1: ("car", lambda i: path[min(i, len(path) - 1)])}, len(path), REGISTRY["illegal_turn"], zone)


def test_auto_illegal_turn_flags_only_the_banned_side():
    assert turn_flagged(-1, ["left"]) and not turn_flagged(1, ["left"])
    assert turn_flagged(1, ["right"]) and not turn_flagged(-1, ["right"])
    assert turn_flagged(-1, ["left", "right"]) and turn_flagged(1, ["left", "right"])


def test_auto_illegal_turn_ignores_going_straight():
    assert not turn_flagged(0, ["left", "right"])


def test_a_finished_u_turn_is_not_called_a_left_or_right_turn():
    """A swing of 150 deg or more belongs to the U-turn rule (on the way round it passes through a 90 deg swing first)."""
    from engine.violations.geometry import turned_side
    mgr, side = ActiveLedgerManager(), "unset"
    for i, (x, y) in enumerate(u_turn_path()):
        mgr.update([Det(1, [int(x - W / 2), int(y - H), W, H])], i / FPS)
        side = turned_side(mgr.ledgers[1], ("test", 0))
    assert side is None
    mgr = ActiveLedgerManager()
    for i, (x, y) in enumerate(go_up_then(-1)):
        mgr.update([Det(1, [int(x - W / 2), int(y - H), W, H])], i / FPS)
        side = turned_side(mgr.ledgers[1], ("test", 0))
    assert side == "left"


# ─── banned vehicle types ────────────────────────────────────────────────────

def test_auto_truck_ban_flags_a_truck_but_not_a_car():
    path = [(200 + 9 * i, 500) for i in range(40)]
    zone = zone_of("truck_ban")
    assert run_scene({1: ("truck", lambda i: path[i])}, 40, REGISTRY["truck_ban"], zone)
    assert not run_scene({1: ("car", lambda i: path[i])}, 40, REGISTRY["truck_ban"], zone)


def test_auto_tricycle_ban_uses_the_enforcers_vehicle_types():
    path = [(200 + 9 * i, 500) for i in range(40)]
    assert not run_scene({1: ("tricycle", lambda i: path[i])}, 40, REGISTRY["tricycle_on_highway"],
                         zone_of("tricycle_on_highway", {"banned_classes": ["motorcycle"]}))
    assert run_scene({1: ("tricycle", lambda i: path[i])}, 40, REGISTRY["tricycle_on_highway"], zone_of("tricycle_on_highway"))


# ─── parking and loading: stopped AND traffic keeps driving past ─────────────

def learned_road():
    return teach(FlowField(), RIGHT)


def parking_run(cars, frames=120, limit=5, field=None, rule="illegal_parking", cls="car"):
    cars = {1: (cls, parked), **cars}
    zone = zone_of(rule, {"time_limit": limit}, field if field is not None else learned_road())
    return run_scene(cars, frames, REGISTRY[rule], zone)


def test_auto_parking_flags_a_car_standing_while_traffic_drives_past():
    assert parking_run({2: ("car", passing)})


def test_auto_parking_ignores_a_stopped_queue():
    assert not parking_run({2: ("car", standing)})              # the neighbour is stopped too: a queue, not parking


def test_auto_parking_ignores_cross_traffic_at_a_junction():
    assert not parking_run({2: ("car", crossing)})              # moves, but not along the road: the light is red here


def test_auto_parking_needs_the_road_to_be_learned():
    assert not parking_run({2: ("car", passing)}, field=FlowField())


def test_auto_parking_ignores_traffic_that_passed_long_ago():
    long_gone = {2: ("car", lambda i: passing(i) if i < 20 else None)}                    # 2 s of traffic, then nothing
    assert not parking_run(long_gone, limit=8)                                            # judged at ~8 s: the last car is 5 s old
    assert parking_run(long_gone, limit=3)                                                # judged at ~3 s: it passed a moment ago


def test_auto_parking_waits_for_the_enforcers_time_limit():
    assert not parking_run({2: ("car", passing)}, frames=40, limit=60)


def test_auto_parking_ignores_a_car_that_keeps_driving():
    cars = {1: ("car", lambda i: (100 + 9 * i, 380)), 2: ("car", passing)}
    zone = zone_of("illegal_parking", {"time_limit": 5}, learned_road())
    assert not run_scene(cars, 120, REGISTRY["illegal_parking"], zone)


def test_auto_loading_flags_a_bus_but_not_a_car():
    assert parking_run({2: ("car", passing)}, limit=8, rule="illegal_loading", cls="bus")
    assert not parking_run({2: ("car", passing)}, limit=8, rule="illegal_loading", cls="car")


def test_auto_loading_ignores_a_bus_in_a_stopped_queue():
    assert not parking_run({2: ("car", standing)}, limit=8, rule="illegal_loading", cls="bus")


# ─── signal light and double parking only need a whole-frame polygon ─────────

def test_auto_signal_light_judges_a_turn_anywhere_in_the_picture():
    path = go_up_then(-1)
    mgr, flagged = ActiveLedgerManager(), False
    zone = zone_of("signal_light", size=BIG)
    for i, (x, y) in enumerate(path):
        mgr.update([Det(1, [int(x - W / 2), int(y - H), W, H])], i / FPS)
        mgr.ledgers[1].blink.append((i / FPS, 0.0, 0.0))                # no indicator at all
        flagged = REGISTRY["signal_light"].evaluate(mgr, 1, [zone]) or flagged
    assert flagged


def test_auto_double_parking_runs_without_a_drawn_zone():
    zone = zone_of("double_parking", {"time_limit": 5}, learned_road())
    assert zone["whole_frame"] and zone["time_limit"] == 5.0
    assert not run_scene({1: ("car", parked), 2: ("car", passing)}, 120, REGISTRY["double_parking"], zone)   # nobody beside it
