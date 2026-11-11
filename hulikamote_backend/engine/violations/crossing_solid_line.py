"""
crossing_solid_line - a vehicle crosses a solid line it must not cross (double yellow, no-overtaking line).

What a line is: two or more points. More than two make a bent line, so a curve in the road is followed
(the nearest straight piece of the line decides, geometry.line_side). Each saved line is one zone, so a road
can have as many lines as it has. The road section (a polygon around the line) is optional and normally not
drawn: the line alone is enough. Nothing has to be drawn at all: when the Forensic run has no drawn line it
finds the painted solid lane lines itself (engine/auto_lines.py, the road finder) and uses them the same way.

Heuristic: a vehicle is flagged on the frame its ground point crosses the line, in either direction, coming
from the side it was first seen on (geometry.crossed_line: it must end up clearly past the line, 30% of its
box width and at least 10 px, so a car wobbling on the line is not a crossing; points beyond the line's ends
are ignored). Legal basis: the no-overtaking / no-crossing rules of RA 4136 and local ordinances (to be
confirmed before it is quoted on a ticket).
"""
import cv2
import numpy as np

from engine.violations.base import Violation
from engine.violations.geometry import crossed_line, point_in_polygon


class CrossingSolidLine(Violation):
    key = "crossing_solid_line"
    zone_key = "solid_line_zones"
    color = (0, 215, 255)

    MIN_PATH_POINTS = 2

    def parse_zone(self, raw):
        line = raw.get("stop_line")                                                   # stored like a stop line, with any number of points
        if not line or len(line) < 2:
            return None
        return {"polygon": raw.get("coordinates") or [], "stop_line": line}          # no polygon = the line alone

    def from_wizard(self, cfg):
        # "line" = the points the operator clicked (ui_vector: the two points older drawings and the paint finder gave)
        zones = []
        for z in cfg.get("rois", []):
            line = z.get("line") or z.get("ui_vector")
            if line and len(line) >= 2:
                zones.append({"coordinates": z.get("polygon") or [], "stop_line": line})
        return zones

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...] (may be empty), "stop_line": [[x1, y1], [x2, y2], ...]}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < self.MIN_PATH_POINTS:
            return False
        _t, cx, cy, _w = ledger.path[-1]
        for i, zone in enumerate(zones):
            if zone["polygon"] and not point_in_polygon(cx, cy, zone["polygon"]):
                continue
            if crossed_line(ledger, (self.key, i), zone.get("stop_line")):
                ledger.violations.add(self.key)
                return True
        return False

    def draw_zone(self, pipe, frame, index, zone):
        """The line itself, bent as drawn (and the road section, when one was drawn)."""
        if zone.get("polygon"):
            cv2.polylines(frame, [np.array(zone["polygon"], dtype=np.int32)], isClosed=True, color=self.color, thickness=2)
        line = zone.get("stop_line")
        if line:
            cv2.polylines(frame, [np.array(line, dtype=np.int32)], isClosed=False, color=self.line_colour(pipe, index),
                          thickness=4, lineType=cv2.LINE_AA)
