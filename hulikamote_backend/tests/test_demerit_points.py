"""demerit_points.py - one confirmed ticket is one point on its plate, however the plate was typed."""
import pytest

from demerit_points import for_plate, normalize_plate, tally


def ticket(n, plate, cls="no_helmet"):
    return {"id": f"t{n}", "plate_text": plate, "cls": cls, "timestamp": f"2026-10-28T08:00:{n:02d}+00:00"}


@pytest.mark.parametrize("typed", ["ABC1234", "abc 1234", "ABC-1234", " Abc  1234 "])
def test_the_same_plate_typed_differently_is_one_plate(typed):
    assert normalize_plate(typed) == "ABC1234"


@pytest.mark.parametrize("typed", ["", None, "unidentified", "no_plate_found", "SCANNING", "  "])
def test_no_plate_read_means_nobody_to_charge(typed):
    assert normalize_plate(typed) == ""


def test_each_confirmed_ticket_is_one_point_and_the_breakdown_adds_up():
    rows = [ticket(1, "ABC1234"), ticket(2, "ABC 1234", "red_light"), ticket(3, "ABC-1234"), ticket(4, "XYZ999")]
    standings = tally(rows)
    top = standings[0]
    assert (top["plate"], top["points"]) == ("ABC-1234", 3)                    # newest spelling is shown
    assert top["by_class"] == {"no_helmet": 2, "red_light": 1}
    assert top["last_at"] == rows[2]["timestamp"]
    assert [(p["plate"], p["points"]) for p in standings[1:]] == [("XYZ999", 1)]


def test_tickets_without_a_plate_are_never_counted():
    assert tally([ticket(1, "unidentified"), ticket(2, "no_plate_found"), ticket(3, "")]) == []


def test_ties_put_the_most_recently_caught_plate_first():
    standings = tally([ticket(1, "OLD111"), ticket(2, "NEW222")])
    assert [p["plate"] for p in standings] == ["NEW222", "OLD111"]


def test_one_plate_lists_its_tickets_newest_first():
    rows = [ticket(1, "ABC1234"), ticket(2, "XYZ999"), ticket(3, "abc 1234", "red_light")]
    found = for_plate(rows, "ABC-1234")
    assert found["points"] == 2
    assert [v["id"] for v in found["violations"]] == ["t3", "t1"]


def test_a_plate_with_no_tickets_has_zero_points():
    found = for_plate([ticket(1, "ABC1234")], "nope 000")
    assert found["points"] == 0 and found["violations"] == [] and found["by_class"] == {}


def test_looking_up_an_unread_plate_finds_nothing_instead_of_every_unread_ticket():
    rows = [ticket(1, "unidentified"), ticket(2, "no_plate_found")]
    assert for_plate(rows, "unidentified")["violations"] == []
