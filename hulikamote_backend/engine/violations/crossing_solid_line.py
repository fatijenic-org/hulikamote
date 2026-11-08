"""
crossing_solid_line - a vehicle crosses a solid line it must not cross (double yellow, no-overtaking line).

Heuristic: the operator draws the road section and the line. A vehicle is flagged on the frame its ground
point crosses the line, in either direction, coming from the side it was first seen on (geometry.crossed_line:
it must end up clearly past the line, 30% of its box width and at least 10 px, so a car wobbling on the line
is not a crossing; points beyond the line's ends are ignored). Legal basis: the no-overtaking / no-crossing
rules of RA 4136 and local ordinances (to be confirmed before it is quoted on a ticket).
"""
from engine.violations.base import Violation
from engine.violations.geometry import crossed_line, point_in_polygon


class CrossingSolidLine(Violation):
    key = "crossing_solid_line"
    zone_key = "solid_line_zones"
    color = (0, 215, 255)

    MIN_PATH_POINTS = 2

    def parse_zone(self, raw):
        if not (raw.get("coordinates") and raw.get("stop_line")):
            return None
        return {"polygon": raw["coordinates"], "stop_line": raw["stop_line"]}      # drawn like a stop line

    def from_wizard(self, cfg):
        # ui_vector = the line's two points
        return [{"coordinates": z["polygon"], "stop_line": z["ui_vector"]}
                for z in cfg.get("rois", []) if z.get("polygon") and z.get("ui_vector")]

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "stop_line": [[x1, y1], [x2, y2]]}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < self.MIN_PATH_POINTS:
            return False
        _t, cx, cy, _w = ledger.path[-1]
        for i, zone in enumerate(zones):
            if point_in_polygon(cx, cy, zone["polygon"]) and crossed_line(ledger, (self.key, i), zone.get("stop_line")):
                ledger.violations.add(self.key)
                return True
        return False
