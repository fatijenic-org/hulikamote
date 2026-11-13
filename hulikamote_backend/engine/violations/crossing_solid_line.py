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

Painted overlay (engine/line_paint.py, for testing): a saved line that carries a `look` is also drawn like paint on the road (solid white or
yellow, double yellow, dashed white; width, wear, perspective taper; vehicles drive over it). The paint is only a picture of the line the rule
already judges: the rule uses the line's points, never the paint. It is drawn on the evidence photos and the result video, never written
into the video, and belongs to the analysis.
"""
import cv2
import numpy as np

from engine import line_paint
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
        zone = {"polygon": raw.get("coordinates") or [], "stop_line": line}          # no polygon = the line alone
        if raw.get("look"):
            zone["look"] = line_paint.look_of(raw["look"])                           # painted on the picture too
            zone["realistic"] = bool(raw.get("realistic", True))
        return zone

    def from_wizard(self, cfg):
        # "line" = the points the operator clicked (ui_vector: the two points older drawings and the paint finder gave)
        zones = []
        realistic = bool(cfg.get("lines_realistic", True))
        for z in cfg.get("rois", []):
            line = z.get("line") or z.get("ui_vector")
            if line and len(line) >= 2:
                zone = {"coordinates": z.get("polygon") or [], "stop_line": line}
                if z.get("look") is not None:                                          # "Paint it": a look, even an empty one, means paint
                    zone["look"] = line_paint.look_of(z["look"])
                    zone["realistic"] = realistic
                zones.append(zone)
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
            painted = zone.get("look") is not None
            if painted:                                                                  # the paint first, vehicles on top of it
                boxes = [d.bbox for d in getattr(pipe, "_draw_dets", ()) if getattr(d, "cls", None) in line_paint.OCCLUDES]
                line_paint.draw(frame, line, zone["look"], zone.get("realistic", True), occluders=boxes)
            cv2.polylines(frame, [np.array(line, dtype=np.int32)], isClosed=False, color=self.line_colour(pipe, index),
                          thickness=2 if painted else 4, lineType=cv2.LINE_AA)
