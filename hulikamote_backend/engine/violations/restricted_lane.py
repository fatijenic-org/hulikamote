"""
restricted_lane - a vehicle type that is not allowed in a lane (e.g. a car in a bus lane).

Heuristic: the vehicle's ground point is inside the zone and its class (the most common class
over its whole track, so one wrong frame cannot decide) is not in the zone's allowed_classes.
An empty allowed list closes the lane to everyone. A class that is still "unknown" is never judged.
"""
from engine.violations.base import Violation
from engine.violations.geometry import point_in_polygon


class RestrictedLane(Violation):
    key = "restricted_lane"
    zone_key = "restricted_lane_zones"
    color = (0, 255, 255)

    def parse_zone(self, raw):
        coords = raw.get("coordinates")
        if not coords:
            return None
        return {"polygon": coords, "allowed_classes": raw.get("allowed_classes", ["bus"])}

    def from_wizard(self, cfg):
        allowed = cfg.get("allowed_classes", ["bus"])
        return [{"coordinates": z["polygon"], "allowed_classes": allowed} for z in cfg.get("rois", []) if z.get("polygon")]

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "allowed_classes": ["bus", ...]}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < 2:
            return False

        cx, cy = ledger.history[-1][1], ledger.history[-1][2]
        for zone in zones:
            if point_in_polygon(cx, cy, zone["polygon"]):
                if ledger.vclass != "unknown" and ledger.vclass not in zone.get("allowed_classes", []):
                    ledger.violations.add(self.key)
                    return True
        return False
