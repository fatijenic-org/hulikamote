"""
crossing_solid_line - a vehicle crosses a solid line it must not cross (double yellow, no-overtaking line).

What a line is: two or more points. More than two make a bent line, so a curve in the road is followed
(the nearest straight piece of the line decides, geometry.line_side). Each saved line is one zone, so a road
can have as many lines as it has. The road section (a polygon around the line) is optional and normally not
drawn: the line alone is enough. Nothing has to be drawn at all: when the Forensic run has no drawn line it
finds the painted solid lane lines itself (engine/auto_lines.py, the road finder) and uses them the same way.

Heuristic: a vehicle is flagged once enough of its FOOTPRINT is past the line, in either direction, coming from the side it was first seen
on. The footprint is where it touches the road: the bottom centre for a motorcycle (or bicycle), the whole bottom edge from lower corner to
lower corner for a car, tricycle, jeepney, bus or truck. "Enough" is the operator's setting `min_overlap` (a share of the footprint, 30% to
start with; the Rules step has a slider): the share that must lie past the line, held for a few pictures in a row, so a car wobbling on the
line is not a crossing; points beyond the line's ends are ignored. Legal basis: the no-overtaking / no-crossing rules of RA 4136 and
local ordinances (to be confirmed before it is quoted on a ticket).

The trackers hand a vehicle's number to another vehicle now and then, so "this number is now on the other side" is not believed on its
own: the vehicle must have been followed picture after picture, from clearly before the line to clearly after it, and its trip must
really cut the line (engine/violations/line_watch.py, engine/track_continuity.py). On a real 4K clip the old check flagged 96 vehicles in
7 minutes, nearly all of them a tracker number that had moved to another vehicle; this one flags the 2 that really drove over the line.

It judges a vehicle that drives ALONG the line and goes over it (a lane change, an overtaking swerve, riding on the line). A vehicle that
goes straight ACROSS it (turning across the road, into or out of a side street) is cross traffic: the turning rules judge that, not this one.
One that stands or creeps on the line is not crossing it either.

Painted overlay (engine/line_paint.py, for testing): a saved line that carries a `look` is also drawn like paint on the road (solid white or
yellow, double yellow, dashed white; width, wear, perspective taper; vehicles drive over it). The paint is only a picture of the line the rule
already judges: the rule uses the line's points, never the paint. It is drawn on the evidence photos and the result video, never written
into the video, and belongs to the analysis.
"""
import cv2
import numpy as np

from engine import line_paint
from engine.track_stitcher import compute_signature
from engine.violations.base import Violation
from engine.violations.geometry import point_in_polygon
from engine.violations.line_watch import DEFAULT_MIN_OVERLAP, LineWatch


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
        zone["min_overlap"] = self._overlap(raw.get("min_overlap"))
        if raw.get("look"):
            zone["look"] = line_paint.look_of(raw["look"])                           # painted on the picture too
            zone["realistic"] = bool(raw.get("realistic", True))
        return zone

    @staticmethod
    def _overlap(value) -> float:
        """The share of the vehicle's footprint that must be past the line, as the operator set it (a fraction, or a percent): 0.05 to 1."""
        try:
            v = float(value)
        except (TypeError, ValueError):
            return DEFAULT_MIN_OVERLAP
        v = v / 100.0 if v > 1.0 else v
        return min(1.0, max(0.05, v))

    def from_wizard(self, cfg):
        # "line" = the points the operator clicked (ui_vector: the two points older drawings and the paint finder gave)
        zones = []
        realistic = bool(cfg.get("lines_realistic", True))
        overlap = self._overlap(cfg.get("min_overlap"))
        for z in cfg.get("rois", []):
            line = z.get("line") or z.get("ui_vector")
            if line and len(line) >= 2:
                zone = {"coordinates": z.get("polygon") or [], "stop_line": line, "min_overlap": overlap}
                if z.get("look") is not None:                                          # "Paint it": a look, even an empty one, means paint
                    zone["look"] = line_paint.look_of(z["look"])
                    own = z["look"].get("realistic") if isinstance(z["look"], dict) else None     # the road markings say it per line
                    zone["realistic"] = realistic if own is None else bool(own)
                zones.append(zone)
        return zones

    def prepare(self, pipe, frame, detections, zones, t):
        """Once per picture: keep it, so the colours of a vehicle can be looked at when its crossing is about to be believed."""
        pipe.ledger_manager.solid_frame = frame

    @staticmethod
    def _signature(mgr, ledger):
        """The colour histogram of the vehicle's box in the picture being judged (None when there is no picture, as in a test)."""
        frame = getattr(mgr, "solid_frame", None)
        if frame is None or not ledger.history:
            return None
        return compute_signature(frame, ledger.history[-1][3])

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...] (may be empty), "stop_line": [[x1, y1], [x2, y2], ...]}.
        Asked for every vehicle on every picture, also for one that was not seen in it: only a NEW picture of the vehicle counts
        (engine/violations/line_watch.py decides whether it drove across the line)."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < self.MIN_PATH_POINTS or not ledger.history:
            return False
        if ledger.latest_class == "unknown":           # the tracker has not said what it is yet
            return False
        t, cx, cy, w = ledger.path[-1]
        sample = (t, cx, cy, w, ledger.history[-1][3][3])
        flagged = False
        for i, zone in enumerate(zones):
            line = zone.get("stop_line")
            if not line or len(line) < 2:
                continue
            watch = ledger.line_watch.setdefault((self.key, i), LineWatch())
            if zone["polygon"] and not point_in_polygon(cx, cy, zone["polygon"]):
                watch.leave(t)
                continue
            crossing = watch.update(sample, line, lambda: self._signature(mgr, ledger), ledger.latest_class,
                                    zone.get("min_overlap", DEFAULT_MIN_OVERLAP))
            if crossing is not None:
                ledger.cross_points.append((crossing.t, crossing.point[0], crossing.point[1]))
                ledger.violations.add(self.key)
                flagged = True
        return flagged

    def has_overlay(self, zone):
        return bool(zone.get("stop_line")) and zone.get("look") is not None

    def draw_overlay(self, pipe, frame, index, zone):
        if self.has_overlay(zone):
            boxes = [d.bbox for d in getattr(pipe, "_draw_dets", ()) if getattr(d, "cls", None) in line_paint.OCCLUDES]
            line_paint.draw(frame, zone["stop_line"], zone["look"], zone.get("realistic", True), occluders=boxes)

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
