"""
counterflow - driving against the legal direction of traffic.

Two ways to know the legal direction:
  drawn         an operator draws a zone with a legal-flow arrow (the original way; kept for tests and as ground truth)
  whole picture nothing drawn: the legal direction is learned from the traffic itself (engine/flow_field.py; the pipeline
                learns the flow on its own when this rule is on and has no zone).
                Drawn zones, when there are any, still take priority.

Zone heuristic: inside a drawn zone, the vehicle's CURRENT heading (steady_heading: the last 0.8 s of ledger.path) points against
the zone's legal-flow arrow (more than 120 deg off), it is really moving, and it keeps doing so for 1.0 s.
  - a parked or crawling vehicle is never judged (box jitter and drift are not driving)
  - a sideways move, a turn or a single noisy frame is not enough
  - a noisy frame or two in the run, or a step over the edge of the drawn road, does not break it (GRACE_S): the heading of a
    far or small vehicle wobbles around the limit, and a rule that restarts its clock at each wobble misses most vehicles
  - a vehicle just outside a drawn zone (within ZONE_MARGIN_WIDTHS box widths) is judged by the nearest zone
  - each zone has its own arrow, so a junction can have several flows
Whole-picture heuristic: the same, against the learned dominant direction of the vehicle's cell.
Cells that are not learned yet, or two-way, are never judged.

A zone whose arrow bends (a road marked with many points) has a `flow_path`: the legal direction is then the direction of the part of the arrow
nearest to the vehicle, so each stretch of a curved road is judged against its own direction.

Two wizard settings of this violation (both only for looking at / testing the rule):
  show_flow    draw the learned flow arrows on the saved photos and the result video (default on)
  invert_flow  TEST: treat the OPPOSITE of the learned (or drawn) direction as legal, so ordinary traffic is flagged.
               It shows that counterflow works on a clip that has no wrong-way car. Photos and video carry a TEST label;
               never confirm or send tickets from such a run.
"""
import math

from engine.violations.base import Violation
from engine.violations.geometry import dot, is_travelling, point_in_polygon, polygon_gap, steady_heading, unit

