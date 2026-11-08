"""
illegal_parking - a vehicle left standing inside a no-parking zone.

Heuristic: inside the zone and slower than 25 px/s (box jitter on a parked car stays below this,
a driving car is far above) for longer than the zone's own time limit (default 180 s).
Needs 5+ position updates so a new track is not judged on nothing.
Automatic (flow_mode "auto", nothing drawn): the whole picture is the zone and the vehicle must also be stopped while
other traffic keeps driving past it along the learned road (a red-light queue is not parking). The enforcer's time
limit applies. Ticking the rule means "no parking on this road".
"""
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, point_in_polygon
from engine.violations.scene import recently_flowing


class IllegalParking(Violation):
    key = "illegal_parking"
    zone_key = "illegal_parking_zones"
    auto = True
    color = (255, 0, 0)

    MIN_UPDATES = 5

    def parse_zone(self, raw):
        coords = raw.get("coordinates")
        if not coords:
            return None
        return {"polygon": coords, "time_limit": float(raw.get("time_limit", 180.0))}

    def from_wizard(self, cfg):
        limit = float(cfg.get("time_limit", 10.0))
        return [{"coordinates": z["polygon"], "time_limit": limit} for z in cfg.get("rois", []) if z.get("polygon")]

    def auto_zone(self, cfg, polygon, frame_size, flow):
        return {"polygon": polygon, "time_limit": float(cfg.get("time_limit", 10.0)),
                "auto": True, "field": flow, "frame_size": frame_size}

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "time_limit": seconds}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES:
            return False

        t, cx, cy = ledger.history[-1][0], ledger.history[-1][1], ledger.history[-1][2]
        zone = None
        if ledger.get_speed() < STOP_SPEED:
            zone = next((z for z in zones if point_in_polygon(cx, cy, z["polygon"])), None)

        if zone is None:
            ledger.stationary_start_time = None
            return False
        if ledger.stationary_start_time is None:
            ledger.stationary_start_time = t
            return False
        flowing = recently_flowing(mgr, ledger, zone, self.key) if zone.get("auto") else True
        if t - ledger.stationary_start_time >= zone.get("time_limit", 180.0) and flowing:
            ledger.violations.add(self.key)
            return True
        return False
