"""
illegal_u_turn - turning right round where a U-turn is prohibited.

Heuristic: inside the zone, the heading has swung by 150 deg or more since the vehicle entered (its path
now points back the way it came) AND it has moved sideways by at least 0.75 box widths from its entry line,
so a vehicle that merely reverses in a straight line is not a U-turn. Headings need half a box width
(at least 15 px) of travel, so a stopped car's box jitter never counts. Any direction of U-turn counts: the
operator only draws the area where U-turns are not allowed (automatic mode: the whole picture; ticking the rule
means "no U-turns here").
"""
from engine.violations.base import Violation
from engine.violations.geometry import U_TURN_COS, dot, point_in_polygon, turn_headings

MIN_SIDEWAYS_WIDTHS = 0.75


class IllegalUTurn(Violation):
    key = "illegal_u_turn"
    zone_key = "illegal_u_turn_zones"
    auto = True
    color = (0, 200, 255)

    MIN_PATH_POINTS = 4

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...]}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < self.MIN_PATH_POINTS:
            return False
        _t, cx, cy, width = ledger.path[-1]
        for i, zone in enumerate(zones):
            if not point_in_polygon(cx, cy, zone["polygon"]):
                continue
            key = (self.key, i)
            headings = turn_headings(ledger, key)
            if headings is None:
                continue
            entry, current = headings
            if dot(entry, current) > U_TURN_COS:
                continue
            ex, ey = ledger.turn_entry[key]
            sideways = abs((cx - ex) * entry[1] - (cy - ey) * entry[0])     # distance from the entry line
            if sideways >= MIN_SIDEWAYS_WIDTHS * width:
                ledger.violations.add(self.key)
                return True
        return False