WRONG_WAY_S = 1.0        # how long it must keep heading against the flow
GRACE_S = 0.5            # a gap this long (not wrong, or off the road) does not break the run; 3 frames if frames come slower, at most GRACE_MAX_S
GRACE_MAX_S = 1.0
AGAINST_COS = math.cos(math.radians(120.0))   # "against" = more than 120 deg off the legal direction
ZONE_MARGIN_WIDTHS = 0.4  # a vehicle this close (in box widths) outside a drawn zone still belongs to it


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
        zone = {"polygon": coords, "vector": (float(vec.get("x_dir", 1.0)), float(vec.get("y_dir", 0.0))),
                "test_reversed": bool(raw.get("test_reversed", False))}
        path = self._clean_path(raw.get("flow_path"))
        if path:
            zone["flow_path"] = path
        return zone

    @staticmethod
    def _clean_path(raw) -> list | None:
        """The arrow of a zone as points: two or more, each [x, y]; anything else = no arrow (the zone's vector is used)."""
        try:
            pts = [[float(p[0]), float(p[1])] for p in raw or []]
        except (TypeError, ValueError, IndexError):
            return None
        return pts if len(pts) >= 2 and all(math.isfinite(v) for p in pts for v in p) else None

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
            item = {"coordinates": z["polygon"], "legal_flow_vector": {"x_dir": dx, "y_dir": dy}, "test_reversed": reverse}
            path = self._clean_path(z.get("path") or z.get("ui_vector"))       # a bent arrow, else the straight one
            if path:
                item["flow_path"] = path[::-1] if reverse else path
            zones.append(item)
        return zones

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        zone = super().whole_frame_zone(cfg, polygon, frame_size, flow)
        zone["show_flow"] = bool(cfg.get("show_flow", True))
        zone["invert"] = bool(cfg.get("invert_flow", False))
        return zone

    def set_test_reversed(self, pipe, on: bool) -> None:
        """Live demo: reverse the legal direction (or put it back) while the camera runs, so ordinary traffic is flagged without
        waiting for a real wrong-way car. The whole-picture rule reads "invert_flow" on every frame; a drawn zone's arrow was fixed
        when the zones were parsed, so it is flipped here. What the traffic taught the flow field is kept. Vehicles flagged under
        the other setting are cleared, so a test never leaves tickets behind after it is switched off. Run it on the pipeline's
        own thread (the live feed's single-thread executor) so it never races a frame."""
        settings = getattr(pipe, "violation_cfg", None)
        if settings is None:
            settings = pipe.violation_cfg = {}
        settings.setdefault(self.key, {})["invert_flow"] = bool(on)
        for zone in getattr(pipe, "rois", {}).get(self.zone_key) or []:
            if bool(zone.get("test_reversed")) != bool(on):
                vx, vy = zone["vector"]
                zone["vector"] = (-vx, -vy)
                if zone.get("flow_path"):
                    zone["flow_path"] = zone["flow_path"][::-1]
                zone["test_reversed"] = bool(on)
        manager = getattr(pipe, "ledger_manager", None)
        for ledger in list(manager.ledgers.values()) if manager is not None else []:
            ledger.violations.discard(self.key)
            for timer in [k for k in list(ledger.stop_timers) if isinstance(k, tuple) and k[:1] == (self.key,)]:
                ledger.stop_timers.pop(timer, None)

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "vector": (x, y)}, or the whole-frame zone (nothing drawn)."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES:
            return False

        cx, cy = ledger.history[-1][1], ledger.history[-1][2]
        found = self._zone_of(zones, cx, cy, ledger.path[-1][3])
        if found is None:
            return False                            # off the judged roads: _sustained breaks the run when the gap lasts
        index, zone = found
        if zone.get("whole_frame"):
            return self._evaluate_learned(ledger, zone)

        legal = unit(*zone.get("vector", (1.0, 0.0)))
        if zone.get("flow_path") and len(zone["flow_path"]) > 2:    # a bent arrow: the direction of the stretch the vehicle is on
            legal = self._legal_here(zone["flow_path"], cx, cy) or legal
        current = steady_heading(ledger)            # None while barely moving
        wrong = (legal != (0.0, 0.0) and current is not None and is_travelling(ledger)
                 and dot(current, legal) < AGAINST_COS)
        return self._sustained(ledger, (self.key, index), wrong)

    @staticmethod
    def _zone_of(zones, cx: float, cy: float, width: float):
        """(index, zone) of the first zone that holds the point; else of the nearest zone within ZONE_MARGIN_WIDTHS box widths of it
        (a vehicle at the edge of a drawn road is still on that road); else None."""
        for i, z in enumerate(zones):
            if z.get("whole_frame") or point_in_polygon(cx, cy, z["polygon"]):
                return i, z
        reach, best = ZONE_MARGIN_WIDTHS * width, None
        for i, z in enumerate(zones):
            gap = polygon_gap(cx, cy, z["polygon"])
            if gap <= reach and (best is None or gap < best[0]):
                best = (gap, i, z)
        return None if best is None else (best[1], best[2])

    @staticmethod
    def _legal_here(path, cx: float, cy: float):
        """The unit direction of the piece of `path` nearest to (cx, cy), or None when the path has no length."""
        best, best_d = None, float("inf")
        for (x0, y0), (x1, y1) in zip(path, path[1:]):
            dx, dy = x1 - x0, y1 - y0
            length2 = dx * dx + dy * dy
            if length2 <= 0:
                continue
            t = max(0.0, min(1.0, ((cx - x0) * dx + (cy - y0) * dy) / length2))
            d = math.hypot(cx - (x0 + t * dx), cy - (y0 + t * dy))
            if d < best_d:
                best, best_d = (dx, dy), d
        return unit(*best) if best else None

    def _evaluate_learned(self, ledger, zone) -> bool:
        head = steady_heading(ledger)               # None while barely moving
        _t, cx, cy, _w = ledger.path[-1]
        width, height = zone["frame_size"]
        verdict = zone["field"].verdict(cx, cy, width, height, head) if head is not None else "unknown"
        if zone.get("invert"):                      # the test: going WITH the learned flow counts as going against it
            verdict = {"with": "against", "against": "with"}.get(verdict, verdict)
        wrong = head is not None and is_travelling(ledger) and verdict == "against"
        return self._sustained(ledger, (self.key, "learned"), wrong)

    def _sustained(self, ledger, key, wrong_way: bool) -> bool:
        """True once the vehicle has headed the wrong way for WRONG_WAY_S; one bad frame never counts. A run is broken only by a gap
        of GRACE_S without a wrong-way frame (checked when the next one comes, so a stale run of an earlier zone is never continued)."""
        if not wrong_way:
            return False
        t = ledger.path[-1][0]
        seen = key + ("seen",)                      # when the last wrong-way frame was
        last = ledger.stop_timers.get(seen)
        frame = t - ledger.path[-2][0] if len(ledger.path) > 1 else 0.0
        if last is None or t - last > min(GRACE_MAX_S, max(GRACE_S, 3 * frame)):
            ledger.stop_timers[key] = t             # a new run (a broken one starts again from here)
        ledger.stop_timers[seen] = t
        if t - ledger.stop_timers.setdefault(key, t) >= WRONG_WAY_S:
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
