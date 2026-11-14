"""Several prohibited-turn arrows in one zone, the time badge of the truck ban, and no_seatbelt judging cars and trucks only."""
from datetime import datetime
from types import SimpleNamespace

import numpy as np

from engine.ledger import ActiveLedgerManager
from engine.specialist_jobs import CabinJob
from engine.video_clock import ClockInfo
from engine.violations import REGISTRY
from engine.violations.truck_ban import draw_time_badge
from tests.engine.test_ledger import BIG_ZONE, drive, go_up_then, sign, turn
from tests.engine.test_ban_hours import RUSH, RULE, clock_at, drive_truck, zone_with


# ─── several arrows ────────────────────────────────────────────────────────────────────────────────────────

def test_a_zone_that_bans_left_and_right_flags_both_and_not_straight():
    both = [{"polygon": BIG_ZONE, "vector": (-1.0, 0.0), "vectors": [(-1.0, 0.0), (1.0, 0.0)]}]
    for side in (-1, 1):
        mgr = ActiveLedgerManager()
        assert drive(mgr, go_up_then(side), turn(mgr, both))
    mgr = ActiveLedgerManager()
    assert not drive(mgr, go_up_then(0), turn(mgr, both))


def test_a_zone_with_one_arrow_still_works_as_before():
    one = [{"polygon": BIG_ZONE, "vector": (-1.0, 0.0)}]                       # no "vectors": an older zone
    mgr = ActiveLedgerManager()
    assert drive(mgr, go_up_then(-1), turn(mgr, one))
    mgr = ActiveLedgerManager()
    assert not drive(mgr, go_up_then(1), turn(mgr, one))


def test_the_wizard_carries_every_arrow_and_the_saved_zone_reads_them_back():
    cfg = {"rois": [{"polygon": [[0, 0], [9, 0], [9, 9]], "vector": {"x_dir": -1.0, "y_dir": 0.0},
                     "vectors": [{"x_dir": -1.0, "y_dir": 0.0}, {"x_dir": 1.0, "y_dir": 0.0}]}]}
    raw = REGISTRY["illegal_turn"].from_wizard(cfg)[0]
    zone = REGISTRY["illegal_turn"].parse_zone(raw)
    assert zone["vectors"] == [(-1.0, 0.0), (1.0, 0.0)] and zone["vector"] == (-1.0, 0.0)
    sign_raw = REGISTRY["disregarding_signs"].from_wizard({"rois": [{**cfg["rois"][0], "sign": "no_turn"}]})[0]
    assert REGISTRY["disregarding_signs"].parse_zone(sign_raw)["vectors"] == [(-1.0, 0.0), (1.0, 0.0)]


def test_no_turn_sign_with_two_arrows():
    mgr = ActiveLedgerManager()
    assert drive(mgr, go_up_then(1), sign(mgr, sign="no_turn", vector=(-1.0, 0.0), vectors=[(-1.0, 0.0), (1.0, 0.0)]))


# ─── the time badge ────────────────────────────────────────────────────────────────────────────────────────

def test_the_truck_ban_notes_the_time_of_each_frame_and_whether_the_ban_is_in_force():
    pipe = SimpleNamespace(clock=clock_at(7, 30))
    zone = zone_with(RUSH)
    RULE.prepare(pipe, None, [], [zone], 12.0)
    assert pipe.truck_time["moment"] == datetime(2026, 11, 5, 7, 30, 12)
    assert pipe.truck_time["hours"] and pipe.truck_time["in_force"] is True
    pipe = SimpleNamespace(clock=ClockInfo(start=None, source="estimate"))
    RULE.prepare(pipe, None, [], [zone_with(RUSH)], 1.0)
    assert pipe.truck_time["moment"] is None and pipe.truck_time["in_force"] is None
    pipe = SimpleNamespace(clock=clock_at(12))
    RULE.prepare(pipe, None, [], [zone_with([])], 1.0)                          # no ban hours set
    assert pipe.truck_time["hours"] is False


def test_the_badge_is_drawn_in_the_upper_right_corner_only():
    frame = np.full((720, 1280, 3), 200, np.uint8)
    draw_time_badge(frame, {"moment": datetime(2026, 11, 5, 7, 30, 12), "source": "screen", "hours": True, "in_force": True})
    assert (frame[:90, 880:] < 200).any()                                       # something in the upper right
    assert (frame[120:, :] == 200).all() and (frame[:, :880] == 200).all()      # nothing anywhere else
    again = np.full((720, 1280, 3), 200, np.uint8)
    draw_time_badge(again, None)
    assert (again == 200).all()                                                 # no information: nothing drawn


def test_the_truck_ban_draws_the_badge_once_however_many_zones():
    pipe = SimpleNamespace(clock=clock_at(7, 30), _light_states={})
    zones = [zone_with(RUSH), zone_with(RUSH)]
    RULE.prepare(pipe, None, [], zones, 1.0)
    one, two = np.full((720, 1280, 3), 200, np.uint8), np.full((720, 1280, 3), 200, np.uint8)
    RULE.draw_zone(pipe, one, 0, zones[0])
    for i, z in enumerate(zones):
        RULE.draw_zone(pipe, two, i, z)
    assert (one == two).all() and (one < 200).any()


# ─── no seatbelt: cars and trucks only ─────────────────────────────────────────────────────────────────────

def test_the_cabin_look_for_seatbelts_is_taken_for_cars_and_trucks_only():
    job = CabinJob()
    for cls, wanted in (("car", True), ("truck", True), ("bus", False), ("jeepney", False), ("tricycle", False), ("motorcycle", False)):
        assert job.wanted(["no_seatbelt"], SimpleNamespace(cls=cls)) is wanted
    assert job.wanted(["distracted_driving"], SimpleNamespace(cls="bus"))      # the phone rule is not changed
    assert job.wanted(["no_seatbelt", "missing_side_mirror"], SimpleNamespace(cls="bus"))


def test_the_tricycle_rule_bans_tricycles_without_any_vehicle_list():
    zone = REGISTRY["tricycle_on_highway"].whole_frame_zone({}, [[0, 0], [1, 0], [1, 1]], (1280, 720), None)
    assert zone["banned_classes"] == ["tricycle"]
