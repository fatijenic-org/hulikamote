"""
counterflow - driving against the legal direction of traffic.

Two ways to know the legal direction:
  drawn         an operator draws a zone with a legal-flow arrow (the original way; kept for tests and as ground truth)
  whole picture nothing drawn: the legal direction is learned from the traffic itself (engine/flow_field.py; the pipeline
                learns the flow on its own when this rule is on and has no zone).
                Drawn zones, when there are any, still take priority.

Zone heuristic: inside a drawn zone, the vehicle's CURRENT heading (ledger.path) points against the zone's
legal-flow arrow (more than 135 deg off), it is really driving, and it keeps doing so for 1.5 s in a row.
  - a parked or crawling vehicle is never judged (box jitter and drift are not driving)
  - a sideways move, a turn or a single noisy frame is not enough
  - each zone has its own arrow, so a junction can have several flows
Whole-picture heuristic: the same, against the learned dominant direction of the vehicle's cell.
Cells that are not learned yet, or two-way, are never judged.

Two wizard settings of this violation (both only for looking at / testing the rule):
  show_flow    draw the learned flow arrows on the saved photos and the result video (default on)
  invert_flow  TEST: treat the OPPOSITE of the learned (or drawn) direction as legal, so ordinary traffic is flagged.
               It shows that counterflow works on a clip that has no wrong-way car. Photos and video carry a TEST label;
               never confirm or send tickets from such a run.
"""
import math

from engine.violations.base import Violation
from engine.violations.geometry import dot, heading, is_driving, point_in_polygon, unit

WRONG_WAY_S = 1.5        # how long it must keep heading against the flow
AGAINST_COS = math.cos(math.radians(135.0))   # "against" = more than 135 deg off the legal direction


class Counterflow(Violation):
    key = "counterflow"
    zone_key = "counterflow_zones"
    whole_frame = True
    needs_flow = True
    color = (255, 0, 255)
    auto = True

    MIN_UPDATES = 4

    def parse_zone(self, raw):
        coords = raw.get("coordinates")
        if not coords:
            return None
        vec = raw.get("legal_flow_vector", {})
        return {"polygon": coords, "vector": (float(vec.get("x_dir", 1.0)), float(vec.get("y_dir", 0.0))),
                "test_reversed": bool(raw.get("test_reversed", False))}

    def from_wizard(self, cfg):
        zones = []
        for z in cfg.get("rois", []):
            if not z.get("polygon"):
                continue
            vec = z.get("vector", {"x_dir": 0.0, "y_dir": 1.0})      # no arrow: assume traffic flows down the picture
            dx, dy = float(vec["x_dir"]), float(vec["y_dir"])
            mag = math.hypot(dx, dy)
            dx, dy = (dx / mag, dy / mag) if mag > 0 else (0.0, 1.0)
            reverse = bool(cfg.get("invert_flow", False))              # the test: the opposite way is "legal"
            if reverse:
                dx, dy = -dx, -dy
            zones.append({"coordinates": z["polygon"], "legal_flow_vector": {"x_dir": dx, "y_dir": dy},
                          "test_reversed": reverse})
        return zones

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        zone = super().whole_frame_zone(cfg, polygon, frame_size, flow)
        zone["show_flow"] = bool(cfg.get("show_flow", True))
        zone["invert"] = bool(cfg.get("invert_flow", False))
        return zone

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "vector": (x, y)}, or the whole-frame zone (nothing drawn)."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES:
            return False

        cx, cy = ledger.history[-1][1], ledger.history[-1][2]
        found = next(((i, z) for i, z in enumerate(zones) if point_in_polygon(cx, cy, z["polygon"])), None)
        if found is None:
            for key in [k for k in ledger.stop_timers if isinstance(k, tuple) and k[:1] == (self.key,)]:
                del ledger.stop_timers[key]         # left the zones: the wrong-way run is broken
            return False
        index, zone = found
        if zone.get("whole_frame"):
            return self._evaluate_learned(ledger, zone)

        legal = unit(*zone.get("vector", (1.0, 0.0)))
        current = heading(ledger)                   # None while barely moving
        wrong = (legal != (0.0, 0.0) and current is not None and is_driving(ledger)
                 and dot(current, legal) < AGAINST_COS)
        return self._sustained(ledger, (self.key, index), wrong)

    def _evaluate_learned(self, ledger, zone) -> bool:
        head = heading(ledger)                      # None while barely moving
        _t, cx, cy, _w = ledger.path[-1]
        width, height = zone["frame_size"]
        verdict = zone["field"].verdict(cx, cy, width, height, head) if head is not None else "unknown"
        if zone.get("invert"):                      # the test: going WITH the learned flow counts as going against it
            verdict = {"with": "against", "against": "with"}.get(verdict, verdict)
        wrong = head is not None and is_driving(ledger) and verdict == "against"
        return self._sustained(ledger, (self.key, "learned"), wrong)

    def _sustained(self, ledger, key, wrong_way: bool) -> bool:
        """True once the vehicle has headed the wrong way for WRONG_WAY_S in a row; one bad frame never counts."""
        if not wrong_way:
            ledger.stop_timers.pop(key, None)       # the wrong-way run is broken
            return False
        t = ledger.path[-1][0]
        start = ledger.stop_timers.setdefault(key, t)
        if t - start >= WRONG_WAY_S:
            ledger.violations.add(self.key)
            return True
        return False

    def draw_zone(self, pipe, frame, index, zone):
        if zone.get("whole_frame"):
            if zone.get("show_flow", True):
                zone["field"].draw(frame, invert=zone.get("invert", False))     # what was learned as the legal flow
        else:
            super().draw_zone(pipe, frame, index, zone)
        if index == 0 and (zone.get("invert") or zone.get("test_reversed")):
            from engine.flow_field import draw_test_banner     # imported here: flow_field itself imports this package
            draw_test_banner(frame)                 # never let a test run pass for a real finding
