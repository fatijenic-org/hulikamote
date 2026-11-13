"""
Ban hours on the banned-in-zone rules (truck ban, tricycle on highway ...): the ban only holds inside the hours the operator set,
judged by the clock of the video (engine/video_clock.py). Synthetic traffic only (no model, no video).
"""
from datetime import datetime
from types import SimpleNamespace

from engine.ledger import ActiveLedgerManager
from engine.video_clock import ClockInfo
from engine.violations import REGISTRY
from tests.helpers import FPS, H, W, Det

RULE = REGISTRY["truck_ban"]
WHOLE = [[0, 0], [1280, 0], [1280, 720], [0, 720]]
RUSH = [["06:00", "09:00"], ["16:00", "19:00"]]


def clock_at(hour, minute=0, second=0, source="metadata", confirmed=True):
    return ClockInfo(start=datetime(2026, 11, 5, hour, minute, second), source=source, confirmed=confirmed)


def unknown_clock():
    return ClockInfo(start=None, source="estimate", confirmed=False, daylight="day")


def zone_with(windows, **extra):
    return {**RULE.whole_frame_zone({"ban_windows": windows}, WHOLE, (1280, 720), None), **extra}


def drive_truck(zone, clock, frames=40, cls="truck", rule=RULE):
    """A truck crosses the picture. Each frame the rule is prepared (its clock look-up) and then judges. True if it is flagged."""
    pipe = SimpleNamespace(clock=clock)
    mgr, flagged = ActiveLedgerManager(), False
    for i in range(frames):
        x, y = 200 + 9 * i, 500
        mgr.update([Det(1, [int(x - W / 2), int(y - H), W, H], cls)], i / FPS)
        rule.prepare(pipe, None, [], [zone], i / FPS)
        if 1 in mgr.ledgers:
            flagged = rule.evaluate(mgr, 1, [zone]) or flagged
    return flagged


# ─── no hours set: as before ─────────────────────────────────────────────────────────────────────────────

def test_with_no_hours_the_ban_holds_all_day_and_needs_no_clock():
    assert drive_truck(zone_with([]), clock_at(3))
    assert drive_truck(zone_with([]), clock_at(12))
    assert drive_truck(zone_with([]), None)
    assert drive_truck(zone_with([]), unknown_clock())


def test_hours_that_cannot_be_read_count_as_no_hours():
    assert drive_truck(zone_with([["soon", "later"], ["07:00", "07:00"]]), clock_at(12))


# ─── hours set and the time known ────────────────────────────────────────────────────────────────────────

def test_a_truck_inside_the_ban_hours_is_flagged():
    for hour in (6, 7, 8, 16, 18):
        assert drive_truck(zone_with(RUSH), clock_at(hour, 30)), hour


def test_a_truck_outside_the_ban_hours_is_not_flagged():
    for hour in (3, 5, 9, 12, 15, 19, 22):
        assert not drive_truck(zone_with(RUSH), clock_at(hour, 30)), hour


def test_the_ban_ends_exactly_at_the_end_of_the_window():
    assert drive_truck(zone_with(RUSH), clock_at(8, 59, 56))          # the truck is inside the ban for its first seconds
    assert not drive_truck(zone_with(RUSH), clock_at(9, 0, 0))        # the window has just closed
    assert drive_truck(zone_with(RUSH), clock_at(5, 59, 56), frames=70)   # the ban starts while it is on screen: from then on it counts


def test_a_car_is_never_flagged_whatever_the_hour():
    assert not drive_truck(zone_with(RUSH), clock_at(7, 30), cls="car")


def test_the_clock_of_the_video_decides_not_the_clock_of_the_computer():
    """An analysis of a video recorded at 7:30 is judged at 7:30 even though the laptop's own time is another."""
    assert drive_truck(zone_with(RUSH), clock_at(7, 30))
    assert not drive_truck(zone_with(RUSH), clock_at(13, 30))


def test_the_zone_says_whether_the_ban_was_in_force():
    zone = zone_with(RUSH)
    drive_truck(zone, clock_at(7, 30), frames=3)
    assert zone["ban_active"] is True
    drive_truck(zone, clock_at(12, 0), frames=3)
    assert zone["ban_active"] is False


# ─── hours set and the time NOT known ────────────────────────────────────────────────────────────────────

def test_when_the_time_is_unknown_the_truck_is_still_flagged_for_a_human_to_check():
    zone = zone_with(RUSH)
    assert drive_truck(zone, unknown_clock())
    assert zone["ban_active"] is None                                   # "not known", neither yes nor no


def test_a_pipeline_without_a_clock_is_the_same_as_an_unknown_time():
    zone = zone_with(RUSH)
    assert drive_truck(zone, None)
    assert zone["ban_active"] is None


# ─── the other banned-in-zone rules share it ─────────────────────────────────────────────────────────────

def test_the_tricycle_rule_can_have_hours_too():
    rule = REGISTRY["tricycle_on_highway"]
    zone = {**rule.whole_frame_zone({"ban_windows": [["06:00", "09:00"]]}, WHOLE, (1280, 720), None)}
    assert drive_truck(zone, clock_at(7), cls="tricycle", rule=rule)
    assert not drive_truck(zone, clock_at(12), cls="tricycle", rule=rule)


# ─── how the hours reach the rule ────────────────────────────────────────────────────────────────────────

def test_the_wizards_hours_are_carried_into_every_zone_it_makes():
    cfg = {"rois": [{"polygon": [[0, 0], [10, 0], [10, 10]]}], "ban_windows": RUSH}
    zones = RULE.from_wizard(cfg)
    assert zones[0]["ban_windows"] == RUSH
    assert RULE.parse_zone(zones[0])["ban_windows"] == RUSH               # ... and survive being saved and read back
    assert RULE.parse_zone({"coordinates": [[0, 0], [10, 0], [10, 10]]})["ban_windows"] == []


def test_the_automatic_zone_carries_the_hours():
    assert RULE.whole_frame_zone({"ban_windows": RUSH}, WHOLE, (1280, 720), None)["ban_windows"] == RUSH
    assert RULE.whole_frame_zone({}, WHOLE, (1280, 720), None)["ban_windows"] == []
