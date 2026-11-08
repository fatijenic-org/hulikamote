"""
banned_in_zone.py - the shared rule behind "this type of vehicle must not be here":
truck_ban (a banned road or lane), tricycle_on_highway (a national highway) and sidewalk_driving (the sidewalk).

Heuristic: the vehicle's class (the most common class over its whole track, so one wrong frame cannot decide;
a class still "unknown" is never judged) is in the zone's banned list AND its ground point stays inside the
zone for `sustain_s` seconds (a vehicle only clipping a corner is ignored). moving_only rules (the sidewalk) also
need the vehicle to be moving, so a car left standing there is illegal_parking, not "driving on the sidewalk".
The banned list comes from the wizard's vehicle-type picker; when it is empty the rule's own default is used.
This is the mirror image of restricted_lane, which lists the types that ARE allowed.
Automatic mode (truck_ban, tricycle_on_highway): the whole picture is the banned area; ticking the rule means
"these types are banned on this road".
"""
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, point_in_polygon


class BannedInZone(Violation):
    banned_default: tuple = ()
    sustain_s = 1.0
    moving_only = False
    MIN_UPDATES = 5

    def _banned(self, source: dict) -> list:
        return list(source.get("banned_classes") or self.banned_default)

    def parse_zone(self, raw):
        if not raw.get("coordinates"):
            return None
        return {"polygon": raw["coordinates"], "banned_classes": self._banned(raw)}

    def from_wizard(self, cfg):
        banned = self._banned(cfg)
        return [{"coordinates": z["polygon"], "banned_classes": banned} for z in cfg.get("rois", []) if z.get("polygon")]

    def auto_zone(self, cfg, polygon, frame_size, flow):
        return {"polygon": polygon, "banned_classes": self._banned(cfg), "auto": True}

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "banned_classes": ["truck", ...]}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES:
            return False
        t, cx, cy = ledger.history[-1][0], ledger.history[-1][1], ledger.history[-1][2]
        timer = f"{self.key}:inside"                      # own timer, never shared with the stop timers
        inside = ledger.vclass != "unknown" and any(
            ledger.vclass in z.get("banned_classes", []) and point_in_polygon(cx, cy, z["polygon"]) for z in zones
        )
        if not inside or (self.moving_only and ledger.get_speed() < STOP_SPEED):
            ledger.stop_timers.pop(timer, None)
            return False
        if t - ledger.stop_timers.setdefault(timer, t) >= self.sustain_s:
            ledger.violations.add(self.key)
            return True
        return False
