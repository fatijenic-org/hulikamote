"""
The time on a ticket (engine/video_clock.py ticket_time / retime / earlier_time, engine/ticket_flags.py, engine/ticket_merge.py):
it follows the ticket's first photo through a merge or a split, and a ticket that depends on the hour with no known time is flagged.
"""
from datetime import datetime

from engine import video_clock as vc
from engine.ticket_flags import annotate_tickets, find_time_flags
from engine.ticket_merge import merge_tickets, split_ticket

CLOCK = vc.ClockInfo(start=datetime(2026, 11, 5, 7, 59, 30), source="metadata", confirmed=True).to_dict()
UNKNOWN = vc.ClockInfo(start=None, source="estimate", confirmed=False, daylight="day", note="No time was found in the video.").to_dict()
HOURS_CONFIG = {"per_violation_configs": {"truck_ban": {"ban_windows": [["06:00", "09:00"]]}, "counterflow": {}},
                "active_violations": ["truck_ban", "counterflow"]}


def ticket(uid, ts, clock=CLOCK, violations=("truck_ban",), hours=True):
    t = {"ticket_uid": uid, "track_id": uid, "violations": list(violations), "plate_text": "unidentified",
         "evidence_paths": [f"{uid}{i}.jpg" for i in range(len(ts))],
         "evidence_meta": [{"file": f"{uid}{i}.jpg", "bbox": [0, 0, 10, 10], "t": t_} for i, t_ in enumerate(ts)]}
    when = vc.ticket_time(clock, min(ts), hours)
    if when:
        t["time"] = when
    return t


def distance(a, b):
    return 0 if a == b else 9


# ─── what goes on a ticket ──────────────────────────────────────────────────────────────────────────────

def test_a_known_time_is_the_clock_start_plus_the_first_photo():
    when = vc.ticket_time(CLOCK, 45)
    assert when == {"at": "2026-11-05T08:00:15", "source": "metadata", "label": "read from the video's own information",
                    "confirmed": True, "start": "2026-11-05T07:59:30"}


def test_an_unknown_time_is_only_recorded_for_a_ticket_that_depends_on_the_hour():
    assert vc.ticket_time(UNKNOWN, 5) is None
    asked = vc.ticket_time(UNKNOWN, 5, hours_matter=True)
    assert asked["at"] is None and asked["needs_check"] is True and asked["confirmed"] is False
    assert asked["note"] == "No time was found in the video."
    assert vc.ticket_time(None, 5, hours_matter=True) is None and vc.ticket_time(CLOCK, None) is None


def test_clock_wanted_only_when_the_time_can_matter():
    assert vc.clock_wanted({"video_start": "7:30"})
    assert vc.clock_wanted(HOURS_CONFIG)
    assert not vc.clock_wanted({"active_violations": ["truck_ban"], "per_violation_configs": {"truck_ban": {"ban_windows": []}}})
    assert not vc.clock_wanted({"active_violations": ["counterflow"], "per_violation_configs": HOURS_CONFIG["per_violation_configs"]})
    assert not vc.clock_wanted({"video_start": "  ", "active_violations": [], "per_violation_configs": {}})


def test_hours_matter_for_the_rules_that_have_them():
    assert vc.hours_matter(HOURS_CONFIG, ["truck_ban"]) and vc.hours_matter(HOURS_CONFIG, ["counterflow", "truck_ban"])
    assert not vc.hours_matter(HOURS_CONFIG, ["counterflow"]) and not vc.hours_matter(HOURS_CONFIG, [])


# ─── the flag ───────────────────────────────────────────────────────────────────────────────────────────

def test_an_unknown_time_on_an_hour_rule_is_flagged_and_a_known_one_is_not():
    flagged = ticket("a", [3.0], clock=UNKNOWN)
    flags = find_time_flags(flagged)
    assert [f["type"] for f in flags] == ["time_unconfirmed"]
    assert flags[0]["detail"].startswith("No time was found in the video.") and "check the time" in flags[0]["detail"]
    assert find_time_flags(ticket("b", [3.0])) == []
    assert find_time_flags({"violations": ["counterflow"]}) == []


def test_annotating_gives_the_flag_next_to_the_other_flags():
    tickets = [ticket("a", [3.0], clock=UNKNOWN), ticket("b", [300.0])]
    annotate_tickets(tickets, distance)
    assert [f["type"] for f in tickets[0]["flags"]] == ["time_unconfirmed"] and tickets[1]["flags"] == []


# ─── joining and splitting keep the time true ───────────────────────────────────────────────────────────

def test_joined_tickets_take_the_earlier_time():
    early, late = ticket("a", [2.0]), ticket("b", [50.0])
    merged = merge_tickets(late, early)                 # the car first seen at 2 s, joined into the one seen from 50 s
    assert merged["time"]["at"] == "2026-11-05T07:59:32"
    assert merge_tickets(early, late)["time"]["at"] == "2026-11-05T07:59:32"


def test_a_human_check_survives_a_join():
    unsure, sure = ticket("a", [2.0], clock=UNKNOWN), ticket("b", [50.0])
    merged = merge_tickets(sure, unsure)
    assert merged["time"]["needs_check"] is True and merged["time"]["note"] == "No time was found in the video."
    assert merged["time"]["at"] == "2026-11-05T08:00:20"                  # the one that is known


def test_a_split_gives_each_half_the_time_of_its_own_first_photo():
    whole = ticket("a", [2.0, 40.0, 41.0])
    remaining, new = split_ticket(whole, ["a1.jpg", "a2.jpg"])
    tickets = [remaining, new]
    annotate_tickets(tickets, distance)
    assert remaining["time"]["at"] == "2026-11-05T07:59:32"
    assert new["time"]["at"] == "2026-11-05T08:00:10"
    assert remaining["time"] is not new["time"]          # not one dict shared by both
    assert whole["time"]["at"] == "2026-11-05T07:59:32"   # the original is not touched


def test_a_ticket_with_no_clock_start_is_left_alone_by_the_retime():
    t = {"ticket_uid": "x", "violations": ["counterflow"], "evidence_meta": [{"file": "a", "t": 3.0, "bbox": [0, 0, 1, 1]}]}
    annotate_tickets([t], distance)
    assert "time" not in t
    asked = ticket("y", [3.0], clock=UNKNOWN)
    annotate_tickets([asked], distance)
    assert asked["time"]["at"] is None
