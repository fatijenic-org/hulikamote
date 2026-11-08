"""engine/marks.py - the boxes that show why a vehicle was flagged."""
from engine import marks
from engine.ledger import ActiveLedgerManager
from tests.helpers import Det


def test_mark_follows_the_vehicle():
    rel = marks.to_relative([120, 50, 20, 30], [100, 40, 100, 100])
    assert marks.to_absolute(rel, [300, 40, 100, 100]) == [320, 50, 20, 30]      # moved right 200 px
    assert marks.to_absolute(rel, [100, 40, 200, 200]) == [140, 60, 40, 60]      # came closer (2x bigger)


def test_marks_only_drawn_while_violation_flagged_and_fresh():
    mgr = ActiveLedgerManager()
    mgr.update([Det(5, [100, 100, 100, 100], "motorcycle")], 0.0)
    ledger = mgr.ledgers[5]
    marks.set_marks(ledger, "no_helmet", [100, 100, 100, 100], [([110, 90, 30, 30], "NO HELMET", marks.RED)])
    assert marks.current_marks(ledger, [100, 100, 100, 100]) == []               # not flagged yet
    ledger.violations.add("no_helmet")
    assert marks.current_marks(ledger, [100, 100, 100, 100])[0][1] == "NO HELMET"
    mgr.update([Det(5, [100, 100, 100, 100], "motorcycle")], marks.MARK_TTL_S + 1)
    assert marks.current_marks(ledger, [100, 100, 100, 100]) == []               # stale: no fresh look
