"""
stopped_in_zone.py - the shared rule behind "a vehicle must not stand still in this place":
pedestrian_lane (a crosswalk), blocking_intersection (the junction box) and illegal_loading (a no-loading bay).

Heuristic: the vehicle's ground point is inside a zone and it is slower than 25 px/s (box jitter on a
stopped car stays below this) for longer than the zone's own time limit. Each violation has its own timer
(geometry.stopped_too_long keys it by violation), so one car can be timed for several at once.
A violation may judge only some vehicle types (default_classes, e.g. buses and tricycles for loading):
a zone with a "classes" list ignores every other type; a zone without one judges all of them.
A whole-picture zone (nothing drawn) of a rule with `needs_flow` only flags a vehicle that is stopped while other traffic keeps
driving past it along the road (engine/violations/scene.py): the front of a red-light queue is stopped too, and is not parked.
"""
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, point_in_polygon, stopped_too_long
from engine.violations.scene import recently_flowing


class StoppedInZone(Violation):
    default_limit_s = 3.0
    default_classes: tuple | None = None    # None = every vehicle type is judged
    MIN_UPDATES = 5

    def _zone_extra(self, source: dict) -> dict:
        """The vehicle-type filter of a zone, only when this violation has one (keeps older zone dicts unchanged)."""
        classes = list(source.get("classes") or self.default_classes or [])
        return {"classes": classes} if (self.default_classes is not None or source.get("classes")) else {}

    def parse_zone(self, raw):
        if not raw.get("coordinates"):
            return None
        return {"polygon": raw["coordinates"], "time_limit": float(raw.get("time_limit", self.default_limit_s)),
                **self._zone_extra(raw)}

    def from_wizard(self, cfg):
        limit = float(cfg.get("time_limit", self.default_limit_s))
        extra = self._zone_extra({"classes": cfg.get("banned_classes")})    # the wizard's "vehicle types" picker
        return [{"coordinates": z["polygon"], "time_limit": limit, **extra} for z in cfg.get("rois", []) if z.get("polygon")]

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        zone = {"polygon": polygon, "time_limit": float(cfg.get("time_limit", self.default_limit_s)),
                "whole_frame": True, "field": flow, "frame_size": frame_size}
        zone.update(self._zone_extra({"classes": cfg.get("banned_classes")}))
        return zone

    @staticmethod
    def _judged(ledger, zone) -> bool:
        """False for a vehicle type this zone does not look at (and for a class that is still unknown)."""
        classes = zone.get("classes")
        return not classes or (ledger.vclass != "unknown" and ledger.vclass in classes)

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "time_limit": seconds, "classes": [...] (optional)}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES:
            return False
        cx, cy = ledger.history[-1][1], ledger.history[-1][2]
        zone = next((z for z in zones if point_in_polygon(cx, cy, z["polygon"]) and self._judged(ledger, z)), None)
        limit = (zone or {}).get("time_limit") or self.default_limit_s
        flowing = True
        if zone is not None and zone.get("whole_frame") and self.needs_flow and ledger.get_speed() < STOP_SPEED:
            flowing = recently_flowing(mgr, ledger, zone, self.key)       # keep the memory fresh every frame
        if stopped_too_long(ledger, self.key, zone is not None, limit) and flowing:
            ledger.violations.add(self.key)
            return True
        return False
